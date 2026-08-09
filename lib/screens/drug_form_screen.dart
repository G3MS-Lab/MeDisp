import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../application/app_scope.dart';
import '../domain/models.dart';
import '../widgets/medis_app_bar.dart';

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
  int quantity = 10;
  final Map<MealType, int> doses = {MealType.breakfast: 1};
  bool saving = false;
  String? labelImagePath;

  @override
  void dispose() {
    name.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate() || doses.isEmpty) return;
    setState(() => saving = true);
    final drug = Drug(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.text.trim(),
      notes: notes.text.trim(),
      labelImagePath: labelImagePath,
      instructions: doses.entries.map((entry) => DoseInstruction(meal: entry.key, quantity: entry.value)).toList(),
    );
    try {
      await AppScope.of(context).addDrugToSlot(drug, widget.slot.number, quantity);
      if (mounted) Navigator.pop(context);
    } on StateError catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message.toString())));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: MeDisAppBar('เพิ่มยา · ช่อง ${widget.slot.number}'),
        body: Form(
          key: formKey,
          child: ListView(padding: const EdgeInsets.all(24), children: [
            TextFormField(controller: name, decoration: const InputDecoration(labelText: 'ชื่อยา'), validator: (value) => value == null || value.trim().isEmpty ? 'กรุณาระบุชื่อยา' : null),
            const SizedBox(height: 14),
            TextFormField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'รายละเอียด / ข้อควรระวัง')),
            const SizedBox(height: 20),
            Row(children: [
              const Expanded(child: Text('จำนวนยาในช่อง', style: TextStyle(fontWeight: FontWeight.w600))),
              IconButton(onPressed: quantity > 1 ? () => setState(() => quantity--) : null, icon: const Icon(Icons.remove_circle_outline)),
              Text('$quantity เม็ด'),
              IconButton(onPressed: quantity < widget.slot.capacity ? () => setState(() => quantity++) : null, icon: const Icon(Icons.add_circle_outline)),
            ]),
            const SizedBox(height: 12),
            const Text('มื้อและจำนวนยาต่อครั้ง', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ...MealType.values.map((meal) => CheckboxListTile(
                  value: doses.containsKey(meal),
                  title: Text(meal.label),
                  subtitle: doses.containsKey(meal) ? Text('${doses[meal]} เม็ด') : null,
                  secondary: doses.containsKey(meal)
                      ? DropdownButton<int>(value: doses[meal], items: [1, 2, 3, 4].map((n) => DropdownMenuItem(value: n, child: Text('$n'))).toList(), onChanged: (n) => setState(() => doses[meal] = n!))
                      : null,
                  onChanged: (selected) => setState(() => selected! ? doses[meal] = 1 : doses.remove(meal)),
                )),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final source = await showModalBottomSheet<ImageSource>(context: context, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [ListTile(leading: const Icon(Icons.camera_alt), title: const Text('ถ่ายรูป'), onTap: () => Navigator.pop(context, ImageSource.camera)), ListTile(leading: const Icon(Icons.photo_library), title: const Text('เลือกรูป'), onTap: () => Navigator.pop(context, ImageSource.gallery))])));
                if (source == null) return;
                final image = await ImagePicker().pickImage(source: source, imageQuality: 85);
                if (image != null) setState(() => labelImagePath = image.path);
              },
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(labelImagePath == null ? 'ถ่ายหรืออัปโหลดรูปฉลากยา' : 'แนบรูปฉลากยาแล้ว'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(100)),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'กำลังบันทึก...' : 'บันทึกลงเครื่องจ่ายยา')),
          ]),
        ),
      );
}
