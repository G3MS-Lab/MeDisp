import 'package:flutter/material.dart';

import '../application/app_scope.dart';
import '../domain/models.dart';
import '../widgets/medication_change_confirmation.dart';
import 'drug_form_screen.dart';
import 'medication_refill_screen.dart';

Future<void> openMedicationForm(
    BuildContext context, DispenserSlot slot) async {
  final confirmed = await confirmMedicationChange(context, slot);
  if (!confirmed || !context.mounted) return;
  final controller = AppScope.of(context);
  final currentSlot = controller.slots
      .where((value) => value.number == slot.number)
      .firstOrNull;
  if (!controller.connected ||
      currentSlot == null ||
      currentSlot.drug?.id != slot.drug?.id) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('กรุณาตรวจสอบการเชื่อมต่อและเลือกช่องยาอีกครั้ง')));
    return;
  }
  await Navigator.push(context,
      MaterialPageRoute(builder: (_) => DrugFormScreen(slot: currentSlot)));
}

Future<void> openMedicationRefill(
    BuildContext context, DispenserSlot slot) async {
  final confirmed =
      await confirmMedicationChange(context, slot, refilling: true);
  if (!confirmed || !context.mounted) return;
  final controller = AppScope.of(context);
  final currentSlot = controller.slots
      .where((value) => value.number == slot.number)
      .firstOrNull;
  if (!controller.connected ||
      currentSlot == null ||
      currentSlot.drug?.id != slot.drug?.id ||
      currentSlot.isFull) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('กรุณาตรวจสอบการเชื่อมต่อและจำนวนยาในช่องอีกครั้ง')));
    return;
  }
  await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => MedicationRefillScreen(slot: currentSlot)));
}
