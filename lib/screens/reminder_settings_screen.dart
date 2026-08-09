import 'package:flutter/material.dart';

import '../application/app_scope.dart';
import '../domain/models.dart';
import '../widgets/medis_app_bar.dart';

class ReminderSettingsScreen extends StatefulWidget {
  const ReminderSettingsScreen({super.key});
  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
  late Map<MealType, TimeOfDay> times;
  late int minutesBefore;
  late int repeats;
  bool initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      final settings = AppScope.of(context).alertSettings;
      times = Map.of(settings.mealTimes);
      minutesBefore = settings.minutesBefore;
      repeats = settings.repeatCount;
      initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const MeDisAppBar('ตั้งค่าการแจ้งเตือน'),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          const Text('เวลาทานอาหาร', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...MealType.values.map((meal) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('มื้อ${meal.label}'),
                subtitle: Text(times[meal]!.format(context), style: const TextStyle(fontSize: 19)),
                trailing: const Icon(Icons.schedule),
                onTap: () async {
                  final value = await showTimePicker(context: context, initialTime: times[meal]!);
                  if (value != null) setState(() => times[meal] = value);
                },
              )),
          const Divider(height: 32),
          DropdownButtonFormField<int>(value: minutesBefore, decoration: const InputDecoration(labelText: 'แจ้งเตือนก่อนเวลา'), items: [5, 10, 15, 30, 60].map((value) => DropdownMenuItem(value: value, child: Text('$value นาที'))).toList(), onChanged: (value) => setState(() => minutesBefore = value!)),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(value: repeats, decoration: const InputDecoration(labelText: 'จำนวนครั้งที่แจ้งเตือน'), items: [1, 2, 3, 4, 5].map((value) => DropdownMenuItem(value: value, child: Text('$value ครั้ง'))).toList(), onChanged: (value) => setState(() => repeats = value!)),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: () {
              AppScope.of(context).updateAlerts(AlertSettings(mealTimes: times, minutesBefore: minutesBefore, repeatCount: repeats));
              Navigator.pop(context);
            },
            child: const Text('บันทึกการตั้งค่า'),
          ),
        ]),
      );
}
