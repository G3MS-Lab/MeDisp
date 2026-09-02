import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../application/app_scope.dart';
import '../data/local_image_store.dart';
import '../domain/models.dart';
import '../widgets/medis_app_bar.dart';
import '../widgets/medis_event_calendar.dart';
import 'allergy_detail_screen.dart';

class AllergyScreen extends StatefulWidget {
  const AllergyScreen({super.key});
  @override
  State<AllergyScreen> createState() => _AllergyScreenState();
}

class _AllergyScreenState extends State<AllergyScreen> {
  DateTime selected = DateTime.now();
  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final records = controller.allergies
        .where((record) => DateUtils.isSameDay(record.date, selected))
        .toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: const MeDisAppBar('อาการไม่พึงประสงค์'),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showForm(context),
          icon: const Icon(Icons.add),
          label: const Text('เพิ่มอาการ')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        MeDisEventCalendar(
            selectedDate: selected,
            intakes: controller.intakeHistory,
            allergies: controller.allergies,
            showMedicationEvents: false,
            onDateSelected: (date) => setState(() => selected = date)),
        const SizedBox(height: 20),
        Text(
            'บันทึกวันที่ ${selected.day}/${selected.month}/${selected.year + 543}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        if (records.isEmpty)
          const Padding(
              padding: EdgeInsets.all(22),
              child: Center(child: Text('ไม่มีบันทึกอาการ'))),
        ...records.map((record) => Card(
            child: ListTile(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => AllergyDetailScreen(record: record))),
                leading: const Icon(Icons.health_and_safety, color: Colors.red),
                title: Text(record.description),
                subtitle: Text(
                    '${TimeOfDay.fromDateTime(record.date).format(context)} · ${record.symptoms.isEmpty ? 'ไม่ได้ระบุอาการ' : record.symptoms.join(' · ')}'),
                trailing: const Icon(Icons.chevron_right)))),
      ]),
    );
  }

  Future<void> _showForm(BuildContext context) async {
    final controller = AppScope.of(context);
    final draft = await showModalBottomSheet<_AllergyDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AllergyFormSheet(),
    );
    if (draft != null && mounted) {
      final now = DateTime.now();
      await controller.addAllergy(AllergyRecord(
          date: DateTime(selected.year, selected.month, selected.day, now.hour,
              now.minute, now.second),
          description: draft.description.isEmpty
              ? 'อาการไม่พึงประสงค์'
              : draft.description,
          symptoms: draft.symptoms,
          imagePath: draft.imagePath));
    }
  }
}

class _AllergyDraft {
  const _AllergyDraft(this.description, this.symptoms, this.imagePath);
  final String description;
  final Set<String> symptoms;
  final String? imagePath;
}

class _AllergyFormSheet extends StatefulWidget {
  const _AllergyFormSheet();
  @override
  State<_AllergyFormSheet> createState() => _AllergyFormSheetState();
}

class _AllergyFormSheetState extends State<_AllergyFormSheet> {
  final description = TextEditingController();
  final symptoms = <String>{};
  String? imagePath;

  @override
  void dispose() {
    description.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
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
    if (source == null || !mounted) return;
    try {
      final image =
          await ImagePicker().pickImage(source: source, imageQuality: 85);
      if (image == null) return;
      final storedPath =
          await const LocalImageStore().persist(image, category: 'allergies');
      if (mounted) setState(() => imagePath = storedPath);
    } on PlatformException catch (error) {
      if (!mounted) return;
      final denied =
          error.code.contains('denied') || error.code.contains('permission');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(denied
              ? 'ไม่ได้รับอนุญาตให้เข้าถึงกล้องหรือรูปภาพ กรุณาเปิดสิทธิ์ใน Settings'
              : 'ไม่สามารถเปิดกล้องหรือรูปภาพได้: ${error.message ?? error.code}')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('ไม่สามารถแนบรูปภาพได้ กรุณาลองใหม่')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              24, 22, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
                child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 20),
            const Text('บันทึกอาการไม่พึงประสงค์',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            const Text('เลือกอาการ',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
                spacing: 7,
                runSpacing: 7,
                children: ['คลื่นไส้', 'อาเจียน', 'เวียนศีรษะ', 'ผื่น']
                    .map((item) => FilterChip(
                        label: Text(item),
                        selected: symptoms.contains(item),
                        onSelected: (value) => setState(() => value
                            ? symptoms.add(item)
                            : symptoms.remove(item))))
                    .toList()),
            const SizedBox(height: 14),
            TextField(
                controller: description,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'รายละเอียดเพิ่มเติม',
                    hintText: 'เช่น เกิดอาการหลังทานยาชนิดใดและนานเท่าไร',
                    prefixIcon: Icon(Icons.notes_outlined))),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: pickImage,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(imagePath == null
                    ? symptoms.contains('ผื่น')
                        ? 'ถ่าย / อัปโหลดรูปผื่น (จำเป็น)'
                        : 'ถ่าย / อัปโหลดรูป'
                    : 'แนบรูปแล้ว'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50))),
            const SizedBox(height: 14),
            FilledButton(
                onPressed: () {
                  if (symptoms.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('กรุณาเลือกอาการอย่างน้อย 1 รายการ')));
                    return;
                  }
                  if (symptoms.contains('ผื่น') && imagePath == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content:
                            Text('เมื่อเลือกอาการผื่น กรุณาถ่ายหรือแนบรูป')));
                    return;
                  }
                  Navigator.pop(
                      context,
                      _AllergyDraft(description.text.trim(), Set.of(symptoms),
                          imagePath));
                },
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                child: const Text('บันทึกอาการ')),
          ]),
        ),
      );
}
