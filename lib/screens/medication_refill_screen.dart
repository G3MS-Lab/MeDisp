import 'package:flutter/material.dart';

import '../theme/medis_theme.dart';

import '../application/app_scope.dart';
import '../domain/models.dart';
import '../widgets/medication_verify_image.dart';
import '../widgets/medis_app_bar.dart';
import '../widgets/slide_to_confirm.dart';

class MedicationRefillScreen extends StatefulWidget {
  const MedicationRefillScreen({required this.slot, super.key});
  final DispenserSlot slot;

  @override
  State<MedicationRefillScreen> createState() => _MedicationRefillScreenState();
}

class _MedicationRefillScreenState extends State<MedicationRefillScreen> {
  int quantity = 1;
  bool saving = false;

  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await AppScope.of(context)
          .refillDrugInSlot(widget.slot.number, widget.slot.drug!.id, quantity);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('เพิ่มยา $quantity เม็ดแล้ว')));
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', ''))));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    final free = slot.capacity - slot.remaining;
    return Scaffold(
      backgroundColor: MeDisColors.background,
      appBar: MeDisAppBar('เพิ่มยา · ช่อง ${slot.number}'),
      body: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: MeDisSpace.pagePadding,
          children: [
            MedicationVerifyImage(drug: slot.drug!),
            const SizedBox(height: 16),
            Card(
                child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('จำนวนเม็ดที่เพิ่ม',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                        'คงเหลือ ${slot.remaining} เม็ด · เพิ่มได้อีก $free เม็ด'),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      IconButton(
                        key: const Key('decrease-refill'),
                        onPressed: quantity > 1
                            ? () => setState(() => quantity--)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      SizedBox(
                          width: 80,
                          child: Text('$quantity เม็ด',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700))),
                      IconButton(
                        key: const Key('increase-refill'),
                        onPressed: quantity < free
                            ? () => setState(() => quantity++)
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ]),
                    Text(
                        'หลังเพิ่มจะมี ${slot.remaining + quantity} เม็ดในช่อง',
                        textAlign: TextAlign.center),
                  ]),
            )),
            const SizedBox(height: 16),
            SlideToConfirm(
              label: saving ? 'กำลังบันทึก...' : 'สไลด์จนสุดเพื่อบันทึกจำนวนยา',
              onConfirmed: save,
              enabled: !saving,
            ),
          ]),
    );
  }
}
