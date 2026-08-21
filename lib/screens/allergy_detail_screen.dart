import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../widgets/medis_app_bar.dart';
import '../widgets/local_image.dart';

class AllergyDetailScreen extends StatelessWidget {
  const AllergyDetailScreen({required this.record, super.key});
  final AllergyRecord record;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const MeDisAppBar('รายละเอียดอาการแพ้'),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          if (record.imagePath != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: localImage(record.imagePath!,
                  height: 240,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      height: 160,
                      color: const Color(0xFFF1F4F8),
                      alignment: Alignment.center,
                      child: const Text('ไม่พบไฟล์รูปภาพ'))),
            ),
            const SizedBox(height: 18),
          ],
          Text(record.description,
              style:
                  const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
              'วันที่ ${record.date.day}/${record.date.month}/${record.date.year + 543} · ${TimeOfDay.fromDateTime(record.date).format(context)}',
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          const Text('อาการที่บันทึก',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (record.symptoms.isEmpty) const Text('ไม่ได้ระบุอาการ'),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: record.symptoms
                  .map((symptom) => Chip(label: Text(symptom)))
                  .toList()),
        ]),
      );
}
