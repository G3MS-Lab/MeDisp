import 'package:flutter/material.dart';

import '../theme/medis_theme.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../application/app_scope.dart';
import '../data/local_image_store.dart';
import '../domain/models.dart';
import '../widgets/medication_verify_image.dart';
import '../widgets/medis_app_bar.dart';
import '../widgets/medis_ui.dart';
import '../widgets/slide_to_confirm.dart';

class DrugFormScreen extends StatefulWidget {
  const DrugFormScreen({required this.slot, super.key});
  final DispenserSlot slot;

  @override
  State<DrugFormScreen> createState() => _DrugFormScreenState();
}

class _DrugFormScreenState extends State<DrugFormScreen> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final notes = TextEditingController();
  final symptom = TextEditingController(text: 'แก้ปวด / ลดไข้');
  bool isPrn = false;
  int prnQuantity = 1;
  int minIntervalHours = 4;
  int maxDosesPerDay = 4;
  int quantity = 10;
  final Map<MealType, int> doses = {MealType.breakfast: 1};
  final Map<MealType, bool> beforeFood = {MealType.breakfast: true};
  bool saving = false;
  String? dosesError;
  String? labelImagePath;

  bool get isEditing => widget.slot.drug != null;

  @override
  void initState() {
    super.initState();
    final drug = widget.slot.drug;
    if (drug == null) {
      quantity = widget.slot.capacity < 10 ? widget.slot.capacity : 10;
      return;
    }
    name.text = drug.name;
    notes.text = drug.notes;
    labelImagePath = drug.labelImagePath;
    quantity = widget.slot.remaining;
    isPrn = drug.isPrn;
    final config = drug.prnConfig;
    if (config != null) {
      symptom.text = config.symptom;
      prnQuantity = config.quantity;
      minIntervalHours = config.minIntervalHours;
      maxDosesPerDay = config.maxDosesPerDay;
    }
    doses.clear();
    beforeFood.clear();
    for (final instruction in drug.instructions) {
      doses[instruction.meal] = instruction.quantity;
      beforeFood[instruction.meal] = instruction.beforeFood;
    }
  }

  Future<void> pickLabelImage(ImageSource source) async {
    try {
      final image = await ImagePicker().pickImage(
          source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
      if (image != null && mounted) {
        final storedPath = await const LocalImageStore()
            .persist(image, category: 'drug_labels');
        if (mounted) setState(() => labelImagePath = storedPath);
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      final denied =
          error.code.contains('denied') || error.code.contains('permission');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(denied
              ? 'ไม่ได้รับอนุญาตให้เข้าถึงกล้องหรือรูปภาพ กรุณาเปิดสิทธิ์ใน Settings'
              : 'ไม่สามารถเปิดกล้องหรือรูปภาพได้: ${error.message ?? error.code}')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error is StateError
                ? error.message.toString()
                : 'ไม่สามารถแนบรูปภาพได้ กรุณาลองใหม่')));
      }
    }
  }

  Future<void> chooseLabelImage() async {
    final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('ถ่ายรูป'),
                  onTap: () => Navigator.pop(context, ImageSource.camera)),
              ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('เลือกรูป'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery))
            ])));
    if (source != null && mounted) await pickLabelImage(source);
  }

  @override
  void dispose() {
    name.dispose();
    notes.dispose();
    symptom.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    if (!formKey.currentState!.validate()) return;
    if (!isPrn && doses.isEmpty) {
      setState(() => dosesError = 'เลือกอย่างน้อย 1 มื้อที่ต้องทานยา');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('กรุณาเลือกอย่างน้อย 1 มื้อสำหรับยาประจำ')));
      return;
    }
    setState(() => saving = true);
    final original = widget.slot.drug;
    final drug = Drug(
        id: original?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.text.trim(),
        notes: notes.text.trim(),
        labelImagePath: labelImagePath,
        addedAt: original == null ? DateTime.now() : original.addedAt,
        stoppedAt: original?.stoppedAt,
        isPrn: isPrn,
        prnConfig: isPrn
            ? PrnConfig(
                symptom: symptom.text.trim().isEmpty
                    ? 'เมื่อมีอาการ'
                    : symptom.text.trim(),
                quantity: prnQuantity,
                minIntervalHours: minIntervalHours,
                maxDosesPerDay: maxDosesPerDay,
              )
            : null,
        instructions: isPrn
            ? const []
            : doses.entries
                .map((entry) => DoseInstruction(
                    meal: entry.key,
                    quantity: entry.value,
                    beforeFood: beforeFood[entry.key] ?? true))
                .toList());
    try {
      final controller = AppScope.of(context);
      if (isEditing) {
        await controller.updateDrugInSlot(drug, widget.slot.number, quantity);
      } else {
        await controller.addDrugToSlot(drug, widget.slot.number, quantity);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                isEditing ? 'บันทึกการแก้ไขยาแล้ว' : 'เพิ่มยาในเครื่องแล้ว')));
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', ''))));
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: MeDisColors.background,
        appBar: MeDisAppBar(
            '${isEditing ? 'แก้ไขยา' : 'เพิ่มยา'} · ช่อง ${widget.slot.number}'),
        body: Form(
          key: formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: MeDisSpace.pagePadding,
              children: [
                _DrugFormSection(
                    title: 'ข้อมูลยา',
                    icon: Icons.medication_outlined,
                    children: [
                      TextFormField(
                          controller: name,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                              labelText: 'ชื่อยา',
                              prefixIcon: Icon(Icons.medication_outlined)),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'กรุณาระบุชื่อยา'
                                  : null),
                      const SizedBox(height: 14),
                      TextFormField(
                          controller: notes,
                          maxLines: 3,
                          decoration: const InputDecoration(
                              labelText: 'รายละเอียด / ข้อควรระวัง',
                              prefixIcon: Icon(Icons.description_outlined))),
                    ]),
                _DrugFormSection(
                    title: 'ประเภทยา',
                    icon: Icons.category_outlined,
                    children: [
                      MeDisSelectionTile(
                          title: 'ทานประจำตามมื้อ',
                          icon: Icons.schedule_outlined,
                          selected: !isPrn,
                          onTap: () => setState(() => isPrn = false)),
                      const SizedBox(height: 12),
                      MeDisSelectionTile(
                          title: 'ทานเมื่อมีอาการ (PRN)',
                          icon: Icons.healing_outlined,
                          selected: isPrn,
                          onTap: () => setState(() => isPrn = true)),
                    ]),
                _DrugFormSection(
                    title: 'จำนวนยาในช่อง',
                    icon: Icons.inventory_2_outlined,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                            color: MeDisColors.background,
                            borderRadius: BorderRadius.circular(14)),
                        child: Row(children: [
                          Expanded(
                              child: Text(
                                  isEditing
                                      ? 'จำนวนยาคงเหลือ'
                                      : 'จำนวนยาที่ใส่',
                                  style: const TextStyle(
                                      color: MeDisColors.muted))),
                          IconButton(
                              onPressed: quantity > (isEditing ? 0 : 1)
                                  ? () => setState(() => quantity--)
                                  : null,
                              icon: const Icon(Icons.remove_circle_outline)),
                          Text('$quantity',
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700)),
                          IconButton(
                              onPressed: quantity < widget.slot.capacity
                                  ? () => setState(() => quantity++)
                                  : null,
                              icon: const Icon(Icons.add_circle_outline)),
                        ]),
                      ),
                    ]),
                if (isPrn)
                  _DrugFormSection(
                      title: 'วิธีทานยาตามอาการ (PRN)',
                      icon: Icons.healing_outlined,
                      children: [
                        TextFormField(
                          controller: symptom,
                          decoration: const InputDecoration(
                            labelText: 'อาการที่ทาน (ข้อบ่งใช้)',
                            hintText: 'เช่น ปวดศีรษะ, มีไข้, ปวดท้อง, คลื่นไส้',
                            prefixIcon: Icon(Icons.healing),
                          ),
                          validator: (value) =>
                              isPrn && (value == null || value.trim().isEmpty)
                                  ? 'กรุณาระบุอาการที่ทาน'
                                  : null,
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                              color: MeDisColors.background,
                              borderRadius: BorderRadius.circular(14)),
                          child: Row(children: [
                            const Expanded(
                                child: Text('จำนวนที่ทานต่อครั้ง',
                                    style: TextStyle(
                                        color: MeDisColors.text,
                                        fontWeight: FontWeight.w600))),
                            IconButton(
                                onPressed: prnQuantity > 1
                                    ? () => setState(() => prnQuantity--)
                                    : null,
                                icon: const Icon(Icons.remove_circle_outline)),
                            Text('$prnQuantity เม็ด',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                            IconButton(
                                onPressed: prnQuantity < 4
                                    ? () => setState(() => prnQuantity++)
                                    : null,
                                icon: const Icon(Icons.add_circle_outline)),
                          ]),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<int>(
                          isExpanded: true,
                          initialValue: minIntervalHours,
                          decoration: const InputDecoration(
                            labelText: 'ระยะห่างขั้นต่ำในการทานซ้ำ',
                            prefixIcon: Icon(Icons.timelapse_outlined),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 4, child: Text('ทุก 4 ชั่วโมง')),
                            DropdownMenuItem(
                                value: 6, child: Text('ทุก 6 ชั่วโมง')),
                            DropdownMenuItem(
                                value: 8, child: Text('ทุก 8 ชั่วโมง')),
                            DropdownMenuItem(
                                value: 12, child: Text('ทุก 12 ชั่วโมง')),
                          ],
                          onChanged: (val) =>
                              setState(() => minIntervalHours = val ?? 4),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<int>(
                          isExpanded: true,
                          initialValue: maxDosesPerDay,
                          decoration: const InputDecoration(
                            labelText: 'จำนวนครั้งสูงสุดต่อวัน (24 ชม.)',
                            prefixIcon: Icon(Icons.warning_amber_rounded),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 2, child: Text('ไม่เกิน 2 ครั้งต่อวัน')),
                            DropdownMenuItem(
                                value: 4, child: Text('ไม่เกิน 4 ครั้งต่อวัน')),
                            DropdownMenuItem(
                                value: 6, child: Text('ไม่เกิน 6 ครั้งต่อวัน')),
                            DropdownMenuItem(
                                value: 8, child: Text('ไม่เกิน 8 ครั้งต่อวัน')),
                          ],
                          onChanged: (val) =>
                              setState(() => maxDosesPerDay = val ?? 4),
                        ),
                      ])
                else
                  _DrugFormSection(
                      title: 'มื้อและจำนวนยาต่อครั้ง',
                      icon: Icons.schedule_outlined,
                      children: [
                        if (dosesError != null)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(dosesError!,
                                  style: const TextStyle(
                                      color: MeDisColors.error))),
                        ...MealType.values.map((meal) => Column(children: [
                              CheckboxListTile(
                                value: doses.containsKey(meal),
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Text('มื้อ${meal.label}',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600)),
                                onChanged: (selected) => setState(() {
                                  if (selected!) {
                                    dosesError = null;
                                    doses[meal] = 1;
                                    beforeFood[meal] = true;
                                  } else {
                                    doses.remove(meal);
                                    beforeFood.remove(meal);
                                  }
                                }),
                              ),
                              if (doses.containsKey(meal))
                                Row(children: [
                                  const Expanded(
                                      child: Text('ครั้งละ',
                                          style: TextStyle(fontSize: 16))),
                                  IconButton(
                                      onPressed: doses[meal]! > 1
                                          ? () => setState(() =>
                                              doses[meal] = doses[meal]! - 1)
                                          : null,
                                      icon: const Icon(
                                          Icons.remove_circle_outline)),
                                  Text('${doses[meal]} เม็ด',
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700)),
                                  IconButton(
                                      onPressed: doses[meal]! < 4
                                          ? () => setState(() =>
                                              doses[meal] = doses[meal]! + 1)
                                          : null,
                                      icon:
                                          const Icon(Icons.add_circle_outline)),
                                ]),
                              if (doses.containsKey(meal) &&
                                  meal != MealType.bedtime)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [true, false]
                                          .map((before) => ChoiceChip(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 10),
                                                labelStyle: const TextStyle(
                                                    fontSize: 18,
                                                    color: MeDisColors.text),
                                                label: Text(before
                                                    ? 'ก่อนอาหาร'
                                                    : 'หลังอาหาร'),
                                                selected: (beforeFood[meal] ??
                                                        true) ==
                                                    before,
                                                onSelected: (_) => setState(
                                                    () => beforeFood[meal] =
                                                        before),
                                              ))
                                          .toList()),
                                ),
                            ])),
                      ]),
                MedicationVerifyImage(
                  drug: Drug(
                    id: widget.slot.drug?.id ?? 'preview',
                    name: name.text.trim().isEmpty
                        ? 'ยาที่กำลังเพิ่ม'
                        : name.text.trim(),
                    labelImagePath: labelImagePath,
                  ),
                  onPickImage: chooseLabelImage,
                ),
                const SizedBox(height: 16),
                SlideToConfirm(
                  label: saving
                      ? 'กำลังบันทึก...'
                      : isEditing
                          ? 'สไลด์เพื่อบันทึกการแก้ไข'
                          : 'สไลด์เพื่อบันทึกยา',
                  onConfirmed: save,
                  enabled: !saving,
                ),
              ]),
        ),
      );
}

class _DrugFormSection extends StatelessWidget {
  const _DrugFormSection(
      {required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      MeDisSection(title: title, icon: icon, children: children);
}
