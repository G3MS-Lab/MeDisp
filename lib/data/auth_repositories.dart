import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';

abstract interface class AuthStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureAuthStorage implements AuthStorage {
  SecureAuthStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// In-memory adapter for unit and functional tests.
class MemoryAuthStorage implements AuthStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// Device-local authentication which remains usable without internet access.
/// Passwords are stored only as salted PBKDF2-SHA256 hashes in Keychain or the
/// Android secure storage implementation.
class OfflineAuthRepository implements AuthRepository {
  OfflineAuthRepository(this._storage);

  static const _accountsKey = 'medisp.local_auth.accounts.v1';
  static const _sessionKey = 'medisp.local_auth.session.v1';
  static const _iterations = 210000;
  static const _derivedKeyLength = 32;
  static const _saltLength = 16;

  final AuthStorage _storage;
  final StreamController<AppUser?> _changes =
      StreamController<AppUser?>.broadcast();
  AppUser? _user;

  Future<void> initialize() async {
    final sessionId = await _storage.read(_sessionKey);
    if (sessionId == null) return;
    final account = (await _accounts()).where((item) => item.id == sessionId);
    if (account.isEmpty) {
      await _storage.delete(_sessionKey);
      return;
    }
    _user = account.single.user;
  }

  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> get authStateChanges => _changes.stream;

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = _normalizeEmail(email);
    final matches = (await _accounts())
        .where((account) => account.email == normalizedEmail);
    if (matches.isEmpty ||
        !_verifyPassword(password, matches.single.salt, matches.single.hash)) {
      throw StateError('อีเมลหรือรหัสผ่านไม่ถูกต้อง');
    }
    return _startSession(matches.single.user);
  }

  @override
  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final normalizedName = name.trim();
    final normalizedEmail = _normalizeEmail(email);
    if (normalizedName.length < 2 ||
        !normalizedEmail.contains('@') ||
        password.length < 8) {
      throw StateError('กรุณาตรวจสอบชื่อ อีเมล และรหัสผ่านอย่างน้อย 8 ตัว');
    }
    final accounts = await _accounts();
    if (accounts.any((account) => account.email == normalizedEmail)) {
      throw StateError('อีเมลนี้มีบัญชีในเครื่องแล้ว');
    }

    final salt = _randomBytes(_saltLength);
    final account = _LocalAccount(
      id: _newId(),
      email: normalizedEmail,
      displayName: normalizedName,
      salt: base64UrlEncode(salt),
      hash: base64UrlEncode(_derivePassword(password, salt)),
    );
    accounts.add(account);
    await _saveAccounts(accounts);
    return _startSession(account.user);
  }

  @override
  Future<void> resetPassword(String email) async {
    throw UnsupportedError('บัญชีออฟไลน์ไม่สามารถส่งลิงก์รีเซ็ตรหัสผ่านได้');
  }

  @override
  Future<void> signOut() async {
    await _storage.delete(_sessionKey);
    _user = null;
    _changes.add(null);
  }

  Future<AppUser> _startSession(AppUser user) async {
    await _storage.write(_sessionKey, user.id);
    _user = user;
    _changes.add(user);
    return user;
  }

  Future<List<_LocalAccount>> _accounts() async {
    final raw = await _storage.read(_accountsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((value) =>
              _LocalAccount.fromJson(Map<String, dynamic>.from(value as Map)))
          .toList();
    } on FormatException {
      throw StateError('ข้อมูลบัญชีในเครื่องเสียหาย');
    }
  }

  Future<void> _saveAccounts(List<_LocalAccount> accounts) => _storage.write(
      _accountsKey,
      jsonEncode(accounts.map((account) => account.toJson()).toList()));

  String _normalizeEmail(String email) => email.trim().toLowerCase();

  String _newId() => base64UrlEncode(_randomBytes(18)).replaceAll('=', '');

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(length, (_) => random.nextInt(256)));
  }

  Uint8List _derivePassword(String password, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _iterations, _derivedKeyLength));
    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }

  bool _verifyPassword(String password, String saltValue, String hashValue) {
    try {
      final expected = base64Url.decode(hashValue);
      final actual = _derivePassword(password, base64Url.decode(saltValue));
      if (actual.length != expected.length) return false;
      var difference = 0;
      for (var index = 0; index < actual.length; index++) {
        difference |= actual[index] ^ expected[index];
      }
      return difference == 0;
    } on FormatException {
      return false;
    }
  }
}

class _LocalAccount {
  const _LocalAccount({
    required this.id,
    required this.email,
    required this.displayName,
    required this.salt,
    required this.hash,
  });

  final String id;
  final String email;
  final String displayName;
  final String salt;
  final String hash;

  AppUser get user => AppUser(id: id, email: email, displayName: displayName);

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'display_name': displayName,
        'salt': salt,
        'hash': hash,
      };

  factory _LocalAccount.fromJson(Map<String, dynamic> json) => _LocalAccount(
        id: json['id'] as String,
        email: json['email'] as String,
        displayName: json['display_name'] as String,
        salt: json['salt'] as String,
        hash: json['hash'] as String,
      );
}
