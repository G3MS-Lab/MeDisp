import 'package:flutter/material.dart';

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
      user = nextUser;
      if (nextUser != null) await _loadUserData();
      notifyListeners();
    });
    if (user != null) await _loadUserData();
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

  void _rebuildMeals() {
    final today = _now();
    final completedMeals = intakeHistory
        .where((record) => DateUtils.isSameDay(record.takenAt, today))
        .map((record) => record.meal)
        .toSet();
    todayMeals = MealType.values
        .map((meal) {
          final doses = <DrugDose>[];
          final slottedDrugs = slots
              .where((slot) => !slot.isEmpty && slot.remaining > 0)
              .map((slot) => slot.drug!)
              .toList();
          for (final drug in slottedDrugs) {
            for (final instruction
                in drug.instructions.where((item) => item.meal == meal)) {
              doses.add(DrugDose(drug, instruction.quantity));
            }
          }
          return MealPlan(
              type: meal,
              time: alertSettings.mealTimes[meal]!,
              drugs: doses,
              completed: completedMeals.contains(meal));
        })
        .where((meal) => meal.drugs.isNotEmpty)
        .toList();
  }

  Future<void> toggleConnection() async {
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      if (connected) {
        await _dispenser.disconnect();
        connected = false;
      } else {
        connected = await _dispenser.connect();
      }
    } catch (error) {
      connected = false;
      errorMessage = error.toString().replaceFirst('Bad state: ', '');
    }
    busy = false;
    notifyListeners();
  }

  Future<void> addDrugToSlot(Drug drug, int slot, int quantity) async {
    await _dispenser.fillSlot(slot, drug, quantity);
    try {
      await _medications.saveDrug(drug);
    } catch (_) {
      await _dispenser.clearSlot(slot);
      rethrow;
    }
    drugs = await _medications.drugs();
    slots = await _dispenser.slots();
    _rebuildMeals();
    notifyListeners();
  }

  Future<void> completeMeal(MealType type) async {
    final index = todayMeals.indexWhere((meal) => meal.type == type);
    if (index < 0) return;
    final meal = todayMeals[index];
    if (meal.completed) return;
    final now = _now();
    if (MealSchedule.current(todayMeals, now)?.type != type) {
      throw StateError('กดทานแล้วได้เฉพาะมื้อปัจจุบันเท่านั้น');
    }
    await _dispenser
        .consume({for (final dose in meal.drugs) dose.drug.id: dose.quantity});
    final intake = IntakeRecord(
        id: now.microsecondsSinceEpoch.toString(),
        takenAt: now,
        meal: type,
        doses: meal.drugs);
    await _medications.saveIntake(intake);
    intakeHistory = await _medications.intakeHistory();
    slots = await _dispenser.slots();
    todayMeals[index] =
        todayMeals[index].copyWith(completed: true, completedAt: now);
    notifyListeners();
  }

  Future<void> clearSlot(int slotNumber) async {
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
