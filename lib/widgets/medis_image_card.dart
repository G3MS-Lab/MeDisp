import 'package:flutter/material.dart';

import '../theme/medis_theme.dart';

import 'local_image.dart';

class MeDisImageCard extends StatelessWidget {
  const MeDisImageCard(
      {required this.title,
      required this.description,
      this.imagePath,
      this.onPickImage,
      super.key});

  final String title;
  final String description;
  final String? imagePath;
  final VoidCallback? onPickImage;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 180,
            width: double.infinity,
            child: imagePath == null
                ? const ColoredBox(
                    color: MeDisColors.primarySoft,
                    child: Center(
                        child: Icon(Icons.photo_outlined,
                            size: 48, color: MeDisColors.subtle)))
                : Semantics(
                    image: true,
                    label: title,
                    child: localImage(imagePath!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                  Icon(Icons.broken_image_outlined,
                                      size: 36, color: MeDisColors.subtle),
                                  SizedBox(height: 8),
                                  Text('ไม่สามารถแสดงรูปได้',
                                      style:
                                          TextStyle(color: MeDisColors.muted)),
                                ])))),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(description,
                  style: const TextStyle(color: MeDisColors.muted)),
              if (onPickImage != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('pick-medication-image'),
                  onPressed: onPickImage,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: Text(imagePath == null ? 'เพิ่มรูป' : 'เปลี่ยนรูป'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                ),
              ],
            ]),
          ),
        ]),
      );
}
