/**
 * ============================================================================
 * MeDisP - Smart Pill Dispenser (ESP32 Firmware)
 * ============================================================================
 * Features:
 * - BLE GATT Server (Service, Config, Status, Response Characteristics)
 * - Two-Way Communication: Flutter App <-> ESP32
 * - Interactive Serial CLI for manual debugging & hardware testing
 * - Hardware Hooks for motor & drop sensor integration
 * - Time Synchronization (Local Epoch & RTC hook)
 * - Dual Storage Subsystem: MicroSD SPI with LittleFS Flash fallback
 * - Essential Storage: slots.json & schedule.json
 * ============================================================================
 */

#include <Arduino.h>
#include <ArduinoJson.h>
#include <FS.h>
#include <HardwareSerial.h>
#include <LittleFS.h>
#include <NimBLEDevice.h>
#include <SD.h>
#include <SPI.h>
#include <sys/time.h>
#include <time.h>
#include <vector>

// ----------------------------------------------------------------------------
// Hardware Pinout Definitions
// ----------------------------------------------------------------------------
#if defined(CONFIG_IDF_TARGET_ESP32C3) ||                                      \
    defined(CONFIG_IDF_TARGET_ESP32C5) || defined(CONFIG_IDF_TARGET_ESP32C6)
#define SD_CS_PIN 7   // Chip Select
#define SD_MOSI_PIN 6 // Master Out Slave In
#define SD_MISO_PIN 5 // Master In Slave Out
#define SD_SCK_PIN 4  // Serial Clock
#else
#define SD_CS_PIN 5    // Default VSPI CS on classic ESP32
#define SD_MOSI_PIN 23 // Default VSPI MOSI
#define SD_MISO_PIN 19 // Default VSPI MISO
#define SD_SCK_PIN 18  // Default VSPI SCK
#endif

// ----------------------------------------------------------------------------
// BLE GATT UUID Definitions
// ----------------------------------------------------------------------------
#define SERVICE_UUID "12345678-1234-1234-1234-123456789000"
#define CONFIG_CHAR_UUID "12345678-1234-1234-1234-123456789001"   // Write/Read
#define STATUS_CHAR_UUID "12345678-1234-1234-1234-123456789002"   // Read
#define RESPONSE_CHAR_UUID "12345678-1234-1234-1234-123456789003" // Notify

#define DEVICE_NAME "PillDispenser"
#define DEVICE_ID "PD001"
#define NUM_SLOTS 6

// ----------------------------------------------------------------------------
// Storage File Paths (Dual Storage: SD Card with LittleFS fallback)
// ----------------------------------------------------------------------------
#define PATH_DIR_CONFIG "/config"
#define FILE_SCHEDULE "/config/schedule.json"
#define FILE_SLOTS "/config/slots.json"
#define FILE_HISTORY "/config/history.json"

// ----------------------------------------------------------------------------
// Data Models (In-Memory State)
// ----------------------------------------------------------------------------
struct SlotInfo {
  int number;
  int capacity;
  int remaining;
  String drugName;
  String drugId;
  bool isPrn;
  int minIntervalHours;
  int prnQty;
  int maxDosesPerDay;
  String indication;
};

static SlotInfo gSlots[NUM_SLOTS];

// BLE Handles
static NimBLECharacteristic *pConfigChar = nullptr;
static NimBLECharacteristic *pStatusChar = nullptr;
static NimBLECharacteristic *pResponseChar = nullptr;
static bool isBleClientConnected = false;

// Storage Handles
static bool isSdMounted = false;
static bool isLittleFsOk = false;
static fs::FS *pActiveFS = nullptr;

// Time & State
static bool isTimeSynced = false;
static String currentScheduleJson = "";

// High-Reliability BLE Command FIFO Queue (Prevents command dropping during
// burst writes)
#include <queue>
static std::queue<String> bleCommandQueue;
static portMUX_TYPE bleCommandMux = portMUX_INITIALIZER_UNLOCKED;

void enqueueBleCommand(const String &cmd) {
  taskENTER_CRITICAL(&bleCommandMux);
  if (bleCommandQueue.size() < 24) {
    bleCommandQueue.push(cmd);
  }
  taskEXIT_CRITICAL(&bleCommandMux);
}

bool dequeueBleCommand(String &outCmd) {
  bool hasCmd = false;
  taskENTER_CRITICAL(&bleCommandMux);
  if (!bleCommandQueue.empty()) {
    outCmd = bleCommandQueue.front();
    bleCommandQueue.pop();
    hasCmd = true;
  }
  taskEXIT_CRITICAL(&bleCommandMux);
  return hasCmd;
}

// Periodic Time Sync Request (every 15 minutes)
#define TIME_SYNC_INTERVAL_MS 900000UL
static unsigned long lastTimeSyncRequestMs = 0;

struct PrnStatus {
  bool isReady;
  String reason;
  String buttonText;
  int remaining;
  int takenToday;
  int maxDoses;
  int minIntervalHours;
  int minutesUntilNextDose;
  String lastTakenTime;   // e.g. "08:30" or "None today"
  String nextAllowedTime; // e.g. "Available now" or "12:30 (Wait 1h 15m)"
};

// Forward Declarations
PrnStatus checkPrnStatus(int slot);
String getDrugIndication(int slotIdx);
void sendResponseNotification(const char *result, const char *message);
void sendBleEvent(const String &eventJson);
bool writeStorageFile(const char *path, const String &data);
String readStorageFile(const char *path);
void parseAndApplySlots(const String &jsonStr);
void saveSlotsToStorage();
String buildDeviceStatusJson();
bool executeDispense(int slot, int qty, const String &medicine,
                     const String &reqId, String &outErrMsg,
                     bool isScheduled = false, const String &schedTime = "");
void recordIntakeHistory(int slot, int qty, const String &medicine,
                         const char *type, const char *status,
                         const char *schedTime = "");
String findActiveScheduleTimeForSlot(int slot);
void printSerialHistory();
String getCurrentDateStr(int dayOffset = 0);
String getCurrentTimeHHMM();
int countPrnIntakesToday(int slot);
bool isScheduledMealCompletedToday(const String &mealTime);
void refreshCurrentNextionPage();
void handleReqDaily(bool resetOffset);
void handleReqPrn();
void handleReqPrnDetail();
void handleReqTimeline(bool resetOffset);
void handleReqConfirm();
void handleReqAlert();
void handleReqDispensing();
void handleReqSuccess();
void nextionSend(const String &cmd);
void processNextionMessage(String msg);
extern String gCurrentNextionPage;

// ============================================================================
// HARDWARE HOOKS
// ============================================================================

/**
 * [Hook 1: Hardware Dispense Execution]
 * Parameters:
 *   - slot: Medication slot index (1 - 6)
 *   - qty: Number of tablets to dispense
 *   - outErrMsg: Error message if dispense fails
 * Return: true if dispense succeeds, false on error
 */
bool hardwareDispenseSlot(int slot, int qty, String &outErrMsg) {
  Serial.printf("[HARDWARE HOOK] Executing dispense: Slot %d, Qty: %d\n", slot,
                qty);
  // Default mock behavior: assume hardware dispense succeeded
  return true;
}

inline bool dispensePill(int slot, int qty) {
  String err = "";
  return hardwareDispenseSlot(slot, qty, err);
}

/**
 * [Hook 2: Synchronize External RTC Module (e.g., DS3231)]
 */
void hardwareSyncRtc(unsigned long epochTime) {
  Serial.printf("[HARDWARE HOOK] Syncing external RTC to epoch: %lu\n",
                epochTime);
}

/**
 * [Hook 3: Update Slot Hardware Indicators (e.g., LED / Physical Status)]
 */
void hardwareSlotUpdated(int slot, int remaining, const char *drugName) {
  Serial.printf("[HARDWARE HOOK] Slot %d updated: '%s' remaining: %d\n", slot,
                drugName, remaining);
}

// ============================================================================
// Time Subsystem
// ============================================================================
void setSystemEpoch(unsigned long epoch) {
  struct timeval tv = {(time_t)epoch, 0};
  settimeofday(&tv, nullptr);
  isTimeSynced = true;

  hardwareSyncRtc(epoch);

  char buf[64];
  time_t now = epoch;
  struct tm *tm_info = localtime(&now);
  strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", tm_info);
  Serial.printf("[TIME] System time synchronized: %s (Epoch: %lu)\n", buf,
                epoch);
}

String getFormattedTime() {
  time_t now = time(nullptr);
  if (!isTimeSynced || now < 100000) {
    return "BOOT+" + String(millis() / 1000) + "s";
  }
  char buf[32];
  struct tm *tm_info = localtime(&now);
  strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", tm_info);
  return String(buf);
}

unsigned long getSystemEpoch() {
  return isTimeSynced ? (unsigned long)time(nullptr) : 0;
}

String getCurrentDateStr(int dayOffset) {
  time_t now = (time_t)getSystemEpoch();
  if (now > (dayOffset * 86400L)) {
    now -= (dayOffset * 86400L);
  }
  if (!isTimeSynced || now < 100000) {
    return "1970-01-01";
  }
  char buf[16];
  struct tm *tm_info = localtime(&now);
  strftime(buf, sizeof(buf), "%Y-%m-%d", tm_info);
  return String(buf);
}

String getCurrentTimeHHMM() {
  time_t now = (time_t)getSystemEpoch();
  if (!isTimeSynced || now < 100000) {
    return "--:--";
  }
  char buf[8];
  struct tm *tm_info = localtime(&now);
  strftime(buf, sizeof(buf), "%H:%M", tm_info);
  return String(buf);
}

// ============================================================================
// Storage Subsystem (SD Card + LittleFS)
// ============================================================================
void ensureDirectory(const char *path) {
  if (pActiveFS) {
    pActiveFS->mkdir(path);
  }
}

bool writeStorageFile(const char *path, const String &data) {
  if (!pActiveFS)
    return false;
  File f = pActiveFS->open(path, FILE_WRITE);
  if (!f) {
    Serial.printf("[STORAGE ERROR] Failed to write %s\n", path);
    return false;
  }
  f.print(data);
  f.close();
  return true;
}

String readStorageFile(const char *path) {
  if (!pActiveFS || !pActiveFS->exists(path))
    return "";
  File f = pActiveFS->open(path, FILE_READ);
  if (!f)
    return "";
  String content = f.readString();
  f.close();
  return content;
}

void initDefaultSlots() {
  for (int i = 0; i < NUM_SLOTS; i++) {
    gSlots[i].number = i + 1;
    gSlots[i].capacity = 30;
    gSlots[i].remaining = 0;
    gSlots[i].drugName = "";
    gSlots[i].drugId = "";
    gSlots[i].isPrn = false;
    gSlots[i].minIntervalHours = 0;
    gSlots[i].prnQty = 1;
    gSlots[i].maxDosesPerDay = 4;
    gSlots[i].indication = "";
  }
}

String getDrugIndication(int slotIdx) {
  if (slotIdx >= 0 && slotIdx < NUM_SLOTS &&
      gSlots[slotIdx].indication.length() > 0) {
    return gSlots[slotIdx].indication;
  }
  String lower =
      (slotIdx >= 0 && slotIdx < NUM_SLOTS) ? gSlots[slotIdx].drugName : "";
  lower.toLowerCase();
  if (lower.indexOf("ibuprofen") >= 0 || lower.indexOf("nurofen") >= 0)
    return "Pain / Fever / Joint";
  if (lower.indexOf("para") >= 0 || lower.indexOf("tylenol") >= 0)
    return "Headache / Fever";
  if (lower.indexOf("cetirizine") >= 0 || lower.indexOf("zyrtec") >= 0)
    return "Allergy / Runny Nose";
  if (lower.indexOf("loratadine") >= 0 || lower.indexOf("claritin") >= 0)
    return "Allergy / Sneezing";
  if (lower.indexOf("domperidone") >= 0 || lower.indexOf("motilium") >= 0)
    return "Nausea / Vomiting";
  if (lower.indexOf("antacid") >= 0 || lower.indexOf("gaviscon") >= 0)
    return "Heartburn / Gas";
  return "Relief as needed";
}

void parseAndApplySlots(const String &jsonStr) {
#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
#else
  DynamicJsonDocument doc(2048);
#endif
  DeserializationError err = deserializeJson(doc, jsonStr);
  if (err) {
    Serial.printf("[STORAGE] Error parsing slots JSON: %s\n", err.c_str());
    return;
  }

  JsonArray slotsArr;
  if (doc["slots"].is<JsonArray>()) {
    slotsArr = doc["slots"].as<JsonArray>();
  } else if (doc.is<JsonArray>()) {
    slotsArr = doc.as<JsonArray>();
  }

  if (!slotsArr.isNull()) {
    for (JsonObject s : slotsArr) {
      int sNum = 0;
      if (s.containsKey("number"))
        sNum = s["number"] | 0;
      else if (s.containsKey("slot"))
        sNum = s["slot"] | 0;
      else if (s.containsKey("s"))
        sNum = s["s"] | 0;

      if (sNum >= 1 && sNum <= NUM_SLOTS) {
        int idx = sNum - 1;
        gSlots[idx].capacity =
            s.containsKey("capacity") ? (s["capacity"] | 30) : 30;

        if (s.containsKey("remaining"))
          gSlots[idx].remaining = s["remaining"] | 0;
        else if (s.containsKey("rem"))
          gSlots[idx].remaining = s["rem"] | 0;
        else if (s.containsKey("qty"))
          gSlots[idx].remaining = s["qty"] | 0;
        else if (s.containsKey("quantity"))
          gSlots[idx].remaining = s["quantity"] | 0;

        // Flexible drug name extraction
        String drugName = "";
        String drugId = "";
        if (s["drug"].is<JsonObject>()) {
          JsonObject d = s["drug"].as<JsonObject>();
          drugName = d["name"] | d["medicine"] | d["drug_name"] | "";
          drugId = d["id"] | "";
        } else if (s.containsKey("drug")) {
          drugName = s["drug"].as<String>();
          drugId = s["drug_id"] | "";
        } else if (s.containsKey("name")) {
          drugName = s["name"].as<String>();
          drugId = s["id"] | "";
        } else if (s.containsKey("medicine")) {
          drugName = s["medicine"].as<String>();
        } else if (s.containsKey("med")) {
          drugName = s["med"].as<String>();
        }
        gSlots[idx].drugName = drugName;
        gSlots[idx].drugId = drugId;

        // Exhaustive is_prn parsing (bool, int, string, object)
        bool isPrn = false;
        if (s.containsKey("is_prn")) {
          if (s["is_prn"].is<bool>())
            isPrn = s["is_prn"].as<bool>();
          else if (s["is_prn"].is<int>())
            isPrn = (s["is_prn"].as<int>() > 0);
          else if (s["is_prn"].is<const char *>()) {
            String ps = s["is_prn"].as<String>();
            ps.toLowerCase();
            isPrn = (ps == "true" || ps == "1" || ps == "prn");
          }
        } else if (s.containsKey("isPrn")) {
          if (s["isPrn"].is<bool>())
            isPrn = s["isPrn"].as<bool>();
          else if (s["isPrn"].is<int>())
            isPrn = (s["isPrn"].as<int>() > 0);
        } else if (s.containsKey("prn")) {
          if (s["prn"].is<bool>())
            isPrn = s["prn"].as<bool>();
          else if (s["prn"].is<int>())
            isPrn = (s["prn"].as<int>() > 0);
        } else if (s["drug"].is<JsonObject>() &&
                   s["drug"].containsKey("is_prn")) {
          isPrn = s["drug"]["is_prn"].as<bool>();
        } else if (s.containsKey("type") && s["type"].as<String>() == "prn") {
          isPrn = true;
        }

        int minInt =
            s.containsKey("min_interval_hours")
                ? (s["min_interval_hours"] | 0)
                : (s.containsKey("interval_hours") ? (s["interval_hours"] | 0)
                                                   : 0);
        int prnQ = s.containsKey("prn_qty")
                       ? (s["prn_qty"] | 1)
                       : (s.containsKey("qty") ? (s["qty"] | 1) : 1);
        int maxD =
            s.containsKey("max_doses_per_day")
                ? (s["max_doses_per_day"] | 4)
                : (s.containsKey("max_doses") ? (s["max_doses"] | 4) : 4);

        // Smart heuristic: if interval or prn_qty specified, flag as PRN
        if (minInt > 0 || (s.containsKey("prn_qty") && prnQ > 0)) {
          isPrn = true;
        }

        gSlots[idx].isPrn = isPrn;
        gSlots[idx].minIntervalHours = minInt;
        gSlots[idx].prnQty = prnQ;
        gSlots[idx].maxDosesPerDay = maxD;
        if (s.containsKey("indication"))
          gSlots[idx].indication = s["indication"].as<String>();
        else if (s.containsKey("symptom"))
          gSlots[idx].indication = s["symptom"].as<String>();

        Serial.printf("[SLOTS] Slot %d: Drug='%s', Rem=%d, isPrn=%d, "
                      "minInt=%d, prnQty=%d, maxD=%d\n",
                      sNum, gSlots[idx].drugName.c_str(), gSlots[idx].remaining,
                      gSlots[idx].isPrn ? 1 : 0, gSlots[idx].minIntervalHours,
                      gSlots[idx].prnQty, gSlots[idx].maxDosesPerDay);

        hardwareSlotUpdated(sNum, gSlots[idx].remaining,
                            gSlots[idx].drugName.c_str());
      }
    }
  }
}

void saveSlotsToStorage() {
#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
#else
  DynamicJsonDocument doc(2048);
#endif
  JsonArray slotsArr = doc.createNestedArray("slots");
  for (int i = 0; i < NUM_SLOTS; i++) {
    JsonObject s = slotsArr.createNestedObject();
    s["slot"] = gSlots[i].number;
    s["capacity"] = gSlots[i].capacity;
    s["remaining"] = gSlots[i].remaining;
    s["drug"] = gSlots[i].drugName;
    if (gSlots[i].drugId.length() > 0) {
      s["drug_id"] = gSlots[i].drugId;
    }
    if (gSlots[i].indication.length() > 0) {
      s["indication"] = gSlots[i].indication;
    }
    if (gSlots[i].isPrn) {
      s["is_prn"] = true;
      s["min_interval_hours"] = gSlots[i].minIntervalHours;
      s["prn_qty"] = gSlots[i].prnQty;
      s["max_doses_per_day"] = gSlots[i].maxDosesPerDay;
    }
  }
  String output;
  serializeJson(doc, output);
  writeStorageFile(FILE_SLOTS, output);
  if (pStatusChar) {
    pStatusChar->setValue(buildDeviceStatusJson().c_str());
  }
  Serial.printf("[STORAGE] Slots saved (%d bytes)\n", output.length());
}

void updateSlotScheduleInStorage(int slotNum, JsonArray newItems) {
  String content = readStorageFile(FILE_SCHEDULE);
  if (content.length() == 0)
    content = currentScheduleJson;

#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
  JsonDocument newDoc;
#else
  DynamicJsonDocument doc(2048);
  DynamicJsonDocument newDoc(2048);
#endif

  deserializeJson(doc, content);
  newDoc["device_id"] = DEVICE_ID;
  JsonArray scheduleArr = newDoc.createNestedArray("schedule");

  struct TempSchedItem {
    String time;
    int slot;
    String medicine;
    int qty;
    bool hasBeforeFood;
    bool beforeFood;
    int minutes;
  };
  std::vector<TempSchedItem> allItems;

  // Keep existing schedule items from OTHER slots
  if (doc["schedule"].is<JsonArray>()) {
    for (JsonObject item : doc["schedule"].as<JsonArray>()) {
      int s = item["slot"] | item["s"] | 0;
      if (s != slotNum && s >= 1 && s <= NUM_SLOTS) {
        TempSchedItem it;
        it.time = item["time"] | item["t"] | "";
        it.slot = s;
        it.medicine = item["medicine"] | item["med"] | "";
        it.qty = item["qty"] | item["q"] | 1;
        it.hasBeforeFood = item.containsKey("before_food");
        it.beforeFood =
            it.hasBeforeFood ? item["before_food"].as<bool>() : true;
        it.minutes = (it.time.length() >= 5)
                         ? (it.time.substring(0, 2).toInt() * 60 +
                            it.time.substring(3, 5).toInt())
                         : 0;
        allItems.push_back(it);
      }
    }
  }

  // Add the updated schedule items for THIS slot
  String slotDrugName = "";
  for (JsonObject item : newItems) {
    TempSchedItem it;
    it.time = item["time"] | item["t"] | "";
    it.slot = slotNum;
    String med = item["medicine"] | item["med"] | "";
    if (med.length() == 0 && slotNum >= 1 && slotNum <= NUM_SLOTS) {
      med = gSlots[slotNum - 1].drugName;
    }
    it.medicine = med;
    if (slotDrugName.length() == 0 && med.length() > 0) {
      slotDrugName = med;
    }
    it.qty = item["qty"] | item["q"] | 1;
    it.hasBeforeFood = item.containsKey("before_food");
    it.beforeFood = it.hasBeforeFood ? item["before_food"].as<bool>() : true;
    it.minutes = (it.time.length() >= 5)
                     ? (it.time.substring(0, 2).toInt() * 60 +
                        it.time.substring(3, 5).toInt())
                     : 0;
    allItems.push_back(it);
  }

  // Cross-synchronize slot state:
  if (slotNum >= 1 && slotNum <= NUM_SLOTS) {
    int idx = slotNum - 1;
    if (newItems.size() > 0) {
      if (gSlots[idx].drugName.length() == 0 && slotDrugName.length() > 0) {
        gSlots[idx].drugName = slotDrugName;
      }
      gSlots[idx].isPrn = false; // Has scheduled meals
      saveSlotsToStorage();
    } else {
      // If schedule is cleared/empty for this slot but drug is configured, it
      // is PRN
      if (gSlots[idx].drugName.length() > 0) {
        gSlots[idx].isPrn = true;
        saveSlotsToStorage();
      }
    }
  }

  // Sort chronologically by time first, then by slot number
  std::sort(allItems.begin(), allItems.end(),
            [](const TempSchedItem &a, const TempSchedItem &b) {
              if (a.minutes != b.minutes)
                return a.minutes < b.minutes;
              return a.slot < b.slot;
            });

  for (const auto &it : allItems) {
    JsonObject obj = scheduleArr.createNestedObject();
    obj["time"] = it.time;
    obj["slot"] = it.slot;
    obj["medicine"] = it.medicine;
    obj["qty"] = it.qty;
    if (it.hasBeforeFood) {
      obj["before_food"] = it.beforeFood;
    }
  }

  String output;
  serializeJson(newDoc, output);
  writeStorageFile(FILE_SCHEDULE, output);
  currentScheduleJson = output;
  if (pConfigChar) {
    pConfigChar->setValue(output.c_str());
  }
  Serial.printf("[STORAGE] Consolidated schedule for Slot %d (%d items, total "
                "%d bytes)\n",
                slotNum, newItems.size(), output.length());
}

void setupStorage() {
  Serial.println("\n[STORAGE] Initializing storage subsystem...");
  initDefaultSlots();

  SPI.begin(SD_SCK_PIN, SD_MISO_PIN, SD_MOSI_PIN, SD_CS_PIN);
  if (SD.begin(SD_CS_PIN, SPI)) {
    if (SD.cardType() != CARD_NONE) {
      isSdMounted = true;
      pActiveFS = &SD;
      Serial.printf("[STORAGE] SD Card mounted successfully! Size: %lluMB\n",
                    SD.cardSize() / (1024 * 1024));
    }
  }

  if (!isSdMounted) {
    Serial.println(
        "[STORAGE] SD Card not mounted. Falling back to LittleFS...");
    if (LittleFS.begin(true)) {
      isLittleFsOk = true;
      pActiveFS = &LittleFS;
      Serial.println("[STORAGE] LittleFS mounted successfully!");
    } else {
      Serial.println("[STORAGE] Critical: Both SD and LittleFS failed!");
      return;
    }
  }

  ensureDirectory(PATH_DIR_CONFIG);

  // Load slots from storage if existing
  if (pActiveFS->exists(FILE_SLOTS)) {
    String slotsData = readStorageFile(FILE_SLOTS);
    parseAndApplySlots(slotsData);
    Serial.println("[STORAGE] Loaded slots from slots.json");
  }

  // Load schedule if existing, otherwise keep empty
  currentScheduleJson = readStorageFile(FILE_SCHEDULE);
  if (currentScheduleJson.length() == 0) {
    currentScheduleJson = "{\"device_id\":\"" DEVICE_ID "\",\"schedule\":[]}";
  }
}

// ============================================================================
// BLE Helper Functions
// ============================================================================
void sendResponseNotification(const char *result, const char *message) {
  if (!pResponseChar)
    return;
  String payload = "{\"result\":\"" + String(result) + "\",\"message\":\"" +
                   String(message) + "\"}";
  pResponseChar->setValue(payload.c_str());
  pResponseChar->notify();
  Serial.printf("[BLE NOTIFY] %s -> %s\n", result, message);
}

void sendBleEvent(const String &eventJson) {
  if (!pResponseChar)
    return;
  pResponseChar->setValue(eventJson.c_str());
  pResponseChar->notify();
  Serial.printf("[BLE EVENT NOTIFY] %s\n", eventJson.c_str());
}

String buildDeviceStatusJson() {
#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
#else
  DynamicJsonDocument doc(1024);
#endif
  doc["device_id"] = DEVICE_ID;
  doc["status"] = "ready";
  doc["time_synced"] = isTimeSynced;
  doc["epoch"] = getSystemEpoch();
  doc["date"] = getCurrentDateStr(0);
  doc["time"] = getCurrentTimeHHMM();

  JsonArray slotsArr = doc.createNestedArray("slots");
  for (int i = 0; i < NUM_SLOTS; i++) {
    JsonObject s = slotsArr.createNestedObject();
    s["slot"] = gSlots[i].number;
    s["drug"] = gSlots[i].drugName;
    s["remaining"] = gSlots[i].remaining;
    if (gSlots[i].capacity != 30)
      s["capacity"] = gSlots[i].capacity;
    if (gSlots[i].drugId.length() > 0)
      s["drug_id"] = gSlots[i].drugId;
    if (gSlots[i].isPrn) {
      s["is_prn"] = true;
      s["min_interval_hours"] = gSlots[i].minIntervalHours;
      s["prn_qty"] = gSlots[i].prnQty;
      s["max_doses_per_day"] = gSlots[i].maxDosesPerDay;
    }
  }

  String output;
  serializeJson(doc, output);
  return output;
}

String findActiveScheduleTimeForSlot(int slot) {
  String content = readStorageFile(FILE_SCHEDULE);
  if (content.length() == 0)
    content = currentScheduleJson;
#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
#else
  DynamicJsonDocument doc(2048);
#endif
  DeserializationError err = deserializeJson(doc, content);
  if (err || !doc["schedule"].is<JsonArray>()) {
    return "";
  }

  // Load history to see which schedule times for this slot are already taken
  // today
  String histContent = readStorageFile(FILE_HISTORY);
#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument histDoc;
#else
  DynamicJsonDocument histDoc(2048);
#endif
  deserializeJson(histDoc, histContent);
  String todayDate = getCurrentDateStr(0);

  // Find the untaken schedule time closest to current time
  String bestTime = "";
  int minDiff = 99999;
  String nowTime = getCurrentTimeHHMM();
  int nowMinutes = -1;
  if (isTimeSynced && nowTime.length() >= 5) {
    nowMinutes =
        nowTime.substring(0, 2).toInt() * 60 + nowTime.substring(3, 5).toInt();
  }

  for (JsonObject item : doc["schedule"].as<JsonArray>()) {
    int s = item["slot"] | item["s"] | 0;
    if (s == slot) {
      String t = item["time"] | item["t"] | "";
      if (t.length() == 0)
        continue;
      bool taken = false;
      if (histDoc["history"].is<JsonArray>()) {
        for (JsonObject h : histDoc["history"].as<JsonArray>()) {
          String hDate = h["date"] | "";
          int hSlot = h["slot"] | 0;
          String hSched = h["sched_time"] | "";
          if (hDate == todayDate && hSlot == s && hSched == t) {
            taken = true;
            break;
          }
        }
      }
      if (!taken) {
        if (nowMinutes >= 0 && t.length() >= 5) {
          int schedMin =
              t.substring(0, 2).toInt() * 60 + t.substring(3, 5).toInt();
          int diff = abs(nowMinutes - schedMin);
          if (diff < minDiff) {
            minDiff = diff;
            bestTime = t;
          }
        } else if (bestTime.length() == 0) {
          bestTime = t;
        }
      }
    }
  }
  return bestTime;
}

void recordIntakeHistory(int slot, int qty, const String &medicine,
                         const char *type, const char *status,
                         const char *schedTime) {
  unsigned long nowEpoch = getSystemEpoch();
  String dateStr = getCurrentDateStr(0);
  String timeStr = getCurrentTimeHHMM();

  String content = readStorageFile(FILE_HISTORY);
#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
  JsonDocument newDoc;
#else
  DynamicJsonDocument doc(4096);
  DynamicJsonDocument newDoc(4096);
#endif

  deserializeJson(doc, content);
  JsonArray historyArr = newDoc.createNestedArray("history");

  // Keep records within 7 days (7 * 86400 = 604800 seconds)
  unsigned long cutoffEpoch = (nowEpoch > 604800UL) ? (nowEpoch - 604800UL) : 0;

  if (doc["history"].is<JsonArray>()) {
    for (JsonObject r : doc["history"].as<JsonArray>()) {
      unsigned long ep = r["epoch"] | 0;
      if (cutoffEpoch == 0 || ep >= cutoffEpoch) {
        JsonObject kept = historyArr.createNestedObject();
        kept["epoch"] = ep;
        kept["date"] = r["date"] | "";
        kept["time"] = r["time"] | "";
        kept["slot"] = r["slot"] | 0;
        kept["qty"] = r["qty"] | 1;
        kept["med"] = r["med"] | "";
        kept["type"] = r["type"] | "meal";
        kept["status"] = r["status"] | "taken";
        if (r.containsKey("sched_time")) {
          kept["sched_time"] = r["sched_time"] | "";
        }
      }
    }
  }

  // Add the new record
  JsonObject item = historyArr.createNestedObject();
  item["epoch"] = nowEpoch;
  item["date"] = dateStr;
  item["time"] = timeStr;
  item["slot"] = slot;
  item["qty"] = qty;
  item["med"] = safeTruncateUtf8(medicine, 36);
  item["type"] = type;
  item["status"] = status;
  if (schedTime != nullptr && strlen(schedTime) > 0) {
    item["sched_time"] = schedTime;
  }

  String outStr;
  serializeJson(newDoc, outStr);
  writeStorageFile(FILE_HISTORY, outStr);
  Serial.printf(
      "[HISTORY] Recorded intake: %s %s Slot %d Qty %d (%s, %s%s%s)\n",
      dateStr.c_str(), timeStr.c_str(), slot, qty, type, status,
      (schedTime && strlen(schedTime) > 0) ? ", Sched: " : "",
      (schedTime && strlen(schedTime) > 0) ? schedTime : "");
}

int countPrnIntakesToday(int slot) {
  String todayDate = getCurrentDateStr(0);
  String content = readStorageFile(FILE_HISTORY);
  if (content.length() == 0)
    return 0;
#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
#else
  DynamicJsonDocument doc(4096);
#endif
  if (deserializeJson(doc, content))
    return 0;
  if (!doc["history"].is<JsonArray>())
    return 0;

  int count = 0;
  for (JsonObject r : doc["history"].as<JsonArray>()) {
    int s = r["slot"] | 0;
    String d = r["date"] | "";
    String type = r["type"] | "";
    String status = r["status"] | "";
    if (s == slot && d == todayDate && type == "prn" && status == "taken") {
      count++;
    }
  }
  return count;
}

// ============================================================================
// Command Processor
// ============================================================================
bool executeDispense(int slot, int qty, const String &medicine,
                     const String &reqId, String &outErrMsg, bool isScheduled,
                     const String &schedTime) {
  if (slot < 1 || slot > NUM_SLOTS) {
    outErrMsg = "Invalid slot number (1-6)";
    return false;
  }

  int idx = slot - 1;

  // PRN Safety check: daily limit resets every midnight
  if (gSlots[idx].isPrn && !isScheduled) {
    int todayDoses = countPrnIntakesToday(slot);
    int maxDoses =
        gSlots[idx].maxDosesPerDay > 0 ? gSlots[idx].maxDosesPerDay : 4;
    if (todayDoses >= maxDoses) {
      outErrMsg = "PRN daily limit reached (" + String(todayDoses) + "/" +
                  String(maxDoses) + " doses today, resets midnight)";
      Serial.printf("[PRN LIMIT] Slot %d reached daily limit of %d doses. "
                    "Resets at midnight.\n",
                    slot, maxDoses);
      return false;
    }
  }

  Serial.printf("[DISPENSE] Starting dispense: Slot %d, Drug: '%s', Qty: %d\n",
                slot, gSlots[idx].drugName.c_str(), qty);

  bool success = hardwareDispenseSlot(slot, qty, outErrMsg);

  if (success) {
    if (gSlots[idx].remaining >= qty) {
      gSlots[idx].remaining -= qty;
    } else {
      gSlots[idx].remaining = 0;
    }

    saveSlotsToStorage();

    String finalSched = schedTime;
    if (isScheduled && finalSched.length() == 0) {
      finalSched = findActiveScheduleTimeForSlot(slot);
    }

    recordIntakeHistory(slot, qty, gSlots[idx].drugName,
                        isScheduled ? "meal" : "prn", "taken",
                        finalSched.c_str());

    String eventJson =
        "{\"event\":\"DISPENSE_SUCCESS\",\"slot\":" + String(slot) +
        ",\"qty\":" + String(qty) + ",\"medicine\":\"" + gSlots[idx].drugName +
        "\",\"type\":\"" + String(isScheduled ? "meal" : "prn") +
        "\",\"sched_time\":\"" + finalSched +
        "\",\"remaining\":" + String(gSlots[idx].remaining) + ",\"req_id\":\"" +
        reqId + "\"}";
    sendBleEvent(eventJson);

    if (pStatusChar) {
      pStatusChar->setValue(buildDeviceStatusJson().c_str());
    }
    refreshCurrentNextionPage();
    return true;
  } else {
    String eventJson =
        "{\"event\":\"DISPENSE_FAILED\",\"slot\":" + String(slot) +
        ",\"reason\":\"" + outErrMsg + "\",\"req_id\":\"" + reqId + "\"}";
    sendBleEvent(eventJson);
    return false;
  }
}

void processIncomingCommand(const String &jsonPayload) {
#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
#else
  DynamicJsonDocument doc(2048);
#endif
  DeserializationError err = deserializeJson(doc, jsonPayload);
  if (err) {
    Serial.printf("[COMMAND] JSON parse error: %s\n", err.c_str());
    sendResponseNotification("error", "Invalid JSON format");
    return;
  }

  String cmd = doc["cmd"] | doc["command"] | "";
  String reqId = doc["req_id"] | "";

  // 0. PING-PONG HEARTBEAT COMMAND
  if (cmd == "ping") {
    String res = "{\"event\":\"pong\",\"req_id\":\"" + reqId +
                 "\",\"status\":\"ready\",\"time\":\"" + getFormattedTime() + "\"}";
    sendBleEvent(res);
    sendResponseNotification("success", "pong");
    return;
  }

  // 1a. DISPENSE COMMAND
  else if (cmd == "dispense") {
    int slot = doc["slot"] | 1;
    int qty = doc["qty"] | 1;
    String med = doc["medicine"] | "";
    String type = doc["type"] | "";
    String schedTime = doc["sched_time"] | "";
    bool isSched = (type == "meal") || (type == "" && !gSlots[slot - 1].isPrn);
    String errMsg = "";

    if (!executeDispense(slot, qty, med, reqId, errMsg, isSched, schedTime)) {
      sendResponseNotification("error", errMsg.c_str());
    } else {
      sendResponseNotification("success", "Dispense completed");
      refreshCurrentNextionPage();
    }
  }
  // 1b. RECORD INTAKE COMMAND
  else if (cmd == "record_intake") {
    int slot = doc["slot"] | 1;
    int qty = doc["qty"] | 1;
    String med = doc["medicine"] | "";
    String type = doc["type"] | "meal";
    String schedTime = doc["sched_time"] | "";
    String status = doc["status"] | "taken";

    if (slot >= 1 && slot <= NUM_SLOTS) {
      if (med.length() == 0) {
        med = gSlots[slot - 1].drugName;
      }
      if (schedTime.length() == 0 && type == "meal") {
        schedTime = findActiveScheduleTimeForSlot(slot);
      }

      // Decrement slot remaining count and save
      int idx = slot - 1;
      if (gSlots[idx].remaining >= qty) {
        gSlots[idx].remaining -= qty;
      } else {
        gSlots[idx].remaining = 0;
      }
      saveSlotsToStorage();

      // Trigger hardware hook for physical dispensing
      String hookErr = "";
      hardwareDispenseSlot(slot, qty, hookErr);

      // Record to history buffer
      recordIntakeHistory(slot, qty, med, type.c_str(), status.c_str(),
                          schedTime.c_str());

      String eventJson =
          "{\"event\":\"INTAKE_RECORDED\",\"req_id\":\"" + reqId + "\",\"slot\":" + String(slot) +
          ",\"qty\":" + String(qty) + ",\"medicine\":\"" +
          safeTruncateUtf8(med, 36) + "\",\"type\":\"" + type +
          "\",\"sched_time\":\"" + schedTime +
          "\",\"remaining\":" + String(gSlots[idx].remaining) + ",\"time\":\"" +
          getFormattedTime() + "\"}";
      sendBleEvent(eventJson);

      String dispEvent =
          "{\"event\":\"DISPENSE_SUCCESS\",\"req_id\":\"" + reqId + "\",\"slot\":" + String(slot) +
          ",\"qty\":" + String(qty) + ",\"medicine\":\"" +
          safeTruncateUtf8(med, 36) + "\",\"type\":\"" + type +
          "\",\"sched_time\":\"" + schedTime +
          "\",\"remaining\":" + String(gSlots[idx].remaining) + "\"}";
      sendBleEvent(dispEvent);

      if (pStatusChar) {
        pStatusChar->setValue(buildDeviceStatusJson().c_str());
      }
      sendResponseNotification("success", "Intake recorded successfully");
      refreshCurrentNextionPage();
    } else {
      sendResponseNotification("error", "Invalid slot");
    }
  }
  // 2. TIME SYNCHRONIZATION COMMAND
  else if (cmd == "sync_time") {
    unsigned long epoch = doc["epoch"] | 0;
    if (epoch > 0) {
      setSystemEpoch(epoch);
      String res = "{\"event\":\"TIME_SYNC_OK\",\"req_id\":\"" + reqId + "\",\"epoch\":" + String(epoch) +
                   ",\"time\":\"" + getFormattedTime() + "\"}";
      sendBleEvent(res);
      sendResponseNotification("success", "Time synchronized successfully");
      refreshCurrentNextionPage();
    } else {
      sendResponseNotification("error", "Invalid epoch time");
    }
  }
  // 3. SLOTS SYNCHRONIZATION COMMAND
  else if (cmd == "sync_slots") {
    parseAndApplySlots(jsonPayload);
    saveSlotsToStorage();
    String eventJson = "{\"event\":\"SLOTS_SAVED\",\"req_id\":\"" + reqId + "\",\"status\":\"success\","
                       "\"time\":\"" +
                       getFormattedTime() + "\"}";
    sendBleEvent(eventJson);
    sendResponseNotification("success", "Slots configuration saved");
    refreshCurrentNextionPage();
  }
  // 4a. SET SLOT SCHEDULE COMMAND (Per-slot schedule update)
  else if (cmd == "set_slot_schedule") {
    int slot = doc["slot"] | 0;
    if (slot >= 1 && slot <= NUM_SLOTS && doc["schedule"].is<JsonArray>()) {
      updateSlotScheduleInStorage(slot, doc["schedule"].as<JsonArray>());
      String eventJson =
          "{\"event\":\"SCHEDULE_SAVED\",\"slot\":" + String(slot) +
          ",\"status\":\"success\",\"time\":\"" + getFormattedTime() + "\"}";
      sendBleEvent(eventJson);
      sendResponseNotification("success", "Slot schedule stored");
      refreshCurrentNextionPage();
    } else {
      sendResponseNotification("error", "Invalid slot or schedule format");
    }
  }
  // 4b. GET SCHEDULE COMMAND (Stream slot schedule chunked per slot - MTU safe)
  else if (cmd == "get_schedule") {
    String content = readStorageFile(FILE_SCHEDULE);
    if (content.length() == 0)
      content = currentScheduleJson;
#if ARDUINOJSON_VERSION_MAJOR >= 7
    JsonDocument doc;
#else
    DynamicJsonDocument doc(2048);
#endif
    deserializeJson(doc, content);

    for (int s = 1; s <= NUM_SLOTS; s++) {
#if ARDUINOJSON_VERSION_MAJOR >= 7
      JsonDocument slotDoc;
#else
      DynamicJsonDocument slotDoc(512);
#endif
      slotDoc["event"] = "SLOT_SCHEDULE";
      slotDoc["slot"] = s;
      JsonArray schedArr = slotDoc.createNestedArray("schedule");

      if (doc["schedule"].is<JsonArray>()) {
        for (JsonObject item : doc["schedule"].as<JsonArray>()) {
          int slotNum = item["slot"] | item["s"] | 0;
          if (slotNum == s) {
            JsonObject it = schedArr.createNestedObject();
            it["time"] = item["time"] | item["t"] | "";
            it["qty"] = item["qty"] | item["q"] | 1;
            if (item.containsKey("before_food")) {
              it["before_food"] = item["before_food"].as<bool>();
            }
            String med = item["medicine"] | item["med"] | "";
            if (med.length() == 0 && s >= 1 && s <= NUM_SLOTS) {
              med = gSlots[s - 1].drugName;
            }
            it["medicine"] = safeTruncateUtf8(med, 36);
          }
        }
      }

      String slotOut;
      serializeJson(slotDoc, slotOut);
      sendBleEvent(slotOut);
      delay(30);
    }

    sendBleEvent("{\"event\":\"SCHEDULE_SYNC_DONE\",\"status\":\"success\"}");
    sendResponseNotification("success", "Schedule sync finished");
  }
  // 4c. FULL SCHEDULE SYNCHRONIZATION COMMAND
  else if (cmd == "sync_schedule" ||
           (cmd == "" && doc.containsKey("schedule"))) {
    if (!doc.containsKey("device_id") ||
        doc["device_id"].as<String>().length() == 0) {
      sendResponseNotification("error", "Missing or empty 'device_id'");
      return;
    }
    if (!doc["schedule"].is<JsonArray>()) {
      sendResponseNotification("error",
                               "Invalid 'schedule' format; expected array");
      return;
    }

    writeStorageFile(FILE_SCHEDULE, jsonPayload);
    currentScheduleJson = jsonPayload;
    if (pConfigChar) {
      pConfigChar->setValue(jsonPayload.c_str());
    }
    String eventJson = "{\"event\":\"SCHEDULE_SAVED\",\"status\":\"success\","
                       "\"time\":\"" +
                       getFormattedTime() + "\"}";
    sendBleEvent(eventJson);
    sendResponseNotification("success", "configuration stored");
    refreshCurrentNextionPage();
  }
  // 5. STATUS QUERY COMMAND
  else if (cmd == "get_slots" || cmd == "get_status") {
    String status = buildDeviceStatusJson();
    if (pStatusChar) {
      pStatusChar->setValue(status.c_str());
    }
    sendResponseNotification("success", "Status updated");
  }
  // 6. FULL SYNC DATA COMMAND
  else if (cmd == "get_sync_data") {
    String status = buildDeviceStatusJson();
    if (pStatusChar) {
      pStatusChar->setValue(status.c_str());
    }
    if (pConfigChar) {
      pConfigChar->setValue(currentScheduleJson.c_str());
    }
    String syncEvent = "{\"event\":\"SYNC_DATA_READY\",\"status\":\"success\","
                       "\"time_synced\":" +
                       String(isTimeSynced ? "true" : "false") +
                       ",\"epoch\":" + String(getSystemEpoch()) +
                       ",\"time\":\"" + getFormattedTime() + "\"}";
    sendBleEvent(syncEvent);
    sendResponseNotification("success", "Sync data ready");
  }
    // 7. UNLIMITED HISTORY SYNC & CLEAR COMMANDS
  else if (cmd == "sync_history" || cmd == "get_history") {
    int requestedOffset =
        doc.containsKey("day_offset") ? (doc["day_offset"] | 0) : -1;
    String histContent = readStorageFile(FILE_HISTORY);
#if ARDUINOJSON_VERSION_MAJOR >= 7
    JsonDocument hDoc;
#else
    DynamicJsonDocument hDoc(4096);
#endif
    deserializeJson(hDoc, histContent);

    // Collect all distinct dates present in history log
    std::vector<String> targetDates;
    if (requestedOffset >= 0) {
      targetDates.push_back(getCurrentDateStr(requestedOffset));
    } else {
      // Extract unique dates from history in chronological order
      if (hDoc["history"].is<JsonArray>()) {
        for (JsonObject h : hDoc["history"].as<JsonArray>()) {
          String dStr = h["date"] | "";
          if (dStr.length() > 0) {
            bool exists = false;
            for (const String &ed : targetDates) {
              if (ed == dStr) { exists = true; break; }
            }
            if (!exists) targetDates.push_back(dStr);
          }
        }
      }
      // Ensure at least today's date is included even if history is empty
      String todayStr = getCurrentDateStr(0);
      bool hasToday = false;
      for (const String &ed : targetDates) {
        if (ed == todayStr) { hasToday = true; break; }
      }
      if (!hasToday) targetDates.push_back(todayStr);
    }

    for (size_t dIdx = 0; dIdx < targetDates.size(); dIdx++) {
      String targetDate = targetDates[dIdx];

      int matchCount = 0;
      if (hDoc["history"].is<JsonArray>()) {
        for (JsonObject h : hDoc["history"].as<JsonArray>()) {
          if (h["date"] == targetDate) matchCount++;
        }
      }

      if (matchCount == 0) {
#if ARDUINOJSON_VERSION_MAJOR >= 7
        JsonDocument dayDoc;
#else
        DynamicJsonDocument dayDoc(512);
#endif
        dayDoc["event"] = "HISTORY_DAY";
        dayDoc["day_offset"] = (int)dIdx;
        dayDoc["date"] = targetDate;
        dayDoc.createNestedArray("records");
        String dayOutput;
        serializeJson(dayDoc, dayOutput);
        sendBleEvent(dayOutput);
        delay(40);
      } else {
        int currentInChunk = 0;
#if ARDUINOJSON_VERSION_MAJOR >= 7
        JsonDocument dayDoc;
#else
        DynamicJsonDocument dayDoc(512);
#endif
        dayDoc["event"] = "HISTORY_DAY";
        dayDoc["day_offset"] = (int)dIdx;
        dayDoc["date"] = targetDate;
        JsonArray recArr = dayDoc.createNestedArray("records");

        for (JsonObject h : hDoc["history"].as<JsonArray>()) {
          if (h["date"] == targetDate) {
            JsonObject r = recArr.createNestedObject();
            r["time"] = h["time"] | "";
            r["slot"] = h["slot"] | 0;
            r["qty"] = h["qty"] | 1;
            r["med"] = safeTruncateUtf8(h["med"] | "", 36);
            r["type"] = h["type"] | "meal";
            r["status"] = h["status"] | "taken";
            if (h.containsKey("sched_time")) {
              r["sched_time"] = h["sched_time"] | "";
            }
            currentInChunk++;

            if (currentInChunk >= 3) {
              String dayOutput;
              serializeJson(dayDoc, dayOutput);
              sendBleEvent(dayOutput);
              delay(40);

              dayDoc.clear();
              dayDoc["event"] = "HISTORY_DAY";
              dayDoc["day_offset"] = (int)dIdx;
              dayDoc["date"] = targetDate;
              recArr = dayDoc.createNestedArray("records");
              currentInChunk = 0;
            }
          }
        }

        if (currentInChunk > 0) {
          String dayOutput;
          serializeJson(dayDoc, dayOutput);
          sendBleEvent(dayOutput);
          delay(40);
        }
      }
    }

    sendBleEvent("{\"event\":\"HISTORY_SYNC_DONE\",\"req_id\":\"" + reqId + "\",\"status\":\"success\"}");
    sendResponseNotification("success", "History sync finished");
  }
  // 7b. CLEAR HISTORY COMMAND (Preserves today's active records!)
  else if (cmd == "clear_history") {
    String beforeDate = doc.containsKey("before_date") ? doc["before_date"].as<String>() : getCurrentDateStr(0);
    String histContent = readStorageFile(FILE_HISTORY);
#if ARDUINOJSON_VERSION_MAJOR >= 7
    JsonDocument hDoc;
    JsonDocument newHDoc;
#else
    DynamicJsonDocument hDoc(4096);
    DynamicJsonDocument newHDoc(4096);
#endif
    deserializeJson(hDoc, histContent);
    JsonArray newHistArr = newHDoc.createNestedArray("history");

    int keptCount = 0;
    int clearedCount = 0;
    if (hDoc["history"].is<JsonArray>()) {
      for (JsonObject h : hDoc["history"].as<JsonArray>()) {
        String recDate = h["date"] | "";
        // Keep records from today or after beforeDate
        if (recDate.length() > 0 && recDate >= beforeDate) {
          JsonObject kept = newHistArr.createNestedObject();
          kept["date"] = h["date"];
          kept["time"] = h["time"];
          kept["slot"] = h["slot"];
          kept["qty"] = h["qty"];
          kept["med"] = h["med"];
          kept["type"] = h["type"];
          kept["status"] = h["status"];
          if (h.containsKey("sched_time")) kept["sched_time"] = h["sched_time"];
          keptCount++;
        } else {
          clearedCount++;
        }
      }
    }

    String outHist;
    serializeJson(newHDoc, outHist);
    writeStorageFile(FILE_HISTORY, outHist);

    Serial.printf("[STORAGE] History cleared: %d purged, %d preserved (from %s onwards)\n",
                  clearedCount, keptCount, beforeDate.c_str());

    String clearedEvent = "{\"event\":\"HISTORY_CLEARED\",\"req_id\":\"" + reqId + "\",\"status\":\"success\",\"preserved\":" + String(keptCount) + "}";
    sendBleEvent(clearedEvent);
    sendResponseNotification("success", "Past history cleared");
  }
  // 8. FACTORY RESET / CLEAR DATA COMMAND
  else if (cmd == "clear_data" || cmd == "factory_reset") {
    if (pActiveFS) {
      pActiveFS->remove(FILE_SLOTS);
      pActiveFS->remove(FILE_SCHEDULE);
      pActiveFS->remove(FILE_HISTORY);
    }
    initDefaultSlots();
    currentScheduleJson = "{\"device_id\":\"" DEVICE_ID "\",\"schedule\":[]}";
    if (pConfigChar) {
      pConfigChar->setValue(currentScheduleJson.c_str());
    }
    if (pStatusChar) {
      pStatusChar->setValue(buildDeviceStatusJson().c_str());
    }
    String resetEvent =
        "{\"event\":\"DISPENSER_RESET\",\"status\":\"success\"}";
    sendBleEvent(resetEvent);
    sendResponseNotification("success", "Dispenser data cleared completely");
    refreshCurrentNextionPage();
  } else {
    Serial.printf("[COMMAND] Unhandled command: %s\n", cmd.c_str());
  }
}

// ============================================================================
// BLE Callbacks
// ============================================================================
class ConfigCharacteristicCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic *characteristic,
               NimBLEConnInfo &connInfo) override {
    std::string rxValue = characteristic->getValue();
    if (rxValue.length() == 0)
      return;
    enqueueBleCommand(String(rxValue.c_str()));
  }

  void onRead(NimBLECharacteristic *characteristic,
              NimBLEConnInfo &connInfo) override {
    characteristic->setValue(currentScheduleJson.c_str());
  }
};

class StatusCharacteristicCallbacks : public NimBLECharacteristicCallbacks {
  void onRead(NimBLECharacteristic *characteristic,
              NimBLEConnInfo &connInfo) override {
    characteristic->setValue(buildDeviceStatusJson().c_str());
  }
};

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer *pServer, NimBLEConnInfo &connInfo) override {
    isBleClientConnected = true;
    // Set fast BLE connection & supervision timeout (1.5s = 150 * 10ms) to detect killed app instantly
    pServer->updateConnParams(connInfo.getConnHandle(), 16, 32, 0, 150);
    if (pStatusChar) {
      pStatusChar->setValue(buildDeviceStatusJson().c_str());
    }
    if (pConfigChar) {
      pConfigChar->setValue(currentScheduleJson.c_str());
    }
    Serial.printf("[BLE SERVER] Connected! Client address: %s\n",
                  connInfo.getAddress().toString().c_str());
  }

  void onDisconnect(NimBLEServer *pServer, NimBLEConnInfo &connInfo,
                    int reason) override {
    isBleClientConnected = false;
    Serial.printf(
        "[BLE SERVER] Disconnected (reason %d). Restarting advertising...\n",
        reason);
    NimBLEDevice::startAdvertising();
  }
};

// ============================================================================
// Safe UTF-8 truncate to prevent slicing multi-byte characters
String safeTruncateUtf8(const String &str, size_t maxLen) {
  if (str.length() <= maxLen)
    return str;
  size_t len = maxLen;
  while (len > 0 && ((uint8_t)str[len] & 0xC0) == 0x80) {
    len--;
  }
  return str.substring(0, len);
}

// Convert/Transliterate medication name for Nextion's ISO-8859-1 font
String formatNextionDrugName(const String &rawName, int slotNum) {
  if (rawName.length() == 0) {
    return "Slot " + String(slotNum) + " Medication";
  }
  bool hasNonAscii = false;
  for (size_t i = 0; i < rawName.length(); i++) {
    if ((uint8_t)rawName[i] > 127) {
      hasNonAscii = true;
      break;
    }
  }
  if (!hasNonAscii) {
    return safeTruncateUtf8(rawName, 30);
  }

  // Check if string contains mixed ASCII English text (e.g. "Paracetamol 500mg (Fever)")
  String asciiPart = "";
  for (size_t i = 0; i < rawName.length(); i++) {
    char c = rawName[i];
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') || c == ' ' || c == '-' || c == '/' ||
        c == '.') {
      asciiPart += c;
    }
  }
  asciiPart.trim();
  int alphaCount = 0;
  for (size_t i = 0; i < asciiPart.length(); i++) {
    if (isalnum((unsigned char)asciiPart[i]))
      alphaCount++;
  }
  if (alphaCount >= 3) {
    return safeTruncateUtf8(asciiPart, 30);
  }

  // Common Thai medication names mapped to clean ASCII
  if (rawName.indexOf("พารา") >= 0)
    return "Paracetamol 500mg";
  if (rawName.indexOf("ไอบู") >= 0)
    return "Ibuprofen 400mg";
  if (rawName.indexOf("เซทิ") >= 0 || rawName.indexOf("เซทิริ") >= 0)
    return "Cetirizine 10mg";
  if (rawName.indexOf("แอมโล") >= 0)
    return "Amlodipine 5mg";
  if (rawName.indexOf("เมทฟอร์") >= 0 || rawName.indexOf("เบาหวาน") >= 0)
    return "Metformin 500mg";
  if (rawName.indexOf("โอเมพ") >= 0 || rawName.indexOf("ออเมพ") >= 0)
    return "Omeprazole 20mg";
  if (rawName.indexOf("ลอรา") >= 0)
    return "Loratadine 10mg";
  if (rawName.indexOf("คลอเฟน") >= 0)
    return "CPM 4mg";
  if (rawName.indexOf("แก้ปวด") >= 0)
    return "Painkiller";
  if (rawName.indexOf("แก้แพ้") >= 0)
    return "Antihistamine";
  if (rawName.indexOf("ลดกรด") >= 0)
    return "Antacid";
  if (rawName.indexOf("ความดัน") >= 0)
    return "Blood Pressure Med";
  if (rawName.indexOf("ลดไข้") >= 0)
    return "Antipyretic";
  if (rawName.indexOf("วิตามิน") >= 0)
    return "Vitamin";

  return "Slot " + String(slotNum) + " Medication";
}

// ============================================================================
// Interactive Serial CLI (Hardware Debugging)
// ============================================================================
void printSerialSlots() {
  Serial.println("[SLOTS INVENTORY]");
  Serial.println("+------+-----------+----------+---------------+----------+---"
                 "--------+------------------------------+");
  Serial.println("| Slot | Remaining | Type     | PRN Interval  | Dose Qty | "
                 "Max / Day | Drug Name                    |");
  Serial.println("+------+-----------+----------+---------------+----------+---"
                 "--------+------------------------------+");

  // Read schedule once to show dose count for regular meal drugs
  String schedContent = readStorageFile(FILE_SCHEDULE);
  if (schedContent.length() == 0)
    schedContent = currentScheduleJson;
#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument schedDoc;
#else
  DynamicJsonDocument schedDoc(2048);
#endif
  deserializeJson(schedDoc, schedContent);

  for (int i = 0; i < NUM_SLOTS; i++) {
    bool hasDrug = gSlots[i].drugName.length() > 0;
    String med = hasDrug ? gSlots[i].drugName : "[EMPTY]";
    String type = "--";
    String interval = "--";
    String doseStr = "--";
    String maxDayStr = "--";
    if (hasDrug) {
      if (gSlots[i].isPrn) {
        type = "PRN";
        interval = String(gSlots[i].minIntervalHours) + " hrs";
        doseStr = String(gSlots[i].prnQty) +
                  (gSlots[i].prnQty > 1 ? " pills" : " pill");
        maxDayStr = String(gSlots[i].maxDosesPerDay) +
                    (gSlots[i].maxDosesPerDay > 1 ? " doses" : " dose");
      } else {
        type = "Meal";
        int minQ = 999;
        int maxQ = 0;
        if (schedDoc["schedule"].is<JsonArray>()) {
          for (JsonObject item : schedDoc["schedule"].as<JsonArray>()) {
            int s = item["slot"] | item["s"] | 0;
            if (s == gSlots[i].number) {
              int q = item["qty"] | item["q"] | 1;
              if (q < minQ)
                minQ = q;
              if (q > maxQ)
                maxQ = q;
            }
          }
        }
        if (maxQ == 0) {
          doseStr = "Per Meal";
        } else if (minQ == maxQ) {
          doseStr = String(minQ) + (minQ > 1 ? " pills" : " pill");
        } else {
          doseStr = String(minQ) + "-" + String(maxQ) + " pills";
        }
      }
    }
    Serial.printf(
        "|  %2d  |    %3d    | %-8s | %-13s | %-8s | %-9s | %-28s |\n",
        gSlots[i].number, gSlots[i].remaining, type.c_str(), interval.c_str(),
        doseStr.c_str(), maxDayStr.c_str(), safeTruncateUtf8(med, 28).c_str());
  }
  Serial.println("+------+-----------+----------+---------------+----------+---"
                 "--------+------------------------------+");
}

void printSerialSchedule() {
  String todayDate = getCurrentDateStr(0);
  Serial.printf("[ACTIVE SCHEDULE] - Today: %s\n", todayDate.c_str());
  String content = readStorageFile(FILE_SCHEDULE);
  if (content.length() == 0)
    content = currentScheduleJson;
#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
#else
  DynamicJsonDocument doc(2048);
#endif
  DeserializationError err = deserializeJson(doc, content);
  if (err || !doc["schedule"].is<JsonArray>() ||
      doc["schedule"].as<JsonArray>().size() == 0) {
    Serial.println("+------------+------+-----+------------------------------+-"
                   "--------------+---------------+");
    Serial.println("| (No active medication schedule configured for today)     "
                   "                                   |");
    Serial.println("+------------+------+-----+------------------------------+-"
                   "--------------+---------------+");
    return;
  }

  // Load history to see if taken today
  String histContent = readStorageFile(FILE_HISTORY);
#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument histDoc;
#else
  DynamicJsonDocument histDoc(4096);
#endif
  deserializeJson(histDoc, histContent);

  int histCount = histDoc["history"].is<JsonArray>()
                      ? histDoc["history"].as<JsonArray>().size()
                      : 0;
  bool matchedHistory[histCount > 0 ? histCount : 1];
  for (int k = 0; k < histCount; k++)
    matchedHistory[k] = false;

  struct DisplayRow {
    String time;
    int slot;
    int qty;
    String medicine;
    String food;
    int minutes;
  };
  std::vector<DisplayRow> rows;

  for (JsonObject item : doc["schedule"].as<JsonArray>()) {
    DisplayRow r;
    r.time = item["time"] | item["t"] | "--:--";
    r.slot = item["slot"] | item["s"] | 0;
    r.qty = item["qty"] | item["q"] | 1;
    String med = item["medicine"] | item["med"] | "";
    if (med.length() == 0 && r.slot >= 1 && r.slot <= NUM_SLOTS) {
      med = gSlots[r.slot - 1].drugName;
    }
    r.medicine = med;
    r.food = "-";
    if (item.containsKey("before_food")) {
      r.food = item["before_food"].as<bool>() ? "Before Food" : "After Food";
    }
    r.minutes = (r.time.length() >= 5) ? (r.time.substring(0, 2).toInt() * 60 +
                                          r.time.substring(3, 5).toInt())
                                       : 0;
    rows.push_back(r);
  }

  // Sort rows chronologically by time, then by slot
  std::sort(rows.begin(), rows.end(),
            [](const DisplayRow &a, const DisplayRow &b) {
              if (a.minutes != b.minutes)
                return a.minutes < b.minutes;
              return a.slot < b.slot;
            });

  // Calculate current/closest meal minute
  int nowMinutes = -1;
  int closestMealMinutes = -1;
  int minDistance = 24 * 60 + 1;

  if (isTimeSynced) {
    String nowTime = getCurrentTimeHHMM();
    if (nowTime.length() >= 5) {
      nowMinutes = nowTime.substring(0, 2).toInt() * 60 +
                   nowTime.substring(3, 5).toInt();
      for (const auto &r : rows) {
        int direct = abs(r.minutes - nowMinutes);
        int dist = (direct > 12 * 60) ? (24 * 60 - direct) : direct;
        if (dist < minDistance) {
          minDistance = dist;
          closestMealMinutes = r.minutes;
        }
      }
    }
  }

  Serial.println("+------------+------+-----+------------------------------+---"
                 "------------+---------------+");
  Serial.println("| Time       | Slot | Qty | Medicine                     | "
                 "Food Relation | Status        |");
  Serial.println("+------------+------+-----+------------------------------+---"
                 "------------+---------------+");

  for (const auto &r : rows) {
    String statusStr = "[PENDING]";
    int matchedIdx = -1;

    if (histDoc["history"].is<JsonArray>()) {
      JsonArray hArr = histDoc["history"].as<JsonArray>();

      // 1st Pass: Match exact scheduled time
      for (int k = 0; k < histCount; k++) {
        if (matchedHistory[k])
          continue;
        JsonObject h = hArr[k];
        String hDate = h["date"] | "";
        int hSlot = h["slot"] | 0;
        String hType = h["type"] | "";
        String hSched = h["sched_time"] | "";
        if (hDate == todayDate && hSlot == r.slot && hType == "meal" &&
            hSched == r.time) {
          matchedIdx = k;
          break;
        }
      }

      // 2nd Pass: Match first available meal intake for this slot today without
      // explicit sched_time
      if (matchedIdx == -1) {
        for (int k = 0; k < histCount; k++) {
          if (matchedHistory[k])
            continue;
          JsonObject h = hArr[k];
          String hDate = h["date"] | "";
          int hSlot = h["slot"] | 0;
          String hType = h["type"] | "";
          String hSched = h["sched_time"] | "";
          if (hDate == todayDate && hSlot == r.slot && hType == "meal" &&
              hSched.length() == 0) {
            matchedIdx = k;
            break;
          }
        }
      }
    }

    if (matchedIdx != -1) {
      matchedHistory[matchedIdx] = true;
      String hTime =
          histDoc["history"].as<JsonArray>()[matchedIdx]["time"] | "";
      statusStr = "[TAKEN] (" + hTime + ")";
    } else {
      if (nowMinutes >= 0) {
        if (r.minutes == closestMealMinutes) {
          statusStr = "[CURRENT]";
        } else if (r.minutes > nowMinutes) {
          statusStr = "[PENDING]";
        } else {
          statusStr = "[--]";
        }
      } else {
        statusStr = "[PENDING]";
      }
    }

    Serial.printf("|   %-8s |  %2d  |  %2d | %-28s | %-13s | %-13s |\n",
                  r.time.c_str(), r.slot, r.qty,
                  safeTruncateUtf8(r.medicine, 28).c_str(), r.food.c_str(),
                  statusStr.c_str());
  }
  Serial.println("+------------+------+-----+------------------------------+---"
                 "------------+---------------+");
}

void printSerialHistory() {
  Serial.println("[7-DAY INTAKE HISTORY]");
  String content = readStorageFile(FILE_HISTORY);
#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
#else
  DynamicJsonDocument doc(4096);
#endif
  DeserializationError err = deserializeJson(doc, content);
  if (err || !doc["history"].is<JsonArray>() ||
      doc["history"].as<JsonArray>().size() == 0) {
    Serial.println("+------------+-------+------+-----+------------------------"
                   "------+------+---------+");
    Serial.println("| (No intake history recorded in the last 7 days)          "
                   "                            |");
    Serial.println("+------------+-------+------+-----+------------------------"
                   "------+------+---------+");
    return;
  }

  Serial.println("+------------+-------+------+-----+--------------------------"
                 "----+------+---------+");
  Serial.println("| Date       | Time  | Slot | Qty | Medicine                 "
                 "    | Type | Status  |");
  Serial.println("+------------+-------+------+-----+--------------------------"
                 "----+------+---------+");
  JsonArray arr = doc["history"].as<JsonArray>();
  for (int i = arr.size() - 1; i >= 0; i--) {
    JsonObject h = arr[i];
    String d = h["date"] | "";
    String t = h["time"] | "";
    int s = h["slot"] | 0;
    int q = h["qty"] | 1;
    String med = h["med"] | "";
    String type = h["type"] | "meal";
    String st = h["status"] | "taken";
    Serial.printf("| %-10s | %-5s |  %2d  |  %2d | %-28s | %-4s | %-7s |\n",
                  d.c_str(), t.c_str(), s, q, safeTruncateUtf8(med, 28).c_str(),
                  type.c_str(), st.c_str());
  }
  Serial.println("+------------+-------+------+-----+--------------------------"
                 "----+------+---------+");
}

void printAllSummary() {
  Serial.println("==================================================");
  Serial.println("  MeDisP - Smart Pill Dispenser (Data Summary)    ");
  Serial.println("==================================================");
  Serial.printf("Device ID     : %s\n", DEVICE_ID);
  Serial.println("Firmware      : 2.2.0");
  Serial.printf("Storage       : %s\n",
                isSdMounted ? "MicroSD Card (SPI)" : "LittleFS (Internal)");
  Serial.printf("Clock Time    : %s (Epoch: %lu, Synced: %s)\n",
                getFormattedTime().c_str(), getSystemEpoch(),
                isTimeSynced ? "YES" : "NO");
  Serial.printf("Free Heap     : %u bytes\n", ESP.getFreeHeap());
  Serial.printf("BLE Client    : %s\n\n",
                isBleClientConnected ? "CONNECTED" : "DISCONNECTED");

  printSerialSlots();
  Serial.println();
  printSerialSchedule();
  Serial.println("==================================================");
}

void handleSerialCli() {
  if (!Serial.available())
    return;

  String line = Serial.readStringUntil('\n');
  line.trim();
  if (line.length() == 0)
    return;

  Serial.println("\n>> CLI: " + line);

  if (line == "help") {
    Serial.println("Available Debug Commands:");
    Serial.println("  get all              - View all dispenser state summary");
    Serial.println("  status               - View device status JSON");
    Serial.println("  slots                - View tabular list of all 6 slots");
    Serial.println("  schedule             - View today's active schedule & "
                   "intake status");
    Serial.println("  history              - View 7-day intake history log");
    Serial.println(
        "  time                 - View current system clock & epoch");
    Serial.println(
        "  dispense <slot> [qty]- Test dispense on slot (1-6, optional qty)");
    Serial.println(
        "  set slot <1-6> <med> [rem] [prn|meal] - Configure slot medication");
    Serial.println(
        "  set prn <slot> <true|false>           - Toggle PRN mode for slot");
    Serial.println("  req prn              - Force refresh Nextion PRN page");
    Serial.println("  req daily            - Force refresh Nextion Daily page");
    Serial.println(
        "  req timeline         - Force refresh Nextion Timeline page");
    Serial.println(
        "  up / down            - Test Nextion scroll up/down for active page");
    Serial.println("  prn up / prn down    - Test PRN pagination scroll");
    Serial.println("  timeline up / down   - Test Timeline pagination scroll");
    Serial.println("  daily up / down      - Test Daily pagination scroll");
    Serial.println("  prn 1 / 2 / 3        - Test PRN item selection");
    Serial.println("  back                 - Test back button to PRN page");
    Serial.println("  sync_time <sec>      - Manually set epoch timestamp");
    Serial.println("  clear data           - Wipe slots, schedule & history");
    Serial.println("  reboot               - Restart ESP32");
  } else if (line == "get all" || line == "all") {
    printAllSummary();
  } else if (line == "status" || line == "get status") {
    Serial.println(buildDeviceStatusJson());
  } else if (line == "slots" || line == "get slots") {
    printSerialSlots();
  } else if (line == "schedule" || line == "get schedule") {
    printSerialSchedule();
  } else if (line == "history" || line == "get history" || line == "logs") {
    printSerialHistory();
  } else if (line == "time" || line == "get time") {
    Serial.printf("Current Time: %s (Epoch: %lu, Synced: %s)\n",
                  getFormattedTime().c_str(), getSystemEpoch(),
                  isTimeSynced ? "YES" : "NO");
  } else if (line.startsWith("dispense ")) {
    String paramStr = line.substring(9);
    paramStr.trim();
    int spaceIdx = paramStr.indexOf(' ');
    int slot = 0;
    int qty = 1;
    if (spaceIdx > 0) {
      slot = paramStr.substring(0, spaceIdx).toInt();
      qty = paramStr.substring(spaceIdx + 1).toInt();
      if (qty <= 0)
        qty = 1;
    } else {
      slot = paramStr.toInt();
      if (slot >= 1 && slot <= NUM_SLOTS && gSlots[slot - 1].isPrn &&
          gSlots[slot - 1].prnQty > 1) {
        qty = gSlots[slot - 1].prnQty;
      }
    }
    if (slot < 1 || slot > NUM_SLOTS) {
      Serial.println(
          "[CLI] Invalid slot number (1-6). Usage: dispense <slot> [qty]");
      return;
    }
    String err;
    bool isSched = !gSlots[slot - 1].isPrn;
    if (executeDispense(slot, qty, gSlots[slot - 1].drugName, "CLI_MANUAL", err,
                        isSched)) {
      Serial.printf("[CLI] Dispense successful for Slot %d (%d %s) [%s]!\n",
                    slot, qty, qty > 1 ? "pills" : "pill",
                    isSched ? "Meal" : "PRN");
    } else {
      Serial.printf("[CLI] Dispense failed for Slot %d: %s\n", slot,
                    err.c_str());
    }
  } else if (line.startsWith("set slot ")) {
    // Usage: set slot <1-6> <drug_name> [remaining] [prn|meal]
    String param = line.substring(9);
    param.trim();
    int s1 = param.indexOf(' ');
    if (s1 > 0) {
      int sNum = param.substring(0, s1).toInt();
      String rest = param.substring(s1 + 1);
      rest.trim();
      int s2 = rest.indexOf(' ');
      String drug = rest;
      int rem = 20;
      bool isPrn = true;
      if (s2 > 0) {
        drug = rest.substring(0, s2);
        String rest2 = rest.substring(s2 + 1);
        rest2.trim();
        int s3 = rest2.indexOf(' ');
        if (s3 > 0) {
          rem = rest2.substring(0, s3).toInt();
          String t = rest2.substring(s3 + 1);
          t.trim();
          t.toLowerCase();
          isPrn = (t == "prn" || t == "true" || t == "1");
        } else {
          rem = rest2.toInt();
        }
      }
      if (sNum >= 1 && sNum <= NUM_SLOTS) {
        int idx = sNum - 1;
        gSlots[idx].drugName = drug;
        gSlots[idx].remaining = rem;
        gSlots[idx].isPrn = isPrn;
        gSlots[idx].minIntervalHours = 4;
        gSlots[idx].prnQty = 1;
        gSlots[idx].maxDosesPerDay = 4;
        saveSlotsToStorage();
        Serial.printf("[CLI] Slot %d configured: Drug='%s', Rem=%d, isPrn=%d\n",
                      sNum, drug.c_str(), rem, isPrn ? 1 : 0);
        refreshCurrentNextionPage();
      } else {
        Serial.println("[CLI] Invalid slot number (1-6)");
      }
    } else {
      Serial.println(
          "[CLI] Usage: set slot <1-6> <drug_name> [remaining] [prn|meal]");
    }
  } else if (line.startsWith("set prn ")) {
    // Usage: set prn <slot> <true|false>
    String param = line.substring(8);
    param.trim();
    int sp = param.indexOf(' ');
    if (sp > 0) {
      int sNum = param.substring(0, sp).toInt();
      String v = param.substring(sp + 1);
      v.trim();
      v.toLowerCase();
      bool isP = (v == "true" || v == "1" || v == "prn" || v == "yes");
      if (sNum >= 1 && sNum <= NUM_SLOTS) {
        gSlots[sNum - 1].isPrn = isP;
        saveSlotsToStorage();
        Serial.printf("[CLI] Slot %d isPrn set to %s\n", sNum,
                      isP ? "TRUE" : "FALSE");
        refreshCurrentNextionPage();
      }
    }
  } else if (line == "req prn") {
    Serial.println("[CLI] Forcing REQ:PRN refresh...");
    handleReqPrn();
  } else if (line == "req daily") {
    Serial.println("[CLI] Forcing REQ:DAILY refresh...");
    handleReqDaily(false);
  } else if (line == "req timeline") {
    Serial.println("[CLI] Forcing REQ:TIMELINE refresh...");
    handleReqTimeline(false);
  } else if (line == "up" || line == "down") {
    if (gCurrentNextionPage == "Timeline") {
      processNextionMessage(line == "up" ? "CMD:TIMELINE_UP"
                                         : "CMD:TIMELINE_DOWN");
    } else if (gCurrentNextionPage == "Daily") {
      processNextionMessage(line == "up" ? "CMD:DAILY_UP" : "CMD:DAILY_DOWN");
    } else {
      processNextionMessage(line == "up" ? "CMD:PRN_UP" : "CMD:PRN_DOWN");
    }
  } else if (line == "prn up") {
    processNextionMessage("CMD:PRN_UP");
  } else if (line == "prn down") {
    processNextionMessage("CMD:PRN_DOWN");
  } else if (line == "timeline up") {
    processNextionMessage("CMD:TIMELINE_UP");
  } else if (line == "timeline down") {
    processNextionMessage("CMD:TIMELINE_DOWN");
  } else if (line == "daily up") {
    processNextionMessage("CMD:DAILY_UP");
  } else if (line == "daily down") {
    processNextionMessage("CMD:DAILY_DOWN");
  } else if (line == "prn 1" || line == "prn 2" || line == "prn 3") {
    String sel = "CMD:PRN_SELECT_" + line.substring(4);
    processNextionMessage(sel);
  } else if (line == "back") {
    processNextionMessage("CMD:BACK");
  } else if (line == "take pill" || line == "take" || line == "dispense") {
    Serial.println("[CLI] Simulating Take Pill trigger...");
    if (gCurrentNextionPage == "PRNDetail") {
      processNextionMessage("CMD:PRN_TAKE");
      processNextionMessage("CMD:CONFIRM");
    } else {
      processNextionMessage("CMD:DAILY_TAKE");
      processNextionMessage("CMD:CONFIRM");
    }
  } else if (line.startsWith("prn status ")) {
    int s = line.substring(11).toInt();
    if (s >= 1 && s <= NUM_SLOTS) {
      PrnStatus st = checkPrnStatus(s);
      Serial.printf("[PRN STATUS] Slot %d (%s):\n", s,
                    gSlots[s - 1].drugName.c_str());
      Serial.printf("  Ready: %s (Reason: %s, Btn: %s)\n",
                    st.isReady ? "YES" : "NO", st.reason.c_str(),
                    st.buttonText.c_str());
      Serial.printf("  Remaining: %d, Taken Today: %d/%d\n", st.remaining,
                    st.takenToday, st.maxDoses);
      Serial.printf("  Last Intake: %s, Next Allowed: %s\n",
                    st.lastTakenTime.c_str(), st.nextAllowedTime.c_str());
      Serial.printf("  Indication: %s\n", getDrugIndication(s - 1).c_str());
    } else {
      Serial.println("[CLI] Invalid slot number (1-6)");
    }
  } else if (line.startsWith("sync_time ")) {
    unsigned long epoch = strtoul(line.substring(10).c_str(), nullptr, 10);
    setSystemEpoch(epoch);
  } else if (line == "clear data") {
    if (pActiveFS) {
      pActiveFS->remove(FILE_SLOTS);
      pActiveFS->remove(FILE_SCHEDULE);
      pActiveFS->remove(FILE_HISTORY);
    }
    initDefaultSlots();
    currentScheduleJson = "{\"device_id\":\"" DEVICE_ID "\",\"schedule\":[]}";
    writeStorageFile(FILE_SCHEDULE, currentScheduleJson);
    saveSlotsToStorage();
    if (pConfigChar)
      pConfigChar->setValue(currentScheduleJson.c_str());
    if (pStatusChar)
      pStatusChar->setValue(buildDeviceStatusJson().c_str());
    sendBleEvent("{\"event\":\"DISPENSER_RESET\",\"status\":\"success\"}");
    Serial.println("[CLI] Slots, schedule & history cleared (Factory Reset).");
    handleReqDaily(true); // PUSH CLEARED SCREEN IMMEDIATELY
  } else if (line.startsWith("nextion ")) {
    String ncmd = line.substring(8);
    ncmd.trim();
    if (ncmd == "test") {
      Serial.println("[CLI] Sending test pattern to Nextion...");
      nextionSend("page Daily");
      delay(30);
      nextionSetText("tTime", "88:88");
      nextionSetText("t0", "99:99");
      nextionSetText("tQ0", "TEST MODE | ACTIVE");
      nextionSetText("t1", "TEST: CONNECTED!");
      nextionSetText("tQ1", "OK");
      nextionSetText("t2", "ESP32 TO NEXTION");
      nextionSetText("tQ2", "PASSED");
      Serial.println("[CLI] Test pattern sent!");
    } else {
      nextionSend(ncmd);
    }
  } else if (line == "reboot") {
    Serial.println("[CLI] Rebooting ESP32...");
    delay(300);
    ESP.restart();
  } else {
    Serial.println("Unknown command! Type 'help' for options.");
  }
}

// ============================================================================
// Setup and Loop
// ============================================================================

// ============================================================================
// Nextion Display HMI Subsystem (MeDisP HMI v1.1 - White BG, Modals &
// Scrolling)
// ============================================================================
// Direct pin assignment to physical pins labeled RX and TX on the board
static const int NEXTION_RX_PIN = RX; // Physical pin labeled RX on the board
static const int NEXTION_TX_PIN = TX; // Physical pin labeled TX on the board

#define NEXTION_BAUD 9600

// Colors in RGB565
#define COLOR_WHITE 65535         // 0xFFFF
#define COLOR_NAVY_HEADER 9308    // 0x245C (Main pages)
#define COLOR_ORANGE_ALERT 64512  // 0xFC00 (Alert page)
#define COLOR_GREEN_SUCCESS 2016  // 0x07E0 (Success page)
#define COLOR_SLATE_CONFIRM 25388 // 0x632C (Confirm modal)
#define COLOR_BLUE_DISPENSE 11126 // 0x2B76 (Dispensing modal)

// Use core Serial1 instance (universal hardware UART across all ESP32
// architectures)
#if ARDUINO_USB_CDC_ON_BOOT
#define NextionSerial Serial0
#else
#define NextionSerial Serial1
#endif

String gCurrentNextionPage = "Daily";
static int gSelectedPrnSlot =
    3; // Currently selected PRN slot (defaults to first PRN slot 3)
static bool gIsConfirmingPrn =
    false; // true if confirming PRN, false if confirming scheduled meal
static bool gLastDispensedWasPrn =
    false; // Tracks if PRN was just dispensed (prevents accidental Daily jump)
static unsigned long gLastDispenseMs = 0;
static String gActiveMealTime = "";
static bool gActiveBeforeFood = false;

// Pagination Offsets (for replacing overflow medicines >3 on screen)
static int gDailyOffset = 0;    // Paging for Daily when meal has >3 drugs
static int gPrnOffset = 0;      // Paging for PRN when >3 drugs
static int gTimelineOffset = 0; // Paging for Timeline when >3 records

// ----------------------------------------------------------------------------
// High-Speed Nextion Serial Primitives (Zero-delay, Direct Buffer Streaming)
// ----------------------------------------------------------------------------
void nextionSend(const String &cmd) {
  NextionSerial.print(cmd);
  NextionSerial.write(0xFF);
  NextionSerial.write(0xFF);
  NextionSerial.write(0xFF);
  Serial.printf("[NEXTION SEND] %s\n", cmd.c_str());
}

void nextionSetText(const char *comp, const String &val) {
  String sanitized = val;
  sanitized.replace('"', '\'');
  NextionSerial.print(comp);
  NextionSerial.print(".txt=\"");
  NextionSerial.print(sanitized);
  NextionSerial.print("\"");
  NextionSerial.write(0xFF);
  NextionSerial.write(0xFF);
  NextionSerial.write(0xFF);
  Serial.printf("[NEXTION SEND] %s.txt=\"%s\"\n", comp, sanitized.c_str());
}

void nextionSetVisible(const char *comp, bool vis) {
  NextionSerial.print("vis ");
  NextionSerial.print(comp);
  NextionSerial.print(vis ? ",1" : ",0");
  NextionSerial.write(0xFF);
  NextionSerial.write(0xFF);
  NextionSerial.write(0xFF);
  Serial.printf("[NEXTION SEND] vis %s,%d\n", comp, vis ? 1 : 0);
}

void nextionRef(const char *comp) {
  NextionSerial.print("ref ");
  NextionSerial.print(comp);
  NextionSerial.write(0xFF);
  NextionSerial.write(0xFF);
  NextionSerial.write(0xFF);
}

inline void nextionSetText(const String &comp, const String &val) {
  nextionSetText(comp.c_str(), val);
}
inline void nextionSetVisible(const String &comp, bool vis) {
  nextionSetVisible(comp.c_str(), vis);
}
inline void nextionRef(const String &comp) { nextionRef(comp.c_str()); }

void nextionFlush() { NextionSerial.flush(); }

void nextionSetPage(const char *pageName) {
  gCurrentNextionPage = pageName;
  nextionSend(String("page ") + pageName);
}

void nextionSetNavTabsVisible(bool visible) {
  nextionSetVisible("bDailypage", visible);
  nextionSetVisible("bPRNpage", visible);
  nextionSetVisible("bTimelinepage", visible);
}

String getMealNameFromTime(const String &timeStr) {
  if (timeStr.length() < 2)
    return "Meal";
  int hour = timeStr.substring(0, 2).toInt();
  if (hour >= 5 && hour < 11)
    return "Breakfast";
  if (hour >= 11 && hour < 15)
    return "Lunch";
  if (hour >= 15 && hour < 20)
    return "Dinner";
  return "Bedtime";
}

// ----------------------------------------------------------------------------
// Helper: Check if all scheduled doses for a specific meal time were taken
// today
// ----------------------------------------------------------------------------
bool isScheduledMealCompletedToday(const String &mealTime) {
  if (mealTime.length() < 5)
    return false;
  String todayDate = getCurrentDateStr(0);

  String schedContent = readStorageFile(FILE_SCHEDULE);
  if (schedContent.length() == 0)
    schedContent = currentScheduleJson;
#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument sDoc;
#else
  DynamicJsonDocument sDoc(2048);
#endif
  if (deserializeJson(sDoc, schedContent))
    return false;
  if (!sDoc["schedule"].is<JsonArray>())
    return false;

  std::vector<int> requiredSlots;
  for (JsonObject item : sDoc["schedule"].as<JsonArray>()) {
    String t = item["time"] | item["t"] | "";
    if (t == mealTime) {
      int s = item["slot"] | item["s"] | 0;
      if (s >= 1 && s <= NUM_SLOTS) {
        requiredSlots.push_back(s);
      }
    }
  }

  if (requiredSlots.empty())
    return false;

  String histContent = readStorageFile(FILE_HISTORY);
  if (histContent.length() == 0)
    return false;
#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument hDoc;
#else
  DynamicJsonDocument hDoc(4096);
#endif
  if (deserializeJson(hDoc, histContent))
    return false;
  if (!hDoc["history"].is<JsonArray>())
    return false;

  for (int reqSlot : requiredSlots) {
    bool slotTaken = false;
    for (JsonObject r : hDoc["history"].as<JsonArray>()) {
      int s = r["slot"] | 0;
      String d = r["date"] | "";
      String st = r["sched_time"] | "";
      String status = r["status"] | "";
      String type = r["type"] | "";
      if (s == reqSlot &&
          (d == todayDate || d.length() == 0 || d == "1970-01-01") &&
          (status.equalsIgnoreCase("taken") ||
           status.equalsIgnoreCase("TAKEN")) &&
          (type.equalsIgnoreCase("meal") || type.equalsIgnoreCase("MEAL"))) {
        if (st.length() == 0 || st == mealTime) {
          slotTaken = true;
          break;
        }
      }
    }
    if (!slotTaken)
      return false;
  }

  return true;
}

// ----------------------------------------------------------------------------
// PRN Safety & Availability Evaluator
// ----------------------------------------------------------------------------
PrnStatus checkPrnStatus(int slot) {
  PrnStatus st;
  st.isReady = false;
  st.remaining = 0;
  st.takenToday = 0;
  st.maxDoses = 4;
  st.minIntervalHours = 4;
  st.minutesUntilNextDose = 0;
  st.lastTakenTime = "None today";
  st.nextAllowedTime = "Available now";
  st.reason = "Ready to dispense";
  st.buttonText = "TAKE MEDICINE";

  if (slot < 1 || slot > NUM_SLOTS) {
    st.reason = "Invalid slot";
    st.buttonText = "NOT READY";
    return st;
  }

  int idx = slot - 1;
  st.remaining = gSlots[idx].remaining;
  st.maxDoses = gSlots[idx].maxDosesPerDay > 0 ? gSlots[idx].maxDosesPerDay : 4;
  st.minIntervalHours =
      gSlots[idx].minIntervalHours > 0 ? gSlots[idx].minIntervalHours : 4;
  st.takenToday = countPrnIntakesToday(slot);

  // 1. Find last intake time for this slot today from history
  String todayDate = getCurrentDateStr(0);
  String content = readStorageFile(FILE_HISTORY);
  int latestIntakeMin = -1;
  String lastTimeStr = "";
  if (content.length() > 0) {
#if ARDUINOJSON_VERSION_MAJOR >= 7
    JsonDocument doc;
#else
    DynamicJsonDocument doc(4096);
#endif
    if (!deserializeJson(doc, content) && doc["history"].is<JsonArray>()) {
      for (JsonObject r : doc["history"].as<JsonArray>()) {
        int s = r["slot"] | 0;
        String d = r["date"] | "";
        String type = r["type"] | "";
        String status = r["status"] | "";
        if (s == slot && d == todayDate && (type == "prn" || type == "PRN") &&
            (status == "taken" || status == "TAKEN")) {
          String t = r["time"] | "";
          if (t.length() >= 5) {
            int m = t.substring(0, 2).toInt() * 60 + t.substring(3, 5).toInt();
            if (m > latestIntakeMin) {
              latestIntakeMin = m;
              lastTimeStr = t;
            }
          }
        }
      }
    }
  }

  int intervalMin = st.minIntervalHours * 60;
  if (latestIntakeMin >= 0) {
    st.lastTakenTime = lastTimeStr;
    int nextMin = latestIntakeMin + intervalMin;
    int nextH = (nextMin / 60) % 24;
    int nextM = nextMin % 60;
    char nextBuf[16];
    snprintf(nextBuf, sizeof(nextBuf), "%02d:%02d", nextH, nextM);
    st.nextAllowedTime = String(nextBuf);
  } else {
    st.lastTakenTime = "None today";
    st.nextAllowedTime = "Available now";
  }

  // 2. Stock check
  int qty = gSlots[idx].prnQty > 0 ? gSlots[idx].prnQty : 1;
  if (st.remaining < qty) {
    st.isReady = false;
    st.reason = "Out of medication";
    st.buttonText = "OUT OF STOCK";
    st.nextAllowedTime = "Out of stock";
    return st;
  }

  // 3. Daily limit check
  if (st.takenToday >= st.maxDoses) {
    st.isReady = false;
    st.reason = "Daily limit reached (" + String(st.takenToday) + "/" +
                String(st.maxDoses) + ")";
    st.buttonText = "LIMIT REACHED";
    st.nextAllowedTime = "Tomorrow";
    return st;
  }

  // 4. Interval / Cooldown check
  if (latestIntakeMin >= 0 && isTimeSynced) {
    String nowTime = getCurrentTimeHHMM();
    int nowMin = (nowTime.length() >= 5)
                     ? (nowTime.substring(0, 2).toInt() * 60 +
                        nowTime.substring(3, 5).toInt())
                     : 0;
    int diff = nowMin - latestIntakeMin;
    if (diff >= 0 && diff < intervalMin) {
      st.isReady = false;
      st.minutesUntilNextDose = intervalMin - diff;
      int remHours = st.minutesUntilNextDose / 60;
      int remMins = st.minutesUntilNextDose % 60;
      String waitStr = (remHours > 0)
                           ? (String(remHours) + "h " + String(remMins) + "m")
                           : (String(remMins) + " mins");
      st.reason = "Wait " + waitStr;
      st.buttonText = "COOLDOWN (" + waitStr + ")";
      st.nextAllowedTime = st.nextAllowedTime + " (Wait " + waitStr + ")";
      return st;
    }
  }

  st.isReady = true;
  st.reason = "Ready to dispense";
  st.buttonText =
      "TAKE MEDICINE (" + String(qty) + (qty > 1 ? " TABS)" : " TAB)");
  st.nextAllowedTime = "Available now";
  return st;
}

// ----------------------------------------------------------------------------
// 1. REQ:DAILY - Populate Daily Scheduled Meals with Accurate Current Meal
// ----------------------------------------------------------------------------
void handleReqDaily(bool resetOffset) {
  gCurrentNextionPage = "Daily";
  if (resetOffset)
    gDailyOffset = 0;

  nextionSetText("tTime", getCurrentTimeHHMM());

  String schedContent = readStorageFile(FILE_SCHEDULE);
  if (schedContent.length() == 0)
    schedContent = currentScheduleJson;

#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
#else
  DynamicJsonDocument doc(2048);
#endif
  deserializeJson(doc, schedContent);

  // 1. Collect all unique scheduled meal times
  struct MealTimeInfo {
    String time;
    int minutes;
    bool isBefore;
    bool completed;
  };
  std::vector<MealTimeInfo> uniqueMeals;

  if (doc["schedule"].is<JsonArray>()) {
    for (JsonObject item : doc["schedule"].as<JsonArray>()) {
      String t = item["time"] | item["t"] | "";
      if (t.length() >= 5) {
        bool exists = false;
        for (const auto &m : uniqueMeals) {
          if (m.time == t) {
            exists = true;
            break;
          }
        }
        if (!exists) {
          MealTimeInfo mti;
          mti.time = t;
          mti.minutes =
              t.substring(0, 2).toInt() * 60 + t.substring(3, 5).toInt();
          mti.isBefore = item.containsKey("before_food")
                             ? item["before_food"].as<bool>()
                             : true;
          mti.completed = isScheduledMealCompletedToday(t);
          uniqueMeals.push_back(mti);
        }
      }
    }
  }

  // Sort meals chronologically by time
  std::sort(uniqueMeals.begin(), uniqueMeals.end(),
            [](const MealTimeInfo &a, const MealTimeInfo &b) {
              return a.minutes < b.minutes;
            });

  // 2. Select Current Meal based on circular 24-hour distance to current time
  // (matching Flutter MealSchedule.current)
  String targetTime = "";
  bool isBefore = false;
  bool isTargetCompleted = false;

  if (!uniqueMeals.empty()) {
    String nowTime = getCurrentTimeHHMM();
    int currentMinute = 12 * 60; // 12:00 default
    if (nowTime.length() >= 5) {
      currentMinute = nowTime.substring(0, 2).toInt() * 60 +
                      nowTime.substring(3, 5).toInt();
    }

    int closestDistance = 24 * 60 + 1;
    MealTimeInfo *picked = nullptr;
    for (auto &m : uniqueMeals) {
      int direct = abs(m.minutes - currentMinute);
      int distance = direct > 12 * 60 ? (24 * 60 - direct) : direct;
      if (distance < closestDistance) {
        closestDistance = distance;
        picked = &m;
      }
    }
    if (picked) {
      targetTime = picked->time;
      isBefore = picked->isBefore;
      isTargetCompleted = picked->completed;
    }
  }

  // 3. Render Nextion display components
  if (targetTime.length() > 0) {
    gActiveMealTime = targetTime;
    gActiveBeforeFood = isBefore;

    // Header items matching Flutter current meal
    nextionSetText("tNextDose",
                   isTargetCompleted ? "Daily dose (Taken)" : "Daily dose");
    nextionSetText("tNextTime", targetTime);
    nextionSetText("tMeal", getMealNameFromTime(targetTime));
    nextionSetText("tBeforeAfter", isBefore ? "BEFORE MEAL" : "AFTER MEAL");

    struct DrugDoseRow {
      String name;
      int qty;
      int slot;
    };
    std::vector<DrugDoseRow> mealPills;

    for (JsonObject item : doc["schedule"].as<JsonArray>()) {
      String t = item["time"] | item["t"] | "";
      if (t == targetTime) {
        int s = item["slot"] | item["s"] | 1;
        String med = item["medicine"] | item["med"] | "";
        if (med.length() == 0 && s >= 1 && s <= NUM_SLOTS)
          med = gSlots[s - 1].drugName;
        int q = item["qty"] | item["q"] | 1;
        DrugDoseRow row;
        row.name = formatNextionDrugName(med, s);
        row.qty = q;
        row.slot = s;
        mealPills.push_back(row);
      }
    }

    int totalPills = mealPills.size();
    if (gDailyOffset >= totalPills) {
      gDailyOffset = (totalPills > 0) ? (totalPills - 1) : 0;
    }
    if (gDailyOffset < 0)
      gDailyOffset = 0;

    for (int r = 0; r < 3; r++) {
      int idx = gDailyOffset + r;
      String tName = "t" + String(r);
      String tQName = "tQ" + String(r);
      if (idx < totalPills) {
        nextionSetText(tName, mealPills[idx].name);
        int q = mealPills[idx].qty;
        nextionSetText(tQName, String(q) + (q > 1 ? " tablets" : " tablet"));
      } else {
        nextionSetText(tName, "");
        nextionSetText(tQName, "");
      }
    }

    if (isTargetCompleted) {
      nextionSetText("bDispense", "ALREADY TAKEN");
      nextionSend("bDispense.bco=50712"); // Disabled gray
      nextionSend("bDispense.pco=65535");
      nextionSend("tsw bDispense,0"); // DISABLE TOUCH (cannot be clicked)
      nextionSetVisible("bDispense", true);
    } else if (totalPills > 0) {
      nextionSetText("bDispense", "TAKE MEDICINE");
      nextionSend("bDispense.bco=9308"); // Active teal
      nextionSend("bDispense.pco=65535");
      nextionSend("tsw bDispense,1"); // ENABLE TOUCH (pressable)
      nextionSetVisible("bDispense", true);
    } else {
      nextionSetText("bDispense", "NO MEDS");
      nextionSend("bDispense.bco=50712"); // Disabled gray
      nextionSend("bDispense.pco=65535");
      nextionSend("tsw bDispense,0"); // DISABLE TOUCH (cannot be clicked)
      nextionSetVisible("bDispense", true);
    }

    // Overflow scrolling controls for >3 drugs (replace overflow rows)
    if (totalPills > 3) {
      if (gDailyOffset > 0) {
        nextionSetText("bScrollup", "Up");
        nextionSend("bScrollup.bco=50712");
        nextionSend("bScrollup.pco=65535");
        nextionSetVisible("bScrollup", true);
        nextionSend("tsw bScrollup,1");
        nextionRef("bScrollup");
      } else {
        nextionSetVisible("bScrollup", false);
        nextionSend("tsw bScrollup,0");
      }
      if ((gDailyOffset + 3) < totalPills) {
        nextionSetText("bScrolldown", "Down");
        nextionSend("bScrolldown.bco=50712");
        nextionSend("bScrolldown.pco=65535");
        nextionSetVisible("bScrolldown", true);
        nextionSend("tsw bScrolldown,1");
        nextionRef("bScrolldown");
      } else {
        nextionSetVisible("bScrolldown", false);
        nextionSend("tsw bScrolldown,0");
      }
    } else {
      nextionSetVisible("bScrollup", false);
      nextionSetVisible("bScrolldown", false);
      nextionSend("tsw bScrollup,0");
      nextionSend("tsw bScrolldown,0");
    }
  } else {
    // No schedule configured
    gActiveMealTime = "";
    nextionSetText("tNextDose", "Daily dose");
    nextionSetText("tNextTime", "--:--");
    nextionSetText("tMeal", "No schedule");
    nextionSetText("tBeforeAfter", "");
    nextionSetText("t0", "No medication configured");
    nextionSetText("tQ0", "");
    nextionSetText("t1", "See PRN for as-needed meds");
    nextionSetText("tQ1", "");
    nextionSetText("t2", "");
    nextionSetText("tQ2", "");
    nextionSetText("bDispense", "NO MEDS");
    nextionSend("bDispense.bco=50712");
    nextionSend("bDispense.pco=65535");
    nextionSend("tsw bDispense,0");
    nextionSetVisible("bDispense", true);
    nextionSetVisible("bScrollup", false);
    nextionSetVisible("bScrolldown", false);
    nextionSend("tsw bScrollup,0");
    nextionSend("tsw bScrolldown,0");
  }

  // Force component redrawing on Nextion display
  nextionRef("tNextDose");
  nextionRef("tNextTime");
  nextionRef("tMeal");
  nextionRef("tBeforeAfter");
  nextionRef("t0");
  nextionRef("tQ0");
  nextionRef("t1");
  nextionRef("tQ1");
  nextionRef("t2");
  nextionRef("tQ2");
  nextionRef("bDispense");
  nextionFlush();
}

// ----------------------------------------------------------------------------
// 2. REQ:PRN - Populate PRN Medication List with Dynamic Row Touch & Pagination
// ----------------------------------------------------------------------------
void handleReqPrn() {
  gCurrentNextionPage = "PRN";

  nextionSetText("tTime", getCurrentTimeHHMM());
  nextionSetText("tNextDose", "PRN medication");
  nextionSetText("tNextTime", "Tap a medicine to view details");
  nextionSetText("tMeal", "PRN");
  nextionSetText("tBeforeAfter", "AS NEEDED");

  std::vector<SlotInfo> prnSlots;
  for (int i = 0; i < NUM_SLOTS; i++) {
    if (gSlots[i].isPrn && gSlots[i].drugName.length() > 0) {
      prnSlots.push_back(gSlots[i]);
    }
  }

  // FALLBACK: If no slots are marked isPrn, allow user to access any configured
  // slot
  if (prnSlots.empty()) {
    for (int i = 0; i < NUM_SLOTS; i++) {
      if (gSlots[i].drugName.length() > 0) {
        prnSlots.push_back(gSlots[i]);
      }
    }
  }

  int totalPrn = prnSlots.size();
  if (gPrnOffset >= totalPrn) {
    gPrnOffset = (totalPrn > 0) ? (totalPrn - 1) : 0;
  }
  if (gPrnOffset < 0)
    gPrnOffset = 0;

  for (int r = 0; r < 3; r++) {
    int itemIdx = gPrnOffset + r;
    String tName = "t" + String(r);
    String tQName = "tQ" + String(r);

    if (itemIdx < totalPrn) {
      String med = formatNextionDrugName(prnSlots[itemIdx].drugName,
                                         prnSlots[itemIdx].number);
      nextionSetText(tName, med);
      int q = prnSlots[itemIdx].prnQty > 0 ? prnSlots[itemIdx].prnQty : 1;
      nextionSetText(tQName, String(q) + (q > 1 ? " tablets" : " tablet"));
      nextionSend("tsw " + tName + ",1");
      nextionSend("tsw " + tQName + ",1");
    } else {
      nextionSetText(tName,
                     (r == 0 && totalPrn == 0) ? "No PRN configured" : "");
      nextionSetText(tQName, "");
      nextionSend("tsw " + tName + ",0");
      nextionSend("tsw " + tQName + ",0");
    }
  }

  // Action button: In medicine list page, prompt to select a medication first (Gray button)
  if (totalPrn > 0) {
    nextionSetText("bDispense", "PLEASE SELECT A MEDICINE");
  } else {
    nextionSetText("bDispense", "NO PRN MEDICATIONS");
  }
  nextionSend("bDispense.bco=50712"); // Inactive gray
  nextionSend("bDispense.pco=65535"); // White text
  nextionSend("tsw bDispense,1");     // Touch enabled fallback
  nextionSetVisible("bDispense", true);
  nextionRef("bDispense");

  // Overflow scrolling controls for PRN (>3 items) with clean ASCII labels "Up"
  // / "Down"
  if (totalPrn > 3) {
    if (gPrnOffset > 0) {
      nextionSetText("bScrollup", "Up");
      nextionSend("bScrollup.bco=50712");
      nextionSend("bScrollup.pco=65535");
      nextionSetVisible("bScrollup", true);
      nextionSend("tsw bScrollup,1");
      nextionRef("bScrollup");
    } else {
      nextionSetVisible("bScrollup", false);
      nextionSend("tsw bScrollup,0");
    }
    if ((gPrnOffset + 3) < totalPrn) {
      nextionSetText("bScrolldown", "Down");
      nextionSend("bScrolldown.bco=50712");
      nextionSend("bScrolldown.pco=65535");
      nextionSetVisible("bScrolldown", true);
      nextionSend("tsw bScrolldown,1");
      nextionRef("bScrolldown");
    } else {
      nextionSetVisible("bScrolldown", false);
      nextionSend("tsw bScrolldown,0");
    }
  } else {
    nextionSetVisible("bScrollup", false);
    nextionSetVisible("bScrolldown", false);
    nextionSend("tsw bScrollup,0");
    nextionSend("tsw bScrolldown,0");
  }

  // Force component redrawing on Nextion display
  nextionRef("tNextDose");
  nextionRef("tNextTime");
  nextionRef("tMeal");
  nextionRef("tBeforeAfter");
  nextionRef("t0");
  nextionRef("tQ0");
  nextionRef("t1");
  nextionRef("tQ1");
  nextionRef("t2");
  nextionRef("tQ2");
  nextionRef("bDispense");
  nextionFlush();
}

// ----------------------------------------------------------------------------
// 3. REQ:PRN_DETAIL - Detailed Info for Selected PRN Drug & Readiness Guard
// ----------------------------------------------------------------------------
void handleReqPrnDetail() {
  gCurrentNextionPage = "PRNDetail";
  nextionSetText("tTime", getCurrentTimeHHMM());

  // Resolve active PRN slot
  int idx = -1;
  if (gSelectedPrnSlot >= 1 && gSelectedPrnSlot <= NUM_SLOTS &&
      gSlots[gSelectedPrnSlot - 1].drugName.length() > 0) {
    idx = gSelectedPrnSlot - 1;
  } else {
    for (int i = 0; i < NUM_SLOTS; i++) {
      if (gSlots[i].isPrn && gSlots[i].drugName.length() > 0) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      for (int i = 0; i < NUM_SLOTS; i++) {
        if (gSlots[i].drugName.length() > 0) {
          idx = i;
          break;
        }
      }
    }
  }
  if (idx < 0)
    idx = 0;
  gSelectedPrnSlot = idx + 1;

  String med = formatNextionDrugName(gSlots[idx].drugName, idx + 1);
  int qty = gSlots[idx].prnQty > 0 ? gSlots[idx].prnQty : 1;

  PrnStatus st = checkPrnStatus(gSelectedPrnSlot);

  // 1. Header: Medication name and dosage
  nextionSetText("tNextDose", "PRN Medication");
  nextionSetText("tNextTime",
                 med + " (" + String(qty) + (qty > 1 ? " tabs)" : " tab)"));
  nextionSetText("tMeal", String(qty) + (qty > 1 ? " TABLETS" : " TABLET"));
  nextionSetText("tBeforeAfter", "AS NEEDED");

  // 2. Detail Rows:
  // Row 0: Indication / Symptoms
  nextionSetText("t0", "Indication");
  nextionSetText("tQ0", getDrugIndication(idx));

  // Row 1: Last taken time
  nextionSetText("t1", "Last intake");
  nextionSetText("tQ1", st.lastTakenTime);

  // Row 2: Next eligible dose time
  nextionSetText("t2", "Next dose");
  nextionSetText("tQ2", st.nextAllowedTime);

  // 3. Action button: Dispense action guarded by eligibility (gray and disabled if not eligible)
  nextionSetText("bDispense", st.buttonText);
  if (st.isReady) {
    nextionSend("bDispense.bco=9308");  // Active teal
    nextionSend("bDispense.pco=65535"); // White text
    nextionSend("tsw bDispense,1");     // ENABLE TOUCH (pressable)
  } else {
    nextionSend("bDispense.bco=50712"); // Disabled gray
    nextionSend("bDispense.pco=65535");
    nextionSend("tsw bDispense,0"); // DISABLE TOUCH (cannot be clicked)
  }
  nextionSetVisible("bDispense", true);

  // 4. Back button to return to medication list (single button)
  nextionSetText("bScrollup", "< BACK");
  nextionSend("bScrollup.bco=50712");
  nextionSend("bScrollup.pco=65535");
  nextionSend("tsw bScrollup,1");
  nextionSetVisible("bScrollup", true);

  // Hide the second scroll button
  nextionSetVisible("bScrolldown", false);
  nextionSend("tsw bScrolldown,0");

  // Force component redrawing on Nextion display
  nextionRef("tNextDose");
  nextionRef("tNextTime");
  nextionRef("tMeal");
  nextionRef("tBeforeAfter");
  nextionRef("t0");
  nextionRef("tQ0");
  nextionRef("t1");
  nextionRef("tQ1");
  nextionRef("t2");
  nextionRef("tQ2");
  nextionRef("bDispense");
  nextionRef("bScrollup");
  nextionFlush();
}

// ----------------------------------------------------------------------------
// 4. REQ:TIMELINE - Populate Full 24h Today Schedule + History (Chronological)
// ----------------------------------------------------------------------------
void handleReqTimeline(bool resetOffset) {
  gCurrentNextionPage = "Timeline";
  if (resetOffset)
    gTimelineOffset = 0;

  nextionSetText("tTime", getCurrentTimeHHMM());
  nextionSetText("tNextDose", "Today's timeline");
  nextionSetText("tNextTime", "Daily Schedule & PRN History");
  nextionSetText("tMeal", "TODAY");
  nextionSetText("tBeforeAfter", "TIMELINE");

  String schedContent = readStorageFile(FILE_SCHEDULE);
  if (schedContent.length() == 0)
    schedContent = currentScheduleJson;
  String histContent = readStorageFile(FILE_HISTORY);

#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument sDoc;
  JsonDocument hDoc;
#else
  DynamicJsonDocument sDoc(2048);
  DynamicJsonDocument hDoc(4096);
#endif
  deserializeJson(sDoc, schedContent);
  deserializeJson(hDoc, histContent);

  String today = getCurrentDateStr(0);
  String nowTime = getCurrentTimeHHMM();
  int nowMin = (nowTime.length() >= 5) ? (nowTime.substring(0, 2).toInt() * 60 +
                                          nowTime.substring(3, 5).toInt())
                                       : 0;

  struct TimelineRecord {
    int minutes;
    String timeStr;
    String title;
    String status;
  };
  std::vector<TimelineRecord> dayTimeline;

  // 1. Process all PRN intakes from history for today
  if (hDoc["history"].is<JsonArray>()) {
    for (JsonObject h : hDoc["history"].as<JsonArray>()) {
      String d = h["date"] | "";
      String type = h["type"] | "";
      String st = h["status"] | "taken";
      if ((d == today || d.length() == 0) && (type == "prn" || type == "PRN")) {
        String t = h["time"] | "--:--";
        String med = h["med"] | "";
        int m =
            (t.length() >= 5)
                ? (t.substring(0, 2).toInt() * 60 + t.substring(3, 5).toInt())
                : 0;
        TimelineRecord rec;
        rec.minutes = m;
        rec.timeStr = t;
        rec.title = "PRN: " + (med.length() > 0
                                   ? formatNextionDrugName(med, h["slot"] | 1)
                                   : "Medication");
        rec.status = (st == "taken" || st == "TAKEN") ? "TAKEN" : st;
        dayTimeline.push_back(rec);
      }
    }
  }

  // 2. Process all Daily Scheduled Meals for today (from schedule)
  if (sDoc["schedule"].is<JsonArray>()) {
    std::vector<String> uniqueSchedTimes;
    for (JsonObject item : sDoc["schedule"].as<JsonArray>()) {
      String t = item["time"] | item["t"] | "";
      if (t.length() >= 5) {
        bool found = false;
        for (const auto &ut : uniqueSchedTimes) {
          if (ut == t) {
            found = true;
            break;
          }
        }
        if (!found)
          uniqueSchedTimes.push_back(t);
      }
    }

    for (const String &mealTime : uniqueSchedTimes) {
      int sMin = mealTime.substring(0, 2).toInt() * 60 +
                 mealTime.substring(3, 5).toInt();
      TimelineRecord rec;
      rec.minutes = sMin;
      rec.timeStr = mealTime;
      String mealName = getMealNameFromTime(mealTime);

      int pillCount = 0;
      String firstMed = "";
      for (JsonObject item : sDoc["schedule"].as<JsonArray>()) {
        String t = item["time"] | item["t"] | "";
        if (t == mealTime) {
          pillCount++;
          if (firstMed.length() == 0)
            firstMed = item["medicine"] | item["med"] | "";
        }
      }

      if (pillCount > 1) {
        rec.title = mealName + " (" + String(pillCount) + " meds)";
      } else if (firstMed.length() > 0) {
        rec.title = mealName + ": " + firstMed;
      } else {
        rec.title = mealName;
      }

      if (isScheduledMealCompletedToday(mealTime)) {
        rec.status = "TAKEN";
      } else {
        if (sMin + 30 < nowMin) {
          rec.status = "MISSED";
        } else if (abs(sMin - nowMin) <= 30) {
          rec.status = "DUE NOW";
        } else {
          rec.status = "UPCOMING";
        }
      }
      dayTimeline.push_back(rec);
    }
  }

  // 3. Sort chronologically by minutes (00:00 to 23:59)
  std::sort(dayTimeline.begin(), dayTimeline.end(),
            [](const TimelineRecord &a, const TimelineRecord &b) {
              return a.minutes < b.minutes;
            });

  int totalRecords = dayTimeline.size();
  if (gTimelineOffset >= totalRecords) {
    gTimelineOffset = (totalRecords > 0) ? (totalRecords - 1) : 0;
  }
  if (gTimelineOffset < 0)
    gTimelineOffset = 0;

  for (int r = 0; r < 3; r++) {
    int itemIdx = gTimelineOffset + r;
    String tName = "t" + String(r);
    String tQName = "tQ" + String(r);

    if (itemIdx < totalRecords) {
      nextionSetText(tName, dayTimeline[itemIdx].timeStr + "  " +
                                dayTimeline[itemIdx].title);
      nextionSetText(tQName, dayTimeline[itemIdx].status);
    } else {
      nextionSetText(
          tName, (r == 0 && totalRecords == 0) ? "No timeline for today" : "");
      nextionSetText(tQName, "");
    }
  }

  nextionSetText("bDispense", "BACK TO DAILY");
  nextionSend("bDispense.bco=9308");
  nextionSend("bDispense.pco=65535");
  nextionSend("tsw bDispense,1");
  nextionSetVisible("bDispense", true);

  // Overflow scrolling controls for timeline (>3 records) with clean ASCII
  // labels "Up" / "Down"
  if (totalRecords > 3) {
    if (gTimelineOffset > 0) {
      nextionSetText("bScrollup", "Up");
      nextionSend("bScrollup.bco=50712");
      nextionSend("bScrollup.pco=65535");
      nextionSetVisible("bScrollup", true);
      nextionSend("tsw bScrollup,1");
      nextionRef("bScrollup");
    } else {
      nextionSetVisible("bScrollup", false);
      nextionSend("tsw bScrollup,0");
    }
    if ((gTimelineOffset + 3) < totalRecords) {
      nextionSetText("bScrolldown", "Down");
      nextionSend("bScrolldown.bco=50712");
      nextionSend("bScrolldown.pco=65535");
      nextionSetVisible("bScrolldown", true);
      nextionSend("tsw bScrolldown,1");
      nextionRef("bScrolldown");
    } else {
      nextionSetVisible("bScrolldown", false);
      nextionSend("tsw bScrolldown,0");
    }
  } else {
    nextionSetVisible("bScrollup", false);
    nextionSetVisible("bScrolldown", false);
    nextionSend("tsw bScrollup,0");
    nextionSend("tsw bScrolldown,0");
  }

  // Force component redrawing on Nextion display
  nextionRef("tNextDose");
  nextionRef("tNextTime");
  nextionRef("tMeal");
  nextionRef("tBeforeAfter");
  nextionRef("t0");
  nextionRef("tQ0");
  nextionRef("t1");
  nextionRef("tQ1");
  nextionRef("t2");
  nextionRef("tQ2");
  nextionRef("bDispense");
  nextionFlush();
}

// ----------------------------------------------------------------------------
// 5. REQ:CONFIRM - Modal Confirmation Page (Scheduled & PRN Doses)
// ----------------------------------------------------------------------------
void handleReqConfirm() {
  gCurrentNextionPage = "Confirm";
  nextionSetText("tTime", getCurrentTimeHHMM());

  bool canConfirm = false;

  if (gIsConfirmingPrn) {
    // Confirming a PRN Medication
    int idx = (gSelectedPrnSlot >= 1 && gSelectedPrnSlot <= NUM_SLOTS)
                  ? (gSelectedPrnSlot - 1)
                  : 0;
    String medName = formatNextionDrugName(gSlots[idx].drugName, idx + 1);
    int qty = gSlots[idx].prnQty > 0 ? gSlots[idx].prnQty : 1;
    PrnStatus st = checkPrnStatus(gSelectedPrnSlot);

    canConfirm = st.isReady;

    nextionSetText("tNextDose", "Confirm PRN dose");
    nextionSetText("tNextTime", medName + " (" + String(qty) +
                                    (qty > 1 ? " tabs)" : " tab)"));
    nextionSetText("tMeal", "PRN");
    nextionSetText("tBeforeAfter", "AS NEEDED");

    nextionSetText("t0", medName);
    nextionSetText("tQ0", String(qty) + (qty > 1 ? " tablets" : " tablet"));
    nextionSetText("t1", "Indication: " + getDrugIndication(idx));
    nextionSetText("tQ1", "Left: " + String(st.remaining));
    nextionSetText("t2", st.isReady ? "Please confirm to dispense" : st.reason);
    nextionSetText("tQ2", st.isReady ? "READY" : "WAIT");

    // Dynamic Navbar: Highlight PRN tab, de-highlight Daily
    nextionSend("bPRNpage.bco=29369");
    nextionSend("bPRNpage.pco=65535");
    nextionSend("bDailypage.bco=50712");
    nextionSend("bDailypage.pco=0");
    nextionSend("bTimelinepage.bco=50712");
    nextionSend("bTimelinepage.pco=0");
  } else {
    // Confirming Scheduled Meal
    // Highlight Daily tab, de-highlight PRN
    nextionSend("bDailypage.bco=29369");
    nextionSend("bDailypage.pco=65535");
    nextionSend("bPRNpage.bco=50712");
    nextionSend("bPRNpage.pco=0");
    nextionSend("bTimelinepage.bco=50712");
    nextionSend("bTimelinepage.pco=0");
    String schedContent = readStorageFile(FILE_SCHEDULE);
    if (schedContent.length() == 0)
      schedContent = currentScheduleJson;
#if ARDUINOJSON_VERSION_MAJOR >= 7
    JsonDocument doc;
#else
    DynamicJsonDocument doc(2048);
#endif
    deserializeJson(doc, schedContent);

    struct DrugDoseRow {
      String name;
      int qty;
    };
    std::vector<DrugDoseRow> mealPills;

    if (doc["schedule"].is<JsonArray>()) {
      for (JsonObject item : doc["schedule"].as<JsonArray>()) {
        String t = item["time"] | item["t"] | "";
        if (t == gActiveMealTime) {
          int s = item["slot"] | item["s"] | 1;
          String med = item["medicine"] | item["med"] | "";
          if (med.length() == 0 && s >= 1 && s <= NUM_SLOTS)
            med = gSlots[s - 1].drugName;
          int q = item["qty"] | item["q"] | 1;
          DrugDoseRow row;
          row.name = formatNextionDrugName(med, s);
          row.qty = q;
          mealPills.push_back(row);
        }
      }
    }

    int totalPills = mealPills.size();
    canConfirm = (totalPills > 0);

    nextionSetText("tNextDose", "Confirm dose");
    nextionSetText("tNextTime",
                   gActiveMealTime.length() > 0 ? gActiveMealTime : "--:--");
    nextionSetText("tMeal", getMealNameFromTime(gActiveMealTime));
    nextionSetText("tBeforeAfter",
                   gActiveBeforeFood ? "BEFORE MEAL" : "AFTER MEAL");

    if (totalPills > 0) {
      nextionSetText("t0", mealPills[0].name);
      int q0 = mealPills[0].qty;
      nextionSetText("tQ0", String(q0) + (q0 > 1 ? " tablets" : " tablet"));
    } else {
      nextionSetText("t0", "No medication scheduled");
      nextionSetText("tQ0", "");
    }

    if (totalPills > 1) {
      nextionSetText("t1", mealPills[1].name);
      int q1 = mealPills[1].qty;
      nextionSetText("tQ1", String(q1) + (q1 > 1 ? " tablets" : " tablet"));
    } else {
      nextionSetText("t1", "");
      nextionSetText("tQ1", "");
    }

    if (totalPills > 2) {
      nextionSetText("t2", mealPills[2].name);
      int q2 = mealPills[2].qty;
      nextionSetText("tQ2", String(q2) + (q2 > 1 ? " tablets" : " tablet"));
    } else {
      nextionSetText("t2", "");
      nextionSetText("tQ2", "");
    }
  }

  if (canConfirm) {
    nextionSetText("bDispense", "CONFIRM");
    nextionSend("bDispense.bco=9308"); // Active teal
    nextionSend("bDispense.pco=65535");
    nextionSend("tsw bDispense,1"); // ENABLE TOUCH
  } else {
    nextionSetText("bDispense", "NOT READY");
    nextionSend("bDispense.bco=50712"); // Disabled gray
    nextionSend("bDispense.pco=65535");
    nextionSend("tsw bDispense,0"); // DISABLE TOUCH
  }
  nextionSetVisible("bDispense", true);

  nextionSetText("bScrollup", "CANCEL");
  nextionSend("bScrollup.bco=50712");
  nextionSend("bScrollup.pco=65535");
  nextionSend("tsw bScrollup,1");
  nextionSetVisible("bScrollup", true);
  nextionSetVisible("bScrolldown", false);

  nextionFlush();
}

// ----------------------------------------------------------------------------
// 6. REQ:ALERT - Medication Reminder Popup Modal
// ----------------------------------------------------------------------------
void handleReqAlert() {
  gCurrentNextionPage = "Alert";
  nextionSetText("tTime", getCurrentTimeHHMM());
  nextionSetText("tNextDose", "Dose reminder");
  nextionSetText("tNextTime", "Time to take medicine");
  nextionSetText("tMeal", getMealNameFromTime(gActiveMealTime));
  nextionSetText("tBeforeAfter",
                 gActiveBeforeFood ? "BEFORE MEAL" : "AFTER MEAL");

  nextionSetText("t0", "It is time for your medication");
  nextionSetText("tQ0", "NOW");
  nextionSetText("t1", gActiveMealTime + " dose");
  nextionSetText("tQ1", "");
  nextionSetText("t2", "Please take with water");
  nextionSetText("tQ2", "");

  nextionSetText("bDispense", "TAKE NOW");
  nextionSend("bDispense.bco=9308");
  nextionSend("bDispense.pco=65535");
  nextionSend("tsw bDispense,1");
  nextionSetVisible("bDispense", true);

  nextionSetText("bScrollup", "LATER");
  nextionSend("bScrollup.bco=50712");
  nextionSend("tsw bScrollup,1");
  nextionSetVisible("bScrollup", true);
  nextionSetVisible("bScrolldown", false);
  nextionFlush();
}

// ----------------------------------------------------------------------------
// 7. REQ:DISPENSING - Motor In-Progress Dispensing Screen
// ----------------------------------------------------------------------------
void handleReqDispensing() {
  gCurrentNextionPage = "Dispensing";
  nextionSetText("tTime", getCurrentTimeHHMM());
  nextionSetText("tNextDose",
                 gIsConfirmingPrn ? "Dispensing PRN" : "Dispensing");
  nextionSetText("tNextTime", "Please wait");
  nextionSetText("tMeal", "RUNNING");
  nextionSetText("tBeforeAfter", "WAIT");

  nextionSetText("t0", "Checking tray");
  nextionSetText("tQ0", "READY");
  nextionSetText("t1", "Releasing medication");
  nextionSetText("tQ1", "ACTIVE");
  nextionSetText("t2", "Please wait...");
  nextionSetText("tQ2", "...");

  if (gIsConfirmingPrn) {
    nextionSend("bPRNpage.bco=29369");
    nextionSend("bPRNpage.pco=65535");
    nextionSend("bDailypage.bco=50712");
    nextionSend("bDailypage.pco=0");
  } else {
    nextionSend("bDailypage.bco=29369");
    nextionSend("bDailypage.pco=65535");
    nextionSend("bPRNpage.bco=50712");
    nextionSend("bPRNpage.pco=0");
  }

  nextionSetText("bDispense", "CANCEL");
  nextionSend("bDispense.bco=50712");
  nextionSend("tsw bDispense,1");
  nextionSetVisible("bDispense", true);
  nextionSetVisible("bScrollup", false);
  nextionSetVisible("bScrolldown", false);
  nextionFlush();
}

// ----------------------------------------------------------------------------
// 8. REQ:SUCCESS - Dose Complete Notification Screen
// ----------------------------------------------------------------------------
void handleReqSuccess() {
  gCurrentNextionPage = "Success";
  nextionSetText("tTime", getCurrentTimeHHMM());
  nextionSetText("tNextDose",
                 gIsConfirmingPrn ? "PRN dose complete" : "Dose complete");
  nextionSetText("tNextTime", "Recorded " + getCurrentTimeHHMM());
  nextionSetText("tMeal", "TAKEN");
  nextionSetText("tBeforeAfter", "COMPLETE");

  nextionSetText("t0", "Medicine dispensed");
  nextionSetText("tQ0", "TAKEN");
  nextionSetText("t1", "Please collect your pills");
  nextionSetText("tQ1", "TAKEN");
  nextionSetText("t2", "Thank you");
  nextionSetText("tQ2", "DONE");

  if (gIsConfirmingPrn) {
    nextionSend("bPRNpage.bco=29369");
    nextionSend("bPRNpage.pco=65535");
    nextionSend("bDailypage.bco=50712");
    nextionSend("bDailypage.pco=0");
  } else {
    nextionSend("bDailypage.bco=29369");
    nextionSend("bDailypage.pco=65535");
    nextionSend("bPRNpage.bco=50712");
    nextionSend("bPRNpage.pco=0");
  }

  nextionSetText("bDispense", "OK");
  nextionSend("bDispense.bco=9308");
  nextionSend("bDispense.pco=65535");
  nextionSend("tsw bDispense,1");
  nextionSetVisible("bDispense", true);
  nextionSetVisible("bScrollup", false);
  nextionSetVisible("bScrolldown", false);
  nextionFlush();
}

// ----------------------------------------------------------------------------
// Helper: Refresh Current Page Dynamically
// ----------------------------------------------------------------------------
void refreshCurrentNextionPage() {
  nextionSetText("tTime", getCurrentTimeHHMM());
  nextionFlush();
  if (gCurrentNextionPage == "Daily")
    handleReqDaily(false);
  else if (gCurrentNextionPage == "PRN")
    handleReqPrn();
  else if (gCurrentNextionPage == "PRNDetail")
    handleReqPrnDetail();
  else if (gCurrentNextionPage == "Timeline")
    handleReqTimeline(false);
}

// ----------------------------------------------------------------------------
// Nextion Command Dispatcher (Handles All Page Transitions, Selections &
// Actions)
// ----------------------------------------------------------------------------
void processNextionMessage(String msg) {
  msg.trim();
  if (msg.length() == 0)
    return;
  Serial.printf("[NEXTION RECV] %s\n", msg.c_str());

  // Page Postinitialize requests (when Nextion opens a page)
  if (msg.equalsIgnoreCase("REQ:DAILY") || msg.equalsIgnoreCase("NAV:DAILY")) {
    if ((gIsConfirmingPrn ||
         (gLastDispensedWasPrn && (millis() - gLastDispenseMs < 6000))) &&
        msg.equalsIgnoreCase("REQ:DAILY")) {
      // Screen locally jumped to Daily during/after PRN flow: redirect back to
      // PRN!
      gIsConfirmingPrn = false;
      gLastDispensedWasPrn = false;
      gCurrentNextionPage = "PRN";
      nextionSend("page PRN");
      handleReqPrn();
    } else {
      gIsConfirmingPrn = false;
      handleReqDaily(true);
    }
  } else if (msg.equalsIgnoreCase("REQ:PRN") ||
             msg.equalsIgnoreCase("NAV:PRN")) {
    gIsConfirmingPrn = false;
    handleReqPrn();
  } else if (msg.equalsIgnoreCase("REQ:PRN_DETAIL") ||
             msg.equalsIgnoreCase("REQ:PRNDETAIL")) {
    handleReqPrnDetail();
  } else if (msg.equalsIgnoreCase("REQ:TIMELINE") ||
             msg.equalsIgnoreCase("NAV:TIMELINE")) {
    gIsConfirmingPrn = false;
    handleReqTimeline(true);
  } else if (msg.equalsIgnoreCase("REQ:CONFIRM")) {
    handleReqConfirm();
  } else if (msg.equalsIgnoreCase("REQ:ALERT")) {
    handleReqAlert();
  } else if (msg.equalsIgnoreCase("REQ:DISPENSING")) {
    handleReqDispensing();
  } else if (msg.equalsIgnoreCase("REQ:SUCCESS")) {
    handleReqSuccess();
  }
  // Up/Down Scrolling & Overflow Medication Pagination
  else if (msg.equalsIgnoreCase("CMD:DAILY_UP") ||
           (gCurrentNextionPage == "Daily" &&
            (msg.equalsIgnoreCase("CMD:SCROLL_UP") ||
             msg.equalsIgnoreCase("CMD:UP")))) {
    if (gDailyOffset > 0)
      gDailyOffset--;
    handleReqDaily(false);
  } else if (msg.equalsIgnoreCase("CMD:DAILY_DOWN") ||
             (gCurrentNextionPage == "Daily" &&
              (msg.equalsIgnoreCase("CMD:SCROLL_DOWN") ||
               msg.equalsIgnoreCase("CMD:DOWN")))) {
    gDailyOffset++;
    handleReqDaily(false);
  } else if (msg.equalsIgnoreCase("CMD:PRN_UP") ||
             (gCurrentNextionPage == "PRN" &&
              (msg.equalsIgnoreCase("CMD:SCROLL_UP") ||
               msg.equalsIgnoreCase("CMD:UP")))) {
    if (gPrnOffset > 0)
      gPrnOffset--;
    handleReqPrn();
  } else if (msg.equalsIgnoreCase("CMD:PRN_DOWN") ||
             (gCurrentNextionPage == "PRN" &&
              (msg.equalsIgnoreCase("CMD:SCROLL_DOWN") ||
               msg.equalsIgnoreCase("CMD:DOWN")))) {
    int totalPrn = 0;
    for (int i = 0; i < NUM_SLOTS; i++) {
      if (gSlots[i].isPrn && gSlots[i].drugName.length() > 0)
        totalPrn++;
    }
    if (totalPrn == 0) {
      for (int i = 0; i < NUM_SLOTS; i++) {
        if (gSlots[i].drugName.length() > 0)
          totalPrn++;
      }
    }
    if ((gPrnOffset + 3) < totalPrn) {
      gPrnOffset++;
      handleReqPrn();
    }
  } else if (msg.equalsIgnoreCase("CMD:TIMELINE_UP") ||
             (gCurrentNextionPage == "Timeline" &&
              (msg.equalsIgnoreCase("CMD:SCROLL_UP") ||
               msg.equalsIgnoreCase("CMD:UP")))) {
    if (gTimelineOffset > 0)
      gTimelineOffset--;
    handleReqTimeline(false);
  } else if (msg.equalsIgnoreCase("CMD:TIMELINE_DOWN") ||
             (gCurrentNextionPage == "Timeline" &&
              (msg.equalsIgnoreCase("CMD:SCROLL_DOWN") ||
               msg.equalsIgnoreCase("CMD:DOWN")))) {
    gTimelineOffset++;
    handleReqTimeline(false);
  }
  // Dynamic Medication Row Selection on PRN page (t0/t1/t2 row taps)
  else if (msg.equalsIgnoreCase("CMD:PRN_SELECT_1") ||
           msg.equalsIgnoreCase("CMD:PRN_SELECT_2") ||
           msg.equalsIgnoreCase("CMD:PRN_SELECT_3")) {
    int rowSelected = 0;
    if (msg.equalsIgnoreCase("CMD:PRN_SELECT_1"))
      rowSelected = 0;
    else if (msg.equalsIgnoreCase("CMD:PRN_SELECT_2"))
      rowSelected = 1;
    else if (msg.equalsIgnoreCase("CMD:PRN_SELECT_3"))
      rowSelected = 2;

    std::vector<SlotInfo> prnSlots;
    for (int i = 0; i < NUM_SLOTS; i++) {
      if (gSlots[i].isPrn && gSlots[i].drugName.length() > 0) {
        prnSlots.push_back(gSlots[i]);
      }
    }
    if (prnSlots.empty()) {
      for (int i = 0; i < NUM_SLOTS; i++) {
        if (gSlots[i].drugName.length() > 0) {
          prnSlots.push_back(gSlots[i]);
        }
      }
    }

    int targetSlot = 1;
    int targetIdx = gPrnOffset + rowSelected;
    if (targetIdx < (int)prnSlots.size()) {
      targetSlot = prnSlots[targetIdx].number;
    } else if (!prnSlots.empty()) {
      targetSlot = prnSlots[0].number;
    }

    gSelectedPrnSlot = targetSlot;
    gCurrentNextionPage = "PRNDetail";
    nextionSend("page PRNDetail");
    delay(80);
    handleReqPrnDetail();
  }
  // Navigation & Actions (Take Pill from Daily / Alert / PRN)
  else if (msg.equalsIgnoreCase("CMD:DAILY_TAKE") ||
           msg.equalsIgnoreCase("CMD:ALERT_TAKE") ||
           msg.equalsIgnoreCase("CMD:TAKE_PILL") ||
           msg.equalsIgnoreCase("take pill") ||
           msg.equalsIgnoreCase("take_pill") ||
           msg.equalsIgnoreCase("CMD:TAKE") || msg.equalsIgnoreCase("take")) {
    if (gCurrentNextionPage == "PRN") {
      processNextionMessage("CMD:PRN_SELECT_1");
      return;
    }
    if (gCurrentNextionPage == "PRNDetail") {
      processNextionMessage("CMD:PRN_TAKE");
      return;
    }
    if (gCurrentNextionPage == "Confirm") {
      processNextionMessage("CMD:CONFIRM");
      return;
    }

    if (gActiveMealTime.length() == 0) {
      handleReqDaily(false);
    }
    if (gActiveMealTime.length() == 0) {
      Serial.println(
          "[DAILY REJECT] No active meal scheduled. Staying on Daily.");
      handleReqDaily(false);
      return;
    }
    if (isScheduledMealCompletedToday(gActiveMealTime)) {
      Serial.printf("[DAILY REJECT] Meal at %s already completed today.\n",
                    gActiveMealTime.c_str());
      handleReqDaily(false);
      return;
    }
    gIsConfirmingPrn = false;
    gCurrentNextionPage = "Confirm";
    nextionSend("page Confirm");
    handleReqConfirm();
  } else if (msg.equalsIgnoreCase("CMD:PRN_TAKE")) {
    if (gCurrentNextionPage == "PRN") {
      processNextionMessage("CMD:PRN_SELECT_1");
      return;
    }
    PrnStatus st = checkPrnStatus(gSelectedPrnSlot);
    if (!st.isReady) {
      Serial.printf(
          "[PRN REJECT] Slot %d is not ready (%s). Staying on PRNDetail.\n",
          gSelectedPrnSlot, st.reason.c_str());
      handleReqPrnDetail();
      return;
    }
    gIsConfirmingPrn = true;
    gCurrentNextionPage = "Confirm";
    nextionSend("page Confirm");
    handleReqConfirm();
  } else if (msg.equalsIgnoreCase("CMD:CONFIRM") ||
             msg.equalsIgnoreCase("confirm") ||
             msg.equalsIgnoreCase("CMD:DISPENSE") ||
             msg.equalsIgnoreCase("dispense")) {
    if (gIsConfirmingPrn) {
      PrnStatus st = checkPrnStatus(gSelectedPrnSlot);
      if (!st.isReady) {
        Serial.printf("[CONFIRM REJECT] PRN slot %d not ready (%s).\n",
                      gSelectedPrnSlot, st.reason.c_str());
        handleReqConfirm();
        return;
      }
    } else {
      if (gActiveMealTime.length() == 0) {
        handleReqDaily(false);
      }
      if (gActiveMealTime.length() == 0) {
        Serial.println("[CONFIRM REJECT] No scheduled meal active.");
        handleReqConfirm();
        return;
      }
    }

    gCurrentNextionPage = "Dispensing";
    nextionSend("page Dispensing");
    handleReqDispensing();

    if (gIsConfirmingPrn) {
      gLastDispensedWasPrn = true;
      gLastDispenseMs = millis();
      // Dispense the selected PRN slot
      int s = gSelectedPrnSlot;
      int q = (s >= 1 && s <= NUM_SLOTS && gSlots[s - 1].prnQty > 0)
                  ? gSlots[s - 1].prnQty
                  : 1;
      String med = (s >= 1 && s <= NUM_SLOTS) ? gSlots[s - 1].drugName
                                              : "PRN Medication";
      String err = "";
      executeDispense(s, q, med, "NEXTION_PRN", err, false, "");
    } else {
      gLastDispensedWasPrn = false;
      gLastDispenseMs = millis();
      // Dispense scheduled meal
      String schedContent = readStorageFile(FILE_SCHEDULE);
      if (schedContent.length() == 0)
        schedContent = currentScheduleJson;
#if ARDUINOJSON_VERSION_MAJOR >= 7
      JsonDocument doc;
#else
      DynamicJsonDocument doc(2048);
#endif
      deserializeJson(doc, schedContent);

      if (doc["schedule"].is<JsonArray>()) {
        for (JsonObject item : doc["schedule"].as<JsonArray>()) {
          String t = item["time"] | item["t"] | "";
          if (t == gActiveMealTime) {
            int s = item["slot"] | item["s"] | 1;
            int q = item["qty"] | item["q"] | 1;
            String med = item["medicine"] | item["med"] | "";
            String err = "";
            executeDispense(s, q, med, "NEXTION_HMI", err, true,
                            gActiveMealTime);
          }
        }
      }
    }

    // Dispense completed: instruct Nextion to open Success page
    delay(200);
    gCurrentNextionPage = "Success";
    nextionSend("page Success");
    delay(30);
    handleReqSuccess();
  } else if (msg.equalsIgnoreCase("CMD:CANCEL") ||
             msg.equalsIgnoreCase("CMD:DISPENSING_CANCEL") ||
             msg.equalsIgnoreCase("CMD:SUCCESS_OK") ||
             msg.equalsIgnoreCase("CMD:ALERT_LATER")) {
    if (gIsConfirmingPrn || gLastDispensedWasPrn) {
      gIsConfirmingPrn = false;
      gLastDispensedWasPrn = false;
      gCurrentNextionPage = "PRN";
      nextionSend("page PRN");
      handleReqPrn();
    } else {
      gCurrentNextionPage = "Daily";
      nextionSend("page Daily");
      handleReqDaily(false);
    }
  } else if (msg.equalsIgnoreCase("CMD:BACK")) {
    gIsConfirmingPrn = false;
    gLastDispensedWasPrn = false;
    gCurrentNextionPage = "PRN";
    nextionSend("page PRN");
    delay(60);
    handleReqPrn();
  }
}

// ----------------------------------------------------------------------------
// High-Reliability Nextion Serial Receiver (Supports 0xFF, Raw 0x65, &
// Delimiters)
// ----------------------------------------------------------------------------
void handleNextionIncoming() {
  static String rxBuf = "";
  static unsigned long lastCharMs = 0;
  static uint8_t rawBuf[16];
  static int rawIdx = 0;

  while (NextionSerial.available() > 0) {
    uint8_t b = NextionSerial.read();
    lastCharMs = millis();

    // Check for Nextion 0x65 touch event packet: 0x65 <page> <component_id>
    // <0x01/0x00> 0xFF 0xFF 0xFF ONLY start rawBuf touch event parsing if rxBuf
    // is currently empty!
    if (rxBuf.length() == 0 && b == 0x65 && rawIdx == 0) {
      rawBuf[rawIdx++] = b;
      continue;
    } else if (rawIdx > 0 && rawIdx < 7) {
      rawBuf[rawIdx++] = b;
      if (rawIdx == 7) {
        if (rawBuf[0] == 0x65 && rawBuf[4] == 0xFF && rawBuf[5] == 0xFF &&
            rawBuf[6] == 0xFF) {
          uint8_t pageId = rawBuf[1];
          uint8_t compId = rawBuf[2];
          uint8_t evType = rawBuf[3]; // 0=release, 1=press
          if (evType == 0) {          // On release
            Serial.printf("[NEXTION TOUCH] Page:%d Comp:%d\n", pageId, compId);
            if (compId == 16) { // bScrollup
              if (gCurrentNextionPage == "Confirm")
                processNextionMessage("CMD:CANCEL");
              else if (gCurrentNextionPage == "Alert")
                processNextionMessage("CMD:ALERT_LATER");
              else if (gCurrentNextionPage == "PRNDetail")
                processNextionMessage("CMD:BACK");
              else if (gCurrentNextionPage == "Daily")
                processNextionMessage("CMD:DAILY_UP");
              else if (gCurrentNextionPage == "PRN")
                processNextionMessage("CMD:PRN_UP");
              else if (gCurrentNextionPage == "Timeline")
                processNextionMessage("CMD:TIMELINE_UP");
              else
                processNextionMessage("CMD:SCROLL_UP");
            } else if (compId == 17) { // bScrolldown
              if (gCurrentNextionPage == "Daily")
                processNextionMessage("CMD:DAILY_DOWN");
              else if (gCurrentNextionPage == "PRN")
                processNextionMessage("CMD:PRN_DOWN");
              else if (gCurrentNextionPage == "Timeline")
                processNextionMessage("CMD:TIMELINE_DOWN");
              else
                processNextionMessage("CMD:SCROLL_DOWN");
            } else if (compId == 9) { // bDispense
              if (gCurrentNextionPage == "Daily")
                processNextionMessage("CMD:DAILY_TAKE");
              else if (gCurrentNextionPage == "PRN") {
                processNextionMessage("CMD:PRN_SELECT_1");
              } else if (gCurrentNextionPage == "PRNDetail")
                processNextionMessage("CMD:PRN_TAKE");
              else if (gCurrentNextionPage == "Confirm")
                processNextionMessage("CMD:CONFIRM");
              else if (gCurrentNextionPage == "Timeline")
                processNextionMessage("NAV:DAILY");
              else if (gCurrentNextionPage == "Success")
                processNextionMessage("CMD:SUCCESS_OK");
            } else if (compId == 10 || compId == 13) { // t0 / tQ0
              if (gCurrentNextionPage == "PRN")
                processNextionMessage("CMD:PRN_SELECT_1");
            } else if (compId == 11 || compId == 14) { // t1 / tQ1
              if (gCurrentNextionPage == "PRN")
                processNextionMessage("CMD:PRN_SELECT_2");
            } else if (compId == 12 || compId == 15) { // t2 / tQ2
              if (gCurrentNextionPage == "PRN")
                processNextionMessage("CMD:PRN_SELECT_3");
            }
          }
        } else {
          // If not a valid 0x65 packet, recover all buffered bytes back into
          // rxBuf so no ASCII data is lost!
          for (int k = 0; k < 7; k++) {
            if (rawBuf[k] >= 32 && rawBuf[k] <= 126) {
              rxBuf += (char)rawBuf[k];
            }
          }
        }
        rawIdx = 0;
      }
      continue;
    } else {
      rawIdx = 0;
    }

    // ASCII Terminator delimiter check (0xFF, newline, or carriage return)
    if (b == 0xFF || b == '\n' || b == '\r') {
      if (rxBuf.length() > 0) {
        processNextionMessage(rxBuf);
        rxBuf = "";
      }
    } else if (b >= 32 && b <= 126) {
      rxBuf += (char)b;
    }
  }

  // Inter-character timeout: flush buffer if bytes arrived without terminator
  // (35ms silence)
  if (rawIdx > 0 && (millis() - lastCharMs > 35)) {
    for (int k = 0; k < rawIdx; k++) {
      if (rawBuf[k] >= 32 && rawBuf[k] <= 126) {
        rxBuf += (char)rawBuf[k];
      }
    }
    rawIdx = 0;
  }
  if (rxBuf.length() > 0 && (millis() - lastCharMs > 35)) {
    processNextionMessage(rxBuf);
    rxBuf = "";
  }

  // Auto-update time on Nextion every minute (One-way push)
  static String lastMin = "";
  String currentMin = getCurrentTimeHHMM();
  if (currentMin != lastMin && currentMin != "--:--") {
    lastMin = currentMin;
    nextionSetText("tTime", currentMin);
    nextionRef("tTime");
    nextionFlush();
    // Only refresh if sitting on Daily to avoid interrupting popups
    if (gCurrentNextionPage == "Daily") {
      handleReqDaily(false);
    }
    Serial.println("[NEXTION PUSH] Auto-updated display for minute: " +
                   currentMin);
  }
}

// ----------------------------------------------------------------------------
// Demo Data Seeder for Initial Standalone Testing
// ----------------------------------------------------------------------------
void seedDefaultDemoDataIfEmpty() {
  // If time not synced yet, seed standard 18:00:00 local time (Dinner) first
  // so all seeded history and comparisons use valid today date (2026-11-16)
  if (!isTimeSynced) {
    setSystemEpoch(1794826800); // 18:00:00
  }

  bool alreadySeeded = pActiveFS && pActiveFS->exists("/config/.seeded");
  String sched = readStorageFile(FILE_SCHEDULE);
  bool needsSeed = !alreadySeeded && (sched.length() == 0);

  if (needsSeed) {
    if (pActiveFS)
      writeStorageFile("/config/.seeded", "1");
    Serial.println("[DEMO] Seeding initial slots & schedule for Nextion "
                   "display testing...");
    // Slot 1
    gSlots[0].number = 1;
    gSlots[0].drugName = "Metformin 500 mg";
    gSlots[0].remaining = 14;
    gSlots[0].capacity = 30;
    gSlots[0].isPrn = false;

    // Slot 2
    gSlots[1].number = 2;
    gSlots[1].drugName = "Amlodipine 5 mg";
    gSlots[1].remaining = 14;
    gSlots[1].capacity = 30;
    gSlots[1].isPrn = false;

    // Slot 3 (PRN 1)
    gSlots[2].number = 3;
    gSlots[2].drugName = "Paracetamol 500 mg";
    gSlots[2].remaining = 20;
    gSlots[2].capacity = 30;
    gSlots[2].isPrn = true;
    gSlots[2].prnQty = 1;
    gSlots[2].minIntervalHours = 4;
    gSlots[2].maxDosesPerDay = 4;
    gSlots[2].indication = "Headache / Fever";

    // Slot 4 (PRN 2)
    gSlots[3].number = 4;
    gSlots[3].drugName = "Ibuprofen 400 mg";
    gSlots[3].remaining = 10;
    gSlots[3].capacity = 30;
    gSlots[3].isPrn = true;
    gSlots[3].prnQty = 1;
    gSlots[3].minIntervalHours = 6;
    gSlots[3].maxDosesPerDay = 3;
    gSlots[3].indication = "Pain / Fever / Joint";

    saveSlotsToStorage();

    String defaultSched = "{\"device_id\":\"" DEVICE_ID "\",\"schedule\":["
                          "{\"slot\":1,\"time\":\"08:00\",\"qty\":1,\"before_"
                          "food\":true,\"medicine\":\"Metformin 500 mg\"},"
                          "{\"slot\":1,\"time\":\"12:00\",\"qty\":1,\"before_"
                          "food\":false,\"medicine\":\"Metformin 500 mg\"},"
                          "{\"slot\":2,\"time\":\"12:00\",\"qty\":1,\"before_"
                          "food\":false,\"medicine\":\"Amlodipine 5 mg\"},"
                          "{\"slot\":1,\"time\":\"18:00\",\"qty\":1,\"before_"
                          "food\":false,\"medicine\":\"Metformin 500 mg\"},"
                          "{\"slot\":2,\"time\":\"21:00\",\"qty\":1,\"before_"
                          "food\":false,\"medicine\":\"Amlodipine 5 mg\"}"
                          "]}";
    writeStorageFile(FILE_SCHEDULE, defaultSched);
    currentScheduleJson = defaultSched;

    // Seed realistic taken history for today (both scheduled meal & PRN)
    String todayStr = getCurrentDateStr(0);
    String defaultHist =
        "{\"history\":["
        "{\"date\":\"" +
        todayStr +
        "\",\"time\":\"08:02\",\"slot\":1,\"med\":\"Metformin 500 "
        "mg\",\"qty\":1,\"type\":\"meal\",\"status\":\"taken\",\"trigger\":"
        "\"SCHEDULED\"},"
        "{\"date\":\"" +
        todayStr +
        "\",\"time\":\"09:30\",\"slot\":3,\"med\":\"Paracetamol 500 "
        "mg\",\"qty\":1,\"type\":\"prn\",\"status\":\"taken\",\"trigger\":"
        "\"PRN\"}"
        "]}";
    writeStorageFile(FILE_HISTORY, defaultHist);
  }
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n==================================================");
  Serial.println(
      "  Smart Pill Dispenser (MeDisP) - TEST Firmware (BLE + Nextion HMI)  ");
  Serial.println("==================================================");

  setupStorage();

  // Initialize Nextion Display Serial on physical RX and TX pins
  NextionSerial.begin(NEXTION_BAUD, SERIAL_8N1, NEXTION_RX_PIN, NEXTION_TX_PIN);
  Serial.printf("[NEXTION] Initialized Nextion Serial on RX (GPIO %d), TX "
                "(GPIO %d) at %d baud\n",
                NEXTION_RX_PIN, NEXTION_TX_PIN, NEXTION_BAUD);
  seedDefaultDemoDataIfEmpty();

  // PURE ONE-WAY PUSH: Clear buffer & send data directly to Nextion display on
  // boot
  delay(800);
  NextionSerial.write(0xFF);
  NextionSerial.write(0xFF);
  NextionSerial.write(0xFF);
  NextionSerial.flush();
  nextionSend("bkcmd=0");
  nextionSend("page Daily");
  delay(50);
  handleReqDaily(true);
  Serial.println(
      "[NEXTION PUSH] Sent initial one-way screen update to Nextion!");

  Serial.println("\n[BLE] Initializing NimBLE Peripheral...");
  NimBLEDevice::init(DEVICE_NAME);
  NimBLEDevice::setMTU(517);

  NimBLEServer *pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  NimBLEService *pService = pServer->createService(SERVICE_UUID);

  // Config Characteristic: Read & Write commands
  pConfigChar = pService->createCharacteristic(
      CONFIG_CHAR_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR |
                            NIMBLE_PROPERTY::READ);
  pConfigChar->setValue(currentScheduleJson.c_str());
  pConfigChar->setCallbacks(new ConfigCharacteristicCallbacks());

  // Status Characteristic: Read-only real-time state
  pStatusChar =
      pService->createCharacteristic(STATUS_CHAR_UUID, NIMBLE_PROPERTY::READ);
  pStatusChar->setValue(buildDeviceStatusJson().c_str());
  pStatusChar->setCallbacks(new StatusCharacteristicCallbacks());

  // Response Characteristic: Real-time Notify back to Flutter
  pResponseChar = pService->createCharacteristic(RESPONSE_CHAR_UUID,
                                                 NIMBLE_PROPERTY::NOTIFY);
  pResponseChar->setValue("{\"result\":\"ready\",\"status\":\"standby\"}");

  pService->start();

  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setName(DEVICE_NAME);
  pAdvertising->enableScanResponse(true);
  pAdvertising->setMinInterval(32); // 20ms
  pAdvertising->setMaxInterval(64); // 40ms
  pAdvertising->start();

  Serial.println("[BLE] Advertising started successfully!");
  Serial.printf("[BLE] Device Name : %s\n", DEVICE_NAME);
  Serial.printf("[BLE] Service UUID: %s\n", SERVICE_UUID);
  Serial.println(
      "[CLI] Serial CLI active. Type 'help' to view debug commands.\n");
}

void loop() {
  // 1. Process Serial CLI inputs for hardware debugging
  handleSerialCli();

  // 1b. Process Nextion HMI display inputs and requests
  handleNextionIncoming();

  // Auto-return from Success screen back to Daily/PRN after 3.5 seconds
  static unsigned long successPageEnteredMs = 0;
  if (gCurrentNextionPage == "Success") {
    if (successPageEnteredMs == 0)
      successPageEnteredMs = millis();
    if (millis() - successPageEnteredMs > 3500) {
      successPageEnteredMs = 0;
      if (gLastDispensedWasPrn || gIsConfirmingPrn) {
        gIsConfirmingPrn = false;
        gLastDispensedWasPrn = false;
        gCurrentNextionPage = "PRN";
        nextionSend("page PRN");
        delay(40);
        handleReqPrn();
      } else {
        gCurrentNextionPage = "Daily";
        nextionSend("page Daily");
        delay(40);
        handleReqDaily(true);
      }
    }
  } else {
    successPageEnteredMs = 0;
  }

  // 2. Process asynchronous BLE commands sent from Flutter App (FIFO Queue)
  String bleCmd;
  while (dequeueBleCommand(bleCmd)) {
    Serial.println("\n[BLE RECV] Processing command payload from queue:");
    Serial.println(bleCmd);
    processIncomingCommand(bleCmd);
  }

  // 3. Periodic time sync request (every 15 minutes)
  if (isBleClientConnected &&
      (millis() - lastTimeSyncRequestMs >= TIME_SYNC_INTERVAL_MS)) {
    lastTimeSyncRequestMs = millis();
    String reqEvent = "{\"event\":\"REQUEST_TIME_SYNC\",\"epoch\":" +
                      String(getSystemEpoch()) + ",\"time\":\"" +
                      getFormattedTime() + "\"}";
    sendBleEvent(reqEvent);
    Serial.println("[TIME] Periodic time sync request sent to app");
  }

  delay(20);
}
