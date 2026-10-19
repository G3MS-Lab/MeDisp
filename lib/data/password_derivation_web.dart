import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'password_derivation_pointycastle.dart';

Future<Uint8List> derivePassword(
    String password, Uint8List salt, int iterations, int keyLength) async {
  try {
    final subtle = web.window.crypto.subtle;
    final imported = await subtle
        .importKey(
          'raw',
          Uint8List.fromList(utf8.encode(password)).toJS,
          'PBKDF2'.toJS,
          false,
          ['deriveBits'.toJS].toJS,
        )
        .toDart;
    final algorithm = <String, Object>{
      'name': 'PBKDF2',
      'salt': salt.toJS,
      'iterations': iterations,
      'hash': 'SHA-256',
    }.jsify()!;
    final bits = await subtle
        .deriveBits(
          algorithm,
          imported,
          keyLength * 8,
        )
        .toDart;
    return bits.toDart.asUint8List();
  } catch (_) {
    // Web Crypto is unavailable in some insecure browser contexts.
    return derivePasswordSync(password, salt, iterations, keyLength);
  }
}
