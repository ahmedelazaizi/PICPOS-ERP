// Spec 133 — Cheque Receipt Voucher: Single Customer Credit (FR-010 helper).
//
// When a cheque receipt voucher also carries a settlement discount or a
// delivery-company commission, the discount portion needs its own journal
// entry: the cash-leg JE that would normally carry the discount line
// (`Dr Discount Allowed`) is skipped for cheques to prevent the
// double-customer-credit bug observed on build 3.1.0+202. The commercial-
// papers `pending` autopost handles the cheque amount itself; this helper
// handles ONLY the discount portion so the customer's outstanding balance
// ends up at the same net as a cash receipt would produce.
//
// Symmetric with the cash-receipt path in accounting_autopost_dao.dart
// (around line 836–878), where the discount line rides INSIDE the same
// voucher JE. Here it rides as a standalone JE because the voucher JE no
// longer exists for cheques.
//
// Called from two sites:
//   • treasury_repository_impl.dart::createReceiptVoucher (standalone +
//     client local-fallback path)
//   • api_data_handler.dart::postReceipt (server-side handler — the
//     server runs the same DAO so it needs the same follow-up)
//
// Keeping the helper in its own file avoids duplicating the body and
// gives the symmetry guard test (FR-012) a single grep target.

import '../data/database/database.dart';
import '../domain/entities/accounting_entities.dart';

class ChequeReceiptJEs {
  ChequeReceiptJEs._();

  /// Post `Dr: Discount Allowed / Cr: Customer Sub-Account` for the
  /// discount portion of a cheque receipt voucher.
  ///
  /// Also adjusts `parties.balance` by `-discountAmount`, since the
  /// cash-leg path that would normally do this is skipped for cheques
  /// (see `treasury_dao.dart::createReceiptVoucher` Spec 133 block).
  ///
  /// No-op when `discountAmount <= 0`. When the COA mapping for
  /// `discount_allowed` or `receivables` is missing, the helper silently
  /// returns without posting — the pre-flight check (FR-013) is the
  /// fail-loud surface for missing mappings; reaching here means the
  /// pre-flight already passed for Notes Receivable + customer
  /// sub-account, and Discount Allowed mapping is a strictly weaker
  /// requirement (commission/discount is an optional accounting refinement).
  static Future<void> postDiscountAllowedJournalEntry({
    required AppDatabase db,
    required int partyId,
    required double discountAmount,
    int? costCenterId,
    int? branchId,
  }) async {
    if (discountAmount <= 0) return;

    final discountCode = await db.getMappedAccountCode(
      'discount_allowed',
      AccountingDao.accountPurposes['discount_allowed']!,
    );
    final discountAccount = await db.getAccountByCode(discountCode);
    if (discountAccount == null) return;

    Account? customerAccount;
    final party = await (db.select(db.parties)
          ..where((p) => p.id.equals(partyId))
          ..limit(1))
        .getSingleOrNull();
    if (party?.accountId != null) {
      customerAccount = await db.getAccountById(party!.accountId!);
    }
    customerAccount ??= await db.getAccountByCode(
      await db.getMappedAccountCode(
        'receivables',
        AccountingDao.accountPurposes['receivables']!,
      ),
    );
    if (customerAccount == null) return;

    await db.createJournalEntry(
      description: 'خصم معجل دفع - سند قبض بشيك',
      date: DateTime.now(),
      lines: [
        JournalLine(
          accountId: discountAccount.id,
          debit: discountAmount,
          credit: 0,
          description: 'خصم مسموح به',
        ),
        JournalLine(
          accountId: customerAccount.id,
          debit: 0,
          credit: discountAmount,
          description: 'تسوية عميل',
        ),
      ],
      referenceType: 'receipt_voucher_discount',
      isAutoPosted: true,
      costCenterId: costCenterId,
      branchId: branchId,
    );

    await db.adjustPartyBalance(partyId, -discountAmount);
  }
}
