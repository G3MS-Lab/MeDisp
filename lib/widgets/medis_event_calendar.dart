import 'package:flutter/material.dart';

import '../theme/medis_theme.dart';

import '../domain/models.dart';

enum DayMedicationStatus {
  completed,
  partial,
  missed,
  pending,
  taken,
}

class MeDisEventCalendar extends StatelessWidget {
  const MeDisEventCalendar({
    required this.selectedDate,
    required this.intakes,
    required this.allergies,
    required this.onDateSelected,
    this.drugs = const [],
    this.showMedicationEvents = true,
    this.showAllergyEvents = true,
    super.key,
  });

  final DateTime selectedDate;
  final List<IntakeRecord> intakes;
  final List<AllergyRecord> allergies;
  final List<Drug> drugs;
  final ValueChanged<DateTime> onDateSelected;
  final bool showMedicationEvents;
  final bool showAllergyEvents;

  static const _months = [
    'มกราคม',
    'กุมภาพันธ์',
    'มีนาคม',
    'เมษายน',
    'พฤษภาคม',
    'มิถุนายน',
    'กรกฎาคม',
    'สิงหาคม',
    'กันยายน',
    'ตุลาคม',
    'พฤศจิกายน',
    'ธันวาคม'
  ];

  void _changeMonth(int offset) {
    final target = DateTime(selectedDate.year, selectedDate.month + offset);
    onDateSelected(target);
  }

  DayMedicationStatus? _getMedicationStatus(
      DateTime date, Set<MealType> completedMeals, bool hasPrn) {
    final today = DateUtils.dateOnly(DateTime.now());
    final targetDate = DateUtils.dateOnly(date);

    if (targetDate.isAfter(today)) return null;

    final activeScheduledDrugs = drugs.where((drug) {
      if (drug.isPrn) return false;
      if (drug.addedAt != null) {
        final added = DateUtils.dateOnly(drug.addedAt!);
        if (targetDate.isBefore(added)) return false;
      }
      if (drug.stoppedAt != null) {
        final stopped = DateUtils.dateOnly(drug.stoppedAt!);
        if (targetDate.isAfter(stopped)) return false;
      }
      return true;
    }).toList();

    final expectedMeals = <MealType>{};
    for (final drug in activeScheduledDrugs) {
      for (final instruction in drug.instructions) {
        expectedMeals.add(instruction.meal);
      }
    }

    if (activeScheduledDrugs.isNotEmpty && expectedMeals.isNotEmpty) {
      if (expectedMeals.every(completedMeals.contains)) {
        return DayMedicationStatus.completed;
      } else if (completedMeals.isNotEmpty || hasPrn) {
        return DayMedicationStatus.partial;
      } else {
        if (DateUtils.isSameDay(targetDate, today)) {
          return DayMedicationStatus.pending;
        } else {
          return DayMedicationStatus.missed;
        }
      }
    } else {
      if (completedMeals.isNotEmpty || hasPrn) {
        return DayMedicationStatus.taken;
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(selectedDate.year, selectedDate.month);
    final dayCount = DateUtils.getDaysInMonth(first.year, first.month);
    final offset = first.weekday % 7;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: Column(children: [
          Row(children: [
            IconButton(
                tooltip: 'เดือนก่อนหน้า',
                onPressed: () => _changeMonth(-1),
                icon: const Icon(Icons.chevron_left)),
            Expanded(
                child: Text(
                    '${_months[selectedDate.month - 1]} ${selectedDate.year + 543}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w700))),
            IconButton(
                tooltip: 'เดือนถัดไป',
                onPressed: () => _changeMonth(1),
                icon: const Icon(Icons.chevron_right)),
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
                children: ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส']
                    .map((day) => Expanded(
                        child: Text(day,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: MeDisColors.subtle,
                                fontWeight: FontWeight.w700))))
                    .toList()),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent:
                    (showMedicationEvents && showAllergyEvents
                            ? 94
                            : (showMedicationEvents ? 78 : 64)) +
                        (MediaQuery.textScalerOf(context).scale(15) - 15) * 2),
            itemCount: ((offset + dayCount + 6) ~/ 7) * 7,
            itemBuilder: (_, index) {
              final day = index - offset + 1;
              if (day < 1 || day > dayCount) return const SizedBox();
              final date = DateTime(first.year, first.month, day);
              final meals = showMedicationEvents
                  ? intakes
                      .where((record) =>
                          !record.isPrn &&
                          record.meal != null &&
                          DateUtils.isSameDay(record.takenAt, date))
                      .map((record) => record.meal!)
                      .toSet()
                  : <MealType>{};
              final hasPrn = showMedicationEvents
                  ? intakes.any((record) =>
                      record.isPrn && DateUtils.isSameDay(record.takenAt, date))
                  : false;
              final allergyCount = showAllergyEvents
                  ? allergies
                      .where((record) => DateUtils.isSameDay(record.date, date))
                      .length
                  : 0;
              final dayStatus = showMedicationEvents
                  ? _getMedicationStatus(date, meals, hasPrn)
                  : null;
              final selected = DateUtils.isSameDay(selectedDate, date);
              final today = DateUtils.isSameDay(DateTime.now(), date);
              return Padding(
                padding: const EdgeInsets.all(2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onDateSelected(date),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: selected
                          ? MeDisColors.primarySoft
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: selected
                              ? MeDisColors.primary
                              : today
                                  ? MeDisColors.border
                                  : Colors.transparent,
                          width: selected ? 1.5 : 1),
                    ),
                    child: Column(children: [
                      Text('$day',
                          style: TextStyle(
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              color: MeDisColors.text)),
                      const Spacer(),
                      if (showMedicationEvents) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _MedicationMarkerGrid(completedMeals: meals),
                            if (hasPrn) ...[
                              const SizedBox(width: 2),
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: MeDisColors.prn,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (dayStatus != null) ...[
                          const SizedBox(height: 2),
                          _DayStatusBadge(status: dayStatus),
                        ],
                      ],
                      if (allergyCount > 0) ...[
                        const SizedBox(height: 2),
                        const Icon(Icons.warning_rounded,
                            size: 15, color: MeDisColors.error),
                      ],
                    ]),
                  ),
                ),
              );
            },
          ),
          const Divider(height: 22),
          Wrap(spacing: 12, runSpacing: 8, children: [
            if (showMedicationEvents) ...[
              ...MealType.values.map((meal) =>
                  _LegendDot(color: meal.color, label: 'ยา${meal.label}')),
              const _LegendDot(color: MeDisColors.prn, label: 'ยาตามอาการ'),
              const _LegendDot(color: MeDisColors.success, label: 'ทานครบ'),
              const _LegendDot(color: MeDisColors.warning, label: 'ทานบางส่วน'),
              const _LegendDot(color: MeDisColors.error, label: 'ไม่ได้ทาน'),
            ],
            if (showAllergyEvents)
              const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.warning_rounded, size: 17, color: MeDisColors.error),
                SizedBox(width: 5),
                Text('อาการไม่พึงประสงค์', style: TextStyle(fontSize: 12))
              ])
          ]),
        ]),
      ),
    );
  }
}

class _DayStatusBadge extends StatelessWidget {
  const _DayStatusBadge({required this.status});
  final DayMedicationStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color, bgColor) = switch (status) {
      DayMedicationStatus.completed => (
          'ทานครบ',
          MeDisColors.success,
          MeDisColors.successSoft
        ),
      DayMedicationStatus.partial => (
          'ทานบางส่วน',
          MeDisColors.warning,
          MeDisColors.warningSoft
        ),
      DayMedicationStatus.missed => (
          'ไม่ได้ทาน',
          MeDisColors.error,
          MeDisColors.errorSoft
        ),
      DayMedicationStatus.pending => (
          'ยังไม่ทาน',
          MeDisColors.muted,
          MeDisColors.primarySoft
        ),
      DayMedicationStatus.taken => (
          'ทานแล้ว',
          MeDisColors.success,
          MeDisColors.successSoft
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: color,
            height: 1.15,
          ),
        ),
      ),
    );
  }
}

class _MedicationMarkerGrid extends StatelessWidget {
  const _MedicationMarkerGrid({required this.completedMeals});
  final Set<MealType> completedMeals;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 22,
        height: 22,
        child: Column(children: [
          for (var row = 0; row < 2; row++)
            Expanded(
              child: Row(children: [
                for (var column = 0; column < 2; column++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(1),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: completedMeals
                                  .contains(MealType.values[row * 2 + column])
                              ? MealType.values[row * 2 + column].color
                              : MeDisColors.border,
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
        ]),
      );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12))
      ]);
}
