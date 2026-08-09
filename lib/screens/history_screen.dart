import 'package:flutter/material.dart';

import '../application/app_scope.dart';
import '../domain/models.dart';
import '../widgets/medis_app_bar.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int selectedDay = DateTime.now().day.clamp(1, 31).toInt();

  @override
  Widget build(BuildContext context) {
    final meals = AppScope.of(context).todayMeals;
    return Scaffold(
      appBar: const MeDisAppBar('ประวัติการทานยา'),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Center(child: Text('ธันวาคม 2569', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
        const SizedBox(height: 16),
        _MealLegend(),
        const SizedBox(height: 12),
        _Calendar(selectedDay: selectedDay, onSelect: (day) => setState(() => selectedDay = day)),
        const SizedBox(height: 22),
        Text('วันที่ $selectedDay', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ...meals.map((meal) => Card(
              child: ListTile(
                onTap: () => showDialog<void>(context: context, builder: (_) => _MealHistoryDialog(meal: meal, day: selectedDay)),
                leading: CircleAvatar(backgroundColor: meal.type.color, child: Icon(meal.completed ? Icons.check : Icons.schedule, color: Colors.white)),
                title: Text(meal.type.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${meal.totalPills} เม็ด · ${meal.time.format(context)}'),
                trailing: const Icon(Icons.chevron_right),
              ),
            )),
      ]),
    );
  }
}

class _MealLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Wrap(spacing: 10, runSpacing: 6, children: MealType.values.map((meal) => Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 12, height: 12, color: meal.color), const SizedBox(width: 4), Text(meal.label)])).toList());
}

class _Calendar extends StatelessWidget {
  const _Calendar({required this.selectedDay, required this.onSelect});
  final int selectedDay;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: .82),
        itemCount: 35,
        itemBuilder: (_, i) {
          final day = i + 1;
          if (day > 31) return const SizedBox();
          return InkWell(
            onTap: () => onSelect(day),
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: selectedDay == day ? Colors.green : const Color(0xFFCCCCCC), width: selectedDay == day ? 2 : .5)),
              child: Column(children: [
                Align(alignment: Alignment.topLeft, child: Padding(padding: const EdgeInsets.all(3), child: Text('$day', style: const TextStyle(fontSize: 10)))),
                Expanded(child: GridView.count(physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, children: MealType.values.map((meal) => Container(color: day % (meal.index + 2) == 0 ? meal.color : const Color(0xFFF4F4F4))).toList())),
              ]),
            ),
          );
        },
      );
}

class _MealHistoryDialog extends StatelessWidget {
  const _MealHistoryDialog({required this.meal, required this.day});
  final MealPlan meal;
  final int day;
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('$day ธันวาคม · ${meal.type.label}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: meal.drugs.map((dose) => ListTile(contentPadding: EdgeInsets.zero, title: Text(dose.drug.name), trailing: Text('${dose.quantity} เม็ด'))).toList()),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ปิด'))],
      );
}
