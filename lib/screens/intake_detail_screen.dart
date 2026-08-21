import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../widgets/medis_app_bar.dart';
import 'drug_detail_screen.dart';

class IntakeDetailScreen extends StatelessWidget {
  const IntakeDetailScreen({required this.record, super.key});
  final IntakeRecord record;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const MeDisAppBar('รายละเอียดการทานยา'),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Card(
              child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
                backgroundColor: record.meal.color,
                child: const Icon(Icons.check, color: Colors.white)),
            title: Text(record.meal.label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
                '${record.takenAt.day}/${record.takenAt.month}/${record.takenAt.year + 543} · ${TimeOfDay.fromDateTime(record.takenAt).format(context)}'),
          )),
          const SizedBox(height: 15),
          const Text('รายการยาที่ทาน',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...record.doses.map((dose) => Card(
                child: ListTile(
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => DrugDetailScreen(drug: dose.drug))),
                  leading: const Icon(Icons.medication_outlined),
                  title: Text(dose.drug.name),
                  subtitle: Text(
                      '${dose.quantity} เม็ด · ${(dose.drug.instructionFor(record.meal)?.beforeFood ?? true) ? 'ก่อนอาหาร' : 'หลังอาหาร'}'),
                  trailing: const Icon(Icons.chevron_right),
                ),
              )),
        ]),
      );
}
