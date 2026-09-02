import 'package:flutter/material.dart';

import '../application/app_scope.dart';
import '../domain/models.dart';
import 'all_drugs_screen.dart';
import 'allergy_screen.dart';
import 'dispenser_screen.dart';
import 'drug_detail_screen.dart';
import 'history_screen.dart';

class HubScreen extends StatelessWidget {
  const HubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final occupiedSlots =
        controller.slots.where((slot) => !slot.isEmpty).toList();
    final drugSlots = <String, DispenserSlot>{
      for (final slot in occupiedSlots) slot.drug!.id: slot
    }.values.toList();
    final remainingPills =
        occupiedSlots.fold<int>(0, (total, slot) => total + slot.remaining);
    final items = [
      _Menu('ประวัติการทานยา', Icons.calendar_month_outlined,
          const HistoryScreen()),
      _Menu(
          'จัดการยา', Icons.medical_services_outlined, const DispenserScreen()),
      _Menu('ประวัติยาทั้งหมด', Icons.history_rounded, const AllDrugsScreen()),
      _Menu('อาการไม่พึงประสงค์', Icons.health_and_safety_outlined,
          const AllergyScreen()),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 24),
      children: [
        const Text('MeDis',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Color(0xFF313131))),
        const SizedBox(height: 5),
        Text(
            controller.connected
                ? 'เชื่อมต่อเครื่องจ่ายยาแล้ว'
                : 'เครื่องจ่ายยายังไม่เชื่อมต่อ',
            style: TextStyle(
                color: controller.connected ? Colors.green : Colors.orange)),
        if (controller.errorMessage != null) ...[
          const SizedBox(height: 6),
          Text(controller.errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
        const SizedBox(height: 24),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 22,
              crossAxisSpacing: 22,
              childAspectRatio: 1),
          itemBuilder: (_, i) => InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => items[i].screen)),
            child: Ink(
              decoration: BoxDecoration(
                  color: const Color(0xFFE8F0FC),
                  borderRadius: BorderRadius.circular(16)),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(items[i].icon,
                        size: 58, color: const Color(0xFF397BD9)),
                    const SizedBox(height: 14),
                    Text(items[i].title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF313131))),
                  ]),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FC),
                    borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.medication_outlined,
                    color: Color(0xFF397BD9))),
            title: const Text('ยาในเครื่องตอนนี้',
                style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
                '${drugSlots.length} ประเภท · เหลือรวม $remainingPills เม็ด'),
            children: drugSlots.isEmpty
                ? const [
                    Padding(
                        padding: EdgeInsets.fromLTRB(20, 8, 20, 22),
                        child: Text('ยังไม่มียาในเครื่องจ่ายยา',
                            style: TextStyle(color: Colors.grey)))
                  ]
                : drugSlots.map((slot) {
                    final drug = slot.drug!;
                    return ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => DrugDetailScreen(drug: drug))),
                      leading: CircleAvatar(
                          backgroundColor: const Color(0xFFDFF6E5),
                          child: Text('${slot.number}',
                              style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w800))),
                      title: Text(drug.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                          'ช่อง ${slot.number} · เหลือ ${slot.remaining}/${slot.capacity} เม็ด\n${drug.instructions.map((dose) => '${dose.meal.label} ${dose.beforeFood ? 'ก่อนอาหาร' : 'หลังอาหาร'}').join(' · ')}'),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                    );
                  }).toList(),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: controller.busy ? null : controller.toggleConnection,
          icon: Icon(controller.connected
              ? Icons.bluetooth_disabled
              : Icons.bluetooth_connected),
          label: Text(controller.busy
              ? 'กำลังเชื่อมต่อ...'
              : controller.connected
                  ? 'ยกเลิกการเชื่อมต่อ'
                  : 'เชื่อมต่อเครื่องจ่ายยา'),
        ),
      ],
    );
  }
}

class _Menu {
  const _Menu(this.title, this.icon, this.screen);
  final String title;
  final IconData icon;
  final Widget screen;
}
