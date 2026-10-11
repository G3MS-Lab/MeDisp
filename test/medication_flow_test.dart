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

  test('adherence supports custom ranges and stops counting after drug stop',
      () {
    final drug = Drug(
        id: 'stopped-drug',
        name: 'Stopped medicine',
        addedAt: DateTime(2026, 8, 1),
        stoppedAt: DateTime(2026, 8, 3),
        instructions: const [
          DoseInstruction(meal: MealType.breakfast, quantity: 1)
        ]);
    final report = const AdherenceService().calculate(
        period: AdherencePeriod.custom,
        now: DateTime(2026, 8, 10),
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 8, 7),
        drugs: [drug],
        intakes: const []);

    expect(report.start, DateTime(2026, 8, 1));
    expect(report.end, DateTime(2026, 8, 7));
    expect(report.expected, 3);
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

    await restored.clearSlot(1);
    expect(restored.drugs.single.stoppedAt, DateTime(2026, 1, 1, 7, 5));
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
        drugAllergies: 'แพ้ยาเพนิซิลลิน',
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
    expect(restored.profile.drugAllergies, 'แพ้ยาเพนิซิลลิน');
    expect(restored.profile.emergencyPhone, '1669');
    expect(restored.alertSettings.minutesBefore, 30);
    expect(restored.alertSettings.repeatCount, 3);
    expect(restored.alertSettings.mealTimes[MealType.breakfast],
        const TimeOfDay(hour: 8, minute: 15));
  });

  test('24-hour time formatting formats correctly with leading zeros', () {
    const morning = TimeOfDay(hour: 7, minute: 5);
    const evening = TimeOfDay(hour: 19, minute: 30);
    const midnight = TimeOfDay(hour: 0, minute: 0);
    expect(morning.format24Hour(), '07:05');
    expect(evening.format24Hour(), '19:30');
    expect(midnight.format24Hour(), '00:00');

    final dtMorning = DateTime(2026, 9, 18, 8, 4);
    final dtNight = DateTime(2026, 9, 18, 23, 59);
    expect(dtMorning.formatTime24Hour(), '08:04');
    expect(dtNight.formatTime24Hour(), '23:59');
  });

  test('PRN medication flow enforces cooldown interval and daily limit',
      () async {
    SharedPreferences.setMockInitialValues({});
    final auth = OfflineAuthRepository(MemoryAuthStorage());
    await auth.initialize();
    await auth.register(
        name: 'PRN Patient',
        email: 'prn@example.com',
        password: 'securepass');

    var currentTime = DateTime(2026, 3, 10, 8, 0);
    final controller = AppController(
        auth,
        PersistentDispenserRepository(auth),
        PersistentMedicationRepository(auth),
        now: () => currentTime);
    await controller.initialize();
    await controller.toggleConnection();

    const prnDrug = Drug(
      id: 'prn-para',
      name: 'Paracetamol 500mg',
      isPrn: true,
      prnConfig: PrnConfig(
        symptom: 'แก้ปวด / ลดไข้',
        quantity: 1,
        minIntervalHours: 4,
        maxDosesPerDay: 2,
      ),
    );

    await controller.addDrugToSlot(prnDrug, 2, 10);
    expect(controller.prnSlots.length, 1);
    expect(controller.prnSlots.first.drug?.name, 'Paracetamol 500mg');
    expect(controller.todayMeals, isEmpty); // PRN does not appear in meal checklist!

    // Initially available
    final initialStatus = controller.checkPrnStatus(prnDrug);
    expect(initialStatus.canTake, isTrue);
    expect(initialStatus.dosesTakenLast24Hours, 0);

    // Take dose 1 at 08:00
    await controller.completePrnIntake(prnDrug);
    expect(controller.slots[1].remaining, 9);
    expect(controller.intakeHistory.length, 1);
    expect(controller.intakeHistory.first.isPrn, isTrue);
    expect(controller.intakeHistory.first.reason, 'แก้ปวด / ลดไข้');

    // 1 hour later (09:00) -> cooldown active
    currentTime = DateTime(2026, 3, 10, 9, 0);
    final cooldownStatus = controller.checkPrnStatus(prnDrug);
    expect(cooldownStatus.canTake, isFalse);
    expect(cooldownStatus.remainingWait?.inHours, 3);
    await expectLater(
        controller.completePrnIntake(prnDrug), throwsStateError);

    // 4.5 hours later (12:30) -> cooldown passed, can take dose 2
    currentTime = DateTime(2026, 3, 10, 12, 30);
    expect(controller.checkPrnStatus(prnDrug).canTake, isTrue);
    await controller.completePrnIntake(prnDrug);
    expect(controller.slots[1].remaining, 8);
    expect(controller.intakeHistory.length, 2);

    // 5 hours later (17:30) -> cooldown passed, but hit max limit of 2 doses / 24 hours
    currentTime = DateTime(2026, 3, 10, 17, 30);
    final limitStatus = controller.checkPrnStatus(prnDrug);
    expect(limitStatus.canTake, isFalse);
    expect(limitStatus.dosesTakenLast24Hours, 2);
    expect(limitStatus.reason, contains('ครบโควตาสูงสุด 2 ครั้ง'));
    await expectLater(
        controller.completePrnIntake(prnDrug), throwsStateError);

    // Adherence ignores PRN drug
    final report = const AdherenceService().calculate(
      period: AdherencePeriod.day,
      now: currentTime,
      drugs: [prnDrug],
      intakes: controller.intakeHistory,
    );
    expect(report.expected, 0);
    expect(report.drugs, isEmpty);

    // Persists across restart
    final restored = AppController(
        auth,
        PersistentDispenserRepository(auth),
        PersistentMedicationRepository(auth),
        now: () => currentTime);
    await restored.initialize();
    expect(restored.prnSlots.single.drug?.isPrn, isTrue);
    expect(restored.prnSlots.single.drug?.prnConfig?.symptom,
        'แก้ปวด / ลดไข้');
    expect(restored.slots[1].remaining, 8);
  });
}

