import 'package:flutter/material.dart';

import '../application/app_scope.dart';
import '../widgets/medis_app_bar.dart';

class AllDrugsScreen extends StatelessWidget {
  const AllDrugsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Scaffold(
      appBar: const MeDisAppBar('ประวัติยาทั้งหมด'),
      body: ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: controller.drugs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final drug = controller.drugs[i];
          return Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.medication_outlined)), title: Text(drug.name), subtitle: Text(drug.instructions.map((dose) => '${dose.meal.label} ${dose.quantity} เม็ด').join(' · ')), trailing: const Icon(Icons.chevron_right)));
        },
      ),
    );
  }
}
