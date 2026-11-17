#pragma once

#include "MeDisP_Config.h"

// ============================================================================
// BLE Helper Functions
// ============================================================================
inline void sendResponseNotification(const char *result, const char *message) {
  if (!pResponseChar)
    return;
  String payload = "{\"result\":\"" + String(result) + "\",\"message\":\"" +
                   String(message) + "\"}";
  pResponseChar->setValue(payload.c_str());
  pResponseChar->notify();
  Serial.printf("[BLE NOTIFY] %s -> %s\n", result, message);
}

inline void sendBleEvent(const String &eventJson) {
  if (!pResponseChar)
    return;
  pResponseChar->setValue(eventJson.c_str());
  pResponseChar->notify();
  Serial.printf("[BLE EVENT NOTIFY] %s\n", eventJson.c_str());
}

inline String buildDeviceStatusJson() {
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

inline bool executeDispense(int slot, int qty, const String &medicine,
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

// ============================================================================
// Decomposed BLE Command Handlers
// ============================================================================

// 0. PING-PONG HEARTBEAT COMMAND
inline void handleBlePing(const JsonDocument &doc, const String &reqId) {
  String res = "{\"event\":\"pong\",\"req_id\":\"" + reqId +
               "\",\"status\":\"ready\",\"time\":\"" + getFormattedTime() + "\"}";
  sendBleEvent(res);
  sendResponseNotification("success", "pong");
}

// 1a. DISPENSE COMMAND
inline void handleBleDispense(const JsonDocument &doc, const String &reqId) {
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
inline void handleBleRecordIntake(const JsonDocument &doc, const String &reqId) {
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

    int idx = slot - 1;
    if (gSlots[idx].remaining >= qty) {
      gSlots[idx].remaining -= qty;
    } else {
      gSlots[idx].remaining = 0;
    }
    saveSlotsToStorage();

    String hookErr = "";
    hardwareDispenseSlot(slot, qty, hookErr);

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
inline void handleBleSyncTime(const JsonDocument &doc, const String &reqId) {
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
inline void handleBleSyncSlots(const String &jsonPayload, const String &reqId) {
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
inline void handleBleSetSlotSchedule(const JsonDocument &doc, const String &reqId) {
  int slot = doc["slot"] | 0;
  if (slot >= 1 && slot <= NUM_SLOTS && doc["schedule"].is<JsonArrayConst>()) {
#if ARDUINOJSON_VERSION_MAJOR >= 7
    updateSlotScheduleInStorage(slot, doc["schedule"].as<JsonArrayConst>());
#else
    updateSlotScheduleInStorage(slot, doc["schedule"].as<JsonArray>());
#endif
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
inline void handleBleGetSchedule(const String &reqId) {
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
inline void handleBleSyncSchedule(const JsonDocument &doc, const String &jsonPayload, const String &reqId) {
  if (!doc.containsKey("device_id") ||
      doc["device_id"].as<String>().length() == 0) {
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
                     "\"time\":\"" +
                     getFormattedTime() + "\"}";
  sendBleEvent(eventJson);
  sendResponseNotification("success", "configuration stored");
  refreshCurrentNextionPage();
}

// 5. STATUS QUERY COMMAND
inline void handleBleGetSlotsOrStatus() {
  String status = buildDeviceStatusJson();
  if (pStatusChar) {
    pStatusChar->setValue(status.c_str());
  }
  sendResponseNotification("success", "Status updated");
}

// 6. FULL SYNC DATA COMMAND
inline void handleBleGetSyncData() {
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

// 7. UNLIMITED HISTORY SYNC COMMAND
inline void handleBleSyncHistory(const JsonDocument &doc, const String &reqId) {
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
inline void handleBleClearHistory(const JsonDocument &doc, const String &reqId) {
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
inline void handleBleFactoryReset() {
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
  refreshCurrentNextionPage();
}

// ============================================================================
// BLE Command Dispatcher Router
// ============================================================================
inline void processIncomingCommand(const String &jsonPayload) {
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

  if (cmd == "ping") {
    handleBlePing(doc, reqId);
  } else if (cmd == "dispense") {
    handleBleDispense(doc, reqId);
  } else if (cmd == "record_intake") {
    handleBleRecordIntake(doc, reqId);
  } else if (cmd == "sync_time") {
    handleBleSyncTime(doc, reqId);
  } else if (cmd == "sync_slots") {
    handleBleSyncSlots(jsonPayload, reqId);
  } else if (cmd == "set_slot_schedule") {
    handleBleSetSlotSchedule(doc, reqId);
  } else if (cmd == "get_schedule") {
    handleBleGetSchedule(reqId);
  } else if (cmd == "sync_schedule" || (cmd == "" && doc.containsKey("schedule"))) {
    handleBleSyncSchedule(doc, jsonPayload, reqId);
  } else if (cmd == "get_slots" || cmd == "get_status") {
    handleBleGetSlotsOrStatus();
  } else if (cmd == "get_sync_data") {
    handleBleGetSyncData();
  } else if (cmd == "sync_history" || cmd == "get_history") {
    handleBleSyncHistory(doc, reqId);
  } else if (cmd == "clear_history") {
    handleBleClearHistory(doc, reqId);
  } else if (cmd == "clear_data" || cmd == "factory_reset") {
    handleBleFactoryReset();
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
    Serial.printf("[BLE SERVER] Disconnected (reason %d). Restarting advertising...\n", reason);
    NimBLEDevice::startAdvertising();
  }
};

inline void setupBleServer() {
  Serial.println("\n[BLE] Initializing NimBLE Peripheral...");
  NimBLEDevice::init(DEVICE_NAME);
  NimBLEDevice::setMTU(517);

  NimBLEServer *pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  NimBLEService *pService = pServer->createService(SERVICE_UUID);

  // Config Characteristic: Read & Write commands
  pConfigChar = pService->createCharacteristic(
      CONFIG_CHAR_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR | NIMBLE_PROPERTY::READ);
  pConfigChar->setValue(currentScheduleJson.c_str());
  pConfigChar->setCallbacks(new ConfigCharacteristicCallbacks());

  // Status Characteristic: Read-only real-time state
  pStatusChar = pService->createCharacteristic(STATUS_CHAR_UUID, NIMBLE_PROPERTY::READ);
  pStatusChar->setValue(buildDeviceStatusJson().c_str());
  pStatusChar->setCallbacks(new StatusCharacteristicCallbacks());

  // Response Characteristic: Real-time Notify back to Flutter
  pResponseChar = pService->createCharacteristic(RESPONSE_CHAR_UUID, NIMBLE_PROPERTY::NOTIFY);
  pResponseChar->setValue("{\"result\":\"ready\",\"status\":\"standby\"}");

  pService->start();

  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();

  // Primary advertisement packet: Broadcast Device Name so every scanner sees "PillDispenser"
  NimBLEAdvertisementData advData;
  advData.setFlags(0x06); // General Discoverable + BR/EDR Not Supported
  advData.setName(DEVICE_NAME);
  pAdvertising->setAdvertisementData(advData);

  // Scan response packet: Holds Service UUID and full name
  NimBLEAdvertisementData scanData;
  scanData.setName(DEVICE_NAME);
  scanData.addServiceUUID(NimBLEUUID(SERVICE_UUID));
  pAdvertising->setScanResponseData(scanData);

  pAdvertising->enableScanResponse(true);
  pAdvertising->setMinInterval(32); // 20ms
  pAdvertising->setMaxInterval(64); // 40ms
  pAdvertising->start();

  Serial.println("[BLE] Advertising started successfully!");
  Serial.printf("[BLE] Device Name : %s\n", DEVICE_NAME);
  Serial.printf("[BLE] Service UUID: %s\n", SERVICE_UUID);
}

