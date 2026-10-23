import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/logging/diagnostic_logger.dart';
import 'legacy_identifiers.dart';
import 'security_service.dart';
import 'storage_key_migration.dart';

/// Computes invoice integrity signatures with a per-install secret.
class InvoiceIntegrityService {
  /// HMAC key of the legacy (pre-v2) signatures already stored on invoices.
  /// Byte-identical to the previous literal (pinned by a test); assembled at
  /// runtime so the old product name is not in the binary.
  static String get _legacySecretKey => LegacyIdentifiers.integritySalt;
  static const _secretSetting = 'invoice_integrity_secret_v2';
  static String? _installSecret;

  static const _secretStorageKey = 'picpos_invoice_integrity_secret_v2';

  /// Loads the per-install secret from device-local secure storage.
  /// The callbacks remain available for unit tests; production never stores
  /// this secret in the synced settings table.
  static Future<void> initialize({
    Future<String?> Function(String key)? readSetting,
    Future<void> Function(String key, String value)? writeSetting,
    FlutterSecureStorage? storage,
  }) async {
    try {
      final secureStorage = storage;
      final stored = secureStorage != null
          ? await StorageKeyMigration.read(
              FlutterSecureSecretStore(secureStorage),
              newKey: _secretStorageKey,
              oldKey: LegacyIdentifiers.integritySecretStorageKey,
            )
          : await readSetting!(_secretSetting);
      if (stored != null && stored.isNotEmpty) {
        _installSecret = stored;
        return;
      }
      final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
      final generated = base64Url.encode(bytes);
      if (secureStorage != null) {
        await secureStorage.write(key: _secretStorageKey, value: generated);
      } else {
        await writeSetting!(_secretSetting, generated);
      }
      _installSecret = generated;
    } catch (error, stack) {
      if (error is DatabaseKeyUnavailableException) rethrow;
      _installSecret = null;
      await DiagnosticLogger.logError('INVOICE_INTEGRITY',
          'secure secret initialization failed', error, stack);
    }
  }

  static String computeSalesInvoiceHash({
    required String invoiceNumber,
    required DateTime invoiceDate,
    required double total,
    required double subtotal,
    required double discount,
    required double tax,
    required double paid,
    required int? customerId,
    required int userId,
    required String paymentMethod,
  }) => _computeHash(_salesPayload(
        invoiceNumber,
        invoiceDate,
        total,
        subtotal,
        discount,
        tax,
        paid,
        customerId,
        userId,
        paymentMethod,
      ));

  static String computePurchaseInvoiceHash({
    required String invoiceNumber,
    required DateTime invoiceDate,
    required double total,
    required double subtotal,
    required double discount,
    required double tax,
    required double paid,
    required int supplierId,
    required String paymentMethod,
  }) => _computeHash([
        invoiceNumber,
        invoiceDate.toIso8601String(),
        total.toStringAsFixed(4),
        subtotal.toStringAsFixed(4),
        discount.toStringAsFixed(4),
        tax.toStringAsFixed(4),
        paid.toStringAsFixed(4),
        supplierId.toString(),
        paymentMethod,
      ].join('|'));

  static bool verifySalesInvoiceHash({
    required String storedHash,
    required String invoiceNumber,
    required DateTime invoiceDate,
    required double total,
    required double subtotal,
    required double discount,
    required double tax,
    required double paid,
    required int? customerId,
    required int userId,
    required String paymentMethod,
  }) {
    final payload = _salesPayload(invoiceNumber, invoiceDate, total, subtotal,
        discount, tax, paid, customerId, userId, paymentMethod);
    return _verify(storedHash, payload);
  }

  static bool verifyPurchaseInvoiceHash({
    required String storedHash,
    required String invoiceNumber,
    required DateTime invoiceDate,
    required double total,
    required double subtotal,
    required double discount,
    required double tax,
    required double paid,
    required int supplierId,
    required String paymentMethod,
  }) {
    final payload = [
      invoiceNumber,
      invoiceDate.toIso8601String(),
      total.toStringAsFixed(4),
      subtotal.toStringAsFixed(4),
      discount.toStringAsFixed(4),
      tax.toStringAsFixed(4),
      paid.toStringAsFixed(4),
      supplierId.toString(),
      paymentMethod,
    ].join('|');
    return _verify(storedHash, payload);
  }

  static String _salesPayload(String number, DateTime date, double total,
      double subtotal, double discount, double tax, double paid, int? party,
      int user, String payment) => [
        number,
        date.toIso8601String(),
        total.toStringAsFixed(4),
        subtotal.toStringAsFixed(4),
        discount.toStringAsFixed(4),
        tax.toStringAsFixed(4),
        paid.toStringAsFixed(4),
        (party ?? 0).toString(),
        user.toString(),
        payment,
      ].join('|');

  static String _computeHash(String payload) {
    final secret = _installSecret;
    if (secret == null) {
      // Test and recovery callers may sign before startup initialization. Keep
      // the fallback in the legacy format so verification remains consistent;
      // production startup always initializes the per-install v2 secret first.
      return Hmac(sha256, utf8.encode(_legacySecretKey))
          .convert(utf8.encode(payload))
          .toString();
    }
    return 'v2:${Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(payload))}';
  }

  static bool _verify(String stored, String payload) {
    if (stored.startsWith('v2:')) {
      if (_installSecret == null) return false;
      return stored == _computeHash(payload);
    }
    final legacy = Hmac(sha256, utf8.encode(_legacySecretKey))
        .convert(utf8.encode(payload))
        .toString();
    return stored == legacy;
  }
}
