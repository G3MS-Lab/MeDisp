#pragma once

#include "MeDisP_Config.h"

// ============================================================================
// Time Subsystem
// ============================================================================
inline void setSystemEpoch(unsigned long epoch) {
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

inline String getFormattedTime() {
  time_t now = time(nullptr);
  if (!isTimeSynced || now < 100000) {
    return "BOOT+" + String(millis() / 1000) + "s";
  }
  char buf[32];
  struct tm *tm_info = localtime(&now);
  strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", tm_info);
  return String(buf);
}

inline unsigned long getSystemEpoch() {
  return isTimeSynced ? (unsigned long)time(nullptr) : 0;
}

inline String getCurrentDateStr(int dayOffset) {
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

inline String getCurrentTimeHHMM() {
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
inline void ensureDirectory(const char *path) {
  if (pActiveFS) {
    pActiveFS->mkdir(path);
  }
}

inline bool writeStorageFile(const char *path, const String &data) {
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

inline String readStorageFile(const char *path) {
  if (!pActiveFS || !pActiveFS->exists(path))
    return "";
  File f = pActiveFS->open(path, FILE_READ);
  if (!f)
    return "";
  String content = f.readString();
  f.close();
  return content;
}

inline void initDefaultSlots() {
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

inline String getDrugIndication(int slotIdx) {
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

inline void parseAndApplySlots(const String &jsonStr) {
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

inline void saveSlotsToStorage() {
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

#if ARDUINOJSON_VERSION_MAJOR >= 7
inline void updateSlotScheduleInStorage(int slotNum, JsonArrayConst newItems) {
#else
inline void updateSlotScheduleInStorage(int slotNum, JsonArray newItems) {
#endif
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
#if ARDUINOJSON_VERSION_MAJOR >= 7
  for (JsonObjectConst item : newItems) {
#else
  for (JsonObject item : newItems) {
#endif
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
      // If schedule is cleared/empty for this slot but drug is configured, it is PRN
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
  Serial.printf("[STORAGE] Consolidated schedule for Slot %d (%d items, total %d bytes)\n",
                slotNum, newItems.size(), output.length());
}

inline void setupStorage() {
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

  // Clean up any legacy demo mock data marker if present
  if (pActiveFS && pActiveFS->exists("/config/.seeded")) {
    pActiveFS->remove("/config/.seeded");
    pActiveFS->remove(FILE_SLOTS);
    pActiveFS->remove(FILE_SCHEDULE);
    pActiveFS->remove(FILE_HISTORY);
    Serial.println("[STORAGE] Removed legacy demo mock data. Resetting to clean empty state.");
  }

  // Load slots from storage if existing, otherwise initialize clean empty slots
  if (pActiveFS && pActiveFS->exists(FILE_SLOTS)) {
    String slotsData = readStorageFile(FILE_SLOTS);
    parseAndApplySlots(slotsData);
    Serial.println("[STORAGE] Loaded slots from slots.json");
  } else {
    initDefaultSlots();
    saveSlotsToStorage();
    Serial.println("[STORAGE] Initialized clean empty slots 1-6 (no mock data).");
  }

  // Load schedule if existing, otherwise initialize clean empty schedule
  currentScheduleJson = readStorageFile(FILE_SCHEDULE);
  if (currentScheduleJson.length() == 0) {
    currentScheduleJson = "{\"device_id\":\"" DEVICE_ID "\",\"schedule\":[]}";
    writeStorageFile(FILE_SCHEDULE, currentScheduleJson);
    Serial.println("[STORAGE] Initialized clean empty schedule.");
  }

  // Initialize empty history if not existing
  if (pActiveFS && !pActiveFS->exists(FILE_HISTORY)) {
    writeStorageFile(FILE_HISTORY, "{\"history\":[]}");
    Serial.println("[STORAGE] Initialized clean empty history.");
  }
}

inline String findActiveScheduleTimeForSlot(int slot) {
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

inline void recordIntakeHistory(int slot, int qty, const String &medicine,
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

inline int countPrnIntakesToday(int slot) {
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

inline void seedDefaultDemoDataIfEmpty() {
  // Mock data removed per user request. System starts with completely clean empty state.
}

