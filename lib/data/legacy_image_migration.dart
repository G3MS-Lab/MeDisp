import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Replace embedded images only after their external storage has committed.
/// Each preference is replaced independently, so interrupted runs can resume.
Future<void> migrateLegacyImagePreferences(
    Future<String> Function(String dataUrl) storeImage) async {
  final preferences = await SharedPreferences.getInstance();
  for (final key in preferences.getKeys()) {
    final isMedicationCollection = key.startsWith('medisp_') &&
        (key.endsWith('_drugs') || key.endsWith('_allergies'));
    if (!isMedicationCollection && !key.startsWith('dispenser_slots_')) {
      continue;
    }
    final raw = preferences.getString(key);
    if (raw == null || !raw.contains('data:image/')) continue;
    try {
      final records = jsonDecode(raw) as List;
      var changed = false;
      Future<void> migrateRecord(Map<String, dynamic> record) async {
        for (final field in ['label_image_path', 'image_path']) {
          final path = record[field];
          if (path is String && path.startsWith('data:image/')) {
            record[field] = await storeImage(path);
            changed = true;
          }
        }
        final drug = record['drug'];
        if (drug is Map<String, dynamic>) await migrateRecord(drug);
      }

      for (final record in records.cast<Map<String, dynamic>>()) {
        await migrateRecord(record);
      }
      if (changed) await preferences.setString(key, jsonEncode(records));
    } catch (error) {
      // Keep the original records usable when storage is unavailable.
      debugPrint('Image migration deferred for $key: $error');
    }
  }
}
