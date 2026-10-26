import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  @override
  Future<void> updateSlotsFromDevice(List<DispenserSlot> values) async {
    await (await SharedPreferences.getInstance())
        .setString(_key, jsonEncode(values.map(_slotToJson).toList()));
  }

  Future<void> _save(List<DispenserSlot> values) async {
    await (await SharedPreferences.getInstance())
        .setString(_key, jsonEncode(values.map(_slotToJson).toList()));
    if (!_ble.isConnected || _ble.isMock) return;
    try {
      // 1. Sync slots inventory first (await completion)
      await _syncSlotsWithEsp32(values);
      // Small pause between BLE writes to avoid GATT buffer collision
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // 2. Sync schedule after slots are written (await completion)
      await _syncScheduleWithEsp32(values);
    } catch (e) {
      debugPrint('[BLE SYNC] Error in _save sync: $e');
    }
  }

  Future<void> _syncSlotsWithEsp32(List<DispenserSlot> values) async {
    if (!_ble.isConnected || _ble.isMock) return;
    try {
      final slotsData = values
          .map((slot) => {
                'slot': slot.number,
                'remaining': slot.remaining,
                'drug': slot.drug?.name ?? '',
                if (slot.capacity != 30) 'capacity': slot.capacity,
                if (slot.drug != null) 'is_prn': slot.drug!.isPrn,
                if (slot.drug != null && slot.drug!.isPrn) ...{
                  'min_interval_hours':
                      slot.drug!.prnConfig?.minIntervalHours ?? 4,
                  'prn_qty': slot.drug!.prnConfig?.quantity ?? 1,
                },
              })
          .toList();

      final payload = jsonEncode({'cmd': 'sync_slots', 'slots': slotsData});
      final bytes = utf8.encode(payload);
      if (bytes.length <= 480) {
        await _ble.sendSlots(slotsData);
        debugPrint('[BLE SYNC] ✓ sendSlots succeeded (${bytes.length} bytes)');
      } else {
        debugPrint(
            '[BLE SYNC] Slots payload is large (${bytes.length} bytes > 480B). Splitting into batches...');
        for (var i = 0; i < slotsData.length; i += 2) {
          final batch = slotsData.sublist(
              i, (i + 2 > slotsData.length) ? slotsData.length : i + 2);
          await _ble.sendSlots(batch);
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }
        debugPrint('[BLE SYNC] ✓ sendSlots succeeded via batch splitting');
      }
    } catch (e) {
      debugPrint('[BLE SYNC] ✗ sendSlots failed: $e');
    }
  }

  Future<void> _syncScheduleWithEsp32(List<DispenserSlot> values) async {
    if (!_ble.isConnected || _ble.isMock) return;
    try {
      final scheduleList = <Map<String, dynamic>>[];
      for (final slot in values) {
        // Include any regular (non-PRN) drug across all slots
        if (slot.drug != null && !slot.drug!.isPrn) {
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
              'qty': instruction.quantity,
              'before_food': instruction.beforeFood,
            });
          }
        }
      }

      final payload = jsonEncode({
        'device_id': 'PD001',
        'schedule': scheduleList,
      });

      // BLE GATT attribute limit in Bluetooth specification is 512 bytes
      final bytes = utf8.encode(payload);
      if (bytes.length <= 480) {
        // Safe to send all at once
        await _ble.sendSchedule(payload);
        debugPrint(
            '[BLE SYNC] ✓ sendSchedule succeeded (${scheduleList.length} items for slots: ${scheduleList.map((e) => e["slot"]).toSet().toList()})');
      } else {
        // Payload exceeds safe BLE MTU; split & sync per slot
        debugPrint(
            '[BLE SYNC] Schedule payload is large (${bytes.length} bytes > 480B). Splitting by slot...');
        for (final slot in values) {
          final slotItems = scheduleList
              .where((item) => item['slot'] == slot.number)
              .toList();
          var slotCmd = <String, dynamic>{
            'cmd': 'set_slot_schedule',
            'device_id': 'PD001',
            'slot': slot.number,
            'schedule': slotItems,
          };
          if (utf8.encode(jsonEncode(slotCmd)).length > 480) {
            // Trim medicine names in slotItems to stay under MTU
            final trimmedItems = slotItems.map((item) {
              final med = item['medicine'] as String? ?? '';
              return {
                ...item,
                'medicine': med.length > 20 ? med.substring(0, 20) : med,
              };
            }).toList();
            slotCmd = {
              'cmd': 'set_slot_schedule',
              'device_id': 'PD001',
              'slot': slot.number,
              'schedule': trimmedItems,
            };
          }
          await _ble.sendCommand(slotCmd);
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }
        debugPrint(
            '[BLE SYNC] ✓ sendSchedule succeeded via per-slot splitting (${scheduleList.length} items)');
      }
    } catch (e) {
      debugPrint('[BLE SYNC] ✗ sendSchedule failed: $e');
    }
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
