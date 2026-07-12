import 'dart:convert';
import 'package:crypto/crypto.dart';

/// S02: Invoice Integrity Service — HMAC-SHA256 hash for tamper detection.
///
/// Computes a deterministic hash from immutable invoice fields.
/// This hash is stored alongside the invoice to detect any unauthorized
/// modifications to the financial data after creation.
class InvoiceIntegrityService {
  /// Secret key for HMAC — derived from app identity (not user-changeable)
  static const _secretKey = 'UralCash-ERP-Integrity-v1';

  /// Compute integrity hash for a sales invoice.
  ///
  /// The hash is computed from:
  /// - Invoice number
  /// - Invoice date (ISO string)
  /// - Total amount
  /// - Subtotal
  /// - Discount
  /// - Tax
  /// - Paid amount
  /// - Customer ID (or 0)
  /// - User ID
  /// - Payment method
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
  }) {
    final payload = [
      invoiceNumber,
      invoiceDate.toIso8601String(),
      total.toStringAsFixed(4),
      subtotal.toStringAsFixed(4),
      discount.toStringAsFixed(4),
      tax.toStringAsFixed(4),
      paid.toStringAsFixed(4),
      (customerId ?? 0).toString(),
      userId.toString(),
      paymentMethod,
    ].join('|');

    return _computeHmac(payload);
  }

  /// Compute integrity hash for a purchase invoice.
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

    return _computeHmac(payload);
  }

  /// Verify an existing hash against current invoice data.
  /// Returns true if the data hasn't been tampered with.
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
    final computed = computeSalesInvoiceHash(
      invoiceNumber: invoiceNumber,
      invoiceDate: invoiceDate,
      total: total,
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      paid: paid,
      customerId: customerId,
      userId: userId,
      paymentMethod: paymentMethod,
    );
    return computed == storedHash;
  }

  /// Verify an existing hash against current purchase invoice data.
  /// Returns true if the data hasn't been tampered with.
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
    final computed = computePurchaseInvoiceHash(
      invoiceNumber: invoiceNumber,
      invoiceDate: invoiceDate,
      total: total,
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      paid: paid,
      supplierId: supplierId,
      paymentMethod: paymentMethod,
    );
    return computed == storedHash;
  }

  /// Internal HMAC-SHA256 computation
  static String _computeHmac(String payload) {
    final key = utf8.encode(_secretKey);
    final bytes = utf8.encode(payload);
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(bytes);
    return digest.toString();
  }
}
