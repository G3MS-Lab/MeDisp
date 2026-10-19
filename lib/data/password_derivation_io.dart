import 'package:flutter/foundation.dart';

import 'password_derivation_pointycastle.dart';

Future<Uint8List> derivePassword(
        String password, Uint8List salt, int iterations, int keyLength) =>
    compute(_deriveInIsolate, (password, salt, iterations, keyLength));

Uint8List _deriveInIsolate((String, Uint8List, int, int) args) =>
    derivePasswordSync(args.$1, args.$2, args.$3, args.$4);
