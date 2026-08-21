import 'package:flutter/material.dart';

import '../application/app_scope.dart';
import '../domain/models.dart';
import '../widgets/medis_app_bar.dart';
import '../widgets/medis_event_calendar.dart';
import 'intake_detail_screen.dart';
import 'adherence_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime selectedDate = DateUtils.dateOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final history = controller.intakeHistory;
    final selectedRecords = history
        .where((record) => DateUtils.isSameDay(record.takenAt, selectedDate))
        .toList();
    return Scaffold(
      appBar: MeDisAppBar('ประวัติการทานยา', actions: [
        IconButton(
            tooltip: 'ดู Adherence Rate',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AdherenceScreen())),
            icon: const Icon(Icons.analytics_outlined))
      ]),
      backgroundColor: const Color(0xFFF4F7FC),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        MeDisEventCalendar(
            selectedDate: selectedDate,
            intakes: history,
            allergies: controller.allergies,
            showAllergyEvents: false,
            onDateSelected: (date) => setState(() => selectedDate = date)),
        const SizedBox(height: 22),
        Text(
            'วันที่ ${selectedDate.day}/${selectedDate.month}/${selectedDate.year + 543}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (selectedRecords.isEmpty)
          const Card(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('ไม่มีประวัติการทานยาในวันนี้')))),
        ...selectedRecords.map((record) => Card(
              child: ListTile(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => IntakeDetailScreen(record: record))),
                leading: CircleAvatar(
                    backgroundColor: record.meal.color,
                    child: const Icon(Icons.check, color: Colors.white)),
                title: Text(record.meal.label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    '${record.doses.fold<int>(0, (sum, dose) => sum + dose.quantity)} เม็ด · ${TimeOfDay.fromDateTime(record.takenAt).format(context)}'),
                trailing: const Icon(Icons.chevron_right),
              ),
            )),
      ]),
    );
  }
}
