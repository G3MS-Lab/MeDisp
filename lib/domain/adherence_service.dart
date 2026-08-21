import 'models.dart';

enum AdherencePeriod { week, month }

class DrugAdherence {
  const DrugAdherence(
      {required this.drug, required this.taken, required this.expected});
  final Drug drug;
  final int taken;
  final int expected;
  double get rate => expected == 0 ? 0 : (taken / expected).clamp(0, 1);
}

class AdherenceReport {
  const AdherenceReport(
      {required this.start,
      required this.end,
      required this.drugs,
      required this.taken,
      required this.expected});
  final DateTime start;
  final DateTime end;
  final List<DrugAdherence> drugs;
  final int taken;
  final int expected;
  double get rate => expected == 0 ? 0 : (taken / expected).clamp(0, 1);
}

class AdherenceService {
  const AdherenceService();

  AdherenceReport calculate({
    required AdherencePeriod period,
    required DateTime now,
    required List<Drug> drugs,
    required List<IntakeRecord> intakes,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final start = period == AdherencePeriod.week
        ? today.subtract(Duration(days: today.weekday - 1))
        : DateTime(today.year, today.month);
    final actualEvents = <String>{};
    for (final intake in intakes) {
      final date = DateTime(
          intake.takenAt.year, intake.takenAt.month, intake.takenAt.day);
      if (date.isBefore(start) || date.isAfter(today)) continue;
      for (final dose in intake.doses) {
        actualEvents.add(
            '${dose.drug.id}|${date.toIso8601String()}|${intake.meal.name}');
      }
    }

    final results = <DrugAdherence>[];
    var totalTaken = 0;
    var totalExpected = 0;
    for (final drug in drugs) {
      final added = drug.addedAt == null
          ? start
          : DateTime(
              drug.addedAt!.year, drug.addedAt!.month, drug.addedAt!.day);
      final activeStart = added.isAfter(start) ? added : start;
      var expected = 0;
      var taken = 0;
      if (!activeStart.isAfter(today)) {
        for (var date = activeStart;
            !date.isAfter(today);
            date = date.add(const Duration(days: 1))) {
          for (final instruction in drug.instructions) {
            expected++;
            if (actualEvents.contains(
                '${drug.id}|${date.toIso8601String()}|${instruction.meal.name}')) {
              taken++;
            }
          }
        }
      }
      results.add(DrugAdherence(drug: drug, taken: taken, expected: expected));
      totalTaken += taken;
      totalExpected += expected;
    }
    return AdherenceReport(
        start: start,
        end: today,
        drugs: results,
        taken: totalTaken,
        expected: totalExpected);
  }
}
