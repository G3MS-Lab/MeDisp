import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';

import 'ble_dispenser_service.dart';

class PersistentDispenserRepository implements DispenserRepository {
  PersistentDispenserRepository(this._auth, [BleDispenserService? ble])
      : _ble = ble ?? BleDispenserService.instance;

  final AuthRepository _auth;
  final BleDispenserService _ble;
  bool _mockConnected = false;

  bool get _connected => _mockConnected || _ble.isConnected;

  String get _key => 'dispenser_slots_${_auth.currentUser?.id ?? 'anonymous'}';

  @override
  Future<bool> connect() async {
    if (_ble.isConnected) return true;
    return _mockConnected = true;
  }

  @override
  Future<void> disconnect() async {
    _mockConnected = false;
    await _ble.disconnect();
  }

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

  Future<void> _save(List<DispenserSlot> values) async {
    await (await SharedPreferences.getInstance())
        .setString(_key, jsonEncode(values.map(_slotToJson).toList()));
    _syncScheduleWithEsp32(values);
  }

  void _syncScheduleWithEsp32(List<DispenserSlot> values) {
    if (!_ble.isConnected || _ble.isMock) return;
    try {
      final scheduleList = <Map<String, dynamic>>[];
      for (final slot in values) {
        if (slot.drug != null && slot.remaining > 0) {
          for (final instruction in slot.drug!.instructions) {
            final timeStr = switch (instruction.meal) {
              MealType.breakfast => '08:00',
              MealType.lunch => '12:00',
              MealType.dinner => '18:00',
              MealType.bedtime => '21:00',
            };
            scheduleList.add({
              'time': timeStr,
              'slot': slot.number,
              'medicine': slot.drug!.name,
            });
          }
        }
      }
      if (scheduleList.isNotEmpty) {
        final payload = jsonEncode({
          'device_id': 'PD001',
          'schedule': scheduleList,
        });
        _ble.sendSchedule(payload).catchError((_) => false);
      }
    } catch (_) {}
  }

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
                'stopped_at': slot.drug!.stoppedAt?.toIso8601String(),
                'is_prn': slot.drug!.isPrn,
                'prn_config': slot.drug!.prnConfig == null
                    ? null
                    : {
                        'symptom': slot.drug!.prnConfig!.symptom,
                        'quantity': slot.drug!.prnConfig!.quantity,
                        'min_interval_hours':
                            slot.drug!.prnConfig!.minIntervalHours,
                        'max_doses_per_day':
                            slot.drug!.prnConfig!.maxDosesPerDay,
                      },
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
            stoppedAt: drugJson['stopped_at'] == null
                ? null
                : DateTime.parse(drugJson['stopped_at'] as String),
            isPrn: (drugJson['is_prn'] as bool?) ?? false,
            prnConfig: drugJson['prn_config'] == null
                ? null
                : PrnConfig(
                    symptom: (drugJson['prn_config']['symptom'] as String?) ?? '',
                    quantity: (drugJson['prn_config']['quantity'] as int?) ?? 1,
                    minIntervalHours: (drugJson['prn_config']
                            ['min_interval_hours'] as int?) ??
                        4,
                    maxDosesPerDay: (drugJson['prn_config']['max_doses_per_day']
                            as int?) ??
                        4,
                  ),
            instructions: (drugJson['instructions'] as List? ?? const [])
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
