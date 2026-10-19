import 'package:flutter/material.dart';

import '../theme/medis_theme.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../application/app_scope.dart';
import '../data/local_image_store.dart';
import '../domain/models.dart';
import '../widgets/medis_app_bar.dart';
import '../widgets/medis_event_calendar.dart';
import '../widgets/medis_image_card.dart';
import '../widgets/medis_ui.dart';
import '../widgets/slide_to_confirm.dart';
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
      backgroundColor: MeDisColors.background,
      appBar: const MeDisAppBar('อาการไม่พึงประสงค์'),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showForm(context),
          icon: const Icon(Icons.add),
          label: const Text('เพิ่มอาการ')),
      body: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 104),
          children: [
            MeDisEventCalendar(
                selectedDate: selected,
                intakes: controller.intakeHistory,
                allergies: controller.allergies,
                showMedicationEvents: false,
                onDateSelected: (date) => setState(() => selected = date)),
            const SizedBox(height: 20),
            Text(
                'บันทึกวันที่ ${selected.day}/${selected.month}/${selected.year + 543}',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            if (records.isEmpty)
              const MeDisEmptyState(
                  icon: Icons.health_and_safety_outlined,
                  title: 'ไม่มีบันทึกอาการ',
                  message: 'กด “เพิ่มอาการ” เพื่อบันทึกสิ่งที่สังเกตหลังทานยา'),
            ...records.map((record) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                AllergyDetailScreen(record: record))),
                    leading: const Icon(Icons.health_and_safety,
                        color: MeDisColors.error),
                    title: Text(record.description),
                    subtitle: Text(
                        '${record.date.formatTime24Hour()} · ${record.symptoms.isEmpty ? 'ไม่ได้ระบุอาการ' : record.symptoms.join(' · ')}'),
                    trailing: const Icon(Icons.chevron_right)))),
          ]),
    );
  }

  Future<void> _showForm(BuildContext context) async {
    final controller = AppScope.of(context);
    final confirmed = await confirmMeDisAction(context,
        title: 'เพิ่มบันทึกอาการ',
        message: 'สไลด์เพื่อเปิดฟอร์มบันทึกอาการหลังทานยา',
        actionLabel: 'เพิ่มข้อมูลอาการ');
    if (!confirmed || !context.mounted) return;
    final draft = await showModalBottomSheet<_AllergyDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AllergyFormSheet(),
    );
    if (draft != null && mounted) {
      final now = DateTime.now();
      try {
        await controller.addAllergy(AllergyRecord(
            date: DateTime(selected.year, selected.month, selected.day,
                now.hour, now.minute, now.second),
            description: draft.description.isEmpty
                ? 'อาการไม่พึงประสงค์'
                : draft.description,
            symptoms: draft.symptoms,
            imagePath: draft.imagePath));
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('บันทึกอาการแล้ว')));
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(error.toString().replaceFirst('Bad state: ', ''))));
        }
      }
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
  String? symptomsError;
  String? descriptionError;

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
      final image = await ImagePicker().pickImage(
          source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
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
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error is StateError
                ? error.message.toString()
                : 'ไม่สามารถแนบรูปภาพได้ กรุณาลองใหม่')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
              24, 22, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
                child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                        color: MeDisColors.border,
                        borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 20),
            const Text('บันทึกอาการไม่พึงประสงค์',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            const Text('เลือกอาการ',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
                spacing: 7,
                runSpacing: 7,
                children: const [
                  ('คลื่นไส้', false),
                  ('อาเจียน', false),
                  ('เวียนศีรษะ', false),
                  ('ผื่น', true),
                  ('อื่นๆ', true),
                ]
                    .map((item) => FilterChip(
                        label: Text(item.$2 ? '${item.$1} *' : item.$1),
                        selected: symptoms.contains(item.$1),
                        onSelected: (value) => setState(() {
                              value
                                  ? symptoms.add(item.$1)
                                  : symptoms.remove(item.$1);
                              symptomsError = null;
                            })))
                    .toList()),
            if (symptomsError != null)
              Text(symptomsError!,
                  style:
                      const TextStyle(color: MeDisColors.error, fontSize: 13)),
            const SizedBox(height: 6),
            Text(
              '* หมายถึง จำเป็นต้องระบุรายละเอียดเพิ่มเติม',
              style: TextStyle(
                fontSize: 12,
                color: (symptoms.contains('ผื่น') || symptoms.contains('อื่นๆ'))
                    ? MeDisColors.error
                    : MeDisColors.subtle,
                fontWeight:
                    (symptoms.contains('ผื่น') || symptoms.contains('อื่นๆ'))
                        ? FontWeight.w600
                        : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
                controller: description,
                maxLines: 3,
                onChanged: (_) => setState(() => descriptionError = null),
                decoration: InputDecoration(
                    errorText: descriptionError,
                    labelText: (symptoms.contains('ผื่น') ||
                            symptoms.contains('อื่นๆ'))
                        ? 'รายละเอียดเพิ่มเติม * (จำเป็น)'
                        : 'รายละเอียดเพิ่มเติม',
                    labelStyle: TextStyle(
                      color: (symptoms.contains('ผื่น') ||
                              symptoms.contains('อื่นๆ'))
                          ? MeDisColors.error
                          : null,
                    ),
                    hintText: (symptoms.contains('ผื่น') ||
                            symptoms.contains('อื่นๆ'))
                        ? 'จำเป็นต้องระบุรายละเอียด เช่น ลักษณะผื่นหรืออาการอื่นๆ'
                        : 'เช่น เกิดอาการหลังทานยาชนิดใดและนานเท่าไร',
                    prefixIcon: const Icon(Icons.notes_outlined))),
            const SizedBox(height: 12),
            MeDisImageCard(
                title: 'รูปอาการ (ถ้ามี)',
                description: 'แนบรูปเพื่อใช้ติดตามอาการในภายหลัง',
                imagePath: imagePath,
                onPickImage: pickImage),
            const SizedBox(height: 14),
            SlideToConfirm(
                sliderKey: const Key('save-allergy-slider'),
                onConfirmed: () {
                  if (symptoms.isEmpty) {
                    setState(
                        () => symptomsError = 'เลือกอาการอย่างน้อย 1 รายการ');
                    return;
                  }
                  final needsDetails =
                      symptoms.contains('ผื่น') || symptoms.contains('อื่นๆ');
                  if (needsDetails && description.text.trim().isEmpty) {
                    setState(() => descriptionError =
                        'ระบุลักษณะอาการหรือตำแหน่งที่เกิดอาการ');
                    return;
                  }
                  Navigator.pop(
                      context,
                      _AllergyDraft(description.text.trim(), Set.of(symptoms),
                          imagePath));
                },
                label: 'สไลด์เพื่อบันทึกอาการ'),
          ]),
        ),
      );
}
