import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:medisp/data/auth_repositories.dart';
import 'package:medisp/data/password_derivation.dart';
import 'package:medisp/data/password_derivation_pointycastle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('password derivation preserves the existing PBKDF2-SHA256 format',
      () async {
    final salt = Uint8List.fromList(List.generate(16, (index) => index));
    final expected =
        derivePasswordSync('a Thai password รหัสผ่าน', salt, 210000, 32);
    expect(await derivePassword('a Thai password รหัสผ่าน', salt, 210000, 32),
        expected);
  });

  test('an account with the previous hash can still sign in', () async {
    final storage = MemoryAuthStorage();
    const email = 'legacy@example.com';
    const password = 'legacy-password';
    final salt = Uint8List.fromList(List.generate(16, (index) => index + 1));
    final account = {
      'id': 'legacy-account',
      'email': email,
      'display_name': 'Legacy Patient',
      'salt': base64UrlEncode(salt),
      'hash': base64UrlEncode(derivePasswordSync(password, salt, 210000, 32)),
    };
    await storage.write('medisp.local_auth.accounts.v1', jsonEncode([account]));
    final auth = OfflineAuthRepository(storage);
    await auth.initialize();
    final user = await auth.signIn(email: email, password: password);
    expect(user.id, 'legacy-account');
    await auth.signOut();
    await expectLater(
        auth.signIn(email: email, password: 'incorrect'), throwsStateError);
  });
}
