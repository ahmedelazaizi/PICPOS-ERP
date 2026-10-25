// Turns an UNEXPECTED exception thrown below the warehouse routes into a
// stable, honest refusal (WH-005). Before this every such exception became a
// bare `500 internal`, which the phone treats as retryable, so one closed
// period or one unmapped account blocked the whole offline queue forever.
//
// Permanent, caused by the data/books  -> 4xx with a stable code. The phone
//                                         rejects the entry and shows why.
// Transient (locked database)           -> 503 `busy`; the phone retries.
// Anything else                         -> 500 `internal`; the phone retries a
//                                         bounded number of times, then parks
//                                         the entry for review.
//
// The exception TEXT is never returned: messages from the stock layer can
// carry quantities, and a blind counter must not learn them.
import 'wh_http.dart';

/// Phrases of the books' own refusals (`validateFinancialPeriod`, the stock
/// layer's account lookups). The lower layers throw plain `Exception`/
/// `StateError` with these Arabic messages; matching them here keeps the
/// ratcheted DAO files untouched.
const _periodClosed = [
  'فترة محاسبية مغلقة',
  'سنة مالية مغلقة',
  'لا توجد سنة مالية',
];
const _accountsNotMapped = [
  'غير مربوط',
  'غير مربوطة',
];

WhError classifyWhFailure(Object error) {
  if (error is WhError) return error;
  final text = '$error';
  if (_periodClosed.any(text.contains)) return WhError('period_closed', 409);
  if (_accountsNotMapped.any(text.contains)) return WhError('accounts_not_mapped', 409);
  final lower = text.toLowerCase();
  // SQLite: "UNIQUE constraint failed"; PostgreSQL: SQLSTATE 23505.
  if (lower.contains('unique constraint failed') || lower.contains('23505') || lower.contains('duplicate key value')) {
    return WhError('duplicate_document', 409);
  }
  if (lower.contains('database is locked') || lower.contains('sqlite_busy') || lower.contains('40001') ||
      lower.contains('40p01') || lower.contains('deadlock')) {
    return WhError('busy', 503);
  }
  return WhError('internal', 500);
}
