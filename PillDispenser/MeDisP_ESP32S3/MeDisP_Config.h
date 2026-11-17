#pragma once

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
#include <queue>
#include <algorithm>

// ============================================================================
// Hardware Pinout Definitions (Aligned with Official Wiring Diagram)
// ============================================================================
// MicroSD SPI Pins (ESP32-S3 default FSPI bus)
#define SD_CS_PIN 14        // IO14: SPI CS (Chip Select)
#define SD_MOSI_PIN 11      // IO11: SPI MOSI
#define SD_MISO_PIN 13      // IO13: SPI MISO
#define SD_SCK_PIN 12       // IO12: SPI CLK (Clock)

// UART Port 1: Nextion HMI Display
#define NEXTION_TX_PIN 17   // IO17: TX to HMI RX (Yellow wire)
#define NEXTION_RX_PIN 18   // IO18: RX from HMI TX (Orange wire)
#define NEXTION_BAUD 9600

// UART Port 2: Mechanism / Motor Controller (ESP32)
#define CTRL_TX_PIN 15      // IO15: TX to Motor ESP RX IO16 (Dark Blue wire)
#define CTRL_RX_PIN 16      // IO16: RX from Motor ESP TX IO17 (Cyan wire)
#define CTRL_BAUD 115200

// I2S Audio Subsystem (PCM5102 DAC -> TDA2030 Amplifier)
#define I2S_BCK_PIN 4       // IO04: I2S BCK Bit Clock (Green wire)
#define I2S_LCK_PIN 5       // IO05: I2S LCK Word Select / LRCK (Purple wire)
#define I2S_DIN_PIN 6       // IO06: I2S DIN Serial Data (Mint wire)

// I2C Bus (Sensors / Peripherals)
#define I2C_SDA_PIN 8       // IO08: I2C SDA
#define I2C_SCL_PIN 3       // IO03: I2C SCL

// Onboard Status Indication
#define RGB_LED_PIN 38      // IO38: Onboard Addressable RGB LED

// ============================================================================
// BLE GATT UUID Definitions
// ============================================================================
#define SERVICE_UUID "12345678-1234-1234-1234-123456789000"
#define CONFIG_CHAR_UUID "12345678-1234-1234-1234-123456789001"   // Write/Read
#define STATUS_CHAR_UUID "12345678-1234-1234-1234-123456789002"   // Read
#define RESPONSE_CHAR_UUID "12345678-1234-1234-1234-123456789003" // Notify

#define DEVICE_NAME "PillDispenser"
#define DEVICE_ID "PD001"
#define NUM_SLOTS 6

// ============================================================================
// Storage File Paths (Dual Storage: SD Card with LittleFS fallback)
// ============================================================================
#define PATH_DIR_CONFIG "/config"
#define FILE_SCHEDULE "/config/schedule.json"
#define FILE_SLOTS "/config/slots.json"
#define FILE_HISTORY "/config/history.json"

// Periodic Time Sync Request (every 15 minutes)
#define TIME_SYNC_INTERVAL_MS 900000UL

// ============================================================================
// Nextion Display HMI Architecture & Registry (MeDisP HMI v1.1)
// ----------------------------------------------------------------------------
// [GROUP A]: STATIC ASSETS & STYLING (EDITABLE DIRECTLY IN NEXTION EDITOR .HMI)
// - Wallpapers & Icons (pic, picc)
// - Typography & Fonts (font family, font sizes, ISO-8859-1 ascii mapping)
// - Default Component Geometries (x, y, w, h) & Touch Event Triggers
// - Static Labels (Page titles, fixed button labels, e.g. "Take", "Cancel")
// - Default Color Palette (bco, pco)
// * Modifying these directly in Nextion Editor does NOT require ESP32 code changes!
// ----------------------------------------------------------------------------
// [GROUP B]: REAL-TIME DYNAMIC DATA (SENT BY ESP32 FIRMWARE OVER UART)
// - Active Page Routing (page Daily, page Dispensing, page Success, etc.)
// - Live Drug Names, Schedules & Dose Info (tDailyTime.txt, tDailyPill.txt, etc.)
// - Live PRN Status, Stocks & Countdown Timers (tPrnName0..3, tPrnQty0..3, etc.)
// - Real-time Safety Guard & Button Locks (tsw bDispense,1/0, bco color transitions)
// - Hardware Dispense Progress Bar (jProgress.val = 0..100)
// - Real-time Epoch Clock Sync (tClock.txt = "HH:MM")
// ============================================================================

// Standard Nextion RGB565 Color Codes
#define COLOR_WHITE 65535         // 0xFFFF
#define COLOR_NAVY_HEADER 9308    // 0x245C (Main pages)
#define COLOR_ORANGE_ALERT 64512  // 0xFC00 (Alert page)
#define COLOR_GREEN_SUCCESS 2016  // 0x07E0 (Success page)
#define COLOR_SLATE_CONFIRM 25388 // 0x632C (Confirm modal)
#define COLOR_BLUE_DISPENSE 11126 // 0x2B76 (Dispensing modal)

// ----------------------------------------------------------------------------
// [GROUP A]: HMI Static Fallback Commands
// (Can be configured inside the .HMI project file so the MCU doesn't need to send them)
// ----------------------------------------------------------------------------
namespace NextionHmiStyle {
  // Navigation Bar Inactive / Active Colors
  const char TAB_DAILY_ACTIVE[]       = "bDailypage.bco=29369";    // Blue highlight
  const char TAB_DAILY_INACTIVE[]     = "bDailypage.bco=50712";    // Gray
  const char TAB_PRN_ACTIVE[]         = "bPRNpage.bco=29369";
  const char TAB_PRN_INACTIVE[]       = "bPRNpage.bco=50712";
  const char TAB_TIME_ACTIVE[]        = "bTimelinepage.bco=29369";
  const char TAB_TIME_INACTIVE[]      = "bTimelinepage.bco=50712";

  // Action & Scroll Buttons (Default background & font colors)
  const char BTN_SCROLL_BG[]          = "bScrollup.bco=50712";     // Gray button
  const char BTN_SCROLL_DOWN_BG[]     = "bScrolldown.bco=50712";
  const char TEXT_WHITE[]             = "pco=65535";               // White text
  const char TEXT_DARK[]              = "pco=0";                   // Black text
}

// ----------------------------------------------------------------------------
// [GROUP B]: Real-Time Dynamic Commands (Sent by ESP32 MCU)
// (Must be driven by MCU firmware during runtime for state, safety, and timing)
// ----------------------------------------------------------------------------
namespace NextionLiveCtrl {
  // Page Transitions (Triggered by user taps, schedule alarms, or dispense completion)
  const char PAGE_DAILY[]             = "page Daily";
  const char PAGE_PRN[]               = "page PRN";
  const char PAGE_PRN_DETAIL[]        = "page PRNDetail";
  const char PAGE_CONFIRM[]           = "page Confirm";
  const char PAGE_DISPENSING[]        = "page Dispensing";
  const char PAGE_SUCCESS[]           = "page Success";
  const char PAGE_ALERT[]             = "page Alert";
  const char PAGE_TIMELINE[]          = "page Timeline";

  // Live Dispense Button States (Guarded by medicine stock & cooldown timer)
  const char BTN_DISPENSE_ACTIVE[]    = "bDispense.bco=9308";      // Teal: Ready to take
  const char BTN_DISPENSE_DISABLED[]  = "bDispense.bco=50712";     // Gray: Cooldown / Locked
  const char BTN_DISPENSE_UNLOCK[]    = "tsw bDispense,1";         // Enable click
  const char BTN_DISPENSE_LOCK[]      = "tsw bDispense,0";         // Disable click
}

// ============================================================================
// Data Models (In-Memory State)
// ============================================================================
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

struct DispenseRequest {
  int slot;
  int qty;
  bool isCompleted;
  bool isSuccess;
  String errMsg;
};

// ============================================================================
// Global Variable Declarations (Externally Defined in MeDisP_ESP32S3.ino)
// ============================================================================
extern HardwareSerial NextionSerial;
extern HardwareSerial CtrlSerial;

extern bool gEnableMockDispense;
extern SlotInfo gSlots[NUM_SLOTS];

// BLE Handles
extern NimBLECharacteristic *pConfigChar;
extern NimBLECharacteristic *pStatusChar;
extern NimBLECharacteristic *pResponseChar;
extern bool isBleClientConnected;

// Storage Handles
extern bool isSdMounted;
extern bool isLittleFsOk;
extern fs::FS *pActiveFS;

// Time & State
extern bool isTimeSynced;
extern String currentScheduleJson;
extern unsigned long lastTimeSyncRequestMs;

// Nextion State
extern String gCurrentNextionPage;
extern int gSelectedPrnSlot;
extern bool gIsConfirmingPrn;
extern bool gLastDispensedWasPrn;
extern unsigned long gLastDispenseMs;
extern String gActiveMealTime;
extern bool gActiveBeforeFood;

extern int gDailyOffset;
extern int gPrnOffset;
extern int gTimelineOffset;

// Core 0 Synchronization Primitives
extern DispenseRequest gCurrentDispenseReq;
extern SemaphoreHandle_t gDispenseMutex;
extern SemaphoreHandle_t gDispenseStartSem;
extern SemaphoreHandle_t gDispenseDoneSem;

// BLE Command FIFO Queue
extern std::queue<String> bleCommandQueue;
extern portMUX_TYPE bleCommandMux;

// ============================================================================
// Inline Helper Functions
// ============================================================================
inline void enqueueBleCommand(const String &cmd) {
  taskENTER_CRITICAL(&bleCommandMux);
  if (bleCommandQueue.size() < 24) {
    bleCommandQueue.push(cmd);
  }
  taskEXIT_CRITICAL(&bleCommandMux);
}

inline bool dequeueBleCommand(String &outCmd) {
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

// Safe UTF-8 truncate to prevent slicing multi-byte characters
inline String safeTruncateUtf8(const String &str, size_t maxLen) {
  if (str.length() <= maxLen)
    return str;
  size_t len = maxLen;
  while (len > 0 && ((uint8_t)str[len] & 0xC0) == 0x80) {
    len--;
  }
  return str.substring(0, len);
}

// ============================================================================
// Forward Function Declarations Across Subsystems
// ============================================================================
// Time & Storage
void setSystemEpoch(unsigned long epoch);
String getFormattedTime();
unsigned long getSystemEpoch();
String getCurrentDateStr(int dayOffset = 0);
String getCurrentTimeHHMM();
void ensureDirectory(const char *path);
bool writeStorageFile(const char *path, const String &data);
String readStorageFile(const char *path);
void initDefaultSlots();
String getDrugIndication(int slotIdx);
void parseAndApplySlots(const String &jsonStr);
void saveSlotsToStorage();
#if ARDUINOJSON_VERSION_MAJOR >= 7
void updateSlotScheduleInStorage(int slotNum, JsonArrayConst newItems);
#else
void updateSlotScheduleInStorage(int slotNum, JsonArray newItems);
#endif
void setupStorage();
String findActiveScheduleTimeForSlot(int slot);
void recordIntakeHistory(int slot, int qty, const String &medicine,
                         const char *type, const char *status,
                         const char *schedTime = "");
int countPrnIntakesToday(int slot);
void seedDefaultDemoDataIfEmpty();

// Hardware
String getSlotGrayCode(int slot);
bool sendCtrlCommandWaitResponse(const String &cmd, const String &expectedKey,
                                 String &outResp, unsigned long timeoutMs = 4000);
bool executePhysicalDispenseStepByStep(int slot, int qty, String &outErrMsg);
bool serviceOpenPillContainer(bool openDoor);
bool hardwareDispenseSlot(int slot, int qty, String &outErrMsg);
inline bool dispensePill(int slot, int qty) {
  String err = "";
  return hardwareDispenseSlot(slot, qty, err);
}
void hardwareSyncRtc(unsigned long epochTime);
void hardwareSlotUpdated(int slot, int remaining, const char *drugName);
void TaskCore0HardwareController(void *pvParameters);

// BLE
void sendResponseNotification(const char *result, const char *message);
void sendBleEvent(const String &eventJson);
String buildDeviceStatusJson();
bool executeDispense(int slot, int qty, const String &medicine,
                     const String &reqId, String &outErrMsg,
                     bool isScheduled = false, const String &schedTime = "");
void processIncomingCommand(const String &jsonPayload);
void setupBleServer();

// Nextion
String formatNextionDrugName(const String &rawName, int slotNum);
void nextionApplyPageStaticStyle(const char *pageName);
void nextionSetDispenseButtonState(const String &btnText, bool isReady);
void nextionSend(const String &cmd);
void nextionSetText(const char *comp, const String &val);
void nextionSetVisible(const char *comp, bool vis);
void nextionRef(const char *comp);
inline void nextionSetText(const String &comp, const String &val);
inline void nextionSetVisible(const String &comp, bool vis);
inline void nextionRef(const String &comp);
void nextionFlush();
void nextionSetPage(const char *pageName);
void nextionSetNavTabsVisible(bool visible);
String getMealNameFromTime(const String &timeStr);
bool isScheduledMealCompletedToday(const String &mealTime);
PrnStatus checkPrnStatus(int slot);
void handleReqDaily(bool resetOffset);
void handleReqPrn();
void handleReqPrnDetail();
void handleReqTimeline(bool resetOffset);
void handleReqConfirm();
void handleReqAlert();
void handleReqDispensing();
void handleReqSuccess();
void refreshCurrentNextionPage();
void handleNextionPageReq(const String &msg);
void handleNextionScroll(const String &msg);
void handleNextionPrnSelect(int rowSelected);
void handleNextionDailyTake();
void handleNextionPrnTake();
void handleNextionConfirm();
void handleNextionCancel();
void handleNextionBack();
void processNextionMessage(String msg);
void handleNextionIncoming();

// CLI
void printSerialSlots();
void printSerialSchedule();
void printSerialHistory();
void printAllSummary();
void handleSerialCli();

