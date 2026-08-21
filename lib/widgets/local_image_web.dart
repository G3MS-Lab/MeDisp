import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

Widget localImage(
  String path, {
  double? width,
  double? height,
  BoxFit? fit,
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  try {
    final comma = path.indexOf(',');
    final bytes =
        comma < 0 ? Uint8List(0) : base64Decode(path.substring(comma + 1));
    return Image.memory(
      bytes,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
    );
  } catch (_) {
    return const SizedBox();
  }
}
