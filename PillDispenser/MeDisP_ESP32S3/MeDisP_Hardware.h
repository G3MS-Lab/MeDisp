#pragma once

#include "MeDisP_Config.h"

// ============================================================================
// HARDWARE CONTROLLER SUBSYSTEM & GRAY CODE DISPENSING (CORE 0)
// ============================================================================

/**
 * 4-Bit Gray Code Mapping for Motor Rotation:
 * Standard Gray code sequence:
 * Slot 1: "0001"
 * Slot 2: "0011"
 * Slot 3: "0010"
 * Slot 4: "0110"
 * Slot 5: "0111"
 * Slot 6: "0101"
 * Slot 7: "0100"
 * Slot 8: "1100"
 * Slot 9: "1101"
 * Slot 10: "1111"
 * Slot 11: "1110"
 * Slot 12: "1010"
 */
inline String getSlotGrayCode(int slot) {
  switch (slot) {
    case 1:  return "0001"; // Slot 1 Gray Code
    case 2:  return "0011"; // Slot 2 Gray Code
    case 3:  return "0010"; // Slot 3 Gray Code
    case 4:  return "0110"; // Slot 4 Gray Code
    case 5:  return "0111"; // Slot 5 Gray Code
    case 6:  return "0101"; // Slot 6 Gray Code
    case 7:  return "0100"; // Slot 7 Gray Code
    case 8:  return "1100"; // Slot 8 Gray Code
    case 9:  return "1101"; // Slot 9 Gray Code
    case 10: return "1111"; // Slot 10 Gray Code
    case 11: return "1110"; // Slot 11 Gray Code
    case 12: return "1010"; // Slot 12 Gray Code
    default: return "0001";
  }
}

/**
 * Helper to send command to Controller ESP32 over UART2 and await specific response
 * Returns true if expected response received within timeoutMs
 */
inline bool sendCtrlCommandWaitResponse(const String &cmd, const String &expectedKey,
                                       String &outResp, unsigned long timeoutMs) {
  // Clear any stale incoming bytes
  while (CtrlSerial.available()) {
    CtrlSerial.read();
  }

  Serial.printf("[CTRL TX] -> %s\n", cmd.c_str());
  CtrlSerial.print(cmd);
  CtrlSerial.print("\n");
  CtrlSerial.flush();

  unsigned long startMs = millis();
  String rxBuffer = "";
  while (millis() - startMs < timeoutMs) {
    while (CtrlSerial.available()) {
      char c = (char)CtrlSerial.read();
      if (c == '\n' || c == '\r') {
        rxBuffer.trim();
        if (rxBuffer.length() > 0) {
          Serial.printf("[CTRL RX] <- %s\n", rxBuffer.c_str());
          outResp = rxBuffer;
          if (expectedKey.length() == 0 || rxBuffer.indexOf(expectedKey) >= 0) {
            return true;
          }
          rxBuffer = "";
        }
      } else {
        rxBuffer += c;
      }
    }
    vTaskDelay(pdMS_TO_TICKS(10));
  }

  Serial.printf("[CTRL TIMEOUT] Did not receive '%s' for command '%s'\n", expectedKey.c_str(), cmd.c_str());
  return false;
}

/**
 * Physical Dispense Sequence Engine:
 * Executes multi-step dispensing routine with status checks at every stage:
 * 1. Motor Rotation (mr,<gray_code>)
 * 2. Drop Picker to Tube (lr,down)
 * 3. Vacuum Air Pump On (ap,on)
 * 4. Verify Vacuum Sensor (status,apvac)
 * 5. Lift Picker (lr,up)
 * 6. Release Pill into Tray (ap,off)
 */
inline bool executePhysicalDispenseStepByStep(int slot, int qty, String &outErrMsg) {
  Serial.printf("[DISPENSE CORE 0] Starting physical sequence for Slot %d (Qty: %d)\n", slot, qty);

  for (int pill = 1; pill <= qty; pill++) {
    Serial.printf("[DISPENSE CORE 0] Dispensing tablet %d of %d...\n", pill, qty);
    String resp = "";

    // STEP 1: Rotate Motor to the selected slot using 4-bit Gray code
    String grayCode = getSlotGrayCode(slot);
    String mrCmd = "mr," + grayCode;
    // Expected response format from spec: "mr,<gray_code>,success"
    if (!sendCtrlCommandWaitResponse(mrCmd, "success", resp, 6000)) {
      outErrMsg = "Motor rotation failed: " + resp;
      return false;
    }

    // STEP 2: Drop Linear Picker to the tube
    // Request: "lr,down" -> Expected Response: "lr,down,done"
    if (!sendCtrlCommandWaitResponse("lr,down", "done", resp, 5000)) {
      outErrMsg = "Picker drop failed: " + resp;
      return false;
    }

    // STEP 3: Turn on Air Pump to pick the pill
    // Request: "ap,on" -> Expected Response: "received"
    if (!sendCtrlCommandWaitResponse("ap,on", "received", resp, 3000)) {
      outErrMsg = "Air pump start failed: " + resp;
      return false;
    }

    // Small delay to allow vacuum seal to form
    vTaskDelay(pdMS_TO_TICKS(300));

    // STEP 4: Check Vacuum Sensor to confirm pill is attached
    // Request: "status,apvac" -> Expected Response: "status,apvac,active"
    if (!sendCtrlCommandWaitResponse("status,apvac", "active", resp, 3000)) {
      // Inactive or no pill detected
      Serial.printf("[DISPENSE WARN] Vacuum not active (%s), retrying pick once...\n", resp.c_str());
      // Retry once: brief pump off and on
      sendCtrlCommandWaitResponse("ap,off", "received", resp, 1500);
      vTaskDelay(pdMS_TO_TICKS(150));
      sendCtrlCommandWaitResponse("ap,on", "received", resp, 1500);
      vTaskDelay(pdMS_TO_TICKS(300));

      if (!sendCtrlCommandWaitResponse("status,apvac", "active", resp, 2500)) {
        // Still failed: turn off pump and abort
        sendCtrlCommandWaitResponse("ap,off", "received", resp, 1500);
        sendCtrlCommandWaitResponse("lr,up", "done", resp, 4000);
        outErrMsg = "Pill not detected (Vacuum inactive)";
        return false;
      }
    }

    // STEP 5: Lift Picker up with pill
    // Request: "lr,up" -> Expected Response: "lr,up,done"
    if (!sendCtrlCommandWaitResponse("lr,up", "done", resp, 5000)) {
      outErrMsg = "Picker lift failed: " + resp;
      sendCtrlCommandWaitResponse("ap,off", "received", resp, 1500);
      return false;
    }

    // STEP 6: Release pill to tray by turning off vacuum air pump
    // Request: "ap,off" -> Expected Response: "received"
    if (!sendCtrlCommandWaitResponse("ap,off", "received", resp, 3000)) {
      outErrMsg = "Air pump release failed: " + resp;
      return false;
    }

    Serial.printf("[DISPENSE CORE 0] Tablet %d successfully dropped!\n", pill);
    vTaskDelay(pdMS_TO_TICKS(400));
  }

  Serial.println("[DISPENSE CORE 0] All tablets dispensed successfully!");
  return true;
}

/**
 * Container Refill / Service Servo Control (Hook for replenishing pills)
 * Uses Servo Out (so) / Servo In (si) to open dispenser access door
 */
inline bool serviceOpenPillContainer(bool openDoor) {
  String resp = "";
  if (openDoor) {
    // Open container door (Angles configurable per mechanics)
    sendCtrlCommandWaitResponse("so,180", "received", resp, 2500);
    sendCtrlCommandWaitResponse("si,90", "received", resp, 2500);
    return true;
  } else {
    // Close container door
    sendCtrlCommandWaitResponse("si,0", "received", resp, 2500);
    sendCtrlCommandWaitResponse("so,0", "received", resp, 2500);
    return true;
  }
}

/**
 * [Hook 1: Hardware Dispense Execution]
 * Parameters:
 *   - slot: Medication slot index (1 - 6)
 *   - qty: Number of tablets to dispense
 *   - outErrMsg: Error message if dispense fails
 * Return: true if dispense succeeds, false on error
 */
inline bool hardwareDispenseSlot(int slot, int qty, String &outErrMsg) {
  Serial.printf("[HARDWARE HOOK] Dispense invoked: Slot %d, Qty: %d (Mock: %s)\n",
                slot, qty, gEnableMockDispense ? "ACTIVE" : "DISABLED");

  // If Mock mode is active, simulate instant successful dispense immediately
  if (gEnableMockDispense) {
    Serial.println("[MOCK DISPENSE] Simulated immediate dispensing complete.");
    return true;
  }

  // Real Hardware Execution: Delegate to Core 0 task via synchronization primitives
  if (!gDispenseMutex || !gDispenseStartSem || !gDispenseDoneSem) {
    // Fallback direct execution
    return executePhysicalDispenseStepByStep(slot, qty, outErrMsg);
  }

  xSemaphoreTake(gDispenseMutex, portMAX_DELAY);
  gCurrentDispenseReq.slot = slot;
  gCurrentDispenseReq.qty = qty;
  gCurrentDispenseReq.isCompleted = false;
  gCurrentDispenseReq.isSuccess = false;
  gCurrentDispenseReq.errMsg = "";

  // Signal Core 0 to start dispensing
  xSemaphoreGive(gDispenseStartSem);

  // Wait for Core 0 to complete
  xSemaphoreTake(gDispenseDoneSem, pdMS_TO_TICKS(35000)); // up to 35s timeout
  bool res = gCurrentDispenseReq.isSuccess;
  outErrMsg = gCurrentDispenseReq.errMsg;
  xSemaphoreGive(gDispenseMutex);

  return res;
}

/**
 * [Hook 2: Synchronize External RTC Module (e.g., DS3231)]
 */
inline void hardwareSyncRtc(unsigned long epochTime) {
  Serial.printf("[HARDWARE HOOK] Syncing external RTC to epoch: %lu\n", epochTime);
}

/**
 * [Hook 3: Update Slot Hardware Indicators (e.g., LED / Physical Status)]
 */
inline void hardwareSlotUpdated(int slot, int remaining, const char *drugName) {
  Serial.printf("[HARDWARE HOOK] Slot %d updated: '%s' remaining: %d\n", slot, drugName, remaining);
}

/**
 * FreeRTOS Background Task running on CORE 0 dedicated to Hardware Control & UART2
 */
inline void TaskCore0HardwareController(void *pvParameters) {
  Serial.printf("[CORE 0] Hardware & Motor Controller Task started on Core %d\n", xPortGetCoreID());

  while (true) {
    // Wait for dispense request from UI/BLE thread
    if (xSemaphoreTake(gDispenseStartSem, pdMS_TO_TICKS(100)) == pdTRUE) {
      Serial.printf("[CORE 0] Received dispense request for Slot %d, Qty %d\n",
                    gCurrentDispenseReq.slot, gCurrentDispenseReq.qty);

      String err = "";
      bool ok = executePhysicalDispenseStepByStep(gCurrentDispenseReq.slot, gCurrentDispenseReq.qty, err);

      gCurrentDispenseReq.isSuccess = ok;
      gCurrentDispenseReq.errMsg = err;
      gCurrentDispenseReq.isCompleted = true;

      // Notify caller that sequence is finished
      xSemaphoreGive(gDispenseDoneSem);
    }

    // Check for any asynchronous status messages from Controller ESP32
    while (CtrlSerial.available()) {
      String line = CtrlSerial.readStringUntil('\n');
      line.trim();
      if (line.length() > 0) {
        // Only log recognized controller protocol keywords to eliminate noise when unplugged
        if (line.startsWith("mr,") || line.startsWith("lr,") || line.startsWith("ap,") ||
            line.startsWith("status,") || line.startsWith("event,") || line.startsWith("err,")) {
          Serial.printf("[CORE 0 CONTROLLER EVENT] %s\n", line.c_str());
        }
      }
    }

    vTaskDelay(pdMS_TO_TICKS(20));
  }
}

