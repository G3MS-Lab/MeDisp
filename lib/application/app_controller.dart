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

  /// Initial sync upon BLE connection:
  /// 1. Synchronizes phone local time with ESP32
  /// 2. Pulls real-time slot state from ESP32 to overwrite local app state
  Future<void> _performInitialSync() async {
    if (_initialSyncDone) return;
    debugPrint('[BLE SYNC] Performing initial BLE sync on connection (ESP32 -> App)...');

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
          final updatedDrug =
              current.drug ?? Drug(id: 'slot_$slotNum', name: deviceDrug);
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
      slots = await _dispenser.slots();
      _rebuildMeals();
      debugPrint(
          '[BLE SYNC] ✓ Overwrote app slots with ESP32 state: ${slots.map((s) => "S${s.number}:${s.drug?.name ?? "ว่าง"}(${s.remaining})").join(", ")}');
    } else {
      debugPrint('[BLE SYNC] App slots already match ESP32');
    }
  }

  /// Update single slot remaining from ESP32 DISPENSE_SUCCESS event
  Future<void> _handleRemoteDispense(int slotNum, int remaining) async {
    debugPrint(
        '[BLE EVENT] Updating Slot $slotNum remaining from device: $remaining');
    final currentSlots = List<DispenserSlot>.from(await _dispenser.slots());
    final index = currentSlots.indexWhere((s) => s.number == slotNum);
    if (index >= 0) {
      currentSlots[index] = currentSlots[index].copyWith(remaining: remaining);
      await _dispenser.updateSlotsFromDevice(currentSlots);
      slots = await _dispenser.slots();
      _rebuildMeals();
      notifyListeners();
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
          debugPrint(
              '[BLE EVENT] Remote dispense: Slot $slot, remaining: $remaining');
          if (slot != null && remaining != null) {
            _handleRemoteDispense(slot, remaining);
          }
          break;

        case 'SLOTS_SAVED':
          debugPrint('[BLE EVENT] ESP32 confirmed slots saved');
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
    final dayAgo = now.subtract(const Duration(hours: 24));

    final drugIntakesLast24Hours = intakeHistory
        .where((record) => record.isPrn && record.takenAt.isAfter(dayAgo))
        .where((record) => record.doses.any((dose) => dose.drug.id == drug.id))
        .toList()
      ..sort((a, b) => b.takenAt.compareTo(a.takenAt));

    final countLast24h = drugIntakesLast24Hours.length;

    if (countLast24h >= config.maxDosesPerDay) {
      return PrnStatus(
        canTake: false,
        reason:
            'ทานครบโควตาสูงสุด ${config.maxDosesPerDay} ครั้งในรอบ 24 ชม. แล้ว',
        dosesTakenLast24Hours: countLast24h,
        maxDosesPerDay: config.maxDosesPerDay,
      );
    }

    if (drugIntakesLast24Hours.isNotEmpty) {
      final lastTaken = drugIntakesLast24Hours.first.takenAt;
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
          dosesTakenLast24Hours: countLast24h,
          maxDosesPerDay: config.maxDosesPerDay,
          nextAvailableAt: nextAvailable,
          remainingWait: remaining,
        );
      }
    }

    return PrnStatus(
      canTake: true,
      reason: 'พร้อมรับประทานเมื่อมีอาการ',
      dosesTakenLast24Hours: countLast24h,
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
