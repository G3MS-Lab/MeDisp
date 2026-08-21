import '../domain/models.dart';
import '../domain/repositories.dart';

/// Production-safe placeholder that never pretends hardware communication
/// succeeded. Replace this with the manufacturer's BLE or Wi-Fi adapter.
class UnconfiguredDispenserRepository implements DispenserRepository {
  Never _missingProtocol() => throw StateError(
      'ยังไม่ได้ตั้งค่า protocol ของเครื่องจ่ายยา กรุณาระบุ BLE UUID หรือ Wi-Fi API');

  @override
  Future<bool> connect() async => _missingProtocol();
  @override
  Future<void> disconnect() async {}
  @override
  Future<List<DispenserSlot>> slots() async =>
      List.generate(6, (index) => DispenserSlot(number: index + 1));
  @override
  Future<void> fillSlot(int slotNumber, Drug drug, int quantity) async =>
      _missingProtocol();
  @override
  Future<void> consume(Map<String, int> quantityByDrugId) async =>
      _missingProtocol();
  @override
  Future<void> clearSlot(int slotNumber) async => _missingProtocol();
}
