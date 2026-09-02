import 'package:flutter/material.dart';

import '../application/app_scope.dart';
import '../domain/models.dart';
import '../widgets/medis_app_bar.dart';
import 'drug_form_screen.dart';
import 'drug_detail_screen.dart';

class DispenserScreen extends StatelessWidget {
  const DispenserScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Scaffold(
      appBar: const MeDisAppBar('จัดการยา'),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Card(
          child: ListTile(
            leading: Icon(Icons.bluetooth,
                color: controller.connected ? Colors.green : Colors.grey),
            title: Text(controller.connected
                ? 'MeDispenser พร้อมใช้งาน'
                : 'ยังไม่ได้เชื่อมต่อ'),
            subtitle: Text(controller.connected
                ? 'แตะช่องว่างเพื่อเพิ่มยา'
                : 'เชื่อมต่อเครื่องก่อนเพิ่มยา'),
            trailing: Switch(
                value: controller.connected,
                onChanged: (_) => controller.toggleConnection()),
          ),
        ),
        const SizedBox(height: 22),
        const Text('ช่องใส่ยา',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: controller.slots.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 15,
              crossAxisSpacing: 15,
              // Leave enough vertical room for the icon and all three labels
              // on narrow phones and when the system text size is increased.
              childAspectRatio: .9),
          itemBuilder: (_, i) => _SlotCard(
              slot: controller.slots[i], enabled: controller.connected),
        ),
      ]),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({required this.slot, required this.enabled});
  final DispenserSlot slot;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: slot.isEmpty
              ? (!enabled
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => DrugFormScreen(slot: slot))))
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => DrugDetailScreen(drug: slot.drug!))),
          onLongPress: slot.isEmpty
              ? null
              : () async {
                  final remove = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(
                          'นำ ${slot.drug!.name} ออกจากช่อง ${slot.number}?'),
                      content: const Text(
                          'ตารางยาจะอัปเดตทันที แต่ประวัติการทานยาจะไม่ถูกลบ'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('ยกเลิก')),
                        FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('นำออก')),
                      ],
                    ),
                  );
                  if (remove == true && context.mounted) {
                    await AppScope.of(context).clearSlot(slot.number);
                  }
                },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CircleAvatar(
                  radius: 27,
                  backgroundColor: slot.isEmpty
                      ? const Color(0xFFE8F0FC)
                      : const Color(0xFFDFF6E5),
                  child: Icon(slot.isEmpty ? Icons.add : Icons.medication,
                      color:
                          slot.isEmpty ? const Color(0xFF6AA6FF) : Colors.green,
                      size: 30)),
              const SizedBox(height: 10),
              Text('ช่อง ${slot.number}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(slot.drug?.name ?? 'ว่าง',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                  slot.isEmpty
                      ? 'แตะเพื่อเพิ่มยา'
                      : 'คงเหลือ ${slot.remaining} เม็ด',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ),
        ),
      );
}
