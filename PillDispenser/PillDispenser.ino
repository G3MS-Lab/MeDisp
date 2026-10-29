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
#include <LittleFS.h>
#include <NimBLEDevice.h>
#include <SD.h>
#include <SPI.h>
#include <sys/time.h>
#include <time.h>

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
static volatile bool hasNewBleCommand = false;
static String pendingBleCommand = "";

// Periodic Time Sync Request (every 15 minutes)
#define TIME_SYNC_INTERVAL_MS 900000UL
static unsigned long lastTimeSyncRequestMs = 0;

// Forward Declarations
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

// ============================================================================
// HARDWARE HOOKS
// ============================================================================

/**
 * [Hook 1: สั่งจ่ายยาทางฮาร์ดแวร์]
 * Parameters:
 *   - slot: หมายเลขช่องยา (1 - 6)
 *   - qty: จำนวนเม็ดที่ต้องการจ่าย
 *   - outErrMsg: ข้อความระบุข้อผิดพลาดกรณีจ่ายไม่สำเร็จ
 * Return: true ถ้าจ่ายสำเร็จจริง, false ถ้ามีข้อผิดพลาด
 */
bool hardwareDispenseSlot(int slot, int qty, String &outErrMsg) {
  Serial.printf("[HARDWARE HOOK] Executing dispense: Slot %d, Qty: %d\n", slot, qty);
  // ค่าจำลองเริ่มต้น (Mock: ถือว่าฮาร์ดแวร์จ่ายสำเร็จ)
  return true;
}

inline bool dispensePill(int slot, int qty) {
  String err = "";
  return hardwareDispenseSlot(slot, qty, err);
}

/**
 * [Hook 2: ซิงค์เวลากับชิปนาฬิกาภายนอก (RTC Module เช่น DS3231)]
 */
void hardwareSyncRtc(unsigned long epochTime) {
  Serial.printf("[HARDWARE HOOK] Syncing external RTC to epoch: %lu\n", epochTime);
}

/**
 * [Hook 3: อัปเดตข้อมูลช่องยา (เช่น ไฟ LED / จอแสดงผล)]
 */
void hardwareSlotUpdated(int slot, int remaining, const char *drugName) {
  Serial.printf("[HARDWARE HOOK] Slot %d updated: '%s' remaining: %d\n", slot, drugName, remaining);
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
  Serial.printf("[TIME] System time synchronized: %s (Epoch: %lu)\n", buf, epoch);
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
  if (!pActiveFS) return false;
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
  if (!pActiveFS || !pActiveFS->exists(path)) return "";
  File f = pActiveFS->open(path, FILE_READ);
  if (!f) return "";
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
  }
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
      int sNum = s.containsKey("number") ? (s["number"] | 0) : (s["slot"] | 0);

      if (sNum >= 1 && sNum <= NUM_SLOTS) {
        int idx = sNum - 1;
        gSlots[idx].capacity = s["capacity"] | 30;
        gSlots[idx].remaining = s.containsKey("remaining")
                                    ? (s["remaining"] | 0)
                                    : (s["rem"] | 0);

        if (s["drug"].is<JsonObject>()) {
          JsonObject d = s["drug"].as<JsonObject>();
          gSlots[idx].drugName = d["name"] | "";
          gSlots[idx].drugId = d["id"] | "";
        } else {
          gSlots[idx].drugName = s["drug"] | "";
          gSlots[idx].drugId = s["drug_id"] | "";
        }

        gSlots[idx].isPrn = s["is_prn"] | false;
        gSlots[idx].minIntervalHours = s.containsKey("min_interval_hours")
                                           ? (s["min_interval_hours"] | 0)
                                           : (s["interval_hours"] | 0);
        gSlots[idx].prnQty = s.containsKey("prn_qty")
                                 ? (s["prn_qty"] | 1)
                                 : (s["qty"] | 1);
        gSlots[idx].maxDosesPerDay = s.containsKey("max_doses_per_day")
                                         ? (s["max_doses_per_day"] | 4)
                                         : (s.containsKey("max_doses") ? (s["max_doses"] | 4) : 4);

        hardwareSlotUpdated(sNum, gSlots[idx].remaining, gSlots[idx].drugName.c_str());
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
  if (content.length() == 0) content = currentScheduleJson;

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
        it.beforeFood = it.hasBeforeFood ? item["before_food"].as<bool>() : true;
        it.minutes = (it.time.length() >= 5)
            ? (it.time.substring(0, 2).toInt() * 60 + it.time.substring(3, 5).toInt())
            : 0;
        allItems.push_back(it);
      }
    }
  }

  // Add the updated schedule items for THIS slot
  for (JsonObject item : newItems) {
    TempSchedItem it;
    it.time = item["time"] | item["t"] | "";
    it.slot = slotNum;
    String med = item["medicine"] | item["med"] | "";
    if (med.length() == 0 && slotNum >= 1 && slotNum <= NUM_SLOTS) {
      med = gSlots[slotNum - 1].drugName;
    }
    it.medicine = med;
    it.qty = item["qty"] | item["q"] | 1;
    it.hasBeforeFood = item.containsKey("before_food");
    it.beforeFood = it.hasBeforeFood ? item["before_food"].as<bool>() : true;
    it.minutes = (it.time.length() >= 5)
        ? (it.time.substring(0, 2).toInt() * 60 + it.time.substring(3, 5).toInt())
        : 0;
    allItems.push_back(it);
  }

  // Sort chronologically by time first, then by slot number
  std::sort(allItems.begin(), allItems.end(), [](const TempSchedItem &a, const TempSchedItem &b) {
    if (a.minutes != b.minutes) return a.minutes < b.minutes;
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
  Serial.printf("[STORAGE] Consolidated schedule for Slot %d (%d items, total %d bytes)\n",
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
    Serial.println("[STORAGE] SD Card not mounted. Falling back to LittleFS...");
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
  if (!pResponseChar) return;
  String payload = "{\"result\":\"" + String(result) + "\",\"message\":\"" + String(message) + "\"}";
  pResponseChar->setValue(payload.c_str());
  pResponseChar->notify();
  Serial.printf("[BLE NOTIFY] %s -> %s\n", result, message);
}

void sendBleEvent(const String &eventJson) {
  if (!pResponseChar) return;
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
    if (gSlots[i].capacity != 30) s["capacity"] = gSlots[i].capacity;
    if (gSlots[i].drugId.length() > 0) s["drug_id"] = gSlots[i].drugId;
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
  if (content.length() == 0) content = currentScheduleJson;
#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
#else
  DynamicJsonDocument doc(2048);
#endif
  DeserializationError err = deserializeJson(doc, content);
  if (err || !doc["schedule"].is<JsonArray>()) {
    return "";
  }

  // Load history to see which schedule times for this slot are already taken today
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
    nowMinutes = nowTime.substring(0, 2).toInt() * 60 + nowTime.substring(3, 5).toInt();
  }

  for (JsonObject item : doc["schedule"].as<JsonArray>()) {
    int s = item["slot"] | item["s"] | 0;
    if (s == slot) {
      String t = item["time"] | item["t"] | "";
      if (t.length() == 0) continue;
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
          int schedMin = t.substring(0, 2).toInt() * 60 + t.substring(3, 5).toInt();
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
  Serial.printf("[HISTORY] Recorded intake: %s %s Slot %d Qty %d (%s, %s%s%s)\n",
                dateStr.c_str(), timeStr.c_str(), slot, qty, type, status,
                (schedTime && strlen(schedTime) > 0) ? ", Sched: " : "",
                (schedTime && strlen(schedTime) > 0) ? schedTime : "");
}

int countPrnIntakesToday(int slot) {
  String todayDate = getCurrentDateStr(0);
  String content = readStorageFile(FILE_HISTORY);
  if (content.length() == 0) return 0;
#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
#else
  DynamicJsonDocument doc(4096);
#endif
  if (deserializeJson(doc, content)) return 0;
  if (!doc["history"].is<JsonArray>()) return 0;

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
                     const String &reqId, String &outErrMsg,
                     bool isScheduled, const String &schedTime) {
  if (slot < 1 || slot > NUM_SLOTS) {
    outErrMsg = "Invalid slot number (1-6)";
    return false;
  }

  int idx = slot - 1;

  // PRN Safety check: daily limit resets every midnight
  if (gSlots[idx].isPrn && !isScheduled) {
    int todayDoses = countPrnIntakesToday(slot);
    int maxDoses = gSlots[idx].maxDosesPerDay > 0 ? gSlots[idx].maxDosesPerDay : 4;
    if (todayDoses >= maxDoses) {
      outErrMsg = "PRN daily limit reached (" + String(todayDoses) + "/" + String(maxDoses) + " doses today, resets midnight)";
      Serial.printf("[PRN LIMIT] Slot %d reached daily limit of %d doses. Resets at midnight.\n", slot, maxDoses);
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

    String eventJson = "{\"event\":\"DISPENSE_SUCCESS\",\"slot\":" + String(slot) +
                       ",\"qty\":" + String(qty) +
                       ",\"medicine\":\"" + gSlots[idx].drugName +
                       "\",\"type\":\"" + String(isScheduled ? "meal" : "prn") +
                       "\",\"sched_time\":\"" + finalSched +
                       "\",\"remaining\":" + String(gSlots[idx].remaining) +
                       ",\"req_id\":\"" + reqId + "\"}";
    sendBleEvent(eventJson);
    return true;
  } else {
    String eventJson = "{\"event\":\"DISPENSE_FAILED\",\"slot\":" + String(slot) +
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

  // 1a. DISPENSE COMMAND
  if (cmd == "dispense") {
    int slot = doc["slot"] | 1;
    int qty = doc["qty"] | 1;
    String reqId = doc["req_id"] | "";
    String med = doc["medicine"] | "";
    String type = doc["type"] | "";
    String schedTime = doc["sched_time"] | "";
    bool isSched = (type == "meal") || (type == "" && !gSlots[slot - 1].isPrn);
    String errMsg = "";

    if (!executeDispense(slot, qty, med, reqId, errMsg, isSched, schedTime)) {
      sendResponseNotification("error", errMsg.c_str());
    } else {
      sendResponseNotification("success", "Dispense completed");
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
      recordIntakeHistory(slot, qty, med, type.c_str(), status.c_str(), schedTime.c_str());

      String eventJson = "{\"event\":\"INTAKE_RECORDED\",\"slot\":" + String(slot) +
                         ",\"qty\":" + String(qty) +
                         ",\"medicine\":\"" + safeTruncateUtf8(med, 36) +
                         "\",\"type\":\"" + type +
                         "\",\"sched_time\":\"" + schedTime +
                         "\",\"remaining\":" + String(gSlots[idx].remaining) +
                         ",\"time\":\"" + getFormattedTime() + "\"}";
      sendBleEvent(eventJson);
      sendResponseNotification("success", "Intake recorded successfully");
    } else {
      sendResponseNotification("error", "Invalid slot");
    }
  }
  // 2. TIME SYNCHRONIZATION COMMAND
  else if (cmd == "sync_time") {
    unsigned long epoch = doc["epoch"] | 0;
    if (epoch > 0) {
      setSystemEpoch(epoch);
      String res = "{\"event\":\"TIME_SYNC_OK\",\"epoch\":" + String(epoch) +
                   ",\"time\":\"" + getFormattedTime() + "\"}";
      sendBleEvent(res);
      sendResponseNotification("success", "Time synchronized successfully");
    } else {
      sendResponseNotification("error", "Invalid epoch time");
    }
  }
  // 3. SLOTS SYNCHRONIZATION COMMAND
  else if (cmd == "sync_slots") {
    parseAndApplySlots(jsonPayload);
    saveSlotsToStorage();
    String eventJson = "{\"event\":\"SLOTS_SAVED\",\"status\":\"success\","
                       "\"time\":\"" + getFormattedTime() + "\"}";
    sendBleEvent(eventJson);
    sendResponseNotification("success", "Slots configuration saved");
  }
  // 4a. SET SLOT SCHEDULE COMMAND (Per-slot schedule update)
  else if (cmd == "set_slot_schedule") {
    int slot = doc["slot"] | 0;
    if (slot >= 1 && slot <= NUM_SLOTS && doc["schedule"].is<JsonArray>()) {
      updateSlotScheduleInStorage(slot, doc["schedule"].as<JsonArray>());
      String eventJson = "{\"event\":\"SCHEDULE_SAVED\",\"slot\":" + String(slot) +
                         ",\"status\":\"success\",\"time\":\"" + getFormattedTime() + "\"}";
      sendBleEvent(eventJson);
      sendResponseNotification("success", "Slot schedule stored");
    } else {
      sendResponseNotification("error", "Invalid slot or schedule format");
    }
  }
  // 4b. GET SCHEDULE COMMAND (Stream slot schedule chunked per slot - MTU safe)
  else if (cmd == "get_schedule") {
    String content = readStorageFile(FILE_SCHEDULE);
    if (content.length() == 0) content = currentScheduleJson;
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
  else if (cmd == "sync_schedule" || (cmd == "" && doc.containsKey("schedule"))) {
    if (!doc.containsKey("device_id") || doc["device_id"].as<String>().length() == 0) {
      sendResponseNotification("error", "Missing or empty 'device_id'");
      return;
    }
    if (!doc["schedule"].is<JsonArray>()) {
      sendResponseNotification("error", "Invalid 'schedule' format; expected array");
      return;
    }

    writeStorageFile(FILE_SCHEDULE, jsonPayload);
    currentScheduleJson = jsonPayload;
    if (pConfigChar) {
      pConfigChar->setValue(jsonPayload.c_str());
    }
    String eventJson = "{\"event\":\"SCHEDULE_SAVED\",\"status\":\"success\","
                       "\"time\":\"" + getFormattedTime() + "\"}";
    sendBleEvent(eventJson);
    sendResponseNotification("success", "configuration stored");
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
                       "\"time_synced\":" + String(isTimeSynced ? "true" : "false") +
                       ",\"epoch\":" + String(getSystemEpoch()) +
                       ",\"time\":\"" + getFormattedTime() + "\"}";
    sendBleEvent(syncEvent);
    sendResponseNotification("success", "Sync data ready");
  }
  // 7. 7-DAY HISTORY SYNC COMMAND
  else if (cmd == "sync_history" || cmd == "get_history") {
    int requestedOffset = doc.containsKey("day_offset") ? (doc["day_offset"] | 0) : -1;
    String histContent = readStorageFile(FILE_HISTORY);
#if ARDUINOJSON_VERSION_MAJOR >= 7
    JsonDocument hDoc;
#else
    DynamicJsonDocument hDoc(4096);
#endif
    deserializeJson(hDoc, histContent);

    int startDay = (requestedOffset >= 0) ? requestedOffset : 0;
    int endDay = (requestedOffset >= 0) ? requestedOffset : 6;

    for (int d = startDay; d <= endDay; d++) {
      String targetDate = getCurrentDateStr(d);

      // Count matching records for this day
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
        dayDoc["day_offset"] = d;
        dayDoc["date"] = targetDate;
        dayDoc.createNestedArray("records");
        String dayOutput;
        serializeJson(dayDoc, dayOutput);
        sendBleEvent(dayOutput);
        delay(40);
      } else {
        // Send in MTU-safe chunks (max 3 records per packet, payload < 320 bytes)
        int currentInChunk = 0;
#if ARDUINOJSON_VERSION_MAJOR >= 7
        JsonDocument dayDoc;
#else
        DynamicJsonDocument dayDoc(512);
#endif
        dayDoc["event"] = "HISTORY_DAY";
        dayDoc["day_offset"] = d;
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
              dayDoc["day_offset"] = d;
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

    sendBleEvent("{\"event\":\"HISTORY_SYNC_DONE\",\"status\":\"success\"}");
    sendResponseNotification("success", "History sync finished");
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
    String resetEvent = "{\"event\":\"DISPENSER_RESET\",\"status\":\"success\"}";
    sendBleEvent(resetEvent);
    sendResponseNotification("success", "Dispenser data cleared completely");
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
    if (rxValue.length() == 0) return;
    pendingBleCommand = String(rxValue.c_str());
    hasNewBleCommand = true;
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
    Serial.printf("[BLE SERVER] Disconnected (reason %d). Restarting advertising...\n", reason);
    NimBLEDevice::startAdvertising();
  }
};

// ============================================================================
// Safe UTF-8 truncate to prevent slicing multi-byte characters
String safeTruncateUtf8(const String &str, size_t maxLen) {
  if (str.length() <= maxLen) return str;
  size_t len = maxLen;
  while (len > 0 && ((uint8_t)str[len] & 0xC0) == 0x80) {
    len--;
  }
  return str.substring(0, len);
}

// ============================================================================
// Interactive Serial CLI (Hardware Debugging)
// ============================================================================
void printSerialSlots() {
  Serial.println("[SLOTS INVENTORY]");
  Serial.println("+------+-----------+----------+---------------+----------+-----------+------------------------------+");
  Serial.println("| Slot | Remaining | Type     | PRN Interval  | Dose Qty | Max / Day | Drug Name                    |");
  Serial.println("+------+-----------+----------+---------------+----------+-----------+------------------------------+");

  // Read schedule once to show dose count for regular meal drugs
  String schedContent = readStorageFile(FILE_SCHEDULE);
  if (schedContent.length() == 0) schedContent = currentScheduleJson;
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
        doseStr = String(gSlots[i].prnQty) + (gSlots[i].prnQty > 1 ? " pills" : " pill");
        maxDayStr = String(gSlots[i].maxDosesPerDay) + (gSlots[i].maxDosesPerDay > 1 ? " doses" : " dose");
      } else {
        type = "Meal";
        int minQ = 999;
        int maxQ = 0;
        if (schedDoc["schedule"].is<JsonArray>()) {
          for (JsonObject item : schedDoc["schedule"].as<JsonArray>()) {
            int s = item["slot"] | item["s"] | 0;
            if (s == gSlots[i].number) {
              int q = item["qty"] | item["q"] | 1;
              if (q < minQ) minQ = q;
              if (q > maxQ) maxQ = q;
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
    Serial.printf("|  %2d  |    %3d    | %-8s | %-13s | %-8s | %-9s | %-28s |\n",
                  gSlots[i].number, gSlots[i].remaining, type.c_str(),
                  interval.c_str(), doseStr.c_str(), maxDayStr.c_str(), safeTruncateUtf8(med, 28).c_str());
  }
  Serial.println("+------+-----------+----------+---------------+----------+-----------+------------------------------+");
}

void printSerialSchedule() {
  String todayDate = getCurrentDateStr(0);
  Serial.printf("[ACTIVE SCHEDULE] - Today: %s\n", todayDate.c_str());
  String content = readStorageFile(FILE_SCHEDULE);
  if (content.length() == 0) content = currentScheduleJson;
#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
#else
  DynamicJsonDocument doc(2048);
#endif
  DeserializationError err = deserializeJson(doc, content);
  if (err || !doc["schedule"].is<JsonArray>() || doc["schedule"].as<JsonArray>().size() == 0) {
    Serial.println("+------------+------+-----+------------------------------+---------------+---------------+");
    Serial.println("| (No active medication schedule configured for today)                                        |");
    Serial.println("+------------+------+-----+------------------------------+---------------+---------------+");
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

  int histCount = histDoc["history"].is<JsonArray>() ? histDoc["history"].as<JsonArray>().size() : 0;
  bool matchedHistory[histCount > 0 ? histCount : 1];
  for (int k = 0; k < histCount; k++) matchedHistory[k] = false;

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
    r.minutes = (r.time.length() >= 5)
        ? (r.time.substring(0, 2).toInt() * 60 + r.time.substring(3, 5).toInt())
        : 0;
    rows.push_back(r);
  }

  // Sort rows chronologically by time, then by slot
  std::sort(rows.begin(), rows.end(), [](const DisplayRow &a, const DisplayRow &b) {
    if (a.minutes != b.minutes) return a.minutes < b.minutes;
    return a.slot < b.slot;
  });

  // Calculate current/closest meal minute
  int nowMinutes = -1;
  int closestMealMinutes = -1;
  int minDistance = 24 * 60 + 1;

  if (isTimeSynced) {
    String nowTime = getCurrentTimeHHMM();
    if (nowTime.length() >= 5) {
      nowMinutes = nowTime.substring(0, 2).toInt() * 60 + nowTime.substring(3, 5).toInt();
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

  Serial.println("+------------+------+-----+------------------------------+---------------+---------------+");
  Serial.println("| Time       | Slot | Qty | Medicine                     | Food Relation | Status        |");
  Serial.println("+------------+------+-----+------------------------------+---------------+---------------+");

  for (const auto &r : rows) {
    String statusStr = "[PENDING]";
    int matchedIdx = -1;

    if (histDoc["history"].is<JsonArray>()) {
      JsonArray hArr = histDoc["history"].as<JsonArray>();

      // 1st Pass: Match exact scheduled time
      for (int k = 0; k < histCount; k++) {
        if (matchedHistory[k]) continue;
        JsonObject h = hArr[k];
        String hDate = h["date"] | "";
        int hSlot = h["slot"] | 0;
        String hType = h["type"] | "";
        String hSched = h["sched_time"] | "";
        if (hDate == todayDate && hSlot == r.slot && hType == "meal" && hSched == r.time) {
          matchedIdx = k;
          break;
        }
      }

      // 2nd Pass: Match first available meal intake for this slot today without explicit sched_time
      if (matchedIdx == -1) {
        for (int k = 0; k < histCount; k++) {
          if (matchedHistory[k]) continue;
          JsonObject h = hArr[k];
          String hDate = h["date"] | "";
          int hSlot = h["slot"] | 0;
          String hType = h["type"] | "";
          String hSched = h["sched_time"] | "";
          if (hDate == todayDate && hSlot == r.slot && hType == "meal" && hSched.length() == 0) {
            matchedIdx = k;
            break;
          }
        }
      }
    }

    if (matchedIdx != -1) {
      matchedHistory[matchedIdx] = true;
      String hTime = histDoc["history"].as<JsonArray>()[matchedIdx]["time"] | "";
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
                  r.time.c_str(), r.slot, r.qty, safeTruncateUtf8(r.medicine, 28).c_str(),
                  r.food.c_str(), statusStr.c_str());
  }
  Serial.println("+------------+------+-----+------------------------------+---------------+---------------+");
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
  if (err || !doc["history"].is<JsonArray>() || doc["history"].as<JsonArray>().size() == 0) {
    Serial.println("+------------+-------+------+-----+------------------------------+------+---------+");
    Serial.println("| (No intake history recorded in the last 7 days)                                      |");
    Serial.println("+------------+-------+------+-----+------------------------------+------+---------+");
    return;
  }

  Serial.println("+------------+-------+------+-----+------------------------------+------+---------+");
  Serial.println("| Date       | Time  | Slot | Qty | Medicine                     | Type | Status  |");
  Serial.println("+------------+-------+------+-----+------------------------------+------+---------+");
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
  Serial.println("+------------+-------+------+-----+------------------------------+------+---------+");
}

void printAllSummary() {
  Serial.println("==================================================");
  Serial.println("  MeDisP - Smart Pill Dispenser (Data Summary)    ");
  Serial.println("==================================================");
  Serial.printf("Device ID     : %s\n", DEVICE_ID);
  Serial.println("Firmware      : 2.2.0");
  Serial.printf("Storage       : %s\n", isSdMounted ? "MicroSD Card (SPI)" : "LittleFS (Internal)");
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
  if (!Serial.available()) return;

  String line = Serial.readStringUntil('\n');
  line.trim();
  if (line.length() == 0) return;

  Serial.println("\n>> CLI: " + line);

  if (line == "help") {
    Serial.println("Available Debug Commands:");
    Serial.println("  get all              - View all dispenser state summary");
    Serial.println("  status               - View device status JSON");
    Serial.println("  slots                - View tabular list of all 6 slots");
    Serial.println("  schedule             - View today's active schedule & intake status");
    Serial.println("  history              - View 7-day intake history log");
    Serial.println("  time                 - View current system clock & epoch");
    Serial.println("  dispense <slot> [qty]- Test dispense on slot (1-6, optional qty)");
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
      if (qty <= 0) qty = 1;
    } else {
      slot = paramStr.toInt();
      if (slot >= 1 && slot <= NUM_SLOTS && gSlots[slot - 1].isPrn && gSlots[slot - 1].prnQty > 1) {
        qty = gSlots[slot - 1].prnQty;
      }
    }
    if (slot < 1 || slot > NUM_SLOTS) {
      Serial.println("[CLI] Invalid slot number (1-6). Usage: dispense <slot> [qty]");
      return;
    }
    String err;
    bool isSched = !gSlots[slot - 1].isPrn;
    if (executeDispense(slot, qty, gSlots[slot - 1].drugName, "CLI_MANUAL", err, isSched)) {
      Serial.printf("[CLI] Dispense successful for Slot %d (%d %s) [%s]!\n",
                    slot, qty, qty > 1 ? "pills" : "pill", isSched ? "Meal" : "PRN");
    } else {
      Serial.printf("[CLI] Dispense failed for Slot %d: %s\n", slot, err.c_str());
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
    if (pConfigChar) pConfigChar->setValue(currentScheduleJson.c_str());
    if (pStatusChar) pStatusChar->setValue(buildDeviceStatusJson().c_str());
    sendBleEvent("{\"event\":\"DISPENSER_RESET\",\"status\":\"success\"}");
    Serial.println("[CLI] Slots, schedule & history cleared (Factory Reset).");
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
void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n==================================================");
  Serial.println("  Smart Pill Dispenser (MeDisP) - Firmware 2.2.0  ");
  Serial.println("==================================================");

  setupStorage();

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
  Serial.println("[CLI] Serial CLI active. Type 'help' to view debug commands.\n");
}

void loop() {
  // 1. Process Serial CLI inputs for hardware debugging
  handleSerialCli();

  // 2. Process asynchronous BLE commands sent from Flutter App
  if (hasNewBleCommand) {
    hasNewBleCommand = false;
    String payload = pendingBleCommand;
    Serial.println("\n[BLE RECV] Processing command payload:");
    Serial.println(payload);
    processIncomingCommand(payload);
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
