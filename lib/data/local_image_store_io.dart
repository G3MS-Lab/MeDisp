import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class LocalImageStore {
  const LocalImageStore();

  Future<String> persist(XFile image, {required String category}) async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/attachments/$category');
    await directory.create(recursive: true);
    final dot = image.path.lastIndexOf('.');
    final extension =
        dot >= 0 ? image.path.substring(dot).toLowerCase() : '.jpg';
    final destination = File(
        '${directory.path}/${DateTime.now().microsecondsSinceEpoch}$extension');
    await File(image.path).copy(destination.path);
    return destination.path;
  }
}
