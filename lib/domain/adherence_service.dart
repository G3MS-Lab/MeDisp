import 'models.dart';

enum AdherencePeriod { day, week, month, custom }

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
    DateTime? rangeStart,
    DateTime? rangeEnd,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final requestedEnd = rangeEnd == null
        ? today
        : DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
    final end = requestedEnd.isAfter(today) ? today : requestedEnd;
    final start = switch (period) {
      AdherencePeriod.day => end,
      AdherencePeriod.week => end.subtract(Duration(days: end.weekday - 1)),
      AdherencePeriod.month => DateTime(end.year, end.month),
      AdherencePeriod.custom => rangeStart == null
          ? end
          : DateTime(rangeStart.year, rangeStart.month, rangeStart.day),
    };
    final actualEvents = <String>{};
    for (final intake in intakes) {
      final date = DateTime(
          intake.takenAt.year, intake.takenAt.month, intake.takenAt.day);
      if (date.isBefore(start) || date.isAfter(end)) continue;
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
      final stopped = drug.stoppedAt == null
          ? end
          : DateTime(
              drug.stoppedAt!.year, drug.stoppedAt!.month, drug.stoppedAt!.day);
      final activeEnd = stopped.isBefore(end) ? stopped : end;
      var expected = 0;
      var taken = 0;
      if (!activeStart.isAfter(activeEnd)) {
        for (var date = activeStart;
            !date.isAfter(activeEnd);
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
        end: end,
        drugs: results,
        taken: totalTaken,
        expected: totalExpected);
  }
}
