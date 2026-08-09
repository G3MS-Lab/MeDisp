import '../domain/models.dart';
import '../domain/repositories.dart';

class InMemoryDispenserRepository implements DispenserRepository {
  bool _connected = false;
  final List<DispenserSlot> _slots = List.generate(6, (i) => DispenserSlot(number: i + 1));

  @override
  Future<bool> connect() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    return _connected = true;
  }

  @override
  Future<void> disconnect() async => _connected = false;

  @override
  Future<void> fillSlot(int slotNumber, Drug drug, int quantity) async {
    if (!_connected) throw StateError('กรุณาเชื่อมต่อเครื่องจ่ายยาก่อน');
    final index = _slots.indexWhere((slot) => slot.number == slotNumber);
    if (index < 0 || quantity > _slots[index].capacity) throw StateError('จำนวนยาเกินความจุช่อง');
    _slots[index] = _slots[index].copyWith(drug: drug, remaining: quantity);
  }

  @override
  Future<List<DispenserSlot>> slots() async => List.unmodifiable(_slots);
}

class InMemoryMedicationRepository implements MedicationRepository {
  final List<Drug> _drugs = [
    const Drug(id: 'para', name: 'Paracetamol', instructions: [DoseInstruction(meal: MealType.breakfast, quantity: 1), DoseInstruction(meal: MealType.dinner, quantity: 1)]),
    const Drug(id: 'vitc', name: 'Vitamin C', instructions: [DoseInstruction(meal: MealType.breakfast, quantity: 1)]),
    const Drug(id: 'lipo', name: 'Lipo-X', instructions: [DoseInstruction(meal: MealType.breakfast, quantity: 1)]),
  ];
  final List<AllergyRecord> _allergies = [];

  @override
  Future<List<Drug>> drugs() async => List.unmodifiable(_drugs);
  @override
  Future<void> saveDrug(Drug drug) async => _drugs.add(drug);
  @override
  Future<List<AllergyRecord>> allergies() async => List.unmodifiable(_allergies);
  @override
  Future<void> saveAllergy(AllergyRecord record) async => _allergies.add(record);
}
