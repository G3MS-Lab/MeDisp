import 'models.dart';

abstract interface class AuthRepository {
  AppUser? get currentUser;
  Stream<AppUser?> get authStateChanges;
  Future<AppUser> signIn({required String email, required String password});
  Future<AppUser?> register(
      {required String name, required String email, required String password});
  Future<void> resetPassword(String email);
  Future<void> signOut();
}

abstract interface class DispenserRepository {
  Future<bool> connect();
  Future<void> disconnect();
  Future<List<DispenserSlot>> slots();
  Future<void> fillSlot(int slotNumber, Drug drug, int quantity);
  Future<void> consume(Map<String, int> quantityByDrugId);
  Future<void> clearSlot(int slotNumber);
}

abstract interface class MedicationRepository {
  Future<List<Drug>> drugs();
  Future<void> saveDrug(Drug drug);
  Future<List<AllergyRecord>> allergies();
  Future<void> saveAllergy(AllergyRecord record);
  Future<List<IntakeRecord>> intakeHistory();
  Future<void> saveIntake(IntakeRecord record);
  Future<PatientProfile?> patientProfile();
  Future<void> savePatientProfile(PatientProfile profile);
  Future<AlertSettings?> alertSettings();
  Future<void> saveAlertSettings(AlertSettings settings);
}
