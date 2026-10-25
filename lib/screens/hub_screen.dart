import 'package:flutter/material.dart';

import '../application/app_scope.dart';
import '../theme/medis_theme.dart';
import '../widgets/ble_device_picker_sheet.dart';
import '../widgets/medis_ui.dart';
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
    final slots = controller.slots.where((slot) => !slot.isEmpty).toList();
    final items = [
      _Menu('จัดการยา', 'ดูช่องยา เติมยา และแก้ไขข้อมูล',
          Icons.medication_outlined, const DispenserScreen()),
      _Menu('ประวัติการทานยา', 'ปฏิทินและความสม่ำเสมอในการทานยา',
          Icons.calendar_month_outlined, const HistoryScreen()),
      _Menu('ประวัติยาทั้งหมด', 'รายการยาที่เคยบันทึกไว้',
          Icons.inventory_2_outlined, const AllDrugsScreen()),
      _Menu('อาการไม่พึงประสงค์', 'บันทึกและติดตามอาการหลังทานยา',
          Icons.health_and_safety_outlined, const AllergyScreen()),
    ];
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: MeDisSpace.pagePadding,
      children: [
        const MeDisPageHeader(
            title: 'MeDis', subtitle: 'ดูแลเรื่องยาได้ในที่เดียว'),
        LayoutBuilder(builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(20) > 26;
          final columns = constraints.maxWidth < 280 || largeText ? 1 : 2;
          final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
          return Wrap(spacing: 16, runSpacing: 16, children: [
            for (final item in items)
              SizedBox(
                  width: width,
                  child: Semantics(
                    button: true,
                    label: '${item.title} ${item.subtitle}',
                    excludeSemantics: true,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => item.screen)),
                    child: Material(
                      color: MeDisColors.surface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(MeDisRadius.card),
                          side: const BorderSide(color: MeDisColors.border)),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => item.screen)),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 176),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                      width: 72,
                                      height: 72,
                                      decoration: BoxDecoration(
                                          color: MeDisColors.primarySoft,
                                          borderRadius:
                                              BorderRadius.circular(20)),
                                      child: Icon(item.icon,
                                          color: MeDisColors.primary,
                                          size: 44)),
                                  const SizedBox(height: 16),
                                  Text(item.title,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                          height: 1.5)),
                                ]),
                          ),
                        ),
                      ),
                    ),
                  )),
          ]);
        }),
        const SizedBox(height: 24),
        Card(
            child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: MeDisColors.primarySoft,
                      borderRadius: BorderRadius.circular(12)),
                  child:
                      const Icon(Icons.bluetooth, color: MeDisColors.primary)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                        controller.connected
                            ? 'เครื่องจ่ายยาพร้อมใช้งาน'
                            : 'ยังไม่ได้เชื่อมต่อเครื่อง',
                        style: Theme.of(context).textTheme.titleSmall),
                    Text(
                        controller.connected
                            ? (controller.bleService.connectedDeviceName != null
                                ? 'เชื่อมต่อกับ ${controller.bleService.connectedDeviceName}'
                                : 'เชื่อมต่อ MeDispenser แล้ว')
                            : 'เชื่อมต่อเพื่อเติมยาและรับยา',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: MeDisColors.muted)),
                  ])),
              if (controller.busy)
                const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
            const SizedBox(height: 16),
            SizedBox(
                width: double.infinity,
                child: controller.connected
                    ? OutlinedButton.icon(
                        onPressed: controller.busy
                            ? null
                            : controller.disconnectDispenser,
                        icon: const Icon(Icons.bluetooth_connected, size: 20),
                        label: const Text('ตัดการเชื่อมต่อ'))
                    : FilledButton.icon(
                        onPressed: controller.busy
                            ? null
                            : () => showBleDevicePickerSheet(
                                  context: context,
                                  controller: controller,
                                ),
                        icon: const Icon(Icons.bluetooth, size: 20),
                        label: Text(controller.busy
                            ? 'กำลังเชื่อมต่อ...'
                            : 'เชื่อมต่อเครื่องจ่ายยา'))),
          ]),
        )),
        if (controller.errorMessage != null) ...[
          const SizedBox(height: 12),
          MeDisNotice(
              message: controller.errorMessage!,
              color: MeDisColors.error,
              icon: Icons.error_outline),
        ],
        const SizedBox(height: 28),
        Row(children: [
          Expanded(
              child: Text('ยาในเครื่อง',
                  style: Theme.of(context).textTheme.titleMedium)),
          Text('${slots.length}/${controller.slots.length} ช่อง',
              style: const TextStyle(color: MeDisColors.muted)),
        ]),
        const SizedBox(height: 12),
        if (slots.isEmpty)
          const MeDisEmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'ยังไม่มียาในเครื่อง',
              message: 'เข้า “จัดการยา” แล้วแตะช่องว่างเพื่อเพิ่มยา')
        else
          Card(
              child: Column(children: [
            for (var i = 0; i < slots.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 64),
              ListTile(
                leading: CircleAvatar(
                    backgroundColor: MeDisColors.primarySoft,
                    child: Text('${slots[i].number}',
                        style: const TextStyle(color: MeDisColors.primary))),
                title: Text(slots[i].drug!.name),
                subtitle: Text(
                    'คงเหลือ ${slots[i].remaining} จาก ${slots[i].capacity} เม็ด'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            DrugDetailScreen(drug: slots[i].drug!))),
              ),
            ],
          ])),
      ],
    );
  }
}

class _Menu {
  const _Menu(this.title, this.subtitle, this.icon, this.screen);
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget screen;
}
