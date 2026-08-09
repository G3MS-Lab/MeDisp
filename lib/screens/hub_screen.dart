import 'package:flutter/material.dart';

import '../application/app_scope.dart';
import 'all_drugs_screen.dart';
import 'allergy_screen.dart';
import 'dispenser_screen.dart';
import 'history_screen.dart';

class HubScreen extends StatelessWidget {
  const HubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final items = [
      _Menu('ประวัติการทานยา', Icons.calendar_month_outlined, const HistoryScreen()),
      _Menu('จัดการยา', Icons.medical_services_outlined, const DispenserScreen()),
      _Menu('ประวัติยาทั้งหมด', Icons.history_rounded, const AllDrugsScreen()),
      _Menu('การแพ้', Icons.health_and_safety_outlined, const AllergyScreen()),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 24),
      children: [
        const Text('MeDis', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFF313131))),
        const SizedBox(height: 5),
        Text(controller.connected ? 'เชื่อมต่อเครื่องจ่ายยาแล้ว' : 'เครื่องจ่ายยายังไม่เชื่อมต่อ', style: TextStyle(color: controller.connected ? Colors.green : Colors.orange)),
        const SizedBox(height: 24),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 22, crossAxisSpacing: 22, childAspectRatio: 1),
          itemBuilder: (_, i) => InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => items[i].screen)),
            child: Ink(
              decoration: BoxDecoration(color: const Color(0xFFE8F0FC), borderRadius: BorderRadius.circular(16)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(items[i].icon, size: 58, color: const Color(0xFF397BD9)),
                const SizedBox(height: 14),
                Text(items[i].title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF313131))),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: controller.busy ? null : controller.toggleConnection,
          icon: Icon(controller.connected ? Icons.bluetooth_disabled : Icons.bluetooth_connected),
          label: Text(controller.busy ? 'กำลังเชื่อมต่อ...' : controller.connected ? 'ยกเลิกการเชื่อมต่อ' : 'เชื่อมต่อเครื่องจ่ายยา'),
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
