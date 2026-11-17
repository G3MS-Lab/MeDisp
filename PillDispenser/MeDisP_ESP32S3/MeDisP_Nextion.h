#pragma once

#include "MeDisP_Config.h"

// ============================================================================
// Nextion Display HMI Subsystem (MeDisP HMI v1.1 - Modals & Scrolling)
// ----------------------------------------------------------------------------
// Architectural Division of Nextion Responsibilities:
//
// [GROUP A]: HMI Static Styling (Configured directly in Nextion Editor .HMI)
//   - Page layouts, background images (pic), and icon assets
//   - Font sizes, font families, and character encodings
//   - Component (x, y, w, h) coordinates and initial default colors (pco, bco)
//   - Static UI text labels (headers, page titles, fixed button labels)
//   - Touch release events with "Send Component ID" checked
//
// [GROUP B]: Real-time Dynamic Data (Sent by ESP32 MCU over UART Serial)
//   - Active page transitions: nextionSend("page Daily"), "page Success", etc.
//   - Live schedule & drug names: nextionSetText("tDailyPill", "...")
//   - Live PRN status & stock: nextionSetText("tPrnQty0", "...")
//   - Real-time safety locks: nextionSend("tsw bDispense,1"), "tsw bDispense,0"
//   - Hardware progress bars: nextionSend("jProgress.val=...")
// ============================================================================

// Convert/Transliterate medication name for Nextion's ISO-8859-1 font
inline String formatNextionDrugName(const String &rawName, int slotNum) {
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

// ----------------------------------------------------------------------------
// High-Speed Nextion Serial Primitives
// ----------------------------------------------------------------------------
// Set DEBUG_NEXTION to true if you need verbose logging of every Nextion TX command
#ifndef DEBUG_NEXTION
#define DEBUG_NEXTION false
#endif

inline void nextionSend(const String &cmd) {
  NextionSerial.print(cmd);
  NextionSerial.write(0xFF);
  NextionSerial.write(0xFF);
  NextionSerial.write(0xFF);
#if DEBUG_NEXTION
  Serial.printf("[NEXTION SEND] %s\n", cmd.c_str());
#endif
}

inline void nextionSetText(const char *comp, const String &val) {
  String sanitized = val;
  sanitized.replace('"', '\'');
  NextionSerial.print(comp);
  NextionSerial.print(".txt=\"");
  NextionSerial.print(sanitized);
  NextionSerial.print("\"");
  NextionSerial.write(0xFF);
  NextionSerial.write(0xFF);
  NextionSerial.write(0xFF);
#if DEBUG_NEXTION
  Serial.printf("[NEXTION SEND] %s.txt=\"%s\"\n", comp, sanitized.c_str());
#endif
}

inline void nextionSetVisible(const char *comp, bool vis) {
  NextionSerial.print("vis ");
  NextionSerial.print(comp);
  NextionSerial.print(vis ? ",1" : ",0");
  NextionSerial.write(0xFF);
  NextionSerial.write(0xFF);
  NextionSerial.write(0xFF);
#if DEBUG_NEXTION
  Serial.printf("[NEXTION SEND] vis %s,%d\n", comp, vis ? 1 : 0);
#endif
}

inline void nextionRef(const char *comp) {
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

inline void nextionFlush() { NextionSerial.flush(); }

inline void nextionSetPage(const char *pageName) {
  gCurrentNextionPage = pageName;
  nextionSend(String("page ") + pageName);
}

inline void nextionSetNavTabsVisible(bool visible) {
  nextionSetVisible("bDailypage", visible);
  nextionSetVisible("bPRNpage", visible);
  nextionSetVisible("bTimelinepage", visible);
}

inline void nextionApplyPageStaticStyle(const char* pageName) {
  if (strcmp(pageName, "Daily") == 0) {
    nextionSend(NextionHmiStyle::TAB_DAILY_ACTIVE);
    nextionSend(NextionHmiStyle::TAB_PRN_INACTIVE);
    nextionSend(NextionHmiStyle::TAB_TIME_INACTIVE);
  } else if (strcmp(pageName, "PRN") == 0) {
    nextionSend(NextionHmiStyle::TAB_PRN_ACTIVE);
    nextionSend(NextionHmiStyle::TAB_DAILY_INACTIVE);
    nextionSend(NextionHmiStyle::TAB_TIME_INACTIVE);
  } else if (strcmp(pageName, "Timeline") == 0) {
    nextionSend(NextionHmiStyle::TAB_TIME_ACTIVE);
    nextionSend(NextionHmiStyle::TAB_DAILY_INACTIVE);
    nextionSend(NextionHmiStyle::TAB_PRN_INACTIVE);
  }
}

inline void nextionSetDispenseButtonState(const String &btnText, bool isReady) {
  nextionSetText("bDispense", btnText);
  if (isReady) {
    nextionSend(NextionLiveCtrl::BTN_DISPENSE_ACTIVE);
    nextionSend(NextionLiveCtrl::BTN_DISPENSE_UNLOCK);
  } else {
    nextionSend(NextionLiveCtrl::BTN_DISPENSE_DISABLED);
    nextionSend(NextionLiveCtrl::BTN_DISPENSE_LOCK);
  }
}

inline String getMealNameFromTime(const String &timeStr) {
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
// Helper: Check if all scheduled doses for a specific meal time were taken today
// ----------------------------------------------------------------------------
inline bool isScheduledMealCompletedToday(const String &mealTime) {
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
          (status.equalsIgnoreCase("taken") || status.equalsIgnoreCase("TAKEN")) &&
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
inline PrnStatus checkPrnStatus(int slot) {
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
// 1. REQ:DAILY - Populate Daily Scheduled Meals
// ----------------------------------------------------------------------------
inline void handleReqDaily(bool resetOffset) {
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
      nextionSend("tsw bDispense,0");     // DISABLE TOUCH
      nextionSetVisible("bDispense", true);
    } else if (totalPills > 0) {
      nextionSetText("bDispense", "TAKE MEDICINE");
      nextionSend("bDispense.bco=9308");  // Active teal
      nextionSend("bDispense.pco=65535");
      nextionSend("tsw bDispense,1");     // ENABLE TOUCH
      nextionSetVisible("bDispense", true);
    } else {
      nextionSetText("bDispense", "NO MEDS");
      nextionSend("bDispense.bco=50712"); // Disabled gray
      nextionSend("bDispense.pco=65535");
      nextionSend("tsw bDispense,0");     // DISABLE TOUCH
      nextionSetVisible("bDispense", true);
    }

    // Overflow scrolling controls for >3 drugs
    if (totalPills > 3) {
      if (gDailyOffset > 0) {
        nextionSetText("bScrollup", "Up");
        nextionSend("bScrollup.bco=50712");
        nextionSend("bScrollup.pco=65535");
        nextionSetVisible("bScrollup", true);
        nextionSend("tsw bScrollup,1");
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

  nextionFlush();
}

// ----------------------------------------------------------------------------
// 2. REQ:PRN - Populate PRN Medication List
// ----------------------------------------------------------------------------
inline void handleReqPrn() {
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

  // FALLBACK: If no slots are marked isPrn, allow user to access any configured slot
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
      nextionSetText(tName, (r == 0 && totalPrn == 0) ? "No PRN configured" : "");
      nextionSetText(tQName, "");
      nextionSend("tsw " + tName + ",0");
      nextionSend("tsw " + tQName + ",0");
    }
  }

  if (totalPrn > 0) {
    nextionSetText("bDispense", "PLEASE SELECT A MEDICINE");
  } else {
    nextionSetText("bDispense", "NO PRN MEDICATIONS");
  }
  nextionSend("bDispense.bco=50712"); // Inactive gray
  nextionSend("bDispense.pco=65535"); // White text
  nextionSend("tsw bDispense,1");     // Touch enabled fallback
  nextionSetVisible("bDispense", true);

  if (totalPrn > 3) {
    if (gPrnOffset > 0) {
      nextionSetText("bScrollup", "Up");
      nextionSend("bScrollup.bco=50712");
      nextionSend("bScrollup.pco=65535");
      nextionSetVisible("bScrollup", true);
      nextionSend("tsw bScrollup,1");
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

  nextionFlush();
}

// ----------------------------------------------------------------------------
// 3. REQ:PRN_DETAIL - Detailed Info for Selected PRN Drug & Readiness Guard
// ----------------------------------------------------------------------------
inline void handleReqPrnDetail() {
  gCurrentNextionPage = "PRNDetail";
  nextionSetText("tTime", getCurrentTimeHHMM());

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
  nextionSetText("tNextTime", med + " (" + String(qty) + (qty > 1 ? " tabs)" : " tab)"));
  nextionSetText("tMeal", String(qty) + (qty > 1 ? " TABLETS" : " TABLET"));
  nextionSetText("tBeforeAfter", "AS NEEDED");

  // 2. Detail Rows:
  nextionSetText("t0", "Indication");
  nextionSetText("tQ0", getDrugIndication(idx));

  nextionSetText("t1", "Last intake");
  nextionSetText("tQ1", st.lastTakenTime);

  nextionSetText("t2", "Next dose");
  nextionSetText("tQ2", st.nextAllowedTime);

  // 3. Live Action button state
  nextionSetDispenseButtonState(st.buttonText, st.isReady);
  nextionSetVisible("bDispense", true);

  // 4. Back button styling
  nextionSetText("bScrollup", "< BACK");
  nextionSend(NextionHmiStyle::BTN_SCROLL_BG);
  nextionSend("bScrollup." + String(NextionHmiStyle::TEXT_WHITE));
  nextionSend("tsw bScrollup,1");
  nextionSetVisible("bScrollup", true);

  nextionSetVisible("bScrolldown", false);
  nextionSend("tsw bScrolldown,0");

  nextionFlush();
}

// ----------------------------------------------------------------------------
// 4. REQ:TIMELINE - Populate Full 24h Today Schedule + History (Chronological)
// ----------------------------------------------------------------------------
inline void handleReqTimeline(bool resetOffset) {
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
        int m = (t.length() >= 5) ? (t.substring(0, 2).toInt() * 60 + t.substring(3, 5).toInt()) : 0;
        TimelineRecord rec;
        rec.minutes = m;
        rec.timeStr = t;
        rec.title = "PRN: " + (med.length() > 0 ? formatNextionDrugName(med, h["slot"] | 1) : "Medication");
        rec.status = (st == "taken" || st == "TAKEN") ? "TAKEN" : st;
        dayTimeline.push_back(rec);
      }
    }
  }

  // 2. Process all Daily Scheduled Meals for today
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
      nextionSetText(tName, dayTimeline[itemIdx].timeStr + "  " + dayTimeline[itemIdx].title);
      nextionSetText(tQName, dayTimeline[itemIdx].status);
    } else {
      nextionSetText(tName, (r == 0 && totalRecords == 0) ? "No timeline for today" : "");
      nextionSetText(tQName, "");
    }
  }

  nextionSetText("bDispense", "BACK TO DAILY");
  nextionSend("bDispense.bco=9308");
  nextionSend("bDispense.pco=65535");
  nextionSend("tsw bDispense,1");
  nextionSetVisible("bDispense", true);

  if (totalRecords > 3) {
    if (gTimelineOffset > 0) {
      nextionSetText("bScrollup", "Up");
      nextionSend("bScrollup.bco=50712");
      nextionSend("bScrollup.pco=65535");
      nextionSetVisible("bScrollup", true);
      nextionSend("tsw bScrollup,1");
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

  nextionFlush();
}

// ----------------------------------------------------------------------------
// 5. REQ:CONFIRM - Modal Confirmation Page
// ----------------------------------------------------------------------------
inline void handleReqConfirm() {
  gCurrentNextionPage = "Confirm";
  nextionSetText("tTime", getCurrentTimeHHMM());

  bool canConfirm = false;

  if (gIsConfirmingPrn) {
    int idx = (gSelectedPrnSlot >= 1 && gSelectedPrnSlot <= NUM_SLOTS)
                  ? (gSelectedPrnSlot - 1)
                  : 0;
    String medName = formatNextionDrugName(gSlots[idx].drugName, idx + 1);
    int qty = gSlots[idx].prnQty > 0 ? gSlots[idx].prnQty : 1;
    PrnStatus st = checkPrnStatus(gSelectedPrnSlot);

    canConfirm = st.isReady;

    nextionSetText("tNextDose", "Confirm PRN dose");
    nextionSetText("tNextTime", medName + " (" + String(qty) + (qty > 1 ? " tabs)" : " tab)"));
    nextionSetText("tMeal", "PRN");
    nextionSetText("tBeforeAfter", "AS NEEDED");

    nextionSetText("t0", medName);
    nextionSetText("tQ0", String(qty) + (qty > 1 ? " tablets" : " tablet"));
    nextionSetText("t1", "Indication: " + getDrugIndication(idx));
    nextionSetText("tQ1", "Left: " + String(st.remaining));
    nextionSetText("t2", st.isReady ? "Please confirm to dispense" : st.reason);
    nextionSetText("tQ2", st.isReady ? "READY" : "WAIT");

    // Dynamic Navbar styling
    nextionSend("bPRNpage.bco=29369");
    nextionSend("bPRNpage.pco=65535");
    nextionSend("bDailypage.bco=50712");
    nextionSend("bDailypage.pco=0");
    nextionSend("bTimelinepage.bco=50712");
    nextionSend("bTimelinepage.pco=0");
  } else {
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
    nextionSetText("tNextTime", gActiveMealTime.length() > 0 ? gActiveMealTime : "--:--");
    nextionSetText("tMeal", getMealNameFromTime(gActiveMealTime));
    nextionSetText("tBeforeAfter", gActiveBeforeFood ? "BEFORE MEAL" : "AFTER MEAL");

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
    nextionSend("tsw bDispense,1");     // ENABLE TOUCH
  } else {
    nextionSetText("bDispense", "NOT READY");
    nextionSend("bDispense.bco=50712"); // Disabled gray
    nextionSend("bDispense.pco=65535");
    nextionSend("tsw bDispense,0");     // DISABLE TOUCH
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
inline void handleReqAlert() {
  gCurrentNextionPage = "Alert";
  nextionSetText("tTime", getCurrentTimeHHMM());
  nextionSetText("tNextDose", "Dose reminder");
  nextionSetText("tNextTime", "Time to take medicine");
  nextionSetText("tMeal", getMealNameFromTime(gActiveMealTime));
  nextionSetText("tBeforeAfter", gActiveBeforeFood ? "BEFORE MEAL" : "AFTER MEAL");

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
inline void handleReqDispensing() {
  gCurrentNextionPage = "Dispensing";
  nextionSetText("tTime", getCurrentTimeHHMM());
  nextionSetText("tNextDose", gIsConfirmingPrn ? "Dispensing PRN" : "Dispensing");
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
inline void handleReqSuccess() {
  gCurrentNextionPage = "Success";
  nextionSetText("tTime", getCurrentTimeHHMM());
  nextionSetText("tNextDose", gIsConfirmingPrn ? "PRN dose complete" : "Dose complete");
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
// Dynamic Page Refresh Helper
// ----------------------------------------------------------------------------
inline void refreshCurrentNextionPage() {
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

// ============================================================================
// Decomposed Nextion Action Handlers
// ============================================================================

inline void handleNextionPageReq(const String &msg) {
  if (msg.equalsIgnoreCase("REQ:DAILY") || msg.equalsIgnoreCase("NAV:DAILY")) {
    if ((gIsConfirmingPrn ||
         (gLastDispensedWasPrn && (millis() - gLastDispenseMs < 6000))) &&
        msg.equalsIgnoreCase("REQ:DAILY")) {
      // Screen locally jumped to Daily during/after PRN flow: redirect back to PRN!
      gIsConfirmingPrn = false;
      gLastDispensedWasPrn = false;
      gCurrentNextionPage = "PRN";
      nextionSend("page PRN");
      handleReqPrn();
    } else {
      gIsConfirmingPrn = false;
      handleReqDaily(true);
    }
  } else if (msg.equalsIgnoreCase("REQ:PRN") || msg.equalsIgnoreCase("NAV:PRN")) {
    gIsConfirmingPrn = false;
    handleReqPrn();
  } else if (msg.equalsIgnoreCase("REQ:PRN_DETAIL") || msg.equalsIgnoreCase("REQ:PRNDETAIL")) {
    handleReqPrnDetail();
  } else if (msg.equalsIgnoreCase("REQ:TIMELINE") || msg.equalsIgnoreCase("NAV:TIMELINE")) {
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
}

inline void handleNextionScroll(const String &msg) {
  if (msg.equalsIgnoreCase("CMD:DAILY_UP") ||
      (gCurrentNextionPage == "Daily" && (msg.equalsIgnoreCase("CMD:SCROLL_UP") || msg.equalsIgnoreCase("CMD:UP")))) {
    if (gDailyOffset > 0)
      gDailyOffset--;
    handleReqDaily(false);
  } else if (msg.equalsIgnoreCase("CMD:DAILY_DOWN") ||
             (gCurrentNextionPage == "Daily" && (msg.equalsIgnoreCase("CMD:SCROLL_DOWN") || msg.equalsIgnoreCase("CMD:DOWN")))) {
    gDailyOffset++;
    handleReqDaily(false);
  } else if (msg.equalsIgnoreCase("CMD:PRN_UP") ||
             (gCurrentNextionPage == "PRN" && (msg.equalsIgnoreCase("CMD:SCROLL_UP") || msg.equalsIgnoreCase("CMD:UP")))) {
    if (gPrnOffset > 0)
      gPrnOffset--;
    handleReqPrn();
  } else if (msg.equalsIgnoreCase("CMD:PRN_DOWN") ||
             (gCurrentNextionPage == "PRN" && (msg.equalsIgnoreCase("CMD:SCROLL_DOWN") || msg.equalsIgnoreCase("CMD:DOWN")))) {
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
             (gCurrentNextionPage == "Timeline" && (msg.equalsIgnoreCase("CMD:SCROLL_UP") || msg.equalsIgnoreCase("CMD:UP")))) {
    if (gTimelineOffset > 0)
      gTimelineOffset--;
    handleReqTimeline(false);
  } else if (msg.equalsIgnoreCase("CMD:TIMELINE_DOWN") ||
             (gCurrentNextionPage == "Timeline" && (msg.equalsIgnoreCase("CMD:SCROLL_DOWN") || msg.equalsIgnoreCase("CMD:DOWN")))) {
    gTimelineOffset++;
    handleReqTimeline(false);
  }
}

inline void handleNextionPrnSelect(int rowSelected) {
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

inline void handleNextionDailyTake() {
  if (gCurrentNextionPage == "PRN") {
    handleNextionPrnSelect(0);
    return;
  }
  if (gCurrentNextionPage == "PRNDetail") {
    handleNextionPrnTake();
    return;
  }
  if (gCurrentNextionPage == "Confirm") {
    handleNextionConfirm();
    return;
  }

  if (gActiveMealTime.length() == 0) {
    handleReqDaily(false);
  }
  if (gActiveMealTime.length() == 0) {
    Serial.println("[DAILY REJECT] No active meal scheduled. Staying on Daily.");
    handleReqDaily(false);
    return;
  }
  if (isScheduledMealCompletedToday(gActiveMealTime)) {
    Serial.printf("[DAILY REJECT] Meal at %s already completed today.\n", gActiveMealTime.c_str());
    handleReqDaily(false);
    return;
  }
  gIsConfirmingPrn = false;
  gCurrentNextionPage = "Confirm";
  nextionSend("page Confirm");
  handleReqConfirm();
}

inline void handleNextionPrnTake() {
  if (gCurrentNextionPage == "PRN") {
    handleNextionPrnSelect(0);
    return;
  }
  PrnStatus st = checkPrnStatus(gSelectedPrnSlot);
  if (!st.isReady) {
    Serial.printf("[PRN REJECT] Slot %d is not ready (%s). Staying on PRNDetail.\n",
                  gSelectedPrnSlot, st.reason.c_str());
    handleReqPrnDetail();
    return;
  }
  gIsConfirmingPrn = true;
  gCurrentNextionPage = "Confirm";
  nextionSend("page Confirm");
  handleReqConfirm();
}

inline void handleNextionConfirm() {
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
    int s = gSelectedPrnSlot;
    int q = (s >= 1 && s <= NUM_SLOTS && gSlots[s - 1].prnQty > 0)
                ? gSlots[s - 1].prnQty
                : 1;
    String med = (s >= 1 && s <= NUM_SLOTS) ? gSlots[s - 1].drugName : "PRN Medication";
    String err = "";
    executeDispense(s, q, med, "NEXTION_PRN", err, false, "");
  } else {
    gLastDispensedWasPrn = false;
    gLastDispenseMs = millis();
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
          executeDispense(s, q, med, "NEXTION_HMI", err, true, gActiveMealTime);
        }
      }
    }
  }

  delay(200);
  gCurrentNextionPage = "Success";
  nextionSend("page Success");
  delay(30);
  handleReqSuccess();
}

inline void handleNextionCancel() {
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
}

inline void handleNextionBack() {
  gIsConfirmingPrn = false;
  gLastDispensedWasPrn = false;
  gCurrentNextionPage = "PRN";
  nextionSend("page PRN");
  delay(60);
  handleReqPrn();
}

// ----------------------------------------------------------------------------
// Nextion Message Router
// ----------------------------------------------------------------------------
inline void processNextionMessage(String msg) {
  msg.trim();
  if (msg.length() == 0)
    return;

  // Filter out electrical floating noise: only process valid protocol commands
  if (!msg.startsWith("REQ:") && !msg.startsWith("NAV:") && !msg.startsWith("CMD:") &&
      !msg.equalsIgnoreCase("take") && !msg.equalsIgnoreCase("dispense")) {
    return;
  }

  Serial.printf("[NEXTION RECV] %s\n", msg.c_str());

  if (msg.startsWith("REQ:") || msg.startsWith("NAV:") || msg.equalsIgnoreCase("REQ:PRNDETAIL")) {
    handleNextionPageReq(msg);
  } else if (msg.startsWith("CMD:") && (msg.indexOf("UP") >= 0 || msg.indexOf("DOWN") >= 0 || msg.indexOf("SCROLL") >= 0)) {
    handleNextionScroll(msg);
  } else if (msg.equalsIgnoreCase("CMD:PRN_SELECT_1")) {
    handleNextionPrnSelect(0);
  } else if (msg.equalsIgnoreCase("CMD:PRN_SELECT_2")) {
    handleNextionPrnSelect(1);
  } else if (msg.equalsIgnoreCase("CMD:PRN_SELECT_3")) {
    handleNextionPrnSelect(2);
  } else if (msg.equalsIgnoreCase("CMD:DAILY_TAKE") || msg.equalsIgnoreCase("CMD:ALERT_TAKE") ||
             msg.equalsIgnoreCase("CMD:TAKE_PILL") || msg.equalsIgnoreCase("take pill") ||
             msg.equalsIgnoreCase("take_pill") || msg.equalsIgnoreCase("CMD:TAKE") || msg.equalsIgnoreCase("take")) {
    handleNextionDailyTake();
  } else if (msg.equalsIgnoreCase("CMD:PRN_TAKE")) {
    handleNextionPrnTake();
  } else if (msg.equalsIgnoreCase("CMD:CONFIRM") || msg.equalsIgnoreCase("confirm") ||
             msg.equalsIgnoreCase("CMD:DISPENSE") || msg.equalsIgnoreCase("dispense")) {
    handleNextionConfirm();
  } else if (msg.equalsIgnoreCase("CMD:CANCEL") || msg.equalsIgnoreCase("CMD:DISPENSING_CANCEL") ||
             msg.equalsIgnoreCase("CMD:SUCCESS_OK") || msg.equalsIgnoreCase("CMD:ALERT_LATER")) {
    handleNextionCancel();
  } else if (msg.equalsIgnoreCase("CMD:BACK")) {
    handleNextionBack();
  }
}

// ----------------------------------------------------------------------------
// High-Reliability Nextion Serial Receiver
// ----------------------------------------------------------------------------
inline void handleNextionIncoming() {
  static String rxBuf = "";
  static unsigned long lastCharMs = 0;
  static uint8_t rawBuf[16];
  static int rawIdx = 0;

  while (NextionSerial.available() > 0) {
    uint8_t b = NextionSerial.read();
    lastCharMs = millis();

    // Check for Nextion 0x65 touch event packet
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
          // If not a valid 0x65 packet, recover buffered bytes back into rxBuf
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

  // Auto-update time on Nextion every minute
  static String lastMin = "";
  String currentMin = getCurrentTimeHHMM();
  if (currentMin != lastMin && currentMin != "--:--") {
    lastMin = currentMin;
    nextionSetText("tTime", currentMin);
    nextionFlush();
    if (gCurrentNextionPage == "Daily") {
      handleReqDaily(false);
    }
    Serial.println("[NEXTION PUSH] Auto-updated display for minute: " + currentMin);
  }
}

