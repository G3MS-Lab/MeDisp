import 'package:flutter/material.dart';

import '../theme/medis_theme.dart';

import '../application/app_scope.dart';
import '../domain/models.dart';
import '../widgets/medis_app_bar.dart';
import '../widgets/medis_ui.dart';
import '../widgets/slide_to_confirm.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});
  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> fields = {};
  String? bloodType;
  String? gender;
  bool initialized = false;
  bool saving = false;

  TextEditingController field(String key) => fields[key]!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    final profile = AppScope.of(context).profile;
    fields.addAll({
      'name': TextEditingController(text: profile.name),
      'phone': TextEditingController(text: profile.phone),
      'birthDate': TextEditingController(text: profile.birthDate),
      'address': TextEditingController(text: profile.address),
      'height': TextEditingController(text: profile.heightCm?.toString() ?? ''),
      'weight': TextEditingController(text: profile.weightKg?.toString() ?? ''),
      'conditions': TextEditingController(text: profile.medicalConditions),
      'drugAllergies': TextEditingController(text: profile.drugAllergies),
      'caregiverName': TextEditingController(text: profile.caregiverName),
      'relationship':
          TextEditingController(text: profile.caregiverRelationship),
      'caregiverPhone': TextEditingController(text: profile.caregiverPhone),
      'emergencyPhone': TextEditingController(text: profile.emergencyPhone),
    });
    bloodType = profile.bloodType.isEmpty ? null : profile.bloodType;
    gender = profile.gender.isEmpty ? null : profile.gender;
    initialized = true;
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> selectBirthDate() async {
    final initial = DateTime.tryParse(field('birthDate').text) ??
        DateTime(DateTime.now().year - 40);
    final selected = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(1900),
        lastDate: DateTime.now());
    if (selected != null) {
      field('birthDate').text =
          '${selected.year}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> save() async {
    if (saving) return;
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    final controller = AppScope.of(context);
    try {
      await controller.updateProfile(PatientProfile(
        name: field('name').text.trim(),
        email: controller.profile.email,
        phone: field('phone').text.trim(),
        bloodType: bloodType ?? '',
        birthDate: field('birthDate').text.trim(),
        address: field('address').text.trim(),
        gender: gender ?? '',
        heightCm: double.tryParse(field('height').text.trim()),
        weightKg: double.tryParse(field('weight').text.trim()),
        medicalConditions: field('conditions').text.trim(),
        drugAllergies: field('drugAllergies').text.trim(),
        caregiverName: field('caregiverName').text.trim(),
        caregiverRelationship: field('relationship').text.trim(),
        caregiverPhone: field('caregiverPhone').text.trim(),
        emergencyPhone: field('emergencyPhone').text.trim(),
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('บันทึกข้อมูลผู้ป่วยแล้ว')));
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

  String? requiredText(String? value) =>
      value == null || value.trim().isEmpty ? 'กรุณาระบุข้อมูล' : null;

  String? positiveNumber(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final number = double.tryParse(value.trim());
    return number == null || !number.isFinite || number <= 0
        ? 'กรอกตัวเลขที่มากกว่า 0'
        : null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: MeDisColors.background,
        appBar: const MeDisAppBar('แก้ไขข้อมูลผู้ป่วย'),
        body: Form(
          key: formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: MeDisSpace.pagePadding,
              children: [
                _FormSection(title: 'ข้อมูลส่วนตัว', children: [
                  _Input(
                      controller: field('name'),
                      label: 'ชื่อ–นามสกุล',
                      icon: Icons.person_outline,
                      validator: requiredText),
                  DropdownButtonFormField<String>(
                      initialValue: gender,
                      decoration: const InputDecoration(
                          labelText: 'เพศ',
                          prefixIcon: Icon(Icons.wc_outlined)),
                      items: const ['ชาย', 'หญิง', 'ไม่ระบุ']
                          .map((value) => DropdownMenuItem(
                              value: value, child: Text(value)))
                          .toList(),
                      onChanged: (value) => setState(() => gender = value)),
                  _Input(
                      controller: field('birthDate'),
                      label: 'วันเกิด',
                      icon: Icons.cake_outlined,
                      readOnly: true,
                      onTap: selectBirthDate),
                  _Input(
                      controller: field('phone'),
                      label: 'เบอร์โทรศัพท์',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone),
                  _Input(
                      controller: field('address'),
                      label: 'ที่อยู่',
                      icon: Icons.home_outlined,
                      maxLines: 3),
                ]),
                _FormSection(title: 'ข้อมูลสุขภาพ', children: [
                  DropdownButtonFormField<String>(
                      initialValue: bloodType,
                      decoration: const InputDecoration(
                          labelText: 'หมู่เลือด',
                          prefixIcon: Icon(Icons.bloodtype_outlined)),
                      items: const ['A', 'B', 'AB', 'O', 'ไม่ทราบ']
                          .map((value) => DropdownMenuItem(
                              value: value, child: Text(value)))
                          .toList(),
                      onChanged: (value) => setState(() => bloodType = value)),
                  _Input(
                      controller: field('height'),
                      label: 'ส่วนสูง (ซม.)',
                      icon: Icons.height,
                      validator: positiveNumber,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true)),
                  _Input(
                      controller: field('weight'),
                      label: 'น้ำหนัก (กก.)',
                      icon: Icons.monitor_weight_outlined,
                      validator: positiveNumber,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true)),
                  _Input(
                      controller: field('conditions'),
                      label: 'โรคประจำตัว',
                      icon: Icons.medical_information_outlined,
                      maxLines: 2),
                  _Input(
                      controller: field('drugAllergies'),
                      label: 'ประวัติแพ้ยา',
                      icon: Icons.warning_amber_rounded,
                      maxLines: 2),
                ]),
                _FormSection(title: 'ผู้ดูแลและกรณีฉุกเฉิน', children: [
                  _Input(
                      controller: field('caregiverName'),
                      label: 'ชื่อผู้ดูแล',
                      icon: Icons.person_outline),
                  _Input(
                      controller: field('relationship'),
                      label: 'ความสัมพันธ์',
                      icon: Icons.people_outline),
                  _Input(
                      controller: field('caregiverPhone'),
                      label: 'เบอร์ผู้ดูแล',
                      icon: Icons.phone_in_talk_outlined,
                      keyboardType: TextInputType.phone),
                  _Input(
                      controller: field('emergencyPhone'),
                      label: 'เบอร์ติดต่อฉุกเฉิน',
                      icon: Icons.emergency_outlined,
                      keyboardType: TextInputType.phone),
                ]),
                const SizedBox(height: 4),
                SlideToConfirm(
                    sliderKey: const Key('save-profile-slider'),
                    enabled: !saving,
                    onConfirmed: save,
                    label: saving
                        ? 'กำลังบันทึก...'
                        : 'สไลด์เพื่อบันทึกข้อมูลผู้ป่วย'),
              ]),
        ),
      );
}

class _FormSection extends StatelessWidget {
  const _FormSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => MeDisSection(
      title: title,
      children: children
          .expand((child) => [child, const SizedBox(height: 16)])
          .toList());
}

class _Input extends StatelessWidget {
  const _Input(
      {required this.controller,
      required this.label,
      required this.icon,
      this.keyboardType,
      this.maxLines = 1,
      this.readOnly = false,
      this.onTap,
      this.validator});
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool readOnly;
  final VoidCallback? onTap;
  final FormFieldValidator<String>? validator;
  @override
  Widget build(BuildContext context) => TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      textInputAction:
          maxLines > 1 ? TextInputAction.newline : TextInputAction.next,
      readOnly: readOnly,
      onTap: onTap,
      validator: validator,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)));
}
