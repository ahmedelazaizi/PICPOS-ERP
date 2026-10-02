import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Invoice signing with the SAME payload format as the desktop
/// `InvoiceIntegrityService._salesPayload` (lib/services/invoice_integrity_service.dart):
/// `number|ISO date|total|subtotal|discount|tax|paid|customer??0|user|paymentMethod`,
/// amounts with 4 decimals, HMAC-SHA256, `v2:` prefix.
///
/// The secret is per company (`companies.integrity_secret` in the cloud).
String salesIntegrityPayload({
  required String number,
  required DateTime date,
  required double total,
  required double subtotal,
  required double discount,
  required double tax,
  required double paid,
  required int? customerId,
  required int userId,
  required String paymentMethod,
}) =>
    [
      number,
      date.toIso8601String(),
      total.toStringAsFixed(4),
      subtotal.toStringAsFixed(4),
      discount.toStringAsFixed(4),
      tax.toStringAsFixed(4),
      paid.toStringAsFixed(4),
      (customerId ?? 0).toString(),
      userId.toString(),
      paymentMethod,
    ].join('|');

String signV2(String secret, String payload) =>
    'v2:${Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(payload))}';

/// Short form of a `v2:` hash printed on receipts (first 12 hex digits,
/// grouped by 4): enough to compare a paper copy with the stored hash.
String integrityShortHash(String? hash) {
  if (hash == null) return '';
  final hex = hash.startsWith('v2:') ? hash.substring(3) : hash;
  if (hex.length < 12) return hex;
  return '${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}';
}
