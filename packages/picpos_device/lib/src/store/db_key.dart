import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal secret storage (Keystore on device, a map in tests).
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Android: values encrypted with a key held in the Android Keystore
/// (flutter_secure_storage; not backed up off the device).
class KeystoreSecretStore implements SecretStore {
  KeystoreSecretStore([FlutterSecureStorage? s]) : _s = s ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// The SQLCipher passphrase: 256 random bits created on first start, kept
/// only in [SecretStore] (copied from mobile/lib/data/db_key.dart with a
/// per-app [storageKey]).
class DatabaseKey {
  DatabaseKey(this.secrets, {required this.storageKey, Random? random}) : _random = random ?? Random.secure();
  final SecretStore secrets;

  /// e.g. `picpos_pos.db_key.v1`.
  final String storageKey;
  final Random _random;

  Future<String> obtain() async {
    final existing = await secrets.read(storageKey);
    if (existing != null && existing.length == 64) return existing;
    final key = [for (var i = 0; i < 32; i++) _random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
    await secrets.write(storageKey, key);
    return key;
  }
}
