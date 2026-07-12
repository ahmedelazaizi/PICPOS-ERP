// Spec 133 — Cheque Receipt Voucher: Single Customer Credit (FR-013).
//
// Pre-flight COA validation that runs at save time, BEFORE the voucher
// transaction begins. If Notes Receivable is unmapped or the customer
// has no sub-account (and there is no Receivables Control fallback),
// abort the save with an Arabic StateError that names the missing
// piece. Voucher data is not persisted; no commercial paper is created;
// no partial state is left behind.
//
// Matches Spec 082's fail-loud philosophy: every accounting precondition
// is checked at the boundary so the operator sees a clear, actionable
// Arabic message instead of a silent zero-credit (which would be the
// failure mode if the post-Commit-A skip flags caused both the voucher
// path AND the autopost to skip their work without any signal).
//
// Used only from receipt_voucher_dialog._saveVoucher when the operator
// selected payment method = 'check'. Cash and bank-transfer flows do
// not need this — the existing per-arm warnMissing in the autopost
// handles their precondition checks.

import '../data/database/database.dart';

class ChequeReceiptPreflight {
  ChequeReceiptPreflight._();

  /// Throws [StateError] with an Arabic message when a prerequisite
  /// COA mapping is missing for cheque receipts.
  ///
  /// Checks performed (in order):
  /// 1. Notes Receivable account (purpose: `notes_receivable`) is
  ///    resolvable via the standard accounting-mapping resolver.
  /// 2. The customer's sub-account exists, OR Receivables Control
  ///    (purpose: `receivables`) is mapped as a fallback.
  ///
  /// The Discount Allowed account is NOT validated here — it's only
  /// needed when discount > 0, and the discount-only JE helper handles
  /// its absence as a silent skip (a weaker requirement).
  static Future<void> validate({
    required int customerPartyId,
    required AppDatabase db,
  }) async {
    final notesReceivableCode = await db.getMappedAccountCode(
      'notes_receivable',
      AccountingDao.accountPurposes['notes_receivable']!,
    );
    final notesReceivableAccount = await db.getAccountByCode(notesReceivableCode);
    if (notesReceivableAccount == null) {
      throw StateError(
        'حساب أوراق القبض غير مربوط في الدليل المحاسبي. '
        'يرجى مراجعة إعدادات الحسابات.',
      );
    }

    final party = await (db.select(db.parties)
          ..where((p) => p.id.equals(customerPartyId))
          ..limit(1))
        .getSingleOrNull();
    if (party == null) {
      throw StateError('العميل غير موجود. يرجى إعادة اختيار العميل.');
    }

    if (party.accountId != null) {
      final customerSubAccount = await db.getAccountById(party.accountId!);
      if (customerSubAccount != null) {
        return; // happy path — both prerequisites resolved
      }
    }

    // Customer has no sub-account — try the Receivables Control fallback.
    final receivablesCode = await db.getMappedAccountCode(
      'receivables',
      AccountingDao.accountPurposes['receivables']!,
    );
    final receivablesAccount = await db.getAccountByCode(receivablesCode);
    if (receivablesAccount == null) {
      throw StateError(
        'حساب العميل غير مربوط ولا يوجد حساب ذمم العملاء الرئيسي. '
        'يرجى مراجعة بطاقة العميل أو إعدادات الحسابات.',
      );
    }
  }
}
