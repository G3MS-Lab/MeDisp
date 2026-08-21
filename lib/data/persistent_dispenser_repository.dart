import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';

class PersistentDispenserRepository implements DispenserRepository {
  PersistentDispenserRepository(this._auth);
  final AuthRepository _auth;
  bool _connected = false;

  String get _key => 'dispenser_slots_${_auth.currentUser?.id ?? 'anonymous'}';

  @override
  Future<bool> connect() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return _connected = true;
  }

  @override
  Future<void> disconnect() async => _connected = false;

  @override
  Future<List<DispenserSlot>> slots() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) {
      return List.generate(6, (index) => DispenserSlot(number: index + 1));
    }
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(_slotFromJson)
        .toList();
  }

  @override
  Future<void> fillSlot(int slotNumber, Drug drug, int quantity) async {
    if (!_connected) {
      throw StateError('กรุณาเชื่อมต่อเครื่องจ่ายยาก่อน');
    }
    final values = await slots();
    final index = values.indexWhere((slot) => slot.number == slotNumber);
    if (index < 0 || quantity > values[index].capacity) {
      throw StateError('จำนวนยาเกินความจุช่อง');
    }
    values[index] = values[index].copyWith(drug: drug, remaining: quantity);
    await _save(values);
  }

  @override
  Future<void> consume(Map<String, int> quantityByDrugId) async {
    if (!_connected) {
      throw StateError('เครื่องจ่ายยาขาดการเชื่อมต่อ');
    }
    final values = await slots();
    for (final entry in quantityByDrugId.entries) {
      final index = values.indexWhere((slot) => slot.drug?.id == entry.key);
      if (index < 0 || values[index].remaining < entry.value) {
        throw StateError('ยาในช่องไม่เพียงพอ กรุณาเติมยา');
      }
      values[index] = values[index]
          .copyWith(remaining: values[index].remaining - entry.value);
    }
    await _save(values);
  }

  @override
  Future<void> clearSlot(int slotNumber) async {
    final values = await slots();
    final index = values.indexWhere((slot) => slot.number == slotNumber);
    if (index >= 0) {
      values[index] =
          DispenserSlot(number: slotNumber, capacity: values[index].capacity);
    }
    await _save(values);
  }

  Future<void> _save(List<DispenserSlot> values) async =>
      (await SharedPreferences.getInstance())
          .setString(_key, jsonEncode(values.map(_slotToJson).toList()));

  Map<String, dynamic> _slotToJson(DispenserSlot slot) => {
        'number': slot.number,
        'capacity': slot.capacity,
        'remaining': slot.remaining,
        'drug': slot.drug == null
            ? null
            : {
                'id': slot.drug!.id,
                'name': slot.drug!.name,
                'notes': slot.drug!.notes,
                'label_image_path': slot.drug!.labelImagePath,
                'added_at': slot.drug!.addedAt?.toIso8601String(),
                'instructions': slot.drug!.instructions
                    .map((dose) => {
                          'meal': dose.meal.name,
                          'quantity': dose.quantity,
                          'before_food': dose.beforeFood
                        })
                    .toList(),
              },
      };

  DispenserSlot _slotFromJson(Map<String, dynamic> json) {
    final drugJson = json['drug'] as Map<String, dynamic>?;
    final drug = drugJson == null
        ? null
        : Drug(
            id: drugJson['id'] as String,
            name: drugJson['name'] as String,
            notes: (drugJson['notes'] as String?) ?? '',
            labelImagePath: drugJson['label_image_path'] as String?,
            addedAt: drugJson['added_at'] == null
                ? null
                : DateTime.parse(drugJson['added_at'] as String),
            instructions: (drugJson['instructions'] as List)
                .cast<Map<String, dynamic>>()
                .map((dose) => DoseInstruction(
                    meal: MealType.values.byName(dose['meal'] as String),
                    quantity: dose['quantity'] as int,
                    beforeFood: dose['before_food'] as bool))
                .toList(),
          );
    return DispenserSlot(
        number: json['number'] as int,
        capacity: json['capacity'] as int,
        remaining: json['remaining'] as int,
        drug: drug);
  }
}
