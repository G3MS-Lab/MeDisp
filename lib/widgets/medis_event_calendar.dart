import 'package:flutter/material.dart';

import '../domain/models.dart';

class MeDisEventCalendar extends StatelessWidget {
  const MeDisEventCalendar({
    required this.selectedDate,
    required this.intakes,
    required this.allergies,
    required this.onDateSelected,
    this.showMedicationEvents = true,
    this.showAllergyEvents = true,
    super.key,
  });

  final DateTime selectedDate;
  final List<IntakeRecord> intakes;
  final List<AllergyRecord> allergies;
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
                        fontSize: 19, fontWeight: FontWeight.w800))),
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
                                color: Color(0xFF8291A5),
                                fontWeight: FontWeight.w700))))
                    .toList()),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7, childAspectRatio: .66),
            itemCount: 42,
            itemBuilder: (_, index) {
              final day = index - offset + 1;
              if (day < 1 || day > dayCount) return const SizedBox();
              final date = DateTime(first.year, first.month, day);
              final meals = showMedicationEvents
                  ? intakes
                      .where(
                          (record) => DateUtils.isSameDay(record.takenAt, date))
                      .map((record) => record.meal)
                      .toSet()
                  : <MealType>{};
              final allergyCount = showAllergyEvents
                  ? allergies
                      .where((record) => DateUtils.isSameDay(record.date, date))
                      .length
                  : 0;
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
                          ? const Color(0xFFE3EEFC)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: selected
                              ? const Color(0xFF397BD9)
                              : today
                                  ? const Color(0xFF9ABDEA)
                                  : Colors.transparent,
                          width: selected ? 1.5 : 1),
                    ),
                    child: Column(children: [
                      Text('$day',
                          style: TextStyle(
                              fontWeight:
                                  selected ? FontWeight.w800 : FontWeight.w500,
                              color: const Color(0xFF253246))),
                      const Spacer(),
                      if (showMedicationEvents)
                        _MedicationMarkerGrid(completedMeals: meals),
                      if (allergyCount > 0)
                        const Icon(Icons.warning_rounded,
                            size: 16, color: Color(0xFFE04B4B)),
                    ]),
                  ),
                ),
              );
            },
          ),
          const Divider(height: 22),
          Wrap(spacing: 12, runSpacing: 8, children: [
            if (showMedicationEvents)
              ...MealType.values.map((meal) =>
                  _LegendDot(color: meal.color, label: 'ยา${meal.label}')),
            if (showAllergyEvents)
              const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.warning_rounded, size: 17, color: Color(0xFFE04B4B)),
                SizedBox(width: 5),
                Text('อาการไม่พึงประสงค์', style: TextStyle(fontSize: 12))
              ])
          ]),
        ]),
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
                              : const Color(0xFFE5EAF0),
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
