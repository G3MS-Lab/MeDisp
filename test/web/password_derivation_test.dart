@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:medisp/data/auth_repositories.dart';
import 'package:medisp/data/password_derivation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Web Crypto is responsive and matches existing PBKDF2 hashes', () async {
    final salt = Uint8List.fromList(List.generate(16, (index) => index));
    var timerFired = false;
    final timer = Timer(Duration.zero, () => timerFired = true);
    final result =
        await derivePassword('browser password รหัสผ่าน', salt, 210000, 32);
    timer.cancel();
    expect(timerFired, isTrue);
    expect(result,
        base64Url.decode('4_j3r9f7IfVXuCrum66RzOfh0lYlkRouMVOrzmX4oKw='));
  });

  test('a previously saved account can sign in on the web', () async {
    final storage = MemoryAuthStorage();
    final salt = Uint8List.fromList(List.generate(16, (index) => index + 1));
    await storage.write(
        'medisp.local_auth.accounts.v1',
        jsonEncode([
          {
            'id': 'legacy-browser',
            'email': 'legacy@example.com',
            'display_name': 'Legacy',
            'salt': base64UrlEncode(salt),
            'hash': 'kIcqfOyV3ytuGw7V-7_wZYpt1zUMIHcpt01Xax51B48=',
          }
        ]));
    final auth = OfflineAuthRepository(storage);
    await auth.initialize();
    expect(
        (await auth.signIn(
                email: 'legacy@example.com', password: 'legacy-password'))
            .id,
        'legacy-browser');
  });

  test('new browser account can register and sign in again', () async {
    final auth = OfflineAuthRepository(MemoryAuthStorage());
    await auth.initialize();
    final user = await auth.register(
        name: 'New Patient',
        email: 'new@example.com',
        password: 'new-password');
    await auth.signOut();
    final restored =
        await auth.signIn(email: 'new@example.com', password: 'new-password');
    expect(restored.id, user.id);
  });
}
