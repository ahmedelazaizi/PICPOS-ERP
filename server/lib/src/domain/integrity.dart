import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Server-side invoice signing using the SAME payload format as the desktop
/// `InvoiceIntegrityService._salesPayload` (lib/services/invoice_integrity_service.dart):
/// `number|ISO date|total|subtotal|discount|tax|paid|customer??0|user|paymentMethod`,
/// amounts with 4 decimals, HMAC-SHA256, `v2:` prefix.
///
/// The secret is per company (`companies.integrity_secret`). Whether the desktop
/// shares this secret or re-signs on posting is an I-3 decision (ARCHITECTURE-I §7).
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
