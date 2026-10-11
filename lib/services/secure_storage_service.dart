import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db_key_names.dart';

/// Service for handling sensitive data using hardware-backed secure storage.
class SecureStorageService {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Read a value from secure storage
  Future<String?> read(String key) async {
    return _storage.read(key: key);
  }

  /// Write a value to secure storage
  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  /// Delete a value from secure storage
  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  /// Clear all values from secure storage (use with caution).
  ///
  /// ⚠️ **لا يمحو مفاتيح قاعدة البيانات** (`db_key_*` ورمز الاسترداد والمفتاح
  /// الاحتياطيّ القديم): محوُها يفقد القاعدةَ المشفّرة نهائيًّا (E-01).
  /// لذلك لا `deleteAll()` — نمرّ على المفاتيح ونحذف ما عدا المحميّ.
  Future<void> clearAll() async {
    final all = await _storage.readAll();
    for (final key in all.keys.toList()) {
      if (DbKeyNames.isProtected(key)) continue;
      await _storage.delete(key: key);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // E-INVOICING CREDENTIALS
  // ═══════════════════════════════════════════════════════════════════════

  static String _einvoiceSecretKey(String platform) => 'e_invoice_secret_$platform';

  /// Save e-invoice client secret securely
  Future<void> setEInvoiceSecret(String platform, String secret) async {
    await write(_einvoiceSecretKey(platform), secret);
  }

  /// Retrieve e-invoice client secret
  Future<String?> getEInvoiceSecret(String platform) async {
    return read(_einvoiceSecretKey(platform));
  }
}

/// Provider for SecureStorageService
final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});
