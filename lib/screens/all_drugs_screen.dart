import 'package:flutter/material.dart';

import '../theme/medis_theme.dart';

import '../application/app_scope.dart';
import '../domain/models.dart';
import '../widgets/medis_app_bar.dart';
import '../widgets/medis_ui.dart';
import 'dispenser_screen.dart';
import 'drug_detail_screen.dart';

class AllDrugsScreen extends StatelessWidget {
  const AllDrugsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Scaffold(
      appBar: const MeDisAppBar('ประวัติยาทั้งหมด'),
      body: controller.drugs.isEmpty
          ? Center(
              child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: MeDisEmptyState(
                      icon: Icons.medication_outlined,
                      title: 'ยังไม่มีรายการยา',
                      message: 'ยาที่เพิ่มในเครื่องจ่ายยาจะแสดงที่นี่',
                      action: OutlinedButton(
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const DispenserScreen())),
                          child: const Text('จัดการยา')))))
          : ListView.separated(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: MeDisSpace.pagePadding,
              itemCount: controller.drugs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final drug = controller.drugs[i];
                return Card(
                    child: ListTile(
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => DrugDetailScreen(drug: drug))),
                        leading: const CircleAvatar(
                            child: Icon(Icons.medication_outlined)),
                        title: Text(drug.name),
                        subtitle: Text([
                          if (drug.isPrn)
                            'ทานเมื่อมีอาการ (PRN)'
                          else
                            drug.instructions
                                .map((dose) =>
                                    '${dose.meal.label} ${dose.quantity} เม็ด ${dose.beforeFood ? 'ก่อนอาหาร' : 'หลังอาหาร'}')
                                .join(' · '),
                          if (drug.stoppedAt != null)
                            'หยุดยาเมื่อ ${_date(drug.stoppedAt!)}'
                        ].join('\n')),
                        trailing: const Icon(Icons.chevron_right)));
              },
            ),
    );
  }
}

String _date(DateTime value) =>
    '${value.day}/${value.month}/${value.year + 543}';
