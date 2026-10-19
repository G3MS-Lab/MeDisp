import 'package:flutter/material.dart';

import '../theme/medis_theme.dart';

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
          Text('ช่องยา ${slot.number}',
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: MeDisColors.primary)),
          const SizedBox(height: 16),
          if (slot.drug != null) ...[
            MedicationVerifyImage(drug: slot.drug!),
            const SizedBox(height: 12),
          ],
          if (!editing)
            const Text('กรอกข้อมูลยาและตรวจสอบรูปฉลากก่อนบันทึก',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
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
