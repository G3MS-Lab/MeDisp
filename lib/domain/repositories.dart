import 'models.dart';

abstract interface class DispenserRepository {
  Future<bool> connect();
  Future<void> disconnect();
  Future<List<DispenserSlot>> slots();
  Future<void> fillSlot(int slotNumber, Drug drug, int quantity);
}

abstract interface class MedicationRepository {
  Future<List<Drug>> drugs();
  Future<void> saveDrug(Drug drug);
  Future<List<AllergyRecord>> allergies();
  Future<void> saveAllergy(AllergyRecord record);
}
