/**
 * ============================================================================
 * MeDisP Mock Motor & Mechanism Controller (ESP32 Mini / C3 / C5 / D1 Mini)
 * ============================================================================
 * Firmware for the secondary ESP32 microcontroller (ESP32 D1 Mini,
 * ESP32-C3 SuperMini, ESP32-C5, or standard ESP32) acting as a hardware simulator
 * for the pill dispenser mechanisms (carousel stepper, linear actuator, vacuum
 * pump, vacuum sensor, and container door servos).
 *
 * It communicates with the master ESP32-S3 board over hardware Serial UART.
 *
 * ----------------------------------------------------------------------------
 * Physical Wiring Options:
 * ----------------------------------------------------------------------------
 * Option A) If using ESP32 D1 Mini (Standard ESP32 Chip):
 *  ESP32-S3 (Master)                 ESP32 D1 Mini (Mock Controller)
 *  IO15 (TX ESP32)        ──────►    IO16 / RX2 (Pin labeled "16" or "RX2")
 *  IO16 (RX ESP32)        ◄──────    IO17 / TX2 (Pin labeled "17" or "TX2")
 *  GND                    ───────    GND
 *
 * Option B) If using ESP32-C3 SuperMini / ESP32-C5 Mini:
 *  ESP32-S3 (Master)                 ESP32-C3 / C5 SuperMini
 *  IO15 (TX ESP32)        ──────►    GPIO 4 (Pin labeled "4")
 *  IO16 (RX ESP32)        ◄──────    GPIO 5 (Pin labeled "5")
 *  GND                    ───────    GND (Pin labeled "G")
 * ----------------------------------------------------------------------------
 * Baud Rate: 115200 bps
 * ============================================================================
 */

#include <Arduino.h>

// ============================================================================
// 1. UART Pin Definitions for Link to Master ESP32-S3
// ============================================================================
// The compiler automatically picks the right pins based on your board target:
#if defined(CONFIG_IDF_TARGET_ESP32C5) || defined(CONFIG_IDF_TARGET_ESP32C3) || defined(CONFIG_IDF_TARGET_ESP32C6)
  // --- ESP32-C3 / C5 SuperMini ---
  #define S3_RX_PIN 4   // Pin "4" (receives from ESP32-S3 IO15 TX)
  #define S3_TX_PIN 5   // Pin "5" (transmits to ESP32-S3 IO16 RX)
#else
  // --- ESP32 D1 Mini / Standard ESP32 ---
  #define S3_RX_PIN 16  // Pin "IO16" / "RX2" (receives from ESP32-S3 IO15 TX)
  #define S3_TX_PIN 17  // Pin "IO17" / "TX2" (transmits to ESP32-S3 IO16 RX)
#endif

#define S3_BAUD 115200

// Serial1 is used for communicating with ESP32-S3, Serial (USB) for PC debugging
HardwareSerial S3LinkSerial(1);

// Global flag to simulate vacuum pressure sensor detection
// (Toggleable at runtime via the PC Serial Monitor)
bool gSimulateVacuumSuccess = true;

// ----------------------------------------------------------------------------
// Send response string to ESP32-S3 and log to PC Serial Monitor
// ----------------------------------------------------------------------------
void sendResponseToS3(const String &resp) {
  S3LinkSerial.print(resp);
  S3LinkSerial.print("\n");
  S3LinkSerial.flush();
  Serial.printf("[MOCK TX -> S3] %s\n", resp.c_str());
}

// ----------------------------------------------------------------------------
// Decode 4-bit Gray code back to Slot Number (1..12) for display
// ----------------------------------------------------------------------------
int grayCodeToSlot(const String &code) {
  if (code == "0001") return 1;
  if (code == "0011") return 2;
  if (code == "0010") return 3;
  if (code == "0110") return 4;
  if (code == "0111") return 5;
  if (code == "0101") return 6;
  if (code == "0100") return 7;
  if (code == "1100") return 8;
  if (code == "1101") return 9;
  if (code == "1111") return 10;
  if (code == "1110") return 11;
  if (code == "1010") return 12;
  return -1;
}

// ----------------------------------------------------------------------------
// Hardware Command Dispatcher for Packets Received from ESP32-S3
// ----------------------------------------------------------------------------
void processIncomingCommandFromS3(String cmd) {
  cmd.trim();
  if (cmd.length() == 0) return;

  Serial.printf("\n[MOCK RX <- S3] %s\n", cmd.c_str());

  // 1. Rotate carousel to slot by Gray code: "mr,<gray_code>"
  if (cmd.startsWith("mr,")) {
    String grayCode = cmd.substring(3);
    grayCode.trim();
    int slot = grayCodeToSlot(grayCode);
    if (slot > 0) {
      Serial.printf("  ⚙️ [MOTOR] Rotating carousel to Slot %d (Gray code: %s)...\n", slot, grayCode.c_str());
    } else {
      Serial.printf("  ⚙️ [MOTOR] Rotating carousel to Gray code: %s...\n", grayCode.c_str());
    }

    // Simulate physical motor rotation time (350 ms)
    delay(350);

    // Reply adhering to MeDisP protocol: "mr,<gray_code>,success"
    sendResponseToS3("mr," + grayCode + ",success");
    return;
  }

  // 2. Lower linear actuator into pill tube: "lr,down"
  if (cmd == "lr,down") {
    Serial.println("  ⬇️ [LINEAR] Moving picker DOWN into pill tube...");
    delay(250); // Simulate movement duration
    sendResponseToS3("lr,down,done");
    return;
  }

  // 3. Turn on vacuum pump: "ap,on"
  if (cmd == "ap,on") {
    Serial.println("  💨 [AIR PUMP] Vacuum pump ON (Generating suction)...");
    delay(100);
    sendResponseToS3("ap,on,received");
    return;
  }

  // 4. Query vacuum pressure sensor status: "status,apvac"
  if (cmd == "status,apvac") {
    Serial.println("  🔍 [SENSOR] Checking vacuum pressure sensor...");
    delay(100);
    if (gSimulateVacuumSuccess) {
      Serial.println("  ✓ [SENSOR] Pill detected attached! Vacuum ACTIVE.");
      sendResponseToS3("status,apvac,active");
    } else {
      Serial.println("  ⚠️ [SENSOR] Simulation: No pill detected (Vacuum INACTIVE)!");
      sendResponseToS3("status,apvac,inactive");
    }
    return;
  }

  // 5. Raise linear actuator with pill: "lr,up"
  if (cmd == "lr,up") {
    Serial.println("  ⬆️ [LINEAR] Lifting picker UP with tablet...");
    delay(250); // Simulate movement duration
    sendResponseToS3("lr,up,done");
    return;
  }

  // 6. Turn off vacuum pump to release pill into cup: "ap,off"
  if (cmd == "ap,off") {
    Serial.println("  💊 [AIR PUMP] Vacuum pump OFF (Pill released into tray).");
    delay(100);
    sendResponseToS3("ap,off,received");
    return;
  }

  // 7. Door / container servo angles: "so,<ang>" / "si,<ang>"
  if (cmd.startsWith("so,")) {
    Serial.printf("  🚪 [SERVO OUT] Angle: %s°\n", cmd.substring(3).c_str());
    delay(150);
    sendResponseToS3(cmd + ",received");
    return;
  }
  if (cmd.startsWith("si,")) {
    Serial.printf("  🚪 [SERVO IN] Angle: %s°\n", cmd.substring(3).c_str());
    delay(150);
    sendResponseToS3(cmd + ",received");
    return;
  }

  // 8. General status query / Ping
  if (cmd == "status" || cmd == "status,ready") {
    Serial.println("  ℹ️ [STATUS] S3 pinged status.");
    sendResponseToS3("status,ready");
    return;
  }
  if (cmd == "ping") {
    sendResponseToS3("pong");
    return;
  }

  // Fallback for any unknown / custom commands
  Serial.printf("  ❓ [UNKNOWN CMD] Echoing received: %s\n", cmd.c_str());
  sendResponseToS3(cmd + ",received");
}

// ----------------------------------------------------------------------------
// Interactive Debug CLI for PC USB Serial Monitor
// ----------------------------------------------------------------------------
void handleComputerSerialInput() {
  if (!Serial.available()) return;

  String line = Serial.readStringUntil('\n');
  line.trim();
  if (line.length() == 0) return;

  Serial.println("\n>> [PC CLI] " + line);

  if (line == "help" || line == "?") {
    Serial.println("=== Mock Controller Debug Commands ===");
    Serial.println("  vac on       : Simulate pill suction SUCCESS (default)");
    Serial.println("  vac off      : Simulate pill suction FAILURE (tests S3 retry logic)");
    Serial.println("  status       : Show current simulation settings");
    Serial.println("  send <msg>   : Send custom string directly to ESP32-S3");
    Serial.println("======================================");
  } else if (line == "vac on") {
    gSimulateVacuumSuccess = true;
    Serial.println("✓ Vacuum status set to ACTIVE (Pill will be successfully detected).");
  } else if (line == "vac off") {
    gSimulateVacuumSuccess = false;
    Serial.println("⚠️ Vacuum status set to INACTIVE (Will simulate failed pill pick).");
  } else if (line == "status") {
    Serial.printf("Simulate Vacuum Success : %s\n", gSimulateVacuumSuccess ? "TRUE" : "FALSE");
    Serial.printf("S3 Link Port             : RX Pin %d, TX Pin %d at %d baud\n", S3_RX_PIN, S3_TX_PIN, S3_BAUD);
  } else if (line.startsWith("send ")) {
    String msg = line.substring(5);
    sendResponseToS3(msg);
  } else {
    Serial.println("Unknown command! Type 'help' for options.");
  }
}

// ============================================================================
// Arduino Setup
// ============================================================================
void setup() {
  // 1. Initialize USB Serial for PC Debugging & CLI
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n========================================================");
  Serial.println("  MeDisP Mock Motor & Mechanism Controller");
  Serial.println("  Target: ESP32 Mini (D1 Mini / C3 SuperMini / C5 / ESP32)");
  Serial.println("========================================================");

  // 2. Initialize Serial1 for communication with Master ESP32-S3
  pinMode(S3_RX_PIN, INPUT_PULLUP);
  S3LinkSerial.begin(S3_BAUD, SERIAL_8N1, S3_RX_PIN, S3_TX_PIN);
  S3LinkSerial.setTimeout(50);

  Serial.printf("[INIT] Serial link to ESP32-S3 configured:\n");
  Serial.printf("       RX Pin: GPIO %d (Connect to S3 IO15 TX)\n", S3_RX_PIN);
  Serial.printf("       TX Pin: GPIO %d (Connect to S3 IO16 RX)\n", S3_TX_PIN);
  Serial.printf("       Baud Rate: %d bps\n\n", S3_BAUD);
  Serial.println("[READY] Listening for dispensing commands from ESP32-S3...");
  Serial.println("Type 'help' in this terminal for debug simulation options.\n");
}

// ============================================================================
// Arduino Main Loop
// ============================================================================
void loop() {
  // 1. Check for commands received from Master ESP32-S3
  while (S3LinkSerial.available() > 0) {
    String incomingCmd = S3LinkSerial.readStringUntil('\n');
    processIncomingCommandFromS3(incomingCmd);
  }

  // 2. Check for commands entered by developer via PC Serial Monitor
  handleComputerSerialInput();

  delay(10);
}
