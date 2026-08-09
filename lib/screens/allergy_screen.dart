import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../application/app_scope.dart';
import '../domain/models.dart';
import '../widgets/medis_app_bar.dart';

class AllergyScreen extends StatefulWidget {
  const AllergyScreen({super.key});
  @override
  State<AllergyScreen> createState() => _AllergyScreenState();
}

class _AllergyScreenState extends State<AllergyScreen> {
  DateTime selected = DateTime.now();
  @override
  Widget build(BuildContext context) {
    final records = AppScope.of(context).allergies.where((record) => record.date.day == selected.day).toList();
    return Scaffold(
      appBar: const MeDisAppBar('การแพ้และอาการ'),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _showForm(context), icon: const Icon(Icons.add), label: const Text('เพิ่มอาการ')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        CalendarDatePicker(initialDate: selected, firstDate: DateTime(2020), lastDate: DateTime(2035), onDateChanged: (date) => setState(() => selected = date)),
        const Divider(),
        Text('บันทึกวันที่ ${selected.day}/${selected.month}/${selected.year}', style: const TextStyle(fontWeight: FontWeight.w700)),
        if (records.isEmpty) const Padding(padding: EdgeInsets.all(22), child: Center(child: Text('ไม่มีบันทึกอาการ'))),
        ...records.map((record) => Card(child: ListTile(leading: const Icon(Icons.health_and_safety, color: Colors.red), title: Text(record.description), subtitle: Text(record.symptoms.join(' · '))))),
      ]),
    );
  }

  Future<void> _showForm(BuildContext context) async {
    final description = TextEditingController();
    final symptoms = <String>{};
    String? imagePath;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(builder: (context, setModalState) => Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('บันทึกอาการแพ้', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              TextField(controller: description, decoration: const InputDecoration(labelText: 'รายละเอียดเบื้องต้น')),
              Wrap(children: ['มีไข้', 'มึนหัว', 'อาเจียน', 'เจ็บคอ', 'มีผื่น'].map((item) => FilterChip(label: Text(item), selected: symptoms.contains(item), onSelected: (value) => setModalState(() => value ? symptoms.add(item) : symptoms.remove(item)))).toList()),
              OutlinedButton.icon(onPressed: () async {
                final source = await showModalBottomSheet<ImageSource>(context: context, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [ListTile(leading: const Icon(Icons.camera_alt), title: const Text('ถ่ายรูป'), onTap: () => Navigator.pop(context, ImageSource.camera)), ListTile(leading: const Icon(Icons.photo_library), title: const Text('เลือกรูป'), onTap: () => Navigator.pop(context, ImageSource.gallery))])));
                if (source == null) return;
                final image = await ImagePicker().pickImage(source: source, imageQuality: 85);
                if (image != null) setModalState(() => imagePath = image.path);
              }, icon: const Icon(Icons.add_a_photo_outlined), label: Text(imagePath == null ? 'ถ่าย / อัปโหลดรูป' : 'แนบรูปแล้ว')),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => Navigator.pop(sheetContext, true), child: const Text('บันทึกอาการ')),
            ]),
          )),
    );
    if (saved == true && mounted) {
      await AppScope.of(context).addAllergy(AllergyRecord(date: selected, description: description.text.trim().isEmpty ? 'อาการไม่พึงประสงค์' : description.text.trim(), symptoms: symptoms, imagePath: imagePath));
    }
    description.dispose();
  }
}
