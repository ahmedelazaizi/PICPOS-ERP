import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal secret storage (FlutterSecureStorage on device, a map in tests).
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Android: values are encrypted with a key held in the Android Keystore
/// (flutter_secure_storage, not backed up off the device).
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

/// The SQLCipher passphrase of the local database: 256 random bits created
/// on first start, kept only in [SecretStore] (ARCHITECTURE-I §11).
class DatabaseKey {
  DatabaseKey(this.secrets, {Random? random}) : _random = random ?? Random.secure();
  final SecretStore secrets;
  final Random _random;
  static const storageKey = 'picpos_van.db_key.v1';

  Future<String> obtain() async {
    final existing = await secrets.read(storageKey);
    if (existing != null && existing.length == 64) return existing;
    final key = [for (var i = 0; i < 32; i++) _random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
    await secrets.write(storageKey, key);
    return key;
  }
}
