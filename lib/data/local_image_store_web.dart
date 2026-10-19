import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:web/web.dart' as web;

import 'legacy_image_migration.dart';

class LocalImageStore {
  const LocalImageStore();

  static const _databaseName = 'medisp_attachments';
  static const _storeName = 'images';
  static const _prefix = 'medisp-image:';

  Future<web.IDBDatabase> _open() {
    final result = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_databaseName, 1);
    request.onupgradeneeded = ((web.Event _) {
      (request.result as web.IDBDatabase).createObjectStore(_storeName);
    }).toJS;
    request.onsuccess = ((web.Event _) {
      result.complete(request.result as web.IDBDatabase);
    }).toJS;
    request.onerror = ((web.Event _) {
      result.completeError(_storageError(request.error));
    }).toJS;
    return result.future;
  }

  StateError _storageError(web.DOMException? error) => StateError(error?.name ==
          'QuotaExceededError'
      ? 'พื้นที่เก็บรูปภาพในเบราว์เซอร์ไม่เพียงพอ กรุณาเพิ่มพื้นที่ว่างในอุปกรณ์แล้วลองใหม่'
      : 'ไม่สามารถเข้าถึงพื้นที่เก็บรูปภาพได้ กรุณาตรวจสอบการตั้งค่าเบราว์เซอร์แล้วลองใหม่');

  Future<String> persist(XFile image, {required String category}) async =>
      _persistBytes(await image.readAsBytes());

  Future<String> _persistBytes(Uint8List bytes) async {
    // A content key shares images across drugs and slots and makes migration
    // safe to repeat after an interrupted startup.
    final digest = SHA256Digest().process(bytes);
    final key = base64UrlEncode(digest).replaceAll('=', '');
    final database = await _open();
    try {
      final transaction = database.transaction(_storeName.toJS, 'readwrite');
      final committed = Completer<void>();
      transaction.oncomplete = ((web.Event _) => committed.complete()).toJS;
      transaction.onabort = ((web.Event _) {
        committed.completeError(_storageError(transaction.error));
      }).toJS;
      transaction.objectStore(_storeName).put(bytes.toJS, key.toJS);
      await committed.future;
      return '$_prefix$key';
    } finally {
      database.close();
    }
  }

  Future<Uint8List> read(String path) async {
    // Retain compatibility if a legacy migration could not be completed.
    if (path.startsWith('data:image/')) {
      return UriData.parse(path).contentAsBytes();
    }
    if (!path.startsWith(_prefix)) {
      throw StateError('ไม่พบรูปภาพที่แนบไว้');
    }
    final database = await _open();
    try {
      final transaction = database.transaction(_storeName.toJS);
      final result = Completer<Uint8List>();
      final request = transaction
          .objectStore(_storeName)
          .get(path.substring(_prefix.length).toJS);
      request.onsuccess = ((web.Event _) {
        final bytes = request.result;
        if (bytes == null) {
          result.completeError(StateError('ไม่พบรูปภาพที่แนบไว้'));
        } else {
          result.complete((bytes as JSUint8Array).toDart);
        }
      }).toJS;
      request.onerror = ((web.Event _) {
        result.completeError(_storageError(request.error));
      }).toJS;
      return await result.future;
    } finally {
      database.close();
    }
  }

  Future<void> migrateLegacyImages() => migrateLegacyImagePreferences(
      (dataUrl) => _persistBytes(UriData.parse(dataUrl).contentAsBytes()));
}
