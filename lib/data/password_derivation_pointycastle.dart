import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

Uint8List derivePasswordSync(
    String password, Uint8List salt, int iterations, int keyLength) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, iterations, keyLength));
  return derivator.process(Uint8List.fromList(utf8.encode(password)));
}
