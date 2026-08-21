import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medisp/application/app_controller.dart';
import 'package:medisp/data/auth_repositories.dart';
import 'package:medisp/data/persistent_dispenser_repository.dart';
import 'package:medisp/data/persistent_medication_repository.dart';
import 'package:medisp/domain/adherence_service.dart';
import 'package:medisp/domain/models.dart';
import 'package:medisp/domain/meal_schedule.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('adherence calculates expected and taken events per drug', () {
    final drug = Drug(
        id: 'adherence-drug',
        name: 'Daily medicine',
        addedAt: DateTime(2026, 8, 4),
        instructions: const [
          DoseInstruction(meal: MealType.breakfast, quantity: 1),
          DoseInstruction(meal: MealType.dinner, quantity: 1)
        ]);
    final report = const AdherenceService().calculate(
        period: AdherencePeriod.week,
        now: DateTime(2026, 8, 5, 12),
        drugs: [
          drug
        ],
        intakes: [
          IntakeRecord(
              id: 'taken',
              takenAt: DateTime(2026, 8, 4, 7),
              meal: MealType.breakfast,
              doses: [DrugDose(drug, 1)])
        ]);

    expect(report.expected, 4);
    expect(report.taken, 1);
    expect(report.rate, .25);
    expect(report.drugs.single.rate, .25);
  });

  test('meal schedule selects the nearest configured meal across midnight', () {
    const meals = [
      MealPlan(
          type: MealType.breakfast,
          time: TimeOfDay(hour: 7, minute: 0),
          drugs: []),
      MealPlan(
          type: MealType.bedtime,
          time: TimeOfDay(hour: 22, minute: 0),
          drugs: [])
    ];
    expect(MealSchedule.current(meals, DateTime(2026, 1, 1, 6))?.type,
        MealType.breakfast);
    expect(MealSchedule.current(meals, DateTime(2026, 1, 1, 23, 30))?.type,
        MealType.bedtime);
  });

  test('offline auth validates credentials and restores its local session',
      () async {
    final storage = MemoryAuthStorage();
    final auth = OfflineAuthRepository(storage);
    await auth.initialize();
    final user = await auth.register(
        name: 'Local Patient',
        email: 'Patient@Example.com',
        password: 'securepass');

    await auth.signOut();
    await expectLater(
        auth.signIn(email: 'patient@example.com', password: 'wrong-pass'),
        throwsStateError);
    final signedIn =
        await auth.signIn(email: 'patient@example.com', password: 'securepass');
    expect(signedIn.id, user.id);

    final restored = OfflineAuthRepository(storage);
    await restored.initialize();
    expect(restored.currentUser?.id, user.id);
    await expectLater(
        restored.register(
            name: 'Duplicate',
            email: 'PATIENT@example.com',
            password: 'anotherpass'),
        throwsStateError);
  });

  test('registered user medication flow persists and updates inventory',
      () async {
    SharedPreferences.setMockInitialValues({});
    final auth = OfflineAuthRepository(MemoryAuthStorage());
    await auth.initialize();
    await auth.register(
        name: 'Patient One',
        email: 'patient@example.com',
        password: 'securepass');
    final controller = AppController(auth, PersistentDispenserRepository(auth),
        PersistentMedicationRepository(auth),
        now: () => DateTime(2026, 1, 1, 7));
    await controller.initialize();

    expect(controller.drugs, isEmpty);
    expect(controller.todayMeals, isEmpty);
    expect(controller.slots.every((slot) => slot.isEmpty), isTrue);

    await controller.toggleConnection();
    const drug = Drug(id: 'drug-1', name: 'Prescription A', instructions: [
      DoseInstruction(meal: MealType.breakfast, quantity: 2, beforeFood: false)
    ]);
    await controller.addDrugToSlot(drug, 1, 10);
    expect(controller.slots.first.drug?.id, drug.id);
    expect(controller.slots.first.remaining, 10);
    expect(controller.todayMeals.single.totalPills, 2);

    await controller.completeMeal(MealType.breakfast);
    expect(controller.slots.first.remaining, 8);
    expect(controller.todayMeals.first.completed, isTrue);
    expect(controller.intakeHistory.single.doses.first.drug.id, drug.id);

    final restored = AppController(auth, PersistentDispenserRepository(auth),
        PersistentMedicationRepository(auth),
        now: () => DateTime(2026, 1, 1, 7, 5));
    await restored.initialize();
    expect(restored.drugs.single.id, drug.id);
    expect(restored.drugs.single.instructions.single.beforeFood, isFalse);
    expect(restored.slots.first.remaining, 8);
    expect(restored.intakeHistory.single.meal, MealType.breakfast);
    expect(restored.todayMeals.single.completed, isTrue);
  });

  test('profile and reminder settings persist per authenticated user',
      () async {
    SharedPreferences.setMockInitialValues({});
    final auth = OfflineAuthRepository(MemoryAuthStorage());
    await auth.initialize();
    await auth.register(
        name: 'Patient Two', email: 'two@example.com', password: 'securepass');
    final controller = AppController(auth, PersistentDispenserRepository(auth),
        PersistentMedicationRepository(auth));
    await controller.initialize();

    const profile = PatientProfile(
        name: 'Patient Two',
        email: 'two@example.com',
        phone: '0812345678',
        bloodType: 'A',
        birthDate: '2000-01-02',
        address: 'Bangkok',
        gender: 'หญิง',
        heightCm: 165,
        weightKg: 55,
        medicalConditions: 'ความดันโลหิตสูง',
        caregiverName: 'Caregiver',
        caregiverRelationship: 'บุตร',
        caregiverPhone: '0891111111',
        emergencyPhone: '1669');
    const settings = AlertSettings(mealTimes: {
      MealType.breakfast: TimeOfDay(hour: 8, minute: 15),
      MealType.lunch: TimeOfDay(hour: 12, minute: 0),
      MealType.dinner: TimeOfDay(hour: 18, minute: 30),
      MealType.bedtime: TimeOfDay(hour: 22, minute: 0)
    }, minutesBefore: 30, repeatCount: 3);
    await controller.updateProfile(profile);
    await controller.updateAlerts(settings);

    final restored = AppController(auth, PersistentDispenserRepository(auth),
        PersistentMedicationRepository(auth));
    await restored.initialize();
    expect(restored.profile.phone, '0812345678');
    expect(restored.profile.heightCm, 165);
    expect(restored.profile.weightKg, 55);
    expect(restored.profile.caregiverName, 'Caregiver');
    expect(restored.profile.emergencyPhone, '1669');
    expect(restored.alertSettings.minutesBefore, 30);
    expect(restored.alertSettings.repeatCount, 3);
    expect(restored.alertSettings.mealTimes[MealType.breakfast],
        const TimeOfDay(hour: 8, minute: 15));
  });
}
