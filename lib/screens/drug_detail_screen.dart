import 'package:flutter/material.dart';

import '../application/app_scope.dart';
import '../domain/models.dart';
import '../widgets/medis_app_bar.dart';
import '../widgets/local_image.dart';

class DrugDetailScreen extends StatelessWidget {
  const DrugDetailScreen({required this.drug, super.key});

  final Drug drug;

  @override
  Widget build(BuildContext context) {
    final slots = AppScope.of(context)
        .slots
        .where((slot) => slot.drug?.id == drug.id)
        .toList();
    final remaining =
        slots.fold<int>(0, (total, slot) => total + slot.remaining);
    final capacity = slots.fold<int>(0, (total, slot) => total + slot.capacity);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: const MeDisAppBar('ข้อมูลยา'),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        _DrugHeader(drug: drug),
        const SizedBox(height: 16),
        _InventorySection(
            slots: slots, remaining: remaining, capacity: capacity),
        const SizedBox(height: 16),
        _SectionCard(
          icon: Icons.schedule_outlined,
          title: 'ตารางการรับประทาน',
          child: Column(
            children: drug.instructions
                .map((instruction) => _DoseRow(instruction: instruction))
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          icon: Icons.health_and_safety_outlined,
          title: 'รายละเอียดและข้อควรระวัง',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
                color: const Color(0xFFFFF8E8),
                borderRadius: BorderRadius.circular(14)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline, color: Color(0xFFE49B22)),
              const SizedBox(width: 11),
              Expanded(
                  child: Text(
                      drug.notes.trim().isEmpty
                          ? 'ไม่มีข้อมูลหรือข้อควรระวังเพิ่มเติม'
                          : drug.notes,
                      style: const TextStyle(height: 1.45)))
            ]),
          ),
        ),
      ]),
    );
  }
}

class _DrugHeader extends StatelessWidget {
  const _DrugHeader({required this.drug});
  final Drug drug;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 190,
            width: double.infinity,
            child: drug.labelImagePath == null
                ? const _LabelPlaceholder()
                : localImage(drug.labelImagePath!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const _LabelPlaceholder()),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: const Color(0xFFE8F0FC),
                      borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.medication_rounded,
                      color: Color(0xFF397BD9), size: 28)),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(drug.name,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800)),
                    Text('${drug.instructions.length} ช่วงเวลาต่อวัน',
                        style: const TextStyle(color: Color(0xFF68778B)))
                  ]))
            ]),
          )
        ]),
      );
}

class _InventorySection extends StatelessWidget {
  const _InventorySection(
      {required this.slots, required this.remaining, required this.capacity});
  final List<DispenserSlot> slots;
  final int remaining;
  final int capacity;

  @override
  Widget build(BuildContext context) => _SectionCard(
        icon: Icons.inventory_2_outlined,
        title: 'สถานะในเครื่องจ่ายยา',
        child: slots.isEmpty
            ? Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                    color: const Color(0xFFF1F4F8),
                    borderRadius: BorderRadius.circular(14)),
                child: const Row(children: [
                  Icon(Icons.inventory_2_outlined, color: Colors.grey),
                  SizedBox(width: 10),
                  Expanded(child: Text('ยานี้ไม่ได้อยู่ในเครื่องจ่ายยาแล้ว'))
                ]))
            : Column(children: [
                Row(children: [
                  Expanded(
                      child: _StatBox(
                          icon: Icons.grid_view_rounded,
                          label: 'ช่อง',
                          value: slots.map((slot) => slot.number).join(', '))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _StatBox(
                          icon: Icons.medication_outlined,
                          label: 'คงเหลือ',
                          value: '$remaining เม็ด')),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _StatBox(
                          icon: Icons.inventory_outlined,
                          label: 'ความจุ',
                          value: '$capacity เม็ด')),
                ]),
                const SizedBox(height: 15),
                Row(children: [
                  const Text('ปริมาณคงเหลือ',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(capacity == 0
                      ? '0%'
                      : '${(remaining * 100 / capacity).round()}%')
                ]),
                const SizedBox(height: 7),
                ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                        minHeight: 9,
                        value: capacity == 0 ? 0 : remaining / capacity,
                        backgroundColor: const Color(0xFFE5EAF0),
                        color: remaining <= capacity * .2
                            ? const Color(0xFFE04B4B)
                            : const Color(0xFF55B97A))),
              ]),
      );
}

class _StatBox extends StatelessWidget {
  const _StatBox(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
            color: const Color(0xFFF4F7FC),
            borderRadius: BorderRadius.circular(13)),
        child: Column(children: [
          Icon(icon, color: const Color(0xFF397BD9), size: 22),
          const SizedBox(height: 5),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8291A5))),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800))
        ]),
      );
}

class _DoseRow extends StatelessWidget {
  const _DoseRow({required this.instruction});
  final DoseInstruction instruction;

  IconData get mealIcon => switch (instruction.meal) {
        MealType.breakfast => Icons.wb_sunny_outlined,
        MealType.lunch => Icons.light_mode_outlined,
        MealType.dinner => Icons.wb_twilight_outlined,
        MealType.bedtime => Icons.bedtime_outlined,
      };

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: instruction.meal.color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          CircleAvatar(
              backgroundColor: instruction.meal.color.withValues(alpha: .22),
              child: Icon(mealIcon, color: instruction.meal.color)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('มื้อ${instruction.meal.label}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text('${instruction.quantity} เม็ดต่อครั้ง',
                    style: const TextStyle(color: Color(0xFF68778B)))
              ])),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                    instruction.beforeFood
                        ? Icons.restaurant_menu
                        : Icons.restaurant,
                    size: 15,
                    color: const Color(0xFF397BD9)),
                const SizedBox(width: 4),
                Text(instruction.beforeFood ? 'ก่อนอาหาร' : 'หลังอาหาร',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700))
              ]))
        ]),
      );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard(
      {required this.icon, required this.title, required this.child});
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: const Color(0xFF397BD9)),
              const SizedBox(width: 9),
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800))
            ]),
            const Divider(height: 24),
            child,
          ]),
        ),
      );
}

class _LabelPlaceholder extends StatelessWidget {
  const _LabelPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFEAF2FD),
        alignment: Alignment.center,
        child: const Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.image_outlined, size: 48, color: Color(0xFF7FA9DC)),
          SizedBox(height: 8),
          Text('ยังไม่มีรูปฉลากยา', style: TextStyle(color: Color(0xFF68778B)))
        ]),
      );
}
