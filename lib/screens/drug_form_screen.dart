import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../application/app_scope.dart';
import '../data/local_image_store.dart';
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
  final Map<MealType, bool> beforeFood = {MealType.breakfast: true};
  bool saving = false;
  String? labelImagePath;

  Future<void> pickLabelImage(ImageSource source) async {
    try {
      final image =
          await ImagePicker().pickImage(source: source, imageQuality: 85);
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('ไม่สามารถแนบรูปภาพได้ กรุณาลองใหม่')));
      }
    }
  }

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
      addedAt: DateTime.now(),
      instructions: doses.entries
          .map((entry) => DoseInstruction(
              meal: entry.key,
              quantity: entry.value,
              beforeFood: beforeFood[entry.key] ?? true))
          .toList(),
    );
    try {
      await AppScope.of(context)
          .addDrugToSlot(drug, widget.slot.number, quantity);
      if (mounted) {
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
        backgroundColor: const Color(0xFFF4F7FC),
        appBar: MeDisAppBar('เพิ่มยา · ช่อง ${widget.slot.number}'),
        body: Form(
          key: formKey,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            _DrugFormSection(
                title: 'ข้อมูลยา',
                icon: Icons.medication_outlined,
                children: [
                  TextFormField(
                      controller: name,
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
                title: 'จำนวนยาในช่อง',
                icon: Icons.inventory_2_outlined,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF4F7FC),
                        borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Expanded(
                          child: Text('ความจุ ${widget.slot.capacity} เม็ด',
                              style:
                                  const TextStyle(color: Color(0xFF68778B)))),
                      IconButton(
                          onPressed: quantity > 1
                              ? () => setState(() => quantity--)
                              : null,
                          icon: const Icon(Icons.remove_circle_outline)),
                      Text('$quantity',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                      IconButton(
                          onPressed: quantity < widget.slot.capacity
                              ? () => setState(() => quantity++)
                              : null,
                          icon: const Icon(Icons.add_circle_outline)),
                    ]),
                  ),
                ]),
            _DrugFormSection(
                title: 'มื้อและจำนวนยาต่อครั้ง',
                icon: Icons.schedule_outlined,
                children: [
                  ...MealType.values.map((meal) => Column(children: [
                        CheckboxListTile(
                          value: doses.containsKey(meal),
                          contentPadding: EdgeInsets.zero,
                          title: Text('มื้อ${meal.label}'),
                          subtitle: doses.containsKey(meal)
                              ? Text(
                                  '${doses[meal]} เม็ด · ${(beforeFood[meal] ?? true) ? 'ก่อนอาหาร' : 'หลังอาหาร'}')
                              : null,
                          secondary: doses.containsKey(meal)
                              ? DropdownButton<int>(
                                  value: doses[meal],
                                  items: [1, 2, 3, 4]
                                      .map((n) => DropdownMenuItem(
                                          value: n, child: Text('$n')))
                                      .toList(),
                                  onChanged: (n) =>
                                      setState(() => doses[meal] = n!))
                              : null,
                          onChanged: (selected) => setState(() {
                            if (selected!) {
                              doses[meal] = 1;
                              beforeFood[meal] = true;
                            } else {
                              doses.remove(meal);
                              beforeFood.remove(meal);
                            }
                          }),
                        ),
                        if (doses.containsKey(meal))
                          Padding(
                            padding: const EdgeInsets.only(left: 48, bottom: 8),
                            child: SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(
                                    value: true, label: Text('ก่อนอาหาร')),
                                ButtonSegment(
                                    value: false, label: Text('หลังอาหาร')),
                              ],
                              selected: {beforeFood[meal] ?? true},
                              onSelectionChanged: (value) => setState(
                                  () => beforeFood[meal] = value.single),
                            ),
                          ),
                      ])),
                ]),
            _DrugFormSection(
                title: 'รูปฉลากยา',
                icon: Icons.photo_camera_outlined,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final source = await showModalBottomSheet<ImageSource>(
                          context: context,
                          builder: (context) => SafeArea(
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                    ListTile(
                                        leading: const Icon(Icons.camera_alt),
                                        title: const Text('ถ่ายรูป'),
                                        onTap: () => Navigator.pop(
                                            context, ImageSource.camera)),
                                    ListTile(
                                        leading:
                                            const Icon(Icons.photo_library),
                                        title: const Text('เลือกรูป'),
                                        onTap: () => Navigator.pop(
                                            context, ImageSource.gallery))
                                  ])));
                      if (source == null) return;
                      await pickLabelImage(source);
                    },
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(labelImagePath == null
                        ? 'ถ่ายหรืออัปโหลดรูปฉลากยา'
                        : 'แนบรูปฉลากยาแล้ว'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(100)),
                  ),
                  if (labelImagePath != null) ...[
                    const SizedBox(height: 10),
                    const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle,
                              size: 18, color: Colors.green),
                          SizedBox(width: 6),
                          Text('รูปจะถูกเก็บไว้ในแอปอย่างถาวร')
                        ])
                  ]
                ]),
            FilledButton.icon(
                onPressed: saving ? null : save,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54)),
                icon: const Icon(Icons.save_outlined),
                label:
                    Text(saving ? 'กำลังบันทึก...' : 'บันทึกลงเครื่องจ่ายยา')),
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, color: const Color(0xFF397BD9)),
                const SizedBox(width: 9),
                Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800))
              ]),
              const SizedBox(height: 16),
              ...children,
            ]),
          ),
        ),
      );
}
