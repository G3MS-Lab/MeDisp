import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../theme/medis_theme.dart';

class _DayMedicationData {
  const _DayMedicationData({
    required this.percent,
    required this.hasPrn,
    required this.color,
    required this.bgColor,
  });

  final int? percent;
  final bool hasPrn;
  final Color color;
  final Color bgColor;
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

  static Color _rateColor(double rate, {required bool isToday}) {
    if (rate >= 1.0) return MeDisColors.success;
    if (rate >= 0.7) return const Color(0xFF2E8B57);
    if (rate >= 0.4) return MeDisColors.warning;
    if (rate > 0.0) return const Color(0xFFD96B27);
    return isToday ? MeDisColors.muted : MeDisColors.error;
  }

  static Color _rateBgColor(double rate, {required bool isToday}) {
    if (rate >= 0.7) return MeDisColors.successSoft;
    if (rate >= 0.4) return MeDisColors.warningSoft;
    if (rate > 0.0) return const Color(0xFFFFF0E6);
    return isToday ? MeDisColors.primarySoft : MeDisColors.errorSoft;
  }

  _DayMedicationData _calculateDayData(
      DateTime date, Set<MealType> completedMeals, bool hasPrn) {
    final today = DateUtils.dateOnly(DateTime.now());
    final targetDate = DateUtils.dateOnly(date);
    final isToday = DateUtils.isSameDay(targetDate, today);

    if (targetDate.isAfter(today)) {
      return const _DayMedicationData(
        percent: null,
        hasPrn: false,
        color: Colors.transparent,
        bgColor: Colors.transparent,
      );
    }

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

    int? percent;
    Color color = MeDisColors.text;
    Color bgColor = MeDisColors.surface;

    if (activeScheduledDrugs.isNotEmpty && expectedMeals.isNotEmpty) {
      final completedCount = completedMeals.intersection(expectedMeals).length;
      final rate = (completedCount / expectedMeals.length).clamp(0.0, 1.0);
      percent = (rate * 100).round();
      color = _rateColor(rate, isToday: isToday);
      bgColor = _rateBgColor(rate, isToday: isToday);
    } else {
      if (completedMeals.isNotEmpty) {
        percent = 100;
        color = MeDisColors.success;
        bgColor = MeDisColors.successSoft;
      }
    }

    return _DayMedicationData(
      percent: percent,
      hasPrn: hasPrn,
      color: color,
      bgColor: bgColor,
    );
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
                            ? 88
                            : (showMedicationEvents ? 78 : 68)) +
                        (MediaQuery.textScalerOf(context).scale(15) - 15) * 2.5),
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
              final dayData = showMedicationEvents
                  ? _calculateDayData(date, meals, hasPrn)
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
                    padding: const EdgeInsets.symmetric(vertical: 3),
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$day',
                            style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: MeDisColors.text)),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showMedicationEvents && dayData != null) ...[
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (dayData.percent != null)
                                      _PercentBadge(
                                        percent: dayData.percent!,
                                        color: dayData.color,
                                        bgColor: dayData.bgColor,
                                      ),
                                    if (dayData.hasPrn) ...[
                                      if (dayData.percent != null)
                                        const SizedBox(width: 2),
                                      const _PrnSymbol(),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                            if (allergyCount > 0) ...[
                              const SizedBox(height: 2),
                              const Icon(Icons.warning_rounded,
                                  size: 13, color: MeDisColors.error),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const Divider(height: 22),
          Wrap(spacing: 12, runSpacing: 8, children: [
            if (showMedicationEvents) ...[
              const _LegendDot(color: MeDisColors.success, label: '100% ทานครบ'),
              const _LegendDot(color: MeDisColors.warning, label: 'ทานบางส่วน'),
              const _LegendDot(color: MeDisColors.error, label: '0% ไม่ได้ทาน'),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: MeDisColors.prnSoft,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.healing_rounded,
                      size: 12, color: MeDisColors.prn),
                ),
                const SizedBox(width: 5),
                const Text('ยาตามอาการ', style: TextStyle(fontSize: 12)),
              ]),
            ],
            if (showAllergyEvents)
              const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.warning_rounded, size: 17, color: MeDisColors.error),
                SizedBox(width: 5),
                Text('อาการไม่พึงประสงค์', style: TextStyle(fontSize: 12)),
              ]),
          ]),
        ]),
      ),
    );
  }
}

class _PercentBadge extends StatelessWidget {
  const _PercentBadge({
    required this.percent,
    required this.color,
    required this.bgColor,
  });

  final int percent;
  final Color color;
  final Color bgColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$percent%',
            maxLines: 1,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
              height: 1.15,
            ),
          ),
        ),
      );
}

class _PrnSymbol extends StatelessWidget {
  const _PrnSymbol();

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'ทานยาตามอาการ',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: MeDisColors.prnSoft,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Icon(
            Icons.healing_rounded,
            size: 11,
            color: MeDisColors.prn,
          ),
        ),
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
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);
}
