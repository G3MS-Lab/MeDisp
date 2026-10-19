import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'medication_verify_image.dart';
import 'slide_to_confirm.dart';

Future<bool> confirmMedicationChange(BuildContext context, DispenserSlot slot,
    {bool refilling = false}) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) =>
            _MedicationChangeConfirmation(slot: slot, refilling: refilling),
      ) ??
      false;
}

class _MedicationChangeConfirmation extends StatelessWidget {
  const _MedicationChangeConfirmation(
      {required this.slot, required this.refilling});
  final DispenserSlot slot;
  final bool refilling;

  @override
  Widget build(BuildContext context) {
    final editing = !slot.isEmpty;
    return AlertDialog(
      scrollable: true,
      title: Text(refilling
          ? 'ยืนยันการเพิ่มจำนวนยา'
          : editing
              ? 'ยืนยันการแก้ไขยา'
              : 'ยืนยันการเพิ่มยา'),
      content: SizedBox(
        width: 340,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_open_outlined,
              size: 40, color: Color(0xFF397BD9)),
          const SizedBox(height: 12),
          if (slot.drug != null) ...[
            MedicationVerifyImage(drug: slot.drug!),
            const SizedBox(height: 12),
          ],
          Text(
              editing
                  ? '${slot.drug!.name} · ช่อง ${slot.number}'
                  : 'เพิ่มยาในช่อง ${slot.number}',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          SlideToConfirm(
            sliderKey: const Key('medication-confirmation-slider'),
            label: 'สไลด์เพื่อเปิดฟอร์ม',
            onConfirmed: () => Navigator.pop(context, true),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก')),
      ],
    );
  }
}
