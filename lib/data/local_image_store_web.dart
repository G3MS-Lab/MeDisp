import 'dart:convert';

import 'package:image_picker/image_picker.dart';

class LocalImageStore {
  const LocalImageStore();

  Future<String> persist(XFile image, {required String category}) async {
    final bytes = await image.readAsBytes();
    final mimeType = image.mimeType ?? 'image/jpeg';
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }
}
