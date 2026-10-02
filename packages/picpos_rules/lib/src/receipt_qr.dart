/// QR code printed on a receipt — the desktop decision
/// `lib/domain/models/receipt_qr_decision.dart` (`resolveReceiptQr`) and the
/// JoFotara TLV builder (`JofotaraService.generateQrCode`).
/// - E-invoicing enabled: only the gateway's QR once the document is `valid`;
///   otherwise no QR (a registered taxpayer never prints a non-fiscal code).
/// - Not enabled: a readable non-fiscal payload (invoice, date, total,
///   company) plus the document reference, with the disclaimer
///   «ليس إيصالاً ضريبيّاً» printed under the code.
library;

import 'dart:convert';

enum ReceiptQrKind { none, fiscal, nonFiscal }

/// Printed under a non-fiscal QR so it is never taken for a tax receipt.
const kNonFiscalQrDisclaimer = 'ليس إيصالاً ضريبيّاً';

class ReceiptQr {
  const ReceiptQr({required this.kind, required this.payload, required this.disclaimer});
  final ReceiptQrKind kind;

  /// Empty when [kind] is [ReceiptQrKind.none].
  final String payload;

  /// Empty unless [kind] is [ReceiptQrKind.nonFiscal].
  final String disclaimer;
}

/// `yyyy-MM-dd HH:mm` (desktop `ReceiptSaleSummary.fromSale`).
String receiptQrDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// Desktop non-fiscal payload, extended with [reference] (the document's
/// cloud `globalId`, which identifies it uniquely across devices) when given.
String nonFiscalQrPayload({
  required String invoiceNumber,
  required DateTime issuedAt,
  required double total,
  required String companyName,
  String? reference,
}) =>
    'فاتورة: $invoiceNumber\n'
    'التاريخ: ${receiptQrDate(issuedAt)}\n'
    'الإجمالي: ${total.toStringAsFixed(2)}\n'
    'المنشأة: $companyName'
    '${reference == null || reference.isEmpty ? '' : '\nالمرجع: $reference'}';

ReceiptQr resolveReceiptQr({
  required bool eInvoiceEnabled,
  required String? submissionStatus,
  required String? gatewayQrCode,
  required String invoiceNumber,
  required DateTime issuedAt,
  required double total,
  required String companyName,
  String? reference,
}) {
  if (eInvoiceEnabled) {
    final qr = gatewayQrCode ?? '';
    if (submissionStatus == 'valid' && qr.isNotEmpty) {
      return ReceiptQr(kind: ReceiptQrKind.fiscal, payload: qr, disclaimer: '');
    }
    return const ReceiptQr(kind: ReceiptQrKind.none, payload: '', disclaimer: '');
  }
  return ReceiptQr(
    kind: ReceiptQrKind.nonFiscal,
    payload: nonFiscalQrPayload(
        invoiceNumber: invoiceNumber, issuedAt: issuedAt, total: total, companyName: companyName, reference: reference),
    disclaimer: kNonFiscalQrDisclaimer,
  );
}

/// JoFotara / ZATCA-style TLV QR (base64): tag 1 seller name, 2 tax number,
/// 3 date-time, 4 total incl. VAT, 5 VAT — one-byte tag and length, amounts
/// with [decimals] places (desktop `JofotaraService.generateQrCode`).
String jofotaraTlvQr({
  required String sellerName,
  required String sellerTrn,
  required String invoiceDate,
  required double totalAmount,
  required double vatAmount,
  int decimals = 2,
}) {
  final out = <int>[];
  void tlv(int tag, String value) {
    final bytes = utf8.encode(value);
    out
      ..add(tag)
      ..add(bytes.length)
      ..addAll(bytes);
  }

  tlv(1, sellerName);
  tlv(2, sellerTrn);
  tlv(3, invoiceDate);
  tlv(4, totalAmount.toStringAsFixed(decimals));
  tlv(5, vatAmount.toStringAsFixed(decimals));
  return base64Encode(out);
}
