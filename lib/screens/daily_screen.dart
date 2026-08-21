import 'package:flutter/material.dart';

import '../application/app_scope.dart';
import '../domain/meal_schedule.dart';
import '../domain/models.dart';
import 'drug_detail_screen.dart';

class DailyScreen extends StatelessWidget {
  const DailyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final done = controller.todayMeals.where((meal) => meal.completed).length;
    final currentMeal =
        MealSchedule.current(controller.todayMeals, DateTime.now());
    return ListView(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
        children: [
          Stack(alignment: Alignment.bottomLeft, children: [
            ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.asset('assets/images/daily_header.png',
                    height: 150, width: double.infinity, fit: BoxFit.cover)),
            const Padding(
                padding: EdgeInsets.all(18),
                child: Text('Daily Check List',
                    style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF313131)))),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
                child: Text(
                    'วันนี้ทานแล้ว $done จาก ${controller.todayMeals.length} มื้อ',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600))),
            Text('${controller.alertSettings.minutesBefore} นาทีก่อน',
                style: const TextStyle(color: Colors.grey)),
          ]),
          const SizedBox(height: 14),
          if (controller.todayMeals.isEmpty) const _EmptyPlan(),
          ...controller.todayMeals.map((meal) => _MealCard(
              key: ValueKey(meal.type),
              meal: meal,
              isCurrent: meal.type == currentMeal?.type,
              onComplete: () async {
                try {
                  await controller.completeMeal(meal.type);
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            error.toString().replaceFirst('Bad state: ', ''))));
                  }
                }
              })),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Row(children: const [
                CircleAvatar(
                    backgroundColor: Color(0xFFF7F7FA),
                    child: Icon(Icons.warning_rounded, color: Colors.red)),
                SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('ข้อระวัง',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      Text('ตรวจสอบฉลากยาและคำแนะนำจากแพทย์',
                          style: TextStyle(color: Colors.grey))
                    ]))
              ]),
            ),
          ),
        ]);
  }
}

class _MealCard extends StatefulWidget {
  const _MealCard(
      {required this.meal,
      required this.isCurrent,
      required this.onComplete,
      super.key});
  final MealPlan meal;
  final bool isCurrent;
  final Future<void> Function() onComplete;

  @override
  State<_MealCard> createState() => _MealCardState();
}

class _MealCardState extends State<_MealCard> {
  bool expanded = false;

  @override
  void didUpdateWidget(covariant _MealCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCurrent) expanded = true;
  }

  @override
  Widget build(BuildContext context) {
    final meal = widget.meal;
    final showDetails = widget.isCurrent || expanded;
    final beforeFoodDoses = meal.drugs
        .where(
            (dose) => dose.drug.instructionFor(meal.type)?.beforeFood ?? true)
        .toList();
    final afterFoodDoses = meal.drugs
        .where((dose) =>
            !(dose.drug.instructionFor(meal.type)?.beforeFood ?? true))
        .toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.isCurrent
                ? null
                : () => setState(() => expanded = !expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                CircleAvatar(
                    backgroundColor: meal.type.color.withValues(alpha: .18),
                    child: Icon(
                        meal.completed
                            ? Icons.check
                            : Icons.medication_outlined,
                        color: meal.type.color)),
                const SizedBox(width: 13),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('${meal.type.label} · ${meal.time.format(context)}',
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700)),
                      Text(
                          '${meal.totalPills} เม็ด · ${meal.drugs.length} รายการ',
                          style: const TextStyle(color: Colors.grey))
                    ])),
                if (widget.isCurrent)
                  Icon(
                      meal.completed
                          ? Icons.verified_rounded
                          : Icons.notifications_active_outlined,
                      color: meal.completed
                          ? Colors.green
                          : const Color(0xFF6AA6FF))
                else
                  Icon(showDetails ? Icons.expand_less : Icons.expand_more),
              ]),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: showDetails
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Column(children: [
              const Divider(height: 25),
              if (beforeFoodDoses.isNotEmpty)
                _DoseGroup(
                    title: 'ก่อนอาหาร',
                    description: 'ควรทานก่อนเริ่มมื้ออาหาร',
                    icon: Icons.restaurant_menu,
                    color: const Color(0xFF397BD9),
                    doses: beforeFoodDoses),
              if (beforeFoodDoses.isNotEmpty && afterFoodDoses.isNotEmpty)
                const SizedBox(height: 12),
              if (afterFoodDoses.isNotEmpty)
                _DoseGroup(
                    title: 'หลังอาหาร',
                    description: 'ควรทานหลังรับประทานอาหาร',
                    icon: Icons.restaurant,
                    color: const Color(0xFF55B97A),
                    doses: afterFoodDoses),
              const SizedBox(height: 12),
              SizedBox(
                  width: 196,
                  child: FilledButton(
                      onPressed: meal.completed || !widget.isCurrent
                          ? null
                          : () async => widget.onComplete(),
                      child: Text(meal.completed
                          ? 'ทานแล้ว'
                          : widget.isCurrent
                              ? 'ทานแล้ว'
                              : 'ไม่ใช่มื้อปัจจุบัน'))),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _DoseGroup extends StatelessWidget {
  const _DoseGroup({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.doses,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final List<DrugDose> doses;

  @override
  Widget build(BuildContext context) {
    final totalPills =
        doses.fold<int>(0, (total, dose) => total + dose.quantity);
    return Container(
      decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(15)),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 10, 8),
          child: Row(children: [
            Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, size: 20, color: color)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(description,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF68778B)))
                ])),
            Text('${doses.length} รายการ · $totalPills เม็ด',
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w700))
          ]),
        ),
        ...doses.map((dose) => ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 15, right: 8),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => DrugDetailScreen(drug: dose.drug))),
              leading: CircleAvatar(
                  radius: 17,
                  backgroundColor: Colors.white,
                  child:
                      Icon(Icons.medication_outlined, size: 19, color: color)),
              title: Text(dose.drug.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${dose.quantity} เม็ด'),
              trailing: const Icon(Icons.chevron_right),
            )),
        const SizedBox(height: 5),
      ]),
    );
  }
}

class _EmptyPlan extends StatelessWidget {
  const _EmptyPlan();
  @override
  Widget build(BuildContext context) => const Card(
      child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(children: [
            Icon(Icons.medication_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 10),
            Text('ยังไม่มียาในตารางวันนี้')
          ])));
}
