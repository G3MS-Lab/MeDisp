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

  void _openFullScreen(BuildContext context, String path) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => FullScreenImageScreen(
          imagePath: path,
          title: title,
        ),
      ),
    );
  }

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
                : Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: const Key('view-full-screen-image'),
                      onTap: () => _openFullScreen(context, imagePath!),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Semantics(
                              image: true,
                              label: title,
                              child: localImage(imagePath!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Center(
                                          child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                            Icon(Icons.broken_image_outlined,
                                                size: 36,
                                                color: MeDisColors.subtle),
                                            SizedBox(height: 8),
                                            Text('ไม่สามารถแสดงรูปได้',
                                                style: TextStyle(
                                                    color: MeDisColors.muted)),
                                          ])))),
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.62),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.fullscreen_rounded,
                                      size: 16, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text(
                                    'แตะเพื่อดูเต็มจอ',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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

class FullScreenImageScreen extends StatelessWidget {
  const FullScreenImageScreen({
    required this.imagePath,
    required this.title,
    super.key,
  });

  final String imagePath;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Center(
          child: InteractiveViewer(
            key: const Key('full-screen-interactive-viewer'),
            minScale: 0.8,
            maxScale: 4.0,
            child: localImage(
              imagePath,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_outlined,
                        size: 48, color: Colors.white70),
                    SizedBox(height: 10),
                    Text(
                      'ไม่สามารถแสดงรูปภาพได้',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
