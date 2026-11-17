/**
 * ============================================================================
 * MeDisP - Smart Pill Dispenser (ESP32-S3 Dual-Core Firmware)
 * ============================================================================
 * Architecture & Dual-Core Division:
 * - CORE 1 (Protocol & UI Hub):
 *     * BLE GATT Server (NimBLE for Flutter App sync & notifications)
 *     * Nextion Touch Screen HMI UART (Serial1: TX=IO17, RX=IO18 @ 9600 baud)
 *     * MicroSD & LittleFS dual-storage filesystem
 *     * Time synchronization & schedule tracking
 *     * Interactive Serial CLI for manual debugging & diagnostics
 *
 * - CORE 0 (Hardware & Dispensing Controller):
 *     * Controller UART (Serial2: TX=IO15, RX=IO16 @ 115200 baud)
 *     * Multi-step state machine orchestrating physical mechanism:
 *         1. Motor Rotation with 4-bit Gray code: "mr,<gray_code>" ->
 * "mr,<gray_code>,success"
 *         2. Drop picker to tube: "lr,down" -> "lr,down,done"
 *         3. Pill pick with vacuum air pump: "ap,on" -> "ap,on,received"
 *         4. Verify vacuum pressure sensor: "status,apvac" ->
 * "status,apvac,active"
 *         5. Lift picker: "lr,up" -> "lr,up,done"
 *         6. Release pill to tray: "ap,off" -> "ap,off,received"
 *         (Refill container servo controls: "so,180" / "si,90")
 *     * Mock Dispense mode toggle (Active by default for immediate safe
 * testing)
 *
 * Multi-Tab Modular Architecture (Clean Function Separation):
 * - MeDisP_Config.h   : Pinout definitions, UUIDs, structs, styles, and externs
 * - MeDisP_Hardware.h : Gray code mapping, motor controls, vacuum, Core 0
 * FreeRTOS task
 * - MeDisP_Storage.h  : Dual storage (SD/LittleFS), slot/schedule/history
 * persistence
 * - MeDisP_Ble.h      : NimBLE server, GATT events, decomposed BLE command
 * handlers
 * - MeDisP_Nextion.h  : Nextion HMI serial protocol, page renderers, touch
 * message handlers
 * - MeDisP_Cli.h      : Serial CLI command handlers and diagnostics
 * ============================================================================
 */

#include "MeDisP_Ble.h"
#include "MeDisP_Cli.h"
#include "MeDisP_Config.h"
#include "MeDisP_Hardware.h"
#include "MeDisP_Nextion.h"
#include "MeDisP_Storage.h"

// ============================================================================
// Global Variable Definitions (Memory Allocation)
// ============================================================================
HardwareSerial NextionSerial(1); // UART1 for Nextion HMI (RX=18, TX=17)
HardwareSerial CtrlSerial(2); // UART2 for Motor Controller ESP32 (RX=16, TX=15)

bool gEnableMockDispense = false;
SlotInfo gSlots[NUM_SLOTS];

// BLE Handles
NimBLECharacteristic *pConfigChar = nullptr;
NimBLECharacteristic *pStatusChar = nullptr;
NimBLECharacteristic *pResponseChar = nullptr;
bool isBleClientConnected = false;

// Storage Handles
bool isSdMounted = false;
bool isLittleFsOk = false;
fs::FS *pActiveFS = nullptr;

// Time & State
bool isTimeSynced = false;
String currentScheduleJson = "";
unsigned long lastTimeSyncRequestMs = 0;

// Nextion State
String gCurrentNextionPage = "Daily";
int gSelectedPrnSlot = 3;
bool gIsConfirmingPrn = false;
bool gLastDispensedWasPrn = false;
unsigned long gLastDispenseMs = 0;
String gActiveMealTime = "";
bool gActiveBeforeFood = false;

int gDailyOffset = 0;
int gPrnOffset = 0;
int gTimelineOffset = 0;

// Core 0 Synchronization Primitives
DispenseRequest gCurrentDispenseReq;
SemaphoreHandle_t gDispenseMutex = nullptr;
SemaphoreHandle_t gDispenseStartSem = nullptr;
SemaphoreHandle_t gDispenseDoneSem = nullptr;

// BLE Command FIFO Queue
std::queue<String> bleCommandQueue;
portMUX_TYPE bleCommandMux = portMUX_INITIALIZER_UNLOCKED;

// ============================================================================
// Arduino Setup Entry Point
// ============================================================================
void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n==================================================");
  Serial.println(
      "  Smart Pill Dispenser (MeDisP) - ESP32-S3 Dual-Core Firmware");
  Serial.println(
      "  Core 1: BLE + Nextion HMI | Core 0: Motor & Dispensing Controller");
  Serial.println("==================================================");

  // 1. Initialize Dual Storage Subsystem (MicroSD with LittleFS fallback)
  setupStorage();

  // 2. Initialize Nextion HMI UART1 on IO18 (RX), IO17 (TX) @ 9600 baud
  // Set INPUT_PULLUP to prevent floating pin electrical noise when display is
  // unplugged
  pinMode(NEXTION_RX_PIN, INPUT_PULLUP);
  NextionSerial.begin(NEXTION_BAUD, SERIAL_8N1, NEXTION_RX_PIN, NEXTION_TX_PIN);
  NextionSerial.setTimeout(50);
  Serial.printf("[NEXTION] Initialized Nextion Serial on RX (IO %d), TX (IO "
                "%d) at %d baud\n",
                NEXTION_RX_PIN, NEXTION_TX_PIN, NEXTION_BAUD);

  // 3. Initialize Mechanism / Motor Controller UART2 on IO16 (RX), IO15 (TX) @
  // 115200 baud Set INPUT_PULLUP to prevent floating pin electrical noise when
  // motor controller is unplugged
  pinMode(CTRL_RX_PIN, INPUT_PULLUP);
  CtrlSerial.begin(CTRL_BAUD, SERIAL_8N1, CTRL_RX_PIN, CTRL_TX_PIN);
  CtrlSerial.setTimeout(50);
  Serial.printf("[CTRL] Initialized Controller Serial on RX (IO %d), TX (IO "
                "%d) at %d baud\n",
                CTRL_RX_PIN, CTRL_TX_PIN, CTRL_BAUD);

  // 4. Initialize Inter-Core FreeRTOS Semaphores
  gDispenseMutex = xSemaphoreCreateMutex();
  gDispenseStartSem = xSemaphoreCreateBinary();
  gDispenseDoneSem = xSemaphoreCreateBinary();

  // 5. Pin Motor & Hardware Controller Task to CORE 0
  xTaskCreatePinnedToCore(TaskCore0HardwareController, "TaskCore0Ctrl", 8192,
                          nullptr, 1, nullptr,
                          0 // Pin to Core 0!
  );
  Serial.println(
      "[RTOS] Pinned TaskCore0HardwareController to Core 0 successfully.");

  seedDefaultDemoDataIfEmpty();

  // 6. Nextion HMI Initial One-Way Push
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

  // 7. Initialize BLE Peripheral Server (NimBLE)
  setupBleServer();

  Serial.println(
      "[CLI] Serial CLI active. Type 'help' to view debug commands.\n");
}

// ============================================================================
// Arduino Main Loop (Runs on Core 1)
// ============================================================================
void loop() {
  // 1. Process Serial CLI inputs for hardware debugging
  handleSerialCli();

  // 2. Process Nextion HMI display inputs and touch requests
  handleNextionIncoming();

  // 3. Auto-return from Success screen back to Daily/PRN after 3.5 seconds
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

  // 4. Process asynchronous BLE commands sent from Flutter App (FIFO Queue)
  String bleCmd;
  while (dequeueBleCommand(bleCmd)) {
    Serial.println("\n[BLE RECV] Processing command payload from queue:");
    Serial.println(bleCmd);
    processIncomingCommand(bleCmd);
  }

  // 5. Periodic time sync request (every 15 minutes)
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
