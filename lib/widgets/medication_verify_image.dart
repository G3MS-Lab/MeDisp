import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'local_image.dart';

class MedicationVerifyImage extends StatelessWidget {
  const MedicationVerifyImage(
      {required this.drug, this.onPickImage, super.key});

  final Drug drug;
  final VoidCallback? onPickImage;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 180,
            width: double.infinity,
            child: drug.labelImagePath == null
                ? const ColoredBox(
                    color: Color(0xFFEAF2FD),
                    child: Center(
                        child: Icon(Icons.photo_outlined,
                            size: 48, color: Color(0xFF7FA9DC))))
                : localImage(drug.labelImagePath!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_outlined, size: 48))),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  onPickImage == null ? 'ตรวจสอบยาก่อนใส่เครื่อง' : 'รูปฉลากยา',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(drug.labelImagePath == null
                  ? 'ยังไม่มีรูปฉลากยา · ${drug.name}'
                  : 'ตรวจสอบว่ายาที่จะใส่ตรงกับรูปฉลากและชื่อ ${drug.name}'),
              if (onPickImage != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('pick-medication-image'),
                  onPressed: onPickImage,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: Text(drug.labelImagePath == null
                      ? 'เพิ่มรูปฉลาก'
                      : 'เปลี่ยนรูปฉลาก'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ]),
          ),
        ]),
      );
}
