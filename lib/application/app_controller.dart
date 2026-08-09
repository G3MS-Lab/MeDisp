import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';

class AppController extends ChangeNotifier {
  AppController(this._dispenser, this._medications);
  final DispenserRepository _dispenser;
  final MedicationRepository _medications;

  bool connected = false;
  bool busy = false;
  List<DispenserSlot> slots = const [];
  List<Drug> drugs = const [];
  List<AllergyRecord> allergies = const [];
  List<MealPlan> todayMeals = const [];
  AlertSettings alertSettings = const AlertSettings(
    mealTimes: {MealType.breakfast: TimeOfDay(hour: 7, minute: 0), MealType.lunch: TimeOfDay(hour: 11, minute: 45), MealType.dinner: TimeOfDay(hour: 19, minute: 0), MealType.bedtime: TimeOfDay(hour: 21, minute: 0)},
  );
  final profile = const PatientProfile(name: 'ชื่อ นามสกุล', email: 'test@gmail.com', phone: '0999999999', bloodType: 'B', birthDate: '04/04/2547', address: '12 xxx อ.xx ต.xxx แขวง xxx จ.xxxx');

  Future<void> initialize() async {
    drugs = await _medications.drugs();
    slots = await _dispenser.slots();
    allergies = await _medications.allergies();
    _rebuildMeals();
    notifyListeners();
  }

  void _rebuildMeals() {
    todayMeals = MealType.values.map((meal) {
      final doses = <DrugDose>[];
      for (final drug in drugs) {
        for (final instruction in drug.instructions.where((item) => item.meal == meal)) {
          doses.add(DrugDose(drug, instruction.quantity));
        }
      }
      return MealPlan(type: meal, time: alertSettings.mealTimes[meal]!, drugs: doses);
    }).where((meal) => meal.drugs.isNotEmpty).toList();
  }

  Future<void> toggleConnection() async {
    busy = true;
    notifyListeners();
    if (connected) {
      await _dispenser.disconnect();
      connected = false;
    } else {
      connected = await _dispenser.connect();
    }
    busy = false;
    notifyListeners();
  }

  Future<void> addDrugToSlot(Drug drug, int slot, int quantity) async {
    await _medications.saveDrug(drug);
    await _dispenser.fillSlot(slot, drug, quantity);
    drugs = await _medications.drugs();
    slots = await _dispenser.slots();
    _rebuildMeals();
    notifyListeners();
  }

  void completeMeal(MealType type) {
    final index = todayMeals.indexWhere((meal) => meal.type == type);
    if (index < 0) return;
    todayMeals[index] = todayMeals[index].copyWith(completed: true, completedAt: DateTime.now());
    notifyListeners();
  }

  void updateAlerts(AlertSettings value) {
    alertSettings = value;
    _rebuildMeals();
    notifyListeners();
  }

  Future<void> addAllergy(AllergyRecord record) async {
    await _medications.saveAllergy(record);
    allergies = await _medications.allergies();
    notifyListeners();
  }
}
