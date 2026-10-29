import 'package:flutter/material.dart';

import '../theme/medis_theme.dart';

import '../application/app_scope.dart';
import '../domain/models.dart';
import '../widgets/ble_device_picker_sheet.dart';
import '../widgets/medis_app_bar.dart';
import '../widgets/medis_ui.dart';
import 'drug_detail_screen.dart';
import 'medication_form_navigation.dart';

class DispenserScreen extends StatelessWidget {
  const DispenserScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Scaffold(
      appBar: const MeDisAppBar('จัดการยา'),
      body: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: MeDisSpace.pagePadding,
          children: [
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.bluetooth,
                  color: controller.connected
                      ? MeDisColors.success
                      : MeDisColors.muted,
                ),
                title: Text(controller.connected
                    ? 'MeDispenser พร้อมใช้งาน'
                    : 'ยังไม่ได้เชื่อมต่อ'),
                subtitle: Text(controller.connected
                    ? (controller.bleService.connectedDeviceName != null
                        ? 'เชื่อมต่อกับ ${controller.bleService.connectedDeviceName}'
                        : 'สไลด์ยืนยันก่อนเพิ่มหรือแก้ไขยา')
                    : 'เชื่อมต่อเครื่องก่อนเพิ่มหรือแก้ไขยา'),
                trailing: Switch(
                    value: controller.connected,
                    activeThumbColor: Colors.white,
                    activeTrackColor: MeDisColors.success,
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: const Color(0xFFCBD5E1),
                    trackOutlineColor:
                        WidgetStateProperty.resolveWith<Color>((states) {
                      if (states.contains(WidgetState.selected)) {
                        return Colors.transparent;
                      }
                      return const Color(0xFF94A3B8);
                    }),
                    trackOutlineWidth:
                        WidgetStateProperty.resolveWith<double>((states) {
                      if (states.contains(WidgetState.selected)) {
                        return 0.0;
                      }
                      return 1.5;
                    }),
                    thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
                      if (states.contains(WidgetState.selected)) {
                        return const Icon(Icons.check,
                            color: MeDisColors.success, size: 16);
                      }
                      return const Icon(Icons.close_rounded,
                          color: Color(0xFF64748B), size: 16);
                    }),
                    onChanged: controller.busy
                        ? null
                        : (val) {
                            if (val) {
                              showBleDevicePickerSheet(
                                context: context,
                                controller: controller,
                              );
                            } else {
                              controller.disconnectDispenser();
                            }
                          }),
              ),
            ),
            const SizedBox(height: 22),
            const Text('ช่องใส่ยา',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('แตะช่องว่างเพื่อเพิ่มยา หรือแตะยาเพื่อดูรายละเอียด',
                style: TextStyle(color: MeDisColors.muted)),
            const SizedBox(height: 14),
            LayoutBuilder(builder: (context, constraints) {
              final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;
              final columns = constraints.maxWidth < 300 || largeText ? 1 : 2;
              final cardWidth =
                  (constraints.maxWidth - 15 * (columns - 1)) / columns;
              return Wrap(
                spacing: 15,
                runSpacing: 15,
                children: [
                  for (final slot in controller.slots)
                    SizedBox(
                      width: cardWidth,
                      child:
                          _SlotCard(slot: slot, enabled: controller.connected),
                    ),
                ],
              );
            }),
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
        key: ValueKey('medication-slot-${slot.number}'),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: slot.isEmpty
              ? (enabled ? () => openMedicationForm(context, slot) : null)
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => DrugDetailScreen(drug: slot.drug!))),
          onLongPress: slot.isEmpty
              ? null
              : () async {
                  final remove = await confirmMeDisAction(context,
                      title: 'นำ ${slot.drug!.name} ออกจากช่อง ${slot.number}?',
                      message:
                          'ตารางยาจะอัปเดตทันที แต่ประวัติการทานยาจะไม่ถูกลบ',
                      actionLabel: 'นำยาออก',
                      destructive: true);
                  if (remove == true && context.mounted) {
                    try {
                      await AppScope.of(context).clearSlot(slot.number);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('นำยาออกจากช่องแล้ว')));
                      }
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(error
                                .toString()
                                .replaceFirst('Bad state: ', ''))));
                      }
                    }
                  }
                },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                  radius: 30,
                  backgroundColor: MeDisColors.primarySoft,
                  child: Icon(slot.isEmpty ? Icons.add : Icons.medication,
                      color: MeDisColors.primary, size: 30)),
              const SizedBox(height: 10),
              Text('ช่อง ${slot.number}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              Text(slot.drug?.name ?? 'ว่าง',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18)),
              Text(
                  slot.isEmpty
                      ? 'แตะเพื่อเพิ่มยา'
                      : 'คงเหลือ ${slot.remaining} เม็ด',
                  style:
                      const TextStyle(fontSize: 16, color: MeDisColors.muted)),
            ]),
          ),
        ),
      );
}
