#pragma once

#include "MeDisP_Config.h"

// ============================================================================
// Interactive Serial CLI (Hardware Debugging & Diagnostics)
// ============================================================================

inline void printSerialSlots() {
  Serial.println("[SLOTS INVENTORY]");
  Serial.println("+------+-----------+----------+---------------+----------+-----------+------------------------------+");
  Serial.println("| Slot | Remaining | Type     | PRN Interval  | Dose Qty | Max / Day | Drug Name                    |");
  Serial.println("+------+-----------+----------+---------------+----------+-----------+------------------------------+");

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
  Serial.println("+------+-----------+----------+---------------+----------+-----------+------------------------------+");
}

inline void printSerialSchedule() {
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
        if (matchedHistory[k])
          continue;
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
          if (matchedHistory[k])
            continue;
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
                  r.time.c_str(), r.slot, r.qty,
                  safeTruncateUtf8(r.medicine, 28).c_str(), r.food.c_str(),
                  statusStr.c_str());
  }
  Serial.println("+------------+------+-----+------------------------------+---------------+---------------+");
}

inline void printSerialHistory() {
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

inline void printAllSummary() {
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

// ============================================================================
// Decomposed Serial CLI Handlers
// ============================================================================

inline void cliHelp() {
  Serial.println("\n================================================================================");
  Serial.println("         MeDisP Interactive Serial CLI - Command Reference Manual              ");
  Serial.println("================================================================================");

  Serial.println("\n[GROUP 1: SYSTEM & INVENTORY STATUS] (Check system status & drug stock)");
  Serial.println("  status / all         : View full device status JSON & system health");
  Serial.println("  slots                : View formatted inventory table of all 6 slots");
  Serial.println("  schedule             : View today's active meal schedule & intake status");
  Serial.println("  history              : View 7-day pill intake history log");
  Serial.println("  time                 : View system clock, epoch timestamp & sync status");

  Serial.println("\n[GROUP 2: HARDWARE MECHANISM & DISPENSING] (Test motor, vacuum & mechanics)");
  Serial.println("  dispense <slot> [qty]: Trigger multi-step physical dispensing sequence (Core 0)");
  Serial.println("  ctrl status          : Ping Motor Controller UART link (Handshake check)");
  Serial.println("  ctrl <raw_cmd>       : Send raw command directly to Motor Controller");
  Serial.println("                         Examples: 'ctrl mr,0001', 'ctrl lr,down', 'ctrl ap,on',");
  Serial.println("                                   'ctrl status,apvac', 'ctrl lr,up', 'ctrl ap,off'");
  Serial.println("  container open|close : Open/close container door via servos ('so,180' / 'so,0')");
  Serial.println("  mock <on|off>        : Toggle simulated mock dispense vs real mechanism");

  Serial.println("\n[GROUP 3: NEXTION TOUCH SCREEN HMI] (Test Nextion display & UI navigation)");
  Serial.println("  req daily            : Force refresh & render Daily medication page");
  Serial.println("  req prn              : Force refresh & render PRN as-needed medication page");
  Serial.println("  req timeline         : Force refresh & render Timeline schedule page");
  Serial.println("  up / down            : Test scroll up / scroll down on active page");
  Serial.println("  prn 1 / 2 / 3        : Test selecting item 1, 2, or 3 on PRN page");
  Serial.println("  take                 : Simulate pressing 'Take' / 'Dispense' button on screen");
  Serial.println("  back                 : Simulate pressing 'Back' navigation button");

  Serial.println("\n[GROUP 4: STORAGE & HARDWARE DIAGNOSTICS] (Test MicroSD & storage persistence)");
  Serial.println("  sd test              : Exhaustive MicroSD hardware probe, speed & read/write test");
  Serial.println("  clear data           : Factory reset (wipe slots, schedule & history)");

  Serial.println("\n[GROUP 5: MEDICATION & TIME CONFIGURATION] (Configure pills & system clock)");
  Serial.println("  set slot <1-6> <med> [rem] [prn|meal] : Configure slot medication & stock");
  Serial.println("                                          Example: 'set slot 1 Paracetamol 10 meal'");
  Serial.println("  set prn <1-6> <true|false>            : Toggle PRN mode for specific slot");
  Serial.println("  sync_time <epoch>                     : Manually set system Unix timestamp");
  Serial.println("  reboot                                : Restart ESP32-S3");
  Serial.println("================================================================================\n");
}

inline void cliDispense(const String &paramStr) {
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
}

inline void cliSetSlot(const String &param) {
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
    Serial.println("[CLI] Usage: set slot <1-6> <drug_name> [remaining] [prn|meal]");
  }
}

inline void cliSetPrn(const String &param) {
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
      Serial.printf("[CLI] Slot %d isPrn set to %s\n", sNum, isP ? "TRUE" : "FALSE");
      refreshCurrentNextionPage();
    }
  }
}

inline void cliPrnStatus(const String &param) {
  int s = param.toInt();
  if (s >= 1 && s <= NUM_SLOTS) {
    PrnStatus st = checkPrnStatus(s);
    Serial.printf("[PRN STATUS] Slot %d (%s):\n", s, gSlots[s - 1].drugName.c_str());
    Serial.printf("  Ready: %s (Reason: %s, Btn: %s)\n",
                  st.isReady ? "YES" : "NO", st.reason.c_str(), st.buttonText.c_str());
    Serial.printf("  Remaining: %d, Taken Today: %d/%d\n", st.remaining, st.takenToday, st.maxDoses);
    Serial.printf("  Last Intake: %s, Next Allowed: %s\n", st.lastTakenTime.c_str(), st.nextAllowedTime.c_str());
    Serial.printf("  Indication: %s\n", getDrugIndication(s - 1).c_str());
  } else {
    Serial.println("[CLI] Invalid slot number (1-6)");
  }
}

inline void cliClearData() {
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
  handleReqDaily(true);
}

inline void cliNextion(const String &ncmd) {
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
}

inline void cliMock(const String &param) {
  String m = param;
  m.toLowerCase();
  if (m == "on" || m == "1" || m == "true") {
    gEnableMockDispense = true;
    Serial.println("[CLI] Mock dispense mode ENABLED (Simulated dispensing).");
  } else if (m == "off" || m == "0" || m == "false") {
    gEnableMockDispense = false;
    Serial.println("[CLI] Mock dispense mode DISABLED (Real motor controller active).");
  } else {
    Serial.printf("[CLI] Mock mode is currently: %s\n", gEnableMockDispense ? "ENABLED" : "DISABLED");
  }
}

inline void cliCtrl(const String &cmd) {
  String resp = "";
  Serial.printf("[CLI] Sending '%s' directly to motor controller...\n", cmd.c_str());
  if (sendCtrlCommandWaitResponse(cmd, "", resp, 5000)) {
    Serial.printf("[CLI] Controller response: %s\n", resp.c_str());
  } else {
    Serial.println("[CLI] No response from motor controller (timeout).");
  }
}

inline void cliContainer(const String &act) {
  String a = act;
  a.toLowerCase();
  if (a == "open") {
    serviceOpenPillContainer(true);
    Serial.println("[CLI] Container door opened for pill replenishment.");
  } else {
    serviceOpenPillContainer(false);
    Serial.println("[CLI] Container door closed.");
  }
}

inline void cliSdTest() {
  Serial.println("\n==================================================");
  Serial.println("  MicroSD Card Hardware Diagnostic Tool");
  Serial.println("==================================================");
  Serial.printf("Configured Pins : CS=IO%d, MOSI=IO%d, MISO=IO%d, SCK=IO%d\n",
                SD_CS_PIN, SD_MOSI_PIN, SD_MISO_PIN, SD_SCK_PIN);

  // 1. Check electrical idle state of MISO line
  pinMode(SD_CS_PIN, OUTPUT);
  digitalWrite(SD_CS_PIN, HIGH);
  pinMode(SD_MISO_PIN, INPUT_PULLUP);
  delay(10);
  int misoVal = digitalRead(SD_MISO_PIN);
  Serial.printf("1. Electrical Check: MISO Line is %s\n",
                misoVal == HIGH ? "HIGH (Normal with Pull-Up)" : "LOW (WARNING: Line pulled down or shorted!)");

  // 2. Hardware SPI Probe across frequencies
  uint32_t speeds[] = {4000000, 1000000, 400000};
  const char *speedNames[] = {"4 MHz (Standard)", "1 MHz (Low Speed)", "400 kHz (Safe Init)"};
  bool cardFound = false;

  for (int i = 0; i < 3; i++) {
    Serial.printf("\n2.%d Testing SPI Handshake at %s...\n", i + 1, speedNames[i]);
    SPI.begin(SD_SCK_PIN, SD_MISO_PIN, SD_MOSI_PIN, SD_CS_PIN);
    bool ok = SD.begin(SD_CS_PIN, SPI, speeds[i]);
    uint8_t cType = SD.cardType();

    Serial.printf("    Mount Result: %s\n", ok ? "SUCCESS (Mounted!)" : "FAILED");
    Serial.printf("    Detected Type: ");
    if (cType == CARD_NONE) {
      Serial.println("CARD_NONE (No response received from card)");
    } else if (cType == CARD_MMC) {
      Serial.println("CARD_MMC");
      cardFound = true;
    } else if (cType == CARD_SD) {
      Serial.println("CARD_SD (Standard Capacity <= 2GB)");
      cardFound = true;
    } else if (cType == CARD_SDHC) {
      Serial.println("CARD_SDHC (High Capacity / SDXC >= 4GB)");
      cardFound = true;
    } else {
      Serial.println("CARD_UNKNOWN");
      cardFound = true;
    }

    if (ok) {
      uint64_t bytes = SD.cardSize();
      Serial.printf("    ✓ Card Size  : %llu MB (%llu Bytes)\n", bytes / (1024 * 1024), bytes);
      Serial.printf("    ✓ Total Space: %llu MB | Used: %llu MB\n",
                    SD.totalBytes() / (1024 * 1024), SD.usedBytes() / (1024 * 1024));

      // Test File Read & Write
      Serial.println("    Testing file write & read on SD (/test_sd.tmp)...");
      File tf = SD.open("/test_sd.tmp", FILE_WRITE);
      if (tf) {
        tf.println("MeDisP_SD_OK_2026");
        tf.close();
        File rtf = SD.open("/test_sd.tmp", FILE_READ);
        if (rtf) {
          String s = rtf.readString();
          rtf.close();
          SD.remove("/test_sd.tmp");
          if (s.indexOf("MeDisP_SD_OK") >= 0) {
            Serial.println("    ✓ [VERIFIED] Read/Write test PASSED!");
          } else {
            Serial.println("    ⚠️ Read test returned unexpected content.");
          }
        }
      } else {
        Serial.println("    ❌ Failed to create test file on SD.");
      }

      isSdMounted = true;
      pActiveFS = &SD;
      Serial.println("\n✓ MicroSD is fully operational and active as primary storage!");
      return;
    }
    SD.end();
    delay(40);
  }

  Serial.println("\n--------------------------------------------------");
  Serial.println("  Diagnostic Analysis & Solutions");
  Serial.println("--------------------------------------------------");
  if (!cardFound) {
    Serial.println("❌ ERROR: Hardware not responding (CARD_NONE).");
    Serial.println("   Causes & Checks:");
    Serial.println("   1. Power (VCC): If module has a 3.3V regulator chip on board,");
    Serial.println("      it MUST be connected to 5V (VIN), NOT 3.3V.");
    Serial.println("   2. Wires: Check if MOSI and MISO are swapped!");
    Serial.println("      - ESP32 IO11 (MOSI) -> Module MOSI (or DI)");
    Serial.println("      - ESP32 IO13 (MISO) -> Module MISO (or DO)");
    Serial.println("      - ESP32 IO12 (SCK)  -> Module SCK (or CLK)");
    Serial.println("      - ESP32 IO14 (CS)   -> Module CS");
    Serial.println("   3. Insertion: Ensure MicroSD card is clicked fully into socket.");
  } else {
    Serial.println("❌ ERROR: Card was detected but could not mount filesystem.");
    Serial.println("   Cause:");
    Serial.println("   - The card is formatted as exFAT or NTFS! (Arduino SD only supports FAT32).");
    Serial.println("   - Solution: Format the MicroSD card as FAT32 on your PC.");
  }
  Serial.println("==================================================\n");
}

// ----------------------------------------------------------------------------
// Serial CLI Command Dispatcher
// ----------------------------------------------------------------------------
inline void handleSerialCli() {
  if (!Serial.available())
    return;

  String line = Serial.readStringUntil('\n');
  line.trim();
  if (line.length() == 0)
    return;

  Serial.println("\n>> CLI: " + line);

  if (line == "help") {
    cliHelp();
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
    cliDispense(line.substring(9));
  } else if (line.startsWith("set slot ")) {
    cliSetSlot(line.substring(9));
  } else if (line.startsWith("set prn ")) {
    cliSetPrn(line.substring(8));
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
      processNextionMessage(line == "up" ? "CMD:TIMELINE_UP" : "CMD:TIMELINE_DOWN");
    } else if (gCurrentNextionPage == "Daily") {
      processNextionMessage(line == "up" ? "CMD:DAILY_UP" : "CMD:DAILY_DOWN");
    } else {
      processNextionMessage(line == "up" ? "CMD:PRN_UP" : "CMD:PRN_DOWN");
    }
  } else if (line == "prn up" || line == "prn down" ||
             line == "timeline up" || line == "timeline down" ||
             line == "daily up" || line == "daily down") {
    String c = line;
    c.toUpperCase();
    c.replace(" ", "_");
    processNextionMessage("CMD:" + c);
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
    cliPrnStatus(line.substring(11));
  } else if (line.startsWith("sync_time ")) {
    unsigned long epoch = strtoul(line.substring(10).c_str(), nullptr, 10);
    setSystemEpoch(epoch);
  } else if (line == "clear data") {
    cliClearData();
  } else if (line == "sd test" || line == "sd" || line == "test sd") {
    cliSdTest();
  } else if (line.startsWith("mock ")) {
    cliMock(line.substring(5));
  } else if (line.startsWith("ctrl ")) {
    cliCtrl(line.substring(5));
  } else if (line.startsWith("container ")) {
    cliContainer(line.substring(10));
  } else if (line.startsWith("nextion ")) {
    cliNextion(line.substring(8));
  } else if (line == "reboot") {
    Serial.println("[CLI] Rebooting ESP32...");
    delay(300);
    ESP.restart();
  } else {
    Serial.println("Unknown command! Type 'help' for options.");
  }
}

