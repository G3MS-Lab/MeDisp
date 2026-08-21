import 'package:flutter/material.dart';

class AppUser {
  const AppUser(
      {required this.id, required this.email, required this.displayName});
  final String id;
  final String email;
  final String displayName;
}

enum MealType { breakfast, lunch, dinner, bedtime }

extension MealTypeUi on MealType {
  String get label => switch (this) {
        MealType.breakfast => 'เช้า',
        MealType.lunch => 'เที่ยง',
        MealType.dinner => 'เย็น',
        MealType.bedtime => 'ก่อนนอน',
      };

  Color get color => switch (this) {
        MealType.breakfast => const Color(0xFF63B1FF),
        MealType.lunch => const Color(0xFFF4C542),
        MealType.dinner => const Color(0xFFFF8A5B),
        MealType.bedtime => const Color(0xFF284B8F),
      };
}

class DoseInstruction {
  const DoseInstruction(
      {required this.meal, required this.quantity, this.beforeFood = true});
  final MealType meal;
  final int quantity;
  final bool beforeFood;
}

class Drug {
  const Drug(
      {required this.id,
      required this.name,
      required this.instructions,
      this.labelImagePath,
      this.addedAt,
      this.notes = ''});
  final String id;
  final String name;
  final List<DoseInstruction> instructions;
  final String? labelImagePath;
  final DateTime? addedAt;
  final String notes;

  DoseInstruction? instructionFor(MealType meal) {
    for (final instruction in instructions) {
      if (instruction.meal == meal) return instruction;
    }
    return null;
  }
}

class DispenserSlot {
  const DispenserSlot(
      {required this.number,
      this.capacity = 30,
      this.remaining = 0,
      this.drug});
  final int number;
  final int capacity;
  final int remaining;
  final Drug? drug;
  bool get isFull => remaining >= capacity;
  bool get isEmpty => drug == null;

  DispenserSlot copyWith({Drug? drug, int? remaining}) => DispenserSlot(
      number: number,
      capacity: capacity,
      drug: drug ?? this.drug,
      remaining: remaining ?? this.remaining);
}

class MealPlan {
  const MealPlan(
      {required this.type,
      required this.time,
      required this.drugs,
      this.completed = false,
      this.completedAt});
  final MealType type;
  final TimeOfDay time;
  final List<DrugDose> drugs;
  final bool completed;
  final DateTime? completedAt;
  int get totalPills => drugs.fold(0, (sum, item) => sum + item.quantity);

  MealPlan copyWith({bool? completed, DateTime? completedAt}) => MealPlan(
      type: type,
      time: time,
      drugs: drugs,
      completed: completed ?? this.completed,
      completedAt: completedAt ?? this.completedAt);
}

class DrugDose {
  const DrugDose(this.drug, this.quantity);
  final Drug drug;
  final int quantity;
}

class PatientProfile {
  const PatientProfile(
      {required this.name,
      required this.email,
      required this.phone,
      required this.bloodType,
      required this.birthDate,
      required this.address,
      this.gender = '',
      this.heightCm,
      this.weightKg,
      this.medicalConditions = '',
      this.caregiverName = '',
      this.caregiverRelationship = '',
      this.caregiverPhone = '',
      this.emergencyPhone = ''});
  final String name;
  final String email;
  final String phone;
  final String bloodType;
  final String birthDate;
  final String address;
  final String gender;
  final double? heightCm;
  final double? weightKg;
  final String medicalConditions;
  final String caregiverName;
  final String caregiverRelationship;
  final String caregiverPhone;
  final String emergencyPhone;
}

class AlertSettings {
  const AlertSettings(
      {required this.mealTimes, this.minutesBefore = 15, this.repeatCount = 2});
  final Map<MealType, TimeOfDay> mealTimes;
  final int minutesBefore;
  final int repeatCount;

  AlertSettings copyWith(
          {Map<MealType, TimeOfDay>? mealTimes,
          int? minutesBefore,
          int? repeatCount}) =>
      AlertSettings(
        mealTimes: mealTimes ?? this.mealTimes,
        minutesBefore: minutesBefore ?? this.minutesBefore,
        repeatCount: repeatCount ?? this.repeatCount,
      );
}

class AllergyRecord {
  const AllergyRecord(
      {required this.date,
      required this.description,
      required this.symptoms,
      this.imagePath});
  final DateTime date;
  final String description;
  final Set<String> symptoms;
  final String? imagePath;
}

class IntakeRecord {
  const IntakeRecord(
      {required this.id,
      required this.takenAt,
      required this.meal,
      required this.doses});
  final String id;
  final DateTime takenAt;
  final MealType meal;
  final List<DrugDose> doses;
}
