import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'medis_image_card.dart';

class MedicationVerifyImage extends StatelessWidget {
  const MedicationVerifyImage(
      {required this.drug, this.onPickImage, super.key});
  final Drug drug;
  final VoidCallback? onPickImage;

  @override
  Widget build(BuildContext context) => MeDisImageCard(
      title: onPickImage == null ? 'ตรวจสอบยาก่อนใส่เครื่อง' : 'รูปฉลากยา',
      description: drug.labelImagePath == null
          ? 'ยังไม่มีรูปฉลากยา · ${drug.name}'
          : 'ตรวจสอบฉลากและชื่อยา ${drug.name} ให้ตรงกัน',
      imagePath: drug.labelImagePath,
      onPickImage: onPickImage);
}
