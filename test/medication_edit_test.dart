import 'package:flutter_test/flutter_test.dart';
import 'package:medisp/application/app_controller.dart';
import 'package:medisp/data/auth_repositories.dart';
import 'package:medisp/data/persistent_dispenser_repository.dart';
import 'package:medisp/data/persistent_medication_repository.dart';
import 'package:medisp/domain/models.dart';
import 'package:medisp/domain/repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingMedicationRepository extends PersistentMedicationRepository {
  _FailingMedicationRepository(super.auth);
  bool failSave = false;

  @override
  Future<void> saveDrug(Drug drug) async {
    if (failSave) throw StateError('storage unavailable');
    await super.saveDrug(drug);
  }
}

Future<AuthRepository> _auth() async {
  SharedPreferences.setMockInitialValues({});
  final auth = OfflineAuthRepository(MemoryAuthStorage());
  await auth.initialize();
  await auth.register(
      name: 'Patient', email: 'edit@example.com', password: 'password');
  return auth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final original = Drug(
    id: 'existing-drug',
    name: 'Original medicine',
    notes: 'Original notes',
    labelImagePath: 'medisp-image:existing',
    addedAt: DateTime(2026, 1, 1),
    instructions: const [
      DoseInstruction(meal: MealType.breakfast, quantity: 2)
    ],
  );

  test(
      'editing persists one drug, updates meals and retains linked intake history',
      () async {
    final auth = await _auth();
    final controller = AppController(auth, PersistentDispenserRepository(auth),
        PersistentMedicationRepository(auth),
        now: () => DateTime(2026, 1, 1, 7));
    await controller.initialize();
    await controller.toggleConnection();
    await controller.addDrugToSlot(original, 1, 10);
    await controller.completeMeal(MealType.breakfast);
    final edited = original.copyWith(
        name: 'Edited medicine',
        notes: 'Updated notes',
        instructions: const [
          DoseInstruction(meal: MealType.dinner, quantity: 3, beforeFood: false)
        ]);
    await controller.updateDrugInSlot(edited, 1, 8);

    final restored = AppController(auth, PersistentDispenserRepository(auth),
        PersistentMedicationRepository(auth),
        now: () => DateTime(2026, 1, 1, 7));
    await restored.initialize();
    expect(restored.drugs.single.id, original.id);
    expect(restored.drugs.single.name, edited.name);
    expect(restored.drugs.single.notes, edited.notes);
    expect(restored.drugs.single.addedAt, original.addedAt);
    expect(restored.drugs.single.labelImagePath, original.labelImagePath);
    expect(restored.slots.first.drug?.name, edited.name);
    expect(restored.slots.first.remaining, 8);
    expect(restored.todayMeals.single.type, MealType.dinner);
    expect(restored.todayMeals.single.totalPills, 3);
    expect(restored.intakeHistory.single.doses.single.drug.id, original.id);
    expect(restored.intakeHistory.single.doses.single.quantity, 2);
  });

  test('failed edit restores the original slot and its inventory', () async {
    final auth = await _auth();
    final medications = _FailingMedicationRepository(auth);
    final dispenser = PersistentDispenserRepository(auth);
    final controller = AppController(auth, dispenser, medications);
    await controller.initialize();
    await controller.toggleConnection();
    await controller.addDrugToSlot(original, 1, 10);
    medications.failSave = true;
    await expectLater(
        controller.updateDrugInSlot(original.copyWith(name: 'Changed'), 1, 4),
        throwsStateError);
    expect((await dispenser.slots()).first.drug?.name, original.name);
    expect((await dispenser.slots()).first.remaining, 10);
    expect((await medications.drugs()).single.name, original.name);
  });

  test('refill adds pills to the existing drug without changing its details',
      () async {
    final auth = await _auth();
    final controller = AppController(auth, PersistentDispenserRepository(auth),
        PersistentMedicationRepository(auth));
    await controller.initialize();
    await controller.toggleConnection();
    await controller.addDrugToSlot(original, 1, 7);
    await controller.refillDrugInSlot(1, original.id, 5);
    expect(controller.slots.first.remaining, 12);
    expect(controller.slots.first.drug?.id, original.id);
    expect(controller.drugs.single.name, original.name);
    await expectLater(
        controller.refillDrugInSlot(1, original.id, 19), throwsStateError);
    await expectLater(
        controller.refillDrugInSlot(1, 'another-drug', 1), throwsStateError);
    expect(controller.slots.first.remaining, 12);
  });

  test(
      'stale edits, occupied adds and invalid inventory cannot overwrite a slot',
      () async {
    final auth = await _auth();
    final controller = AppController(auth, PersistentDispenserRepository(auth),
        PersistentMedicationRepository(auth));
    await controller.initialize();
    await controller.toggleConnection();
    await controller.addDrugToSlot(original, 1, 10);
    const replacement = Drug(id: 'replacement', name: 'Replacement');
    await expectLater(
        controller.addDrugToSlot(replacement, 1, 5), throwsStateError);
    await expectLater(
        controller.updateDrugInSlot(replacement, 1, 5), throwsStateError);
    await expectLater(
        controller.updateDrugInSlot(original, 1, -1), throwsStateError);
    await expectLater(
        controller.updateDrugInSlot(original, 1, 31), throwsStateError);
    await controller.updateDrugInSlot(original, 1, 0);
    expect(controller.slots.first.remaining, 0);
    expect(controller.drugs, hasLength(1));
    await controller.clearSlot(1);
    await expectLater(
        controller.updateDrugInSlot(original, 1, 5), throwsStateError);
    expect(controller.slots.first.isEmpty, isTrue);
  });
}
