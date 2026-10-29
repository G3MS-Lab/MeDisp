import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../data/ble_dispenser_service.dart';
import '../domain/models.dart';
import '../domain/meal_schedule.dart';
import '../domain/repositories.dart';

class AppController extends ChangeNotifier {
  AppController(this._auth, this._dispenser, this._medications,
      {DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final AuthRepository _auth;
  final DispenserRepository _dispenser;
  final MedicationRepository _medications;
  final DateTime Function() _now;
  final BleDispenserService bleService = BleDispenserService.instance;

  // Sync state
  Timer? _timeSyncTimer;
  StreamSubscription<String>? _bleEventSub;
  bool _initialSyncDone = false;

  bool connected = false;
  bool initialized = false;
  Future<void>? _initialization;
  AppUser? user;
  String? errorMessage;
  bool busy = false;
  List<DispenserSlot> slots = const [];
  List<Drug> drugs = const [];
  List<AllergyRecord> allergies = const [];
  List<IntakeRecord> intakeHistory = const [];
  List<MealPlan> todayMeals = const [];
  AlertSettings alertSettings = const AlertSettings(
    mealTimes: {
      MealType.breakfast: TimeOfDay(hour: 7, minute: 0),
      MealType.lunch: TimeOfDay(hour: 11, minute: 45),
      MealType.dinner: TimeOfDay(hour: 19, minute: 0),
      MealType.bedtime: TimeOfDay(hour: 21, minute: 0)
    },
  );
  PatientProfile profile = const PatientProfile(
      name: 'ชื่อ นามสกุล',
      email: 'test@gmail.com',
      phone: '0999999999',
      bloodType: 'B',
      birthDate: '04/04/2547',
      address: '12 xxx อ.xx ต.xxx แขวง xxx จ.xxxx');

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    user = _auth.currentUser;
    _auth.authStateChanges.listen((nextUser) async {
      // _authenticate loads the new user's data and publishes it once.
      if (busy) return;
      user = nextUser;
      if (nextUser != null) await _loadUserData();
      notifyListeners();
    });
    if (user != null) await _loadUserData();
    bleService.connectionStateStream.listen((isConn) {
      connected = isConn;
      if (isConn && !bleService.isMock) {
        _performInitialSync();
      } else if (!isConn) {
        _stopPeriodicTimeSync();
        _initialSyncDone = false;
      }
      notifyListeners();
    });
    _setupBleEventListener();
    initialized = true;
    notifyListeners();
  }

  Future<void> _loadUserData() async {
    drugs = await _medications.drugs();
    slots = await _dispenser.slots();
    allergies = await _medications.allergies();
    intakeHistory = await _medications.intakeHistory();
    final savedProfile = await _medications.patientProfile();
    profile = savedProfile ??
        PatientProfile(
            name: user!.displayName,
            email: user!.email,
            phone: '',
            bloodType: '',
            birthDate: '',
            address: '');
    if (savedProfile == null) {
      await _medications.savePatientProfile(profile);
    }
    alertSettings = await _medications.alertSettings() ?? alertSettings;
    _rebuildMeals();
  }

  Future<bool> signIn(String email, String password) async =>
      _authenticate(() => _auth.signIn(email: email, password: password));

  Future<bool> register(String name, String email, String password) async =>
      _authenticate(
          () => _auth.register(name: name, email: email, password: password));

  Future<bool> _authenticate(Future<AppUser?> Function() action) async {
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await action();
      if (result == null) {
        errorMessage = 'กรุณาตรวจสอบอีเมลเพื่อยืนยันบัญชีก่อนเข้าสู่ระบบ';
        return false;
      }
      user = result;
      await _loadUserData();
      return true;
    } catch (error) {
      errorMessage = error
          .toString()
          .replaceFirst('AuthException(message: ', '')
          .replaceFirst(RegExp(r', statusCode:.*'), '');
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    user = null;
    connected = false;
    drugs = const [];
    slots = const [];
    allergies = const [];
    todayMeals = const [];
    notifyListeners();
  }

  List<DispenserSlot> get prnSlots => slots
      .where((slot) => !slot.isEmpty && slot.drug != null && slot.drug!.isPrn)
      .toList();

  void _rebuildMeals() {
    final today = _now();
    final todayIntakes = intakeHistory
        .where((record) =>
            !record.isPrn &&
            record.meal != null &&
            DateUtils.isSameDay(record.takenAt, today))
        .toList();
    todayMeals = MealType.values
        .map((meal) {
          final doses = <DrugDose>[];
          final slottedDrugs = slots
              .where((slot) => !slot.isEmpty && slot.remaining > 0)
              .map((slot) => slot.drug!)
              .where((drug) => !drug.isPrn)
              .toList();
          for (final drug in slottedDrugs) {
            for (final instruction
                in drug.instructions.where((item) => item.meal == meal)) {
              doses.add(DrugDose(drug, instruction.quantity));
            }
          }
          final takenDrugIds = todayIntakes
              .where((record) => record.meal == meal)
              .expand((record) => record.doses.map((d) => d.drug.id))
              .toSet();
          final allCompleted = doses.isNotEmpty &&
              doses.every((dose) => takenDrugIds.contains(dose.drug.id));
          return MealPlan(
              type: meal,
              time: alertSettings.mealTimes[meal]!,
              drugs: doses,
              completed: allCompleted);
        })
        .where((meal) => meal.drugs.isNotEmpty)
        .toList();
  }

  Future<bool> connectBleDevice(BluetoothDevice device) async {
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final success = await bleService.connect(device);
      connected = success;
      if (success && !bleService.isMock) {
        await _performInitialSync();
      }
      return success;
    } catch (error) {
      connected = false;
      errorMessage = error
          .toString()
          .replaceFirst('Bad state: ', '')
          .replaceFirst('StateError: ', '')
          .replaceFirst('Exception: ', '');
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  // ===========================================================================
  // BLE Connection & Synchronization
  // ===========================================================================

  MealType _matchMealTypeFromTime(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length >= 2) {
      final hour = int.tryParse(parts[0]) ?? 8;
      if (hour < 11) return MealType.breakfast;
      if (hour < 15) return MealType.lunch;
      if (hour < 20) return MealType.dinner;
      return MealType.bedtime;
    }
    return MealType.breakfast;
  }

  /// Apply schedule for a single slot from ESP32
  Future<void> _applySlotSchedule(
      int slotNumber, List<dynamic> slotItems) async {
    try {
      final currentSlots = List<DispenserSlot>.from(await _dispenser.slots());
      final index = currentSlots.indexWhere((s) => s.number == slotNumber);
      if (index < 0) return;
      final slot = currentSlots[index];

      // Reconstruct drug if slot in blank app is empty but has schedule from ESP32
      Drug? targetDrug = slot.drug;
      if (targetDrug == null) {
        String medName = '';
        for (final item in slotItems) {
          if (item is Map<String, dynamic>) {
            final m = (item['medicine'] as String? ??
                    item['med'] as String? ??
                    '')
                .trim();
            if (m.isNotEmpty) {
              medName = m;
              break;
            }
          }
        }
        if (medName.isNotEmpty) {
          targetDrug = Drug(
            id: 'slot_$slotNumber',
            name: medName,
            isPrn: false,
          );
        }
      }
      if (targetDrug == null || targetDrug.isPrn) return;

      final instructions = slotItems.map((item) {
        if (item is! Map<String, dynamic>) {
          return const DoseInstruction(meal: MealType.breakfast, quantity: 1);
        }
        final timeStr =
            item['time'] as String? ?? item['t'] as String? ?? '08:00';
        final qty = item['qty'] as int? ?? item['q'] as int? ?? 1;
        final beforeFood = item['before_food'] as bool? ?? true;
        final meal = switch (timeStr) {
          '08:00' => MealType.breakfast,
          '12:00' => MealType.lunch,
          '18:00' => MealType.dinner,
          '21:00' => MealType.bedtime,
          _ => _matchMealTypeFromTime(timeStr),
        };
        return DoseInstruction(
          meal: meal,
          quantity: qty,
          beforeFood: beforeFood,
        );
      }).toList();

      final updatedDrug = targetDrug.copyWith(instructions: instructions);
      currentSlots[index] = slot.copyWith(drug: updatedDrug);

      await _dispenser.updateSlotsFromDevice(currentSlots);
      await _medications.saveDrug(updatedDrug);
      drugs = await _medications.drugs();
      slots = await _dispenser.slots();
      _rebuildMeals();
      notifyListeners();
      debugPrint(
          '[BLE SYNC] ✓ Applied schedule for Slot $slotNumber (${instructions.length} items)');
    } catch (e) {
      debugPrint('[BLE SYNC] Error applying slot schedule: $e');
    }
  }

  /// Reconstruct drug meal schedule from ESP32 active schedule
  Future<void> _syncScheduleFromDevice(String scheduleJson) async {
    try {
      final data = jsonDecode(scheduleJson) as Map<String, dynamic>;
      final scheduleArr = data['schedule'] as List<dynamic>?;
      if (scheduleArr == null || scheduleArr.isEmpty) return;

      final currentSlots = List<DispenserSlot>.from(await _dispenser.slots());
      bool changed = false;

      for (var i = 0; i < currentSlots.length; i++) {
        final slot = currentSlots[i];

        final slotItems = scheduleArr.where((item) {
          if (item is! Map<String, dynamic>) return false;
          final s = item['slot'] as int? ?? item['s'] as int? ?? 0;
          return s == slot.number;
        }).toList();

        Drug? targetDrug = slot.drug;
        if (targetDrug == null && slotItems.isNotEmpty) {
          String medName = '';
          for (final item in slotItems) {
            if (item is Map<String, dynamic>) {
              final m = (item['medicine'] as String? ??
                      item['med'] as String? ??
                      '')
                  .trim();
              if (m.isNotEmpty) {
                medName = m;
                break;
              }
            }
          }
          if (medName.isNotEmpty) {
            targetDrug = Drug(
              id: 'slot_${slot.number}',
              name: medName,
              isPrn: false,
            );
          }
        }
        if (targetDrug == null || targetDrug.isPrn) continue;

        if (slotItems.isNotEmpty) {
          final instructions = slotItems.map((item) {
            final timeStr =
                item['time'] as String? ?? item['t'] as String? ?? '08:00';
            final qty = item['qty'] as int? ?? item['q'] as int? ?? 1;
            final beforeFood = item['before_food'] as bool? ?? true;
            final meal = switch (timeStr) {
              '08:00' => MealType.breakfast,
              '12:00' => MealType.lunch,
              '18:00' => MealType.dinner,
              '21:00' => MealType.bedtime,
              _ => _matchMealTypeFromTime(timeStr),
            };
            return DoseInstruction(
              meal: meal,
              quantity: qty,
              beforeFood: beforeFood,
            );
          }).toList();

          final updatedDrug =
              targetDrug.copyWith(instructions: instructions);
          currentSlots[i] = slot.copyWith(drug: updatedDrug);
          await _medications.saveDrug(updatedDrug);
          changed = true;
        }
      }

      if (changed) {
        await _dispenser.updateSlotsFromDevice(currentSlots);
        drugs = await _medications.drugs();
        slots = await _dispenser.slots();
        _rebuildMeals();
        notifyListeners();
        debugPrint('[BLE SYNC] ✓ Synced schedule from ESP32 into app slots');
      }
    } catch (e) {
      debugPrint('[BLE SYNC] Error syncing schedule from device: $e');
    }
  }

  /// Initial sync upon BLE connection:
  /// 1. Synchronizes phone local time with ESP32
  /// 2. Pulls real-time slot state from ESP32 to overwrite local app state
  /// 3. Pulls active schedule from ESP32 to reconstruct drug instructions
  /// 4. Pulls 7-day intake history from ESP32 to reconcile intake status
  Future<void> _performInitialSync() async {
    if (_initialSyncDone) return;
    debugPrint(
        '[BLE SYNC] Performing initial BLE sync on connection (ESP32 -> App)...');

    try {
      // 1. Sync phone time to ESP32
      await bleService.syncTime();
      debugPrint('[BLE SYNC] ✓ Time sync sent successfully');

      // 2. Read device status from ESP32
      final statusJson = await bleService.readStatus();
      debugPrint('[BLE SYNC] Device status: $statusJson');

      if (statusJson != null && statusJson.trim().isNotEmpty) {
        final statusData = jsonDecode(statusJson) as Map<String, dynamic>;
        final deviceSlots = statusData['slots'] as List<dynamic>?;
        if (deviceSlots != null && deviceSlots.isNotEmpty) {
          await _syncSlotsFromDevice(deviceSlots);
        }
      }

      // 3. Request active schedule from ESP32 (streams SLOT_SCHEDULE per slot)
      await bleService.requestScheduleSync();
      // Read active schedule characteristic as fallback
      final scheduleJson = await bleService.readSchedule();
      if (scheduleJson != null && scheduleJson.trim().isNotEmpty) {
        await _syncScheduleFromDevice(scheduleJson);
      }

      // 4. Request 7-day intake history sync from ESP32 (source of truth for last 7 days)
      await bleService.requestHistorySync();
      debugPrint('[BLE SYNC] ✓ Requested 7-day history sync from ESP32');
    } catch (e) {
      debugPrint('[BLE SYNC] Initial sync error: $e');
    }

    _initialSyncDone = true;
    _startPeriodicTimeSync();
    notifyListeners();
  }

  /// Overwrite local app slots with current physical state from ESP32
  Future<void> _syncSlotsFromDevice(List<dynamic> deviceSlots) async {
    final currentSlots = List<DispenserSlot>.from(await _dispenser.slots());
    bool changed = false;

    for (final d in deviceSlots) {
      if (d is! Map<String, dynamic>) continue;
      final slotNum = d['slot'] as int? ?? d['number'] as int?;
      if (slotNum == null || slotNum < 1 || slotNum > currentSlots.length) {
        continue;
      }

      final index = currentSlots.indexWhere((s) => s.number == slotNum);
      if (index < 0) continue;

      final current = currentSlots[index];
      final deviceRemaining = d['remaining'] as int? ?? 0;
      final deviceDrug = (d['drug'] as String? ?? '').trim();

      if (deviceDrug.isEmpty && deviceRemaining == 0) {
        // ESP32 slot is empty -> App slot becomes empty
        if (current.drug != null || current.remaining != 0) {
          currentSlots[index] = DispenserSlot(
            number: slotNum,
            capacity: current.capacity,
            remaining: 0,
            drug: null,
          );
          changed = true;
        }
      } else {
        // ESP32 slot has medication -> Update remaining count from machine
        if (current.remaining != deviceRemaining ||
            (current.drug == null && deviceDrug.isNotEmpty)) {
          final isPrn = (d['is_prn'] as bool?) ?? false;
          final minInterval = (d['min_interval_hours'] as int?) ?? 4;
          final prnQty = (d['prn_qty'] as int?) ?? (d['qty'] as int?) ?? 1;
          final maxDoses = (d['max_doses_per_day'] as int?) ??
              (d['max_doses'] as int?) ??
              4;
          final currentDrug = current.drug;
          final updatedDrug = currentDrug == null
              ? Drug(
                  id: 'slot_$slotNum',
                  name: deviceDrug,
                  isPrn: isPrn,
                  prnConfig: isPrn
                      ? PrnConfig(
                          symptom: 'เมื่อมีอาการ',
                          quantity: prnQty,
                          minIntervalHours: minInterval,
                          maxDosesPerDay: maxDoses,
                        )
                      : null,
                )
              : currentDrug.copyWith(
                  name: deviceDrug,
                  isPrn: isPrn,
                  prnConfig: isPrn
                      ? (currentDrug.prnConfig?.copyWith(
                              quantity: prnQty,
                              minIntervalHours: minInterval,
                              maxDosesPerDay: maxDoses,
                            ) ??
                            PrnConfig(
                              symptom: 'เมื่อมีอาการ',
                              quantity: prnQty,
                              minIntervalHours: minInterval,
                              maxDosesPerDay: maxDoses,
                            ))
                      : null,
                );
          currentSlots[index] = current.copyWith(
            remaining: deviceRemaining,
            drug: updatedDrug,
          );
          changed = true;
        }
      }
    }

    if (changed) {
      await _dispenser.updateSlotsFromDevice(currentSlots);
      for (final slot in currentSlots) {
        if (slot.drug != null) {
          await _medications.saveDrug(slot.drug!);
        }
      }
      drugs = await _medications.drugs();
      slots = await _dispenser.slots();
      _rebuildMeals();
      notifyListeners();
      debugPrint(
          '[BLE SYNC] ✓ Overwrote app slots with ESP32 state: ${slots.map((s) => "S${s.number}:${s.drug?.name ?? "ว่าง"}(${s.remaining})").join(", ")}');
    } else {
      debugPrint('[BLE SYNC] App slots already match ESP32');
    }
  }

  /// Update single slot remaining from ESP32 DISPENSE_SUCCESS event
  /// and record intake if live dispense occurred
  Future<void> _handleRemoteDispense(int slotNum, int remaining,
      {int qty = 1}) async {
    debugPrint(
        '[BLE EVENT] Updating Slot $slotNum remaining from device: $remaining (qty: $qty)');
    final currentSlots = List<DispenserSlot>.from(await _dispenser.slots());
    final index = currentSlots.indexWhere((s) => s.number == slotNum);
    if (index >= 0) {
      currentSlots[index] = currentSlots[index].copyWith(remaining: remaining);
      await _dispenser.updateSlotsFromDevice(currentSlots);
      slots = await _dispenser.slots();

      final drug = currentSlots[index].drug;
      if (drug != null) {
        final now = _now();
        final isPrn = drug.isPrn;
        final timeStr =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        final mealType = isPrn ? null : _matchMealTypeFromTime(timeStr);

        // Check if an intake record already exists to prevent duplicate entries
        final alreadyExists = intakeHistory.any((h) {
          if (isPrn) {
            return h.isPrn &&
                h.doses.any((d) =>
                    d.drug.id == drug.id || d.drug.name == drug.name) &&
                DateUtils.isSameDay(h.takenAt, now) &&
                h.takenAt.difference(now).inMinutes.abs() < 5;
          } else {
            return !h.isPrn &&
                h.meal == mealType &&
                DateUtils.isSameDay(h.takenAt, now) &&
                h.takenAt.difference(now).inMinutes.abs() < 10;
          }
        });

        if (!alreadyExists) {
          final record = IntakeRecord(
            id: 'remote_${now.millisecondsSinceEpoch}_s$slotNum',
            takenAt: now,
            meal: mealType,
            isPrn: isPrn,
            reason: isPrn ? (drug.prnConfig?.symptom ?? 'เมื่อมีอาการ') : null,
            doses: [DrugDose(drug, qty)],
          );
          await _medications.saveIntake(record);
          intakeHistory = await _medications.intakeHistory();
        }
      }

      _rebuildMeals();
      notifyListeners();
    }
  }

  /// Merge a single day's intake history from ESP32 into app's repository.
  /// Note: The device is the source of truth for the last 7 days.
  /// Older history on the app/cloud (> 7 days) is NEVER deleted.
  Future<void> _mergeHistoryDayFromDevice(
      String dateStr, List<dynamic> records) async {
    try {
      final existingRecords =
          List<IntakeRecord>.from(await _medications.intakeHistory());
      final currentSlots = await _dispenser.slots();
      bool changed = false;

      for (final r in records) {
        if (r is! Map<String, dynamic>) continue;
        final timeStr = r['time'] as String? ?? '00:00';
        final slotNum = r['slot'] as int? ?? 1;
        final qty = r['qty'] as int? ?? 1;
        final type = r['type'] as String? ?? 'meal';
        final isPrn = type == 'prn';

        DateTime takenAt;
        try {
          takenAt = DateTime.parse('$dateStr $timeStr:00');
        } catch (_) {
          takenAt = _now();
        }

        final slot =
            currentSlots.where((s) => s.number == slotNum).firstOrNull;
        final medName = (r['med'] as String? ?? '').trim();
        final drug = slot?.drug ??
            Drug(
              id: 'slot_$slotNum',
              name: medName.isNotEmpty ? medName : 'ยาช่อง $slotNum',
              isPrn: isPrn,
            );

        // Ensure drug is saved so dose details and pill count are never lost
        await _medications.saveDrug(drug);

        final mealType = isPrn ? null : _matchMealTypeFromTime(timeStr);

        if (isPrn) {
          final alreadyExists = existingRecords.any((h) =>
              h.isPrn &&
              h.doses.any((d) =>
                  d.drug.id == drug.id ||
                  d.drug.name == drug.name ||
                  d.drug.name == medName) &&
              DateUtils.isSameDay(h.takenAt, takenAt) &&
              h.takenAt.difference(takenAt).inMinutes.abs() < 10);

          if (!alreadyExists) {
            final record = IntakeRecord(
              id: 'esp32_${takenAt.millisecondsSinceEpoch}_s$slotNum',
              takenAt: takenAt,
              meal: null,
              isPrn: true,
              reason: drug.prnConfig?.symptom ?? 'เมื่อมีอาการ',
              doses: [DrugDose(drug, qty)],
            );
            await _medications.saveIntake(record);
            existingRecords.add(record);
            changed = true;
          }
        } else {
          final existingMealIndex = existingRecords.indexWhere((h) =>
              !h.isPrn &&
              (h.meal == mealType ||
                  h.takenAt.difference(takenAt).inMinutes.abs() < 15) &&
              DateUtils.isSameDay(h.takenAt, takenAt));

          if (existingMealIndex >= 0) {
            final existingMeal = existingRecords[existingMealIndex];
            final hasDrug = existingMeal.doses.any((d) =>
                d.drug.id == drug.id ||
                d.drug.name == drug.name ||
                d.drug.name == medName);
            if (!hasDrug) {
              final updatedDoses = List<DrugDose>.from(existingMeal.doses)
                ..add(DrugDose(drug, qty));
              final updatedMeal = IntakeRecord(
                id: existingMeal.id,
                takenAt: existingMeal.takenAt,
                meal: existingMeal.meal ?? mealType,
                isPrn: false,
                reason: existingMeal.reason,
                doses: updatedDoses,
              );
              await _medications.saveIntake(updatedMeal);
              existingRecords[existingMealIndex] = updatedMeal;
              changed = true;
            }
          } else {
            final record = IntakeRecord(
              id: 'esp32_${takenAt.millisecondsSinceEpoch}_s$slotNum',
              takenAt: takenAt,
              meal: mealType,
              isPrn: false,
              reason: null,
              doses: [DrugDose(drug, qty)],
            );
            await _medications.saveIntake(record);
            existingRecords.add(record);
            changed = true;
          }
        }
      }

      if (changed) {
        drugs = await _medications.drugs();
        intakeHistory = await _medications.intakeHistory();
        _rebuildMeals();
        notifyListeners();
        debugPrint('[BLE SYNC] ✓ Merged device history for $dateStr into app');
      }
    } catch (e) {
      debugPrint('[BLE SYNC] Error merging history day: $e');
    }
  }

  /// Start periodic time sync timer (every 15 minutes)
  void _startPeriodicTimeSync() {
    _timeSyncTimer?.cancel();
    _timeSyncTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      if (bleService.isConnected && !bleService.isMock) {
        bleService.syncTime().then((_) {
          debugPrint('[BLE SYNC] Periodic time sync sent');
        }).catchError((e) {
          debugPrint('[BLE SYNC] Periodic time sync failed: $e');
        });
      }
    });
    debugPrint('[BLE SYNC] Periodic time sync timer started (every 15 min)');
  }

  /// Stop periodic time sync timer
  void _stopPeriodicTimeSync() {
    _timeSyncTimer?.cancel();
    _timeSyncTimer = null;
    debugPrint('[BLE SYNC] Periodic time sync timer stopped');
  }

  /// Listen to BLE response/event notifications from ESP32
  void _setupBleEventListener() {
    _bleEventSub?.cancel();
    _bleEventSub = bleService.responseStream.listen(_handleBleEvent);
    debugPrint('[BLE SYNC] BLE event listener set up');
  }

  /// Handle incoming BLE events from ESP32
  void _handleBleEvent(String eventJson) {
    try {
      final data = jsonDecode(eventJson) as Map<String, dynamic>;
      final event = data['event'] as String?;
      if (event == null) return;

      switch (event) {
        case 'REQUEST_TIME_SYNC':
          // ESP32 is requesting time sync (periodic 15-min backup)
          debugPrint('[BLE EVENT] ESP32 requested time sync');
          bleService.syncTime().catchError((_) => false);
          break;

        case 'DISPENSE_SUCCESS':
          // ESP32 dispensed a pill
          final slot = data['slot'] as int?;
          final remaining = data['remaining'] as int?;
          final qty = data['qty'] as int? ?? 1;
          debugPrint(
              '[BLE EVENT] Remote dispense: Slot $slot, remaining: $remaining, qty: $qty');
          if (slot != null && remaining != null) {
            _handleRemoteDispense(slot, remaining, qty: qty);
          }
          break;

        case 'HISTORY_DAY':
          final records = data['records'] as List<dynamic>?;
          final dateStr = data['date'] as String?;
          if (records != null && records.isNotEmpty && dateStr != null) {
            _mergeHistoryDayFromDevice(dateStr, records);
          }
          break;

        case 'HISTORY_SYNC_DONE':
          debugPrint('[BLE EVENT] ESP32 confirmed history sync finished');
          _medications.intakeHistory().then((history) {
            intakeHistory = history;
            _rebuildMeals();
            notifyListeners();
          });
          break;

        case 'INTAKE_RECORDED':
          debugPrint(
              '[BLE EVENT] ESP32 confirmed intake recorded: Slot ${data['slot']}');
          break;

        case 'SLOTS_SAVED':
          debugPrint('[BLE EVENT] ESP32 confirmed slots saved');
          break;

        case 'SLOT_SCHEDULE':
          final slot = data['slot'] as int?;
          final schedule = data['schedule'] as List<dynamic>?;
          if (slot != null && schedule != null) {
            _applySlotSchedule(slot, schedule);
          }
          break;

        case 'SCHEDULE_DATA':
          final schedule = data['schedule'] as List<dynamic>?;
          if (schedule != null && schedule.isNotEmpty) {
            _syncScheduleFromDevice(jsonEncode(data));
          }
          break;

        case 'SCHEDULE_SYNC_DONE':
          debugPrint('[BLE EVENT] Device confirmed schedule sync finished');
          _rebuildMeals();
          notifyListeners();
          break;

        case 'SCHEDULE_SAVED':
          debugPrint('[BLE EVENT] ESP32 confirmed schedule saved');
          break;

        case 'SYNC_DATA_READY':
          debugPrint('[BLE EVENT] ESP32 sync data ready');
          break;

        case 'TIME_SYNC_OK':
          debugPrint('[BLE EVENT] ESP32 confirmed time sync: ${data['time']}');
          break;

        case 'DISPENSER_RESET':
          debugPrint('[BLE EVENT] ESP32 was factory reset');
          break;
      }
    } catch (e) {
      debugPrint('[BLE EVENT] Non-event notification: $eventJson');
    }
  }

  void connectMockDevice() {
    bleService.connectMock();
    connected = true;
    errorMessage = null;
    notifyListeners();
  }

  Future<void> disconnectDispenser() async {
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await bleService.disconnect();
      await _dispenser.disconnect();
      connected = false;
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> toggleConnection() async {
    if (connected) {
      await disconnectDispenser();
    } else {
      connectMockDevice();
    }
  }

  Future<void> addDrugToSlot(Drug drug, int slot, int quantity) =>
      _saveDrugToSlot(drug, slot, quantity, editing: false);

  Future<void> updateDrugInSlot(Drug drug, int slot, int quantity) =>
      _saveDrugToSlot(drug, slot, quantity, editing: true);

  Future<void> refillDrugInSlot(
      int slot, String drugId, int addedQuantity) async {
    final current = (await _dispenser.slots())
        .where((value) => value.number == slot)
        .firstOrNull;
    if (current == null || current.drug?.id != drugId) {
      throw StateError('ข้อมูลช่องยาเปลี่ยนไป กรุณากลับไปเลือกช่องอีกครั้ง');
    }
    if (addedQuantity < 1 ||
        current.remaining + addedQuantity > current.capacity) {
      throw StateError(
          'จำนวนยาที่เพิ่มต้องอยู่ระหว่าง 1 ถึง ${current.capacity - current.remaining} เม็ด');
    }
    await _dispenser.fillSlot(
        slot, current.drug!, current.remaining + addedQuantity);
    slots = await _dispenser.slots();
    _rebuildMeals();
    notifyListeners();
  }

  Future<void> _saveDrugToSlot(Drug drug, int slot, int quantity,
      {required bool editing}) async {
    final previous = (await _dispenser.slots())
        .where((value) => value.number == slot)
        .firstOrNull;
    if (previous == null ||
        (editing ? previous.drug?.id != drug.id : !previous.isEmpty)) {
      throw StateError('ข้อมูลช่องยาเปลี่ยนไป กรุณากลับไปเลือกช่องอีกครั้ง');
    }
    if (quantity < (editing ? 0 : 1) || quantity > previous.capacity) {
      throw StateError(
          'จำนวนยาต้องอยู่ระหว่าง ${editing ? 0 : 1} ถึง ${previous.capacity} เม็ด');
    }
    await _dispenser.fillSlot(slot, drug, quantity);
    try {
      await _medications.saveDrug(drug);
    } catch (_) {
      if (previous.drug == null) {
        await _dispenser.clearSlot(slot);
      } else {
        await _dispenser.fillSlot(slot, previous.drug!, previous.remaining);
      }
      rethrow;
    }
    drugs = await _medications.drugs();
    slots = await _dispenser.slots();
    intakeHistory = await _medications.intakeHistory();
    _rebuildMeals();
    notifyListeners();
  }

  Future<void> completeMeal(MealType type, {List<DrugDose>? doses}) async {
    final index = todayMeals.indexWhere((meal) => meal.type == type);
    if (index < 0) return;
    final meal = todayMeals[index];
    if (meal.completed) return;
    final now = _now();
    if (MealSchedule.current(todayMeals, now)?.type != type) {
      throw StateError('กดทานแล้วได้เฉพาะมื้อปัจจุบันเท่านั้น');
    }
    final dosesToConsume = doses ?? meal.drugs;
    await _dispenser.consume(
        {for (final dose in dosesToConsume) dose.drug.id: dose.quantity});
    final intake = IntakeRecord(
        id: now.microsecondsSinceEpoch.toString(),
        takenAt: now,
        meal: type,
        doses: dosesToConsume);
    await _medications.saveIntake(intake);
    intakeHistory = await _medications.intakeHistory();
    slots = await _dispenser.slots();

    // Sync intake event to connected ESP32 so it records in 7-day history & updates schedule status
    if (bleService.isConnected && !bleService.isMock) {
      final hourStr = meal.time.hour.toString().padLeft(2, '0');
      final minuteStr = meal.time.minute.toString().padLeft(2, '0');
      final schedTime = '$hourStr:$minuteStr';

      for (final dose in dosesToConsume) {
        final slot =
            slots.where((s) => s.drug?.id == dose.drug.id).firstOrNull;
        if (slot != null) {
          try {
            await bleService.recordIntake(
              slot: slot.number,
              qty: dose.quantity,
              medicine: dose.drug.name,
              type: 'meal',
              schedTime: schedTime,
            );
          } catch (e) {
            debugPrint('[BLE INTAKE] Error recording intake to device: $e');
          }
        }
      }
    }

    final today = now;
    final todayIntakeDrugIds = intakeHistory
        .where((record) =>
            !record.isPrn &&
            record.meal == type &&
            DateUtils.isSameDay(record.takenAt, today))
        .expand((record) => record.doses.map((d) => d.drug.id))
        .toSet();
    final allCompleted =
        meal.drugs.every((dose) => todayIntakeDrugIds.contains(dose.drug.id));
    if (allCompleted) {
      todayMeals[index] =
          todayMeals[index].copyWith(completed: true, completedAt: now);
    }
    notifyListeners();
  }

  PrnStatus checkPrnStatus(Drug drug) {
    if (!drug.isPrn) {
      return const PrnStatus(
        canTake: false,
        reason: 'ไม่ใช่ยาตามอาการ',
        dosesTakenLast24Hours: 0,
        maxDosesPerDay: 0,
      );
    }
    final config = drug.prnConfig ??
        const PrnConfig(
            symptom: '', quantity: 1, minIntervalHours: 4, maxDosesPerDay: 4);
    final now = _now();

    // All PRN intakes for this drug, newest first
    final allPrnIntakes = intakeHistory
        .where((record) =>
            record.isPrn &&
            record.doses.any((dose) => dose.drug.id == drug.id))
        .toList()
      ..sort((a, b) => b.takenAt.compareTo(a.takenAt));

    // Daily quota count: resets every midnight (00:00:00)
    final countToday = allPrnIntakes
        .where((record) => DateUtils.isSameDay(record.takenAt, now))
        .length;

    // 1. Enforce max doses per day (resets every midnight)
    if (countToday >= config.maxDosesPerDay) {
      return PrnStatus(
        canTake: false,
        reason:
            'ทานครบโควตาสูงสุด ${config.maxDosesPerDay} ครั้งต่อวันแล้ว (รีเซ็ตเที่ยงคืน)',
        dosesTakenLast24Hours: countToday,
        maxDosesPerDay: config.maxDosesPerDay,
      );
    }

    // 2. Enforce minimum safety interval between consecutive doses
    if (allPrnIntakes.isNotEmpty) {
      final lastTaken = allPrnIntakes.first.takenAt;
      final nextAvailable =
          lastTaken.add(Duration(hours: config.minIntervalHours));
      if (now.isBefore(nextAvailable)) {
        final remaining = nextAvailable.difference(now);
        final hours = remaining.inHours;
        final minutes = remaining.inMinutes % 60;
        final waitStr =
            hours > 0 ? '$hours ชม. $minutes นาที' : '$minutes นาที';
        return PrnStatus(
          canTake: false,
          reason: 'ยังไม่ถึงระยะปลอดภัย กรุณารออีก $waitStr',
          dosesTakenLast24Hours: countToday,
          maxDosesPerDay: config.maxDosesPerDay,
          nextAvailableAt: nextAvailable,
          remainingWait: remaining,
        );
      }
    }

    return PrnStatus(
      canTake: true,
      reason: 'พร้อมรับประทานเมื่อมีอาการ',
      dosesTakenLast24Hours: countToday,
      maxDosesPerDay: config.maxDosesPerDay,
    );
  }

  Future<void> completePrnIntake(Drug drug,
      {int? quantity, String? reason}) async {
    final status = checkPrnStatus(drug);
    if (!status.canTake) {
      throw StateError(status.reason);
    }

    final doseQuantity = quantity ?? drug.prnConfig?.quantity ?? 1;
    final now = _now();

    await _dispenser.consume({drug.id: doseQuantity});
    final intake = IntakeRecord(
      id: now.microsecondsSinceEpoch.toString(),
      takenAt: now,
      meal: null,
      isPrn: true,
      reason: reason ?? drug.prnConfig?.symptom,
      doses: [DrugDose(drug, doseQuantity)],
    );
    await _medications.saveIntake(intake);
    intakeHistory = await _medications.intakeHistory();
    slots = await _dispenser.slots();

    // Sync PRN intake event to connected ESP32 so it records in 7-day history
    if (bleService.isConnected && !bleService.isMock) {
      final slot = slots.where((s) => s.drug?.id == drug.id).firstOrNull;
      if (slot != null) {
        try {
          await bleService.recordIntake(
            slot: slot.number,
            qty: doseQuantity,
            medicine: drug.name,
            type: 'prn',
          );
        } catch (e) {
          debugPrint('[BLE INTAKE] Error recording PRN intake to device: $e');
        }
      }
    }

    notifyListeners();
  }

  Future<void> clearSlot(int slotNumber) async {
    final slot = slots.where((item) => item.number == slotNumber).firstOrNull;
    if (slot?.drug != null) {
      await _medications.saveDrug(slot!.drug!.copyWith(stoppedAt: _now()));
      drugs = await _medications.drugs();
    }
    await _dispenser.clearSlot(slotNumber);
    slots = await _dispenser.slots();
    _rebuildMeals();
    notifyListeners();
  }

  Future<void> updateAlerts(AlertSettings value) async {
    alertSettings = value;
    await _medications.saveAlertSettings(value);
    _rebuildMeals();
    notifyListeners();
  }

  Future<void> updateProfile(PatientProfile value) async {
    await _medications.savePatientProfile(value);
    profile = value;
    notifyListeners();
  }

  Future<void> addAllergy(AllergyRecord record) async {
    await _medications.saveAllergy(record);
    allergies = await _medications.allergies();
    notifyListeners();
  }
}
