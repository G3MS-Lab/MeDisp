import 'package:flutter/material.dart';

import '../application/app_scope.dart';
import '../domain/meal_schedule.dart';
import '../domain/models.dart';
import '../widgets/local_image.dart';
import 'drug_detail_screen.dart';

class DailyScreen extends StatelessWidget {
  const DailyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final done = controller.todayMeals.where((meal) => meal.completed).length;
    final currentMeal =
        MealSchedule.current(controller.todayMeals, DateTime.now());
    final prnSlots = controller.prnSlots;

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              children: [
                Stack(alignment: Alignment.bottomLeft, children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset('assets/images/daily_header.png',
                          height: 125,
                          width: double.infinity,
                          fit: BoxFit.cover)),
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Daily Check List',
                          style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF313131)))),
                ]),
                const SizedBox(height: 14),
                _SlidingTabBar(
                  todayMealsCount: controller.todayMeals.length,
                  doneMealsCount: done,
                  prnSlotsCount: prnSlots.length,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: TabBarView(
              children: [
                _ScheduledMealsTab(
                  done: done,
                  currentMeal: currentMeal,
                ),
                _PrnTab(
                  prnSlots: prnSlots,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SlidingTabBar extends StatelessWidget {
  const _SlidingTabBar({
    required this.todayMealsCount,
    required this.doneMealsCount,
    required this.prnSlotsCount,
  });

  final int todayMealsCount;
  final int doneMealsCount;
  final int prnSlotsCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        splashBorderRadius: BorderRadius.circular(10),
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F001226),
              blurRadius: 4,
              offset: Offset(0, 1.5),
            ),
          ],
        ),
        labelColor: const Color(0xFF397BD9),
        unselectedLabelColor: const Color(0xFF68778B),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.schedule, size: 18),
                const SizedBox(width: 8),
                const Text('ยาตามมื้อ'),
                if (todayMealsCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: doneMealsCount == todayMealsCount
                          ? const Color(0xFF55B97A).withValues(alpha: .15)
                          : const Color(0xFF397BD9).withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$doneMealsCount/$todayMealsCount',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: doneMealsCount == todayMealsCount
                            ? const Color(0xFF55B97A)
                            : const Color(0xFF397BD9),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.medication_outlined, size: 18),
                const SizedBox(width: 8),
                const Text('ตามอาการ'),
                if (prnSlotsCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF397BD9).withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$prnSlotsCount',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF397BD9),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduledMealsTab extends StatelessWidget {
  const _ScheduledMealsTab({
    required this.done,
    required this.currentMeal,
  });

  final int done;
  final MealPlan? currentMeal;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      children: [
        Row(children: [
          Expanded(
              child: Text(
                  'วันนี้ทานแล้ว $done จาก ${controller.todayMeals.length} มื้อ',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600))),
          Text('${controller.alertSettings.minutesBefore} นาทีก่อน',
              style: const TextStyle(color: Colors.grey)),
        ]),
        const SizedBox(height: 12),
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
      ],
    );
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
                      Text('${meal.type.label} · ${meal.time.format24Hour()}',
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
                          : () async {
                              final confirmed =
                                  await _confirmMedicine(context, meal.drugs);
                              if (confirmed && context.mounted) {
                                await widget.onComplete();
                              }
                            },
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

Future<bool> _confirmMedicine(
    BuildContext context, List<DrugDose> doses) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ตรวจสอบยาก่อนทาน'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                      'ยาที่เตรียมไว้ตรงกับรูปและรายการต่อไปนี้หรือไม่?'),
                  const SizedBox(height: 14),
                  ...doses.map((dose) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        clipBehavior: Clip.antiAlias,
                        child: Row(children: [
                          SizedBox(
                            width: 82,
                            height: 82,
                            child: dose.drug.labelImagePath == null
                                ? const ColoredBox(
                                    color: Color(0xFFEAF2FD),
                                    child: Icon(
                                        Icons.image_not_supported_outlined,
                                        color: Color(0xFF7FA9DC)))
                                : localImage(dose.drug.labelImagePath!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.broken_image_outlined)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(dose.drug.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800)),
                                Text('${dose.quantity} เม็ด'),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                        ]),
                      )),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ยังไม่ทาน')),
            FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.check),
                label: const Text('ตรงกับรูป ยืนยันทาน')),
          ],
        ),
      ) ??
      false;
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

class _PrnTab extends StatelessWidget {
  const _PrnTab({required this.prnSlots});
  final List<DispenserSlot> prnSlots;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      children: [
        Row(children: [
          Expanded(
            child: Text(
              'ยาตามอาการในตู้ (${prnSlots.length} รายการ)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const Text('ทานเมื่อมีอาการ',
              style: TextStyle(color: Colors.grey)),
        ]),
        const SizedBox(height: 12),
        if (prnSlots.isEmpty) const _EmptyPrnPlan(),
        ...prnSlots.map((slot) => _PrnDrugCard(
              key: ValueKey(slot.number),
              slot: slot,
            )),
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
                    Text('ข้อระวังการทานยาตามอาการ (PRN)',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                        'ทานเมื่อมีอาการเท่านั้น และสังเกตระยะห่างความปลอดภัย',
                        style: TextStyle(color: Colors.grey))
                  ]))
            ]),
          ),
        ),
      ],
    );
  }
}

class _EmptyPrnPlan extends StatelessWidget {
  const _EmptyPrnPlan();
  @override
  Widget build(BuildContext context) => const Card(
      child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(children: [
            Icon(Icons.medication_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 10),
            Text('ยังไม่มียาตามอาการในตู้จ่ายยา',
                style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            Text(
              'สามารถเพิ่มยา PRN ได้ที่หน้า "จัดการยา" แล้วเลือกประเภทยาเป็น "ทานเมื่อมีอาการ (PRN)"',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ])));
}

class _PrnDrugCard extends StatefulWidget {
  const _PrnDrugCard({required this.slot, super.key});
  final DispenserSlot slot;

  @override
  State<_PrnDrugCard> createState() => _PrnDrugCardState();
}

class _PrnDrugCardState extends State<_PrnDrugCard> {
  bool expanded = true;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final slot = widget.slot;
    final drug = slot.drug!;
    final config = drug.prnConfig ??
        const PrnConfig(
            symptom: 'เมื่อมีอาการ',
            quantity: 1,
            minIntervalHours: 4,
            maxDosesPerDay: 4);
    final status = controller.checkPrnStatus(drug);

    return Card(
      margin: const EdgeInsets.only(bottom: 18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => expanded = !expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                CircleAvatar(
                  backgroundColor: status.canTake
                      ? const Color(0xFF397BD9).withValues(alpha: .18)
                      : const Color(0xFF68778B).withValues(alpha: .15),
                  child: Icon(
                    status.canTake
                        ? Icons.medication_outlined
                        : Icons.access_time_rounded,
                    color: status.canTake
                        ? const Color(0xFF397BD9)
                        : const Color(0xFF68778B),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        drug.name,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'ช่อง ${slot.number} · คงเหลือ ${slot.remaining} เม็ด',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                if (status.canTake)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF55B97A).withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 14, color: Color(0xFF55B97A)),
                        SizedBox(width: 4),
                        Text(
                          'พร้อมทาน',
                          style: TextStyle(
                            color: Color(0xFF55B97A),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4C542).withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.access_time_filled,
                            size: 14, color: Color(0xFFD97706)),
                        SizedBox(width: 4),
                        Text(
                          'รอเวลา',
                          style: TextStyle(
                            color: Color(0xFFB45309),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 8),
                Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ]),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState:
                expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Column(children: [
              const Divider(height: 25),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF397BD9).withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 13, 10, 8),
                    child: Row(children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF397BD9).withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(Icons.healing_outlined,
                            size: 20, color: Color(0xFF397BD9)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              config.symptom.isNotEmpty
                                  ? 'อาการ: ${config.symptom}'
                                  : 'เมื่อมีอาการ',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              'เว้นระยะห่าง ${config.minIntervalHours} ชม. · สูงสุด ${config.maxDosesPerDay} ครั้ง/วัน',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF68778B)),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'ครั้งละ ${config.quantity} เม็ด',
                        style: const TextStyle(
                          color: Color(0xFF397BD9),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ]),
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 15, right: 8),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => DrugDetailScreen(drug: drug)),
                    ),
                    leading: SizedBox(
                      width: 34,
                      height: 34,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: drug.labelImagePath == null
                            ? const CircleAvatar(
                                radius: 17,
                                backgroundColor: Colors.white,
                                child: Icon(Icons.medication_outlined,
                                    size: 19, color: Color(0xFF397BD9)),
                              )
                            : localImage(
                                drug.labelImagePath!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                    Icons.broken_image_outlined,
                                    size: 20),
                              ),
                      ),
                    ),
                    title: Text(drug.name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(status.reason),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                  const SizedBox(height: 5),
                ]),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 196,
                child: FilledButton(
                  onPressed: status.canTake && slot.remaining >= config.quantity
                      ? () async {
                          final confirmed =
                              await _confirmPrnMedicine(context, drug, slot);
                          if (confirmed && context.mounted) {
                            try {
                              await controller.completePrnIntake(drug);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'จ่ายยา ${drug.name} เรียบร้อยแล้ว'),
                                  ),
                                );
                              }
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(error
                                        .toString()
                                        .replaceFirst('Bad state: ', '')),
                                  ),
                                );
                              }
                            }
                          }
                        }
                      : null,
                  child: Text(
                    slot.remaining < config.quantity
                        ? 'ยาหมด'
                        : status.canTake
                            ? 'กดรับยา'
                            : 'รอเวลา',
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

Future<bool> _confirmPrnMedicine(
    BuildContext context, Drug drug, DispenserSlot slot) async {
  final config = drug.prnConfig ??
      const PrnConfig(
          symptom: 'เมื่อมีอาการ',
          quantity: 1,
          minIntervalHours: 4,
          maxDosesPerDay: 4);
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ตรวจสอบยาก่อนทาน'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ยาที่เตรียมไว้ตรงกับรูปและรายการต่อไปนี้หรือไม่?'),
                  const SizedBox(height: 14),
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    clipBehavior: Clip.antiAlias,
                    child: Row(children: [
                      SizedBox(
                        width: 82,
                        height: 82,
                        child: drug.labelImagePath == null
                            ? const ColoredBox(
                                color: Color(0xFFEAF2FD),
                                child: Icon(
                                    Icons.image_not_supported_outlined,
                                    color: Color(0xFF7FA9DC)))
                            : localImage(drug.labelImagePath!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                    Icons.broken_image_outlined)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(drug.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            Text(
                                '${config.quantity} เม็ด (ช่องที่ ${slot.number})'),
                            if (config.symptom.isNotEmpty)
                              Text('อาการ: ${config.symptom}',
                                  style: const TextStyle(
                                      color: Color(0xFF68778B),
                                      fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                    ]),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '• ระบบจะเริ่มนับเวลาความปลอดภัย ${config.minIntervalHours} ชั่วโมง',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF68778B)),
                        ),
                        if (drug.notes.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '• คำแนะนำ: ${drug.notes.trim()}',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF68778B)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยังไม่ทาน'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.check),
              label: const Text('ตรงกับรูป ยืนยันทาน'),
            ),
          ],
        ),
      ) ??
      false;
}
