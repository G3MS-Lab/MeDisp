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
        backgroundColor: const Color(0xFFF4F7FC),
        appBar: const MeDisAppBar('ตั้งค่าการแจ้งเตือน'),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.restaurant_outlined, color: Color(0xFF397BD9)),
                      SizedBox(width: 9),
                      Text('เวลาทานอาหาร',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800))
                    ]),
                    const Divider(height: 24),
                    ...MealType.values.map((meal) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                              backgroundColor:
                                  meal.color.withValues(alpha: .15),
                              child: Icon(Icons.schedule, color: meal.color)),
                          title: Text('มื้อ${meal.label}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(times[meal]!.format(context),
                              style: const TextStyle(fontSize: 19)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            final value = await showTimePicker(
                                context: context, initialTime: times[meal]!);
                            if (value != null) {
                              setState(() => times[meal] = value);
                            }
                          },
                        )),
                  ]),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.notifications_active_outlined,
                          color: Color(0xFF397BD9)),
                      SizedBox(width: 9),
                      Text('รูปแบบการแจ้งเตือน',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800))
                    ]),
                    const SizedBox(height: 18),
                    DropdownButtonFormField<int>(
                        initialValue: minutesBefore,
                        decoration: const InputDecoration(
                            labelText: 'แจ้งเตือนก่อนเวลา',
                            prefixIcon: Icon(Icons.timer_outlined)),
                        items: [5, 10, 15, 30, 60]
                            .map((value) => DropdownMenuItem(
                                value: value, child: Text('$value นาที')))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => minutesBefore = value!)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                        initialValue: repeats,
                        decoration: const InputDecoration(
                            labelText: 'จำนวนครั้งที่แจ้งเตือน',
                            prefixIcon: Icon(Icons.repeat)),
                        items: [1, 2, 3, 4, 5]
                            .map((value) => DropdownMenuItem(
                                value: value, child: Text('$value ครั้ง')))
                            .toList(),
                        onChanged: (value) => setState(() => repeats = value!)),
                  ]),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () async {
              await AppScope.of(context).updateAlerts(AlertSettings(
                  mealTimes: times,
                  minutesBefore: minutesBefore,
                  repeatCount: repeats));
              if (context.mounted) Navigator.pop(context);
            },
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            icon: const Icon(Icons.save_outlined),
            label: const Text('บันทึกการตั้งค่า'),
          ),
        ]),
      );
}
