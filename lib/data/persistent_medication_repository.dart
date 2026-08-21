import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';

class PersistentMedicationRepository implements MedicationRepository {
  PersistentMedicationRepository(this._auth);
  final AuthRepository _auth;

  String _key(String collection) =>
      'medisp_${_auth.currentUser?.id ?? 'anonymous'}_$collection';

  Future<List<Map<String, dynamic>>> _list(String key) async {
    final raw = (await SharedPreferences.getInstance()).getString(_key(key));
    return raw == null
        ? []
        : (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> _saveList(String key, List<Map<String, dynamic>> values) async {
    await (await SharedPreferences.getInstance())
        .setString(_key(key), jsonEncode(values));
  }

  Map<String, dynamic> _drugJson(Drug drug) => {
        'id': drug.id,
        'name': drug.name,
        'notes': drug.notes,
        'label_image_path': drug.labelImagePath,
        'added_at': drug.addedAt?.toIso8601String(),
        'instructions': drug.instructions
            .map((dose) => {
                  'meal': dose.meal.name,
                  'quantity': dose.quantity,
                  'before_food': dose.beforeFood
                })
            .toList(),
      };

  Drug _drug(Map<String, dynamic> json) => Drug(
        id: json['id'] as String,
        name: json['name'] as String,
        notes: (json['notes'] as String?) ?? '',
        labelImagePath: json['label_image_path'] as String?,
        addedAt: json['added_at'] == null
            ? null
            : DateTime.parse(json['added_at'] as String),
        instructions: (json['instructions'] as List)
            .cast<Map<String, dynamic>>()
            .map((dose) => DoseInstruction(
                meal: MealType.values.byName(dose['meal'] as String),
                quantity: dose['quantity'] as int,
                beforeFood: dose['before_food'] as bool))
            .toList(),
      );

  @override
  Future<List<Drug>> drugs() async =>
      (await _list('drugs')).map(_drug).toList();

  @override
  Future<void> saveDrug(Drug drug) async {
    final values = await _list('drugs');
    final index = values.indexWhere((value) => value['id'] == drug.id);
    if (index < 0) {
      values.add(_drugJson(drug));
    } else {
      values[index] = _drugJson(drug);
    }
    await _saveList('drugs', values);
  }

  @override
  Future<List<AllergyRecord>> allergies() async => (await _list('allergies'))
      .map((json) => AllergyRecord(
          date: DateTime.parse(json['date'] as String),
          description: json['description'] as String,
          symptoms: Set<String>.from(json['symptoms'] as List),
          imagePath: json['image_path'] as String?))
      .toList();

  @override
  Future<void> saveAllergy(AllergyRecord record) async {
    final values = await _list('allergies');
    values.add({
      'date': record.date.toIso8601String(),
      'description': record.description,
      'symptoms': record.symptoms.toList(),
      'image_path': record.imagePath
    });
    await _saveList('allergies', values);
  }

  @override
  Future<List<IntakeRecord>> intakeHistory() async {
    final knownDrugs = {for (final drug in await drugs()) drug.id: drug};
    return (await _list('intakes')).map((json) {
      final doses = (json['doses'] as List).cast<Map<String, dynamic>>();
      return IntakeRecord(
          id: json['id'] as String,
          takenAt: DateTime.parse(json['taken_at'] as String),
          meal: MealType.values.byName(json['meal'] as String),
          doses: doses
              .where((dose) => knownDrugs.containsKey(dose['drug_id']))
              .map((dose) => DrugDose(
                  knownDrugs[dose['drug_id']]!, dose['quantity'] as int))
              .toList());
    }).toList();
  }

  @override
  Future<void> saveIntake(IntakeRecord record) async {
    final values = await _list('intakes');
    values.add({
      'id': record.id,
      'taken_at': record.takenAt.toIso8601String(),
      'meal': record.meal.name,
      'doses': record.doses
          .map((dose) => {'drug_id': dose.drug.id, 'quantity': dose.quantity})
          .toList()
    });
    await _saveList('intakes', values);
  }

  @override
  Future<PatientProfile?> patientProfile() async {
    final raw =
        (await SharedPreferences.getInstance()).getString(_key('profile'));
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return PatientProfile(
        name: json['name'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String,
        bloodType: json['blood_type'] as String,
        birthDate: json['birth_date'] as String,
        address: json['address'] as String,
        gender: (json['gender'] as String?) ?? '',
        heightCm: (json['height_cm'] as num?)?.toDouble(),
        weightKg: (json['weight_kg'] as num?)?.toDouble(),
        medicalConditions: (json['medical_conditions'] as String?) ?? '',
        caregiverName: (json['caregiver_name'] as String?) ?? '',
        caregiverRelationship:
            (json['caregiver_relationship'] as String?) ?? '',
        caregiverPhone: (json['caregiver_phone'] as String?) ?? '',
        emergencyPhone: (json['emergency_phone'] as String?) ?? '');
  }

  @override
  Future<void> savePatientProfile(PatientProfile profile) async {
    await (await SharedPreferences.getInstance()).setString(
        _key('profile'),
        jsonEncode({
          'name': profile.name,
          'email': profile.email,
          'phone': profile.phone,
          'blood_type': profile.bloodType,
          'birth_date': profile.birthDate,
          'address': profile.address,
          'gender': profile.gender,
          'height_cm': profile.heightCm,
          'weight_kg': profile.weightKg,
          'medical_conditions': profile.medicalConditions,
          'caregiver_name': profile.caregiverName,
          'caregiver_relationship': profile.caregiverRelationship,
          'caregiver_phone': profile.caregiverPhone,
          'emergency_phone': profile.emergencyPhone
        }));
  }

  @override
  Future<AlertSettings?> alertSettings() async {
    final raw =
        (await SharedPreferences.getInstance()).getString(_key('alerts'));
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return AlertSettings(
      mealTimes: {
        for (final entry
            in (json['meal_times'] as Map<String, dynamic>).entries)
          MealType.values.byName(entry.key): _time(entry.value as String)
      },
      minutesBefore: json['minutes_before'] as int,
      repeatCount: json['repeat_count'] as int,
    );
  }

  TimeOfDay _time(String value) {
    final parts = value.split(':').map(int.parse).toList();
    return TimeOfDay(hour: parts[0], minute: parts[1]);
  }

  String _timeJson(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  @override
  Future<void> saveAlertSettings(AlertSettings settings) async {
    await (await SharedPreferences.getInstance()).setString(
        _key('alerts'),
        jsonEncode({
          'meal_times': {
            for (final entry in settings.mealTimes.entries)
              entry.key.name: _timeJson(entry.value)
          },
          'minutes_before': settings.minutesBefore,
          'repeat_count': settings.repeatCount
        }));
  }
}
