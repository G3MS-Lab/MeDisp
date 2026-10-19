import 'package:flutter/material.dart';

import '../theme/medis_theme.dart';

import '../application/app_scope.dart';
import '../domain/meal_schedule.dart';
import '../domain/models.dart';
import '../widgets/local_image.dart';
import '../widgets/medis_ui.dart';
import '../widgets/slide_to_confirm.dart';
import '../widgets/medication_card.dart';
import 'dispenser_screen.dart';
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
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              children: [
                const _TodayBanner(),
                const SizedBox(height: 16),
                const _SlidingTabBar(),
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

class _TodayBanner extends StatelessWidget {
  const _TodayBanner();

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(MeDisRadius.card),
        child: Stack(children: [
          Positioned.fill(
              child: Image.asset('assets/images/daily_header.png',
                  fit: BoxFit.cover, excludeFromSemantics: true)),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Flexible(
                  flex: 4,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .96),
                        borderRadius: BorderRadius.circular(MeDisRadius.input)),
                    child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('ยาวันนี้',
                              style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: MeDisColors.text,
                                  height: 1.4)),
                          SizedBox(height: 4),
                          Text('ทานยาตรงเวลา\nดูแลสุขภาพทุกวัน',
                              style: TextStyle(
                                  fontSize: 16,
                                  color: MeDisColors.muted,
                                  height: 1.5)),
                        ]),
                  )),
              const Spacer(),
            ]),
          ),
        ]),
      );
}

class _SlidingTabBar extends StatelessWidget {
  const _SlidingTabBar();
  @override
  Widget build(BuildContext context) => Container(
        height: 64,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: MeDisColors.primarySoft,
            borderRadius: BorderRadius.circular(MeDisRadius.card)),
        child: TabBar(
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          indicator: BoxDecoration(
              color: MeDisColors.surface,
              borderRadius: BorderRadius.circular(MeDisRadius.input)),
          labelColor: MeDisColors.primary,
          unselectedLabelColor: MeDisColors.muted,
          labelStyle:
              const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          tabs: const [Tab(text: 'ยาตามมื้อ'), Tab(text: 'ตามอาการ')],
        ),
      );
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
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text('วันนี้ทานแล้ว $done จาก ${controller.todayMeals.length} มื้อ',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        if (controller.todayMeals.isNotEmpty) ...[
          const SizedBox(height: 10),
          ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                  minHeight: 6, value: done / controller.todayMeals.length)),
        ],
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
        const MeDisNotice(message: 'ใช้ยาตามคำแนะนำของแพทย์หรือเภสัชกร'),
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
  bool completing = false;

  @override
  void didUpdateWidget(covariant _MealCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCurrent) expanded = true;
  }

  @override
  Widget build(BuildContext context) {
    final meal = widget.meal;
    final connected = AppScope.of(context).connected;
    final showDetails = widget.isCurrent || expanded;
    final beforeFoodDoses = meal.drugs
        .where(
            (dose) => dose.drug.instructionFor(meal.type)?.beforeFood ?? true)
        .toList();
    final afterFoodDoses = meal.drugs
        .where((dose) =>
            !(dose.drug.instructionFor(meal.type)?.beforeFood ?? true))
        .toList();
    return MeDisMedicationCard(
      title: '${meal.type.label} · ${meal.time.format24Hour()}',
      subtitle: '${meal.totalPills} เม็ด · ${meal.drugs.length} รายการ',
      icon: meal.completed
          ? Icons.check_circle_outline
          : Icons.medication_outlined,
      expanded: showDetails,
      highlighted: widget.isCurrent && !meal.completed,
      onToggle:
          widget.isCurrent ? null : () => setState(() => expanded = !expanded),
      trailing: widget.isCurrent
          ? Icon(
              meal.completed
                  ? Icons.check_circle
                  : Icons.notifications_active_outlined,
              color: meal.completed ? MeDisColors.success : MeDisColors.primary,
              size: 28)
          : null,
      children: [
        if (beforeFoodDoses.isNotEmpty)
          _DoseGroup(
              title: 'ก่อนอาหาร',
              icon: Icons.restaurant_menu,
              color: MeDisColors.primary,
              doses: beforeFoodDoses),
        if (beforeFoodDoses.isNotEmpty && afterFoodDoses.isNotEmpty)
          const SizedBox(height: 12),
        if (afterFoodDoses.isNotEmpty)
          _DoseGroup(
              title: 'หลังอาหาร',
              icon: Icons.restaurant,
              color: MeDisColors.primary,
              doses: afterFoodDoses),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            key: Key('receive-meal-${meal.type.name}'),
            onPressed: (!meal.completed &&
                    widget.isCurrent &&
                    connected &&
                    !completing)
                ? () async {
                    final confirmed =
                        await _confirmMedicine(context, meal.drugs);
                    if (confirmed && context.mounted) {
                      setState(() => completing = true);
                      try {
                        await widget.onComplete();
                      } finally {
                        if (mounted) setState(() => completing = false);
                      }
                    }
                  }
                : null,
            icon: completing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Icon(meal.completed
                    ? Icons.check_circle_outline
                    : Icons.medication_outlined),
            label: Text(
              completing
                  ? 'กำลังดำเนินการ...'
                  : meal.completed
                      ? 'ทานแล้ว'
                      : !connected
                          ? 'เชื่อมต่อเครื่องก่อนรับยา'
                          : widget.isCurrent
                              ? 'รับยา'
                              : 'ไม่ใช่มื้อปัจจุบัน',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

Future<bool> _confirmMedicine(
    BuildContext context, List<DrugDose> doses) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ตรวจสอบยาก่อนทาน'),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                                    color: MeDisColors.primarySoft,
                                    child: Icon(
                                        Icons.image_not_supported_outlined,
                                        color: MeDisColors.subtle))
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
                                        fontWeight: FontWeight.w700)),
                                Text('${dose.quantity} เม็ด'),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                        ]),
                      )),
                  const SizedBox(height: 8),
                  SlideToConfirm(
                      sliderKey: const Key('confirm-intake-slider'),
                      label: 'สไลด์เพื่อยืนยันการทานยา',
                      onConfirmed: () => Navigator.pop(context, true)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ยังไม่ทาน')),
          ],
        ),
      ) ??
      false;
}

class _DoseGroup extends StatelessWidget {
  const _DoseGroup({
    required this.title,
    required this.icon,
    required this.color,
    required this.doses,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<DrugDose> doses;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(MeDisRadius.input),
      clipBehavior: Clip.antiAlias,
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
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700))),
          ]),
        ),
        ...doses.map((dose) => ListTile(
              contentPadding: const EdgeInsets.only(left: 15, right: 8),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => DrugDetailScreen(drug: dose.drug))),
              leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white,
                  child:
                      Icon(Icons.medication_outlined, size: 26, color: color)),
              title: Text(dose.drug.name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600)),
              subtitle: Text('ครั้งละ ${dose.quantity} เม็ด',
                  style: const TextStyle(fontSize: 16)),
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
  Widget build(BuildContext context) => MeDisEmptyState(
      icon: Icons.medication_outlined,
      title: 'ยังไม่มียาในตารางวันนี้',
      message: 'เพิ่มยาประจำและเลือกมื้อทานยา เพื่อเริ่มติดตามที่นี่',
      action: OutlinedButton.icon(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const DispenserScreen())),
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('จัดการยา')));
}

class _PrnTab extends StatelessWidget {
  const _PrnTab({required this.prnSlots});
  final List<DispenserSlot> prnSlots;

  @override
  Widget build(BuildContext context) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Row(children: [
          Expanded(
            child: Text(
              'ยาตามอาการในตู้ (${prnSlots.length} รายการ)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (prnSlots.isEmpty) const _EmptyPrnPlan(),
        ...prnSlots.map((slot) => _PrnDrugCard(
              key: ValueKey(slot.number),
              slot: slot,
            )),
        const MeDisNotice(message: 'ใช้ยาตามคำแนะนำของแพทย์หรือเภสัชกร'),
      ],
    );
  }
}

class _EmptyPrnPlan extends StatelessWidget {
  const _EmptyPrnPlan();
  @override
  Widget build(BuildContext context) => MeDisEmptyState(
      icon: Icons.healing_outlined,
      title: 'ยังไม่มียาตามอาการในตู้จ่ายยา',
      message: 'เพิ่มยาแล้วเลือกประเภท “ทานเมื่อมีอาการ (PRN)”',
      action: OutlinedButton.icon(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const DispenserScreen())),
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('จัดการยา')));
}

class _PrnDrugCard extends StatefulWidget {
  const _PrnDrugCard({required this.slot, super.key});
  final DispenserSlot slot;

  @override
  State<_PrnDrugCard> createState() => _PrnDrugCardState();
}

class _PrnDrugCardState extends State<_PrnDrugCard> {
  bool expanded = true;
  bool dispensing = false;

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

    final enough = slot.remaining >= config.quantity;
    final available = status.canTake && enough;
    final statusText = !enough
        ? 'ยาในช่องไม่เพียงพอ กรุณาเติมยา'
        : !status.canTake
            ? status.reason
            : 'พร้อมรับยาเมื่อมีอาการ';
    return MeDisMedicationCard(
      title: drug.name,
      subtitle: 'ช่อง ${slot.number} · คงเหลือ ${slot.remaining} เม็ด',
      icon: Icons.healing_outlined,
      expanded: expanded,
      highlighted: available && controller.connected,
      onToggle: () => setState(() => expanded = !expanded),
      status: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(available ? Icons.check_circle_outline : Icons.access_time,
            color: available ? MeDisColors.success : MeDisColors.warning,
            size: 22),
        const SizedBox(width: 8),
        Expanded(
            child: Text(statusText,
                style: TextStyle(
                    fontSize: 16,
                    color:
                        available ? MeDisColors.success : MeDisColors.warning,
                    height: 1.5))),
      ]),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: MeDisColors.primarySoft,
              borderRadius: BorderRadius.circular(MeDisRadius.input)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ครั้งละ ${config.quantity} เม็ด',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: MeDisColors.text)),
            const SizedBox(height: 6),
            Text(
                config.symptom.isEmpty
                    ? 'ทานเมื่อมีอาการ'
                    : 'เมื่อ${config.symptom}',
                style: const TextStyle(fontSize: 18, height: 1.5)),
            const Divider(height: 24),
            _PrnInstruction(
                icon: Icons.timer_outlined,
                text: 'เว้นอย่างน้อย ${config.minIntervalHours} ชั่วโมง'),
            const SizedBox(height: 8),
            _PrnInstruction(
                icon: Icons.event_available_outlined,
                text: 'ไม่เกิน ${config.maxDosesPerDay} ครั้งต่อวัน'),
          ]),
        ),
        const SizedBox(height: 8),
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => DrugDetailScreen(drug: drug))),
              icon: const Icon(Icons.info_outline, size: 24),
              label: const Text('ดูข้อมูลยา', style: TextStyle(fontSize: 18)),
            )),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            key: Key('receive-prn-${slot.number}'),
            onPressed: (controller.connected && !dispensing && available)
                ? () async {
                    final confirmed =
                        await _confirmPrnMedicine(context, drug, slot);
                    if (confirmed && context.mounted) {
                      setState(() => dispensing = true);
                      try {
                        await controller.completePrnIntake(drug);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content:
                                  Text('จ่ายยา ${drug.name} เรียบร้อยแล้ว')));
                        }
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(error
                                  .toString()
                                  .replaceFirst('Bad state: ', ''))));
                        }
                      } finally {
                        if (mounted) setState(() => dispensing = false);
                      }
                    }
                  }
                : null,
            icon: dispensing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.healing_outlined),
            label: Text(
              dispensing
                  ? 'กำลังดำเนินการ...'
                  : !controller.connected
                      ? 'เชื่อมต่อเครื่องก่อนรับยา'
                      : !enough
                          ? 'กรุณาเติมยา'
                          : status.canTake
                              ? 'รับยา'
                              : 'ยังไม่ถึงเวลารับยา',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

class _PrnInstruction extends StatelessWidget {
  const _PrnInstruction({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 24, color: MeDisColors.primary),
        const SizedBox(width: 10),
        Expanded(
            child:
                Text(text, style: const TextStyle(fontSize: 16, height: 1.5))),
      ]);
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
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'ยาที่เตรียมไว้ตรงกับรูปและรายการต่อไปนี้หรือไม่?'),
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
                                color: MeDisColors.primarySoft,
                                child: Icon(Icons.image_not_supported_outlined,
                                    color: MeDisColors.subtle))
                            : localImage(drug.labelImagePath!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.broken_image_outlined)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(drug.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            Text(
                                '${config.quantity} เม็ด (ช่องที่ ${slot.number})'),
                            if (config.symptom.isNotEmpty)
                              Text('อาการ: ${config.symptom}',
                                  style: const TextStyle(
                                      color: MeDisColors.muted, fontSize: 12)),
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
                              fontSize: 12, color: MeDisColors.muted),
                        ),
                        if (drug.notes.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '• คำแนะนำ: ${drug.notes.trim()}',
                            style: const TextStyle(
                                fontSize: 12, color: MeDisColors.muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SlideToConfirm(
                      sliderKey: const Key('confirm-intake-slider'),
                      label: 'สไลด์เพื่อยืนยันการทานยา',
                      onConfirmed: () => Navigator.pop(context, true)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยังไม่ทาน'),
            ),
          ],
        ),
      ) ??
      false;
}
