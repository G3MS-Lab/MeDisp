import 'package:flutter/material.dart';

import '../application/app_scope.dart';
import '../domain/models.dart';

class DailyScreen extends StatelessWidget {
  const DailyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final done = controller.todayMeals.where((meal) => meal.completed).length;
    return ListView(padding: const EdgeInsets.fromLTRB(24, 26, 24, 24), children: [
      Stack(alignment: Alignment.bottomLeft, children: [
        ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.asset('assets/images/daily_header.png', height: 150, width: double.infinity, fit: BoxFit.cover)),
        const Padding(padding: EdgeInsets.all(18), child: Text('Daily Check List', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: Color(0xFF313131)))),
      ]),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: Text('วันนี้ทานแล้ว $done จาก ${controller.todayMeals.length} มื้อ', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
        Text('${controller.alertSettings.minutesBefore} นาทีก่อน', style: const TextStyle(color: Colors.grey)),
      ]),
      const SizedBox(height: 14),
      if (controller.todayMeals.isEmpty) const _EmptyPlan(),
      ...controller.todayMeals.map((meal) => _MealCard(meal: meal, onComplete: () => controller.completeMeal(meal.type))),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(children: const [CircleAvatar(backgroundColor: Color(0xFFF7F7FA), child: Icon(Icons.warning_rounded, color: Colors.red)), SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('ข้อระวัง', style: TextStyle(fontWeight: FontWeight.w700)), Text('ตรวจสอบฉลากยาและคำแนะนำจากแพทย์', style: TextStyle(color: Colors.grey))]))]),
        ),
      ),
    ]);
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal, required this.onComplete});
  final MealPlan meal;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              CircleAvatar(backgroundColor: meal.type.color.withOpacity(.18), child: Icon(meal.completed ? Icons.check : Icons.medication_outlined, color: meal.type.color)),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${meal.type.label} · ${meal.time.format(context)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)), Text('${meal.totalPills} เม็ด · ${meal.drugs.length} รายการ', style: const TextStyle(color: Colors.grey))])),
              Icon(meal.completed ? Icons.verified_rounded : Icons.notifications_active_outlined, color: meal.completed ? Colors.green : const Color(0xFF6AA6FF)),
            ]),
            const Divider(height: 25),
            ...meal.drugs.map((dose) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [Expanded(child: Text(dose.drug.name, style: const TextStyle(fontSize: 17))), Text('${dose.quantity} เม็ด')]))),
            const SizedBox(height: 12),
            SizedBox(width: 196, child: FilledButton(onPressed: meal.completed ? null : onComplete, child: Text(meal.completed ? 'ทานแล้ว' : 'ทานแล้ว'))),
          ]),
        ),
      );
}

class _EmptyPlan extends StatelessWidget {
  const _EmptyPlan();
  @override
  Widget build(BuildContext context) => const Card(child: Padding(padding: EdgeInsets.all(28), child: Column(children: [Icon(Icons.medication_outlined, size: 48, color: Colors.grey), SizedBox(height: 10), Text('ยังไม่มียาในตารางวันนี้')])));
}
