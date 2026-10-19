import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/local_image_store_web.dart';

Widget localImage(
  String path, {
  double? width,
  double? height,
  BoxFit? fit,
  ImageErrorWidgetBuilder? errorBuilder,
}) =>
    _StoredImage(
        path: path,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: errorBuilder);

class _StoredImage extends StatefulWidget {
  const _StoredImage(
      {required this.path,
      this.width,
      this.height,
      this.fit,
      this.errorBuilder});

  final String path;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  State<_StoredImage> createState() => _StoredImageState();
}

class _StoredImageState extends State<_StoredImage> {
  late Future<Uint8List> bytes;

  @override
  void initState() {
    super.initState();
    bytes = const LocalImageStore().read(widget.path);
  }

  @override
  void didUpdateWidget(_StoredImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      bytes = const LocalImageStore().read(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
      future: bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return widget.errorBuilder?.call(context, snapshot.error!, null) ??
              SizedBox(width: widget.width, height: widget.height);
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
              width: widget.width,
              height: widget.height,
              child: const Center(
                  child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))));
        }
        return Image.memory(snapshot.data!,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            errorBuilder: widget.errorBuilder);
      });
}
