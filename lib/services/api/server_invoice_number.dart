// R4 — server-side invoice-number collision handling.
//
// The server prefixes client numbers with the BRANCH code only (BR-POS-1), so
// two terminals of one branch (different globalIds) that both issued POS-1
// arrive with the same number. There is no UNIQUE index on invoice_number, so
// on receipt we hand the later arrival the next free number in the same prefix
// (MAX numeric tail + 1). The same globalId is never re-numbered — the
// globalId dedup in postSale returns the existing invoice first.
import 'package:drift/drift.dart';

import '../../core/logging/diagnostic_logger.dart';
import '../../data/database/database.dart';

/// Splits `BR-POS-12` into prefix `BR-POS-` and tail 12; null if no numeric
/// tail after a `-`.
({String prefix, int tail})? splitInvoiceNumber(String number) {
  final i = number.lastIndexOf('-');
  if (i < 0 || i == number.length - 1) return null;
  final tail = int.tryParse(number.substring(i + 1));
  if (tail == null || tail < 0) return null;
  return (prefix: number.substring(0, i + 1), tail: tail);
}

/// Returns the number to store for an incoming sale.
///
/// [desired] unchanged when no invoice with another globalId holds it.
/// Otherwise `<prefix><MAX+1>`. MUST run inside the insert transaction so the
/// read and the insert are atomic.
Future<String?> resolveServerInvoiceNumber(
  AppDatabase db, {
  required String? desired,
  required String? globalId,
}) async {
  if (desired == null || desired.isEmpty) return desired;
  final parts = splitInvoiceNumber(desired);
  if (parts == null) return desired;

  final rows = await (db.select(db.salesInvoices)
        ..where((s) => s.invoiceNumber.like('${parts.prefix}%')))
      .get();
  var max = parts.tail;
  var taken = false;
  for (final r in rows) {
    final p = splitInvoiceNumber(r.invoiceNumber);
    if (p == null || p.prefix != parts.prefix) continue;
    if (p.tail > max) max = p.tail;
    if (r.invoiceNumber == desired && r.globalId != globalId) taken = true;
  }
  if (!taken) return desired;

  final reassigned = '${parts.prefix}${max + 1}';
  await DiagnosticLogger.log('API-SALE',
      '⚠ invoice_number_reassigned: $desired taken by another globalId '
      '(incoming=$globalId) → $reassigned');
  return reassigned;
}
