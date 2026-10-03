// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 — A-04: voucher deletion must reverse the voucher's GL entry
// (whichever referenceType posted it) AND fail-loud / roll back if it can't.
// ═══════════════════════════════════════════════════════════════════════════
//
// `deleteExpenseTransaction` (treasury_reports_dao.dart) used to:
//   (1) reverse ONLY referenceType 'payment_voucher' — so a RECEIPT voucher,
//       OR a payment voucher whose JE was posted by the AutoPostingService /
//       batchPostTreasury / purchase-autopost path (referenceType 'payment'
//       / 'receipt'), had its JE left LIVE on the books after delete; and
//   (2) swallow any reversal failure (debugPrint only) then soft-delete the
//       voucher anyway → the original JE stayed posted while the safe balance
//       was already rolled back → GL vs safes.balance drift, silently.
//
// Producers verified LIVE (referenceType, referenceId = safe_transaction.id):
//   • autoPostReceipt → 'receipt'          (accounting_autopost_dao.dart:1090,1128)
//   • autoPostPayment → 'payment'          (accounting_autopost_dao.dart:1238;
//                                            caller purchase_dao.dart:1194)
//   • _createVoucherJournalEntry (inline) → 'receipt_voucher'/'payment_voucher'
//                                            (treasury_dao.dart:1803)
//
// A04-1 (committee BLOCKER) — the inline producer posts its JE with
//   isAutoPosted=FALSE, but reverseAutoPostedJournalEntriesFor filtered
//   is_auto_posted=1. So the reversal never fired for the PRIMARY (interactive
//   POS/expense) voucher path, and the earlier version of this suite forged
//   isAutoPosted=true for the 'payment_voucher' case → a wrong-model tautology
//   that passed while the real path was broken. Cases C and D below now seed
//   the inline JE with isAutoPosted=FALSE (the real producer model), so they
//   fail against the pre-remediation reverser and pass only after it is
//   relaxed (requireAutoPosted:false) for the voucher-delete call.
//
// This suite pins the fix:
//   A) delete a PAYMENT voucher whose JE is under 'payment' (autopost,        → reversed, GL nets 0.
//      isAutoPosted=true).
//   B) delete a RECEIPT voucher whose JE is under 'receipt' (autopost,        → reversed, GL nets 0.
//      isAutoPosted=true) — the case the OLD hardcoded-'payment_voucher'
//      code missed entirely.
//   C) delete a PAYMENT voucher whose JE is under inline 'payment_voucher'    → reversed, GL nets 0.
//      with isAutoPosted=FALSE (the REAL interactive UI producer) — the A04-1
//      primary path.
//   D) fail-loud: an inline 'payment_voucher' (isAutoPosted=FALSE) whose      → whole delete rolls back
//      reversal hits a sealed period rolls the WHOLE delete back (voucher NOT
//      soft-deleted, safe balance unchanged, no reversal JE).
//
// Harness mirrors test/unit/journal_entry_reversal_by_id_test.dart
// (in-memory AppDatabase.forTesting + explicit seed of exactly what the
// writer needs; standalone mode so createJournalEntry attempts no sync).

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';
import 'package:ural_erp/services/network_service.dart';

void main() {
  late AppDatabase db;
  late int cashId; // asset  (1111)
  late int expenseId; // expense (5299)
  late int revenueId; // revenue (4111)

  setUp(() async {
    db = AppDatabase.forTesting();
    await _clearDatabase(db);
    await _seedFiscalYear(db);
    cashId = await _seedAccount(db, '1111', 'الصندوق', 'asset');
    expenseId = await _seedAccount(db, '5299', 'مصروفات متنوعة', 'expense');
    revenueId = await _seedAccount(db, '4111', 'المبيعات', 'revenue');
    // Standalone → no client/server sync attempt inside createJournalEntry.
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
  });

  tearDown(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    await db.close();
  });

  group('A-04 — reversal matches the producer referenceType', () {
    test('PAYMENT voucher (JE under "payment") is reversed → GL nets to zero',
        () async {
      final safeId = await _seedSafe(db, balance: 900); // after a 100 payment
      final txnId = await _seedVoucher(db,
          safeId: safeId,
          transactionType: 'payment',
          amount: 100,
          globalId: 'pv-payment-1',
          voucherNumber: 'PV-1');
      // Exactly how autoPostPayment stores it: referenceType 'payment',
      // referenceId = safe_transaction.id, isAutoPosted true.
      await _postVoucherJe(db,
          referenceType: 'payment',
          txnId: txnId,
          debitAccountId: expenseId,
          creditAccountId: cashId,
          amount: 100);

      // Sanity — the original posted and moved balances off zero.
      expect(await _bal(db, expenseId), closeTo(100, 1e-9));

      await db.deleteExpenseTransaction(txnId);

      // A balanced reversal exists under the matching void type.
      final reversals = await _reversalsOf(db, 'payment_void', txnId);
      expect(reversals, hasLength(1),
          reason: 'the "payment" JE must be reversed on delete');
      _expectBalanced(await _linesOf(db, reversals.single.id));

      // Net GL per account (post + reversal) is zero.
      expect(await _bal(db, expenseId), closeTo(0, 1e-9));
      expect(await _bal(db, cashId), closeTo(0, 1e-9));

      // Voucher soft-deleted, safe balance restored (+amount).
      expect((await _voucher(db, txnId)).deletedAt, isNotNull);
      expect(await _safeBal(db, safeId), closeTo(1000, 1e-9));
    });

    test('RECEIPT voucher (JE under "receipt") is reversed → GL nets to zero '
        '(old code hardcoded "payment_voucher" and missed this entirely)',
        () async {
      final safeId = await _seedSafe(db, balance: 500);
      final txnId = await _seedVoucher(db,
          safeId: safeId,
          transactionType: 'receipt',
          amount: 50,
          globalId: 'rv-receipt-1',
          voucherNumber: 'RV-1');
      // Exactly how autoPostReceipt stores it: referenceType 'receipt'.
      await _postVoucherJe(db,
          referenceType: 'receipt',
          txnId: txnId,
          debitAccountId: cashId,
          creditAccountId: revenueId,
          amount: 50);

      // Balances are raw signed (SUM(debit) − SUM(credit)); a credited revenue
      // account holds −50.
      expect(await _bal(db, revenueId), closeTo(-50, 1e-9));

      await db.deleteExpenseTransaction(txnId);

      final reversals = await _reversalsOf(db, 'receipt_void', txnId);
      expect(reversals, hasLength(1),
          reason: 'the "receipt" JE must be reversed on delete');
      _expectBalanced(await _linesOf(db, reversals.single.id));

      expect(await _bal(db, cashId), closeTo(0, 1e-9));
      expect(await _bal(db, revenueId), closeTo(0, 1e-9));
      expect((await _voucher(db, txnId)).deletedAt, isNotNull);
    });

    test('PAYMENT voucher (JE under inline "payment_voucher", '
        'isAutoPosted=FALSE — the REAL interactive UI producer) still reverses',
        () async {
      final safeId = await _seedSafe(db, balance: 700);
      final txnId = await _seedVoucher(db,
          safeId: safeId,
          transactionType: 'payment',
          amount: 30,
          globalId: 'pv-inline-1',
          voucherNumber: 'PV-2');
      // A04-1 — model the PRIMARY interactive path EXACTLY:
      // _createVoucherJournalEntry posts under 'payment_voucher' WITHOUT
      // isAutoPosted → false. The pre-remediation reverser filtered
      // is_auto_posted=1, so this row was skipped → NOTHING reversed and the
      // voucher was soft-deleted anyway (GL vs safes.balance drift). Seeding
      // isAutoPosted:false makes this test FAIL against the pre-remediation
      // code and PASS only once the reverser is relaxed for the voucher-delete
      // call (requireAutoPosted:false).
      await _postVoucherJe(db,
          referenceType: 'payment_voucher',
          txnId: txnId,
          debitAccountId: expenseId,
          creditAccountId: cashId,
          amount: 30,
          isAutoPosted: false);

      await db.deleteExpenseTransaction(txnId);

      final reversals = await _reversalsOf(db, 'payment_voucher_void', txnId);
      expect(reversals, hasLength(1));
      expect(await _bal(db, expenseId), closeTo(0, 1e-9));
      expect(await _bal(db, cashId), closeTo(0, 1e-9));
      expect((await _voucher(db, txnId)).deletedAt, isNotNull);
    });
  });

  group('A-04 — fail-loud: a failed reversal rolls back the whole delete', () {
    test('reversal JE that fails the period-lock rolls back the delete '
        '(voucher NOT deleted, safe balance unchanged, no reversal posted)',
        () async {
      final now = DateTime.now();
      // A month that is NOT the current month but is inside the same (open)
      // fiscal year — so the voucher itself sits in an OPEN period and the
      // delete's own validateFinancialPeriod(tx.createdAt) passes, while the
      // reversal (posted with date: DateTime.now()) hits the CLOSED current
      // month and throws inside createJournalEntry → the enclosing
      // transaction() must roll back the entire delete.
      final openMonth =
          now.month == 1 ? DateTime(now.year, 6, 15) : DateTime(now.year, 1, 15);

      final safeId = await _seedSafe(db, balance: 500);
      final txnId = await _seedVoucher(db,
          safeId: safeId,
          transactionType: 'payment',
          amount: 100,
          globalId: 'pv-rollback-1',
          voucherNumber: 'PV-3',
          createdAt: openMonth);
      // A04-1 — model the PRIMARY interactive path ('payment_voucher',
      // isAutoPosted=FALSE). This ALSO proves the fail-loud path is reached
      // for a real interactive voucher: pre-remediation the reverser filtered
      // is_auto_posted=1, skipped this row, threw NOTHING, and committed the
      // soft-delete (no rollback) → the `throwsA` below FAILS on the old code.
      // Only once the reverser is relaxed (requireAutoPosted:false) does the
      // reversal actually fire, hit the sealed current-month period, throw,
      // and roll the whole delete back. Original posts fine in the OPEN month.
      await _postVoucherJe(db,
          referenceType: 'payment_voucher',
          txnId: txnId,
          debitAccountId: expenseId,
          creditAccountId: cashId,
          amount: 100,
          date: openMonth,
          isAutoPosted: false);

      // Now seal the CURRENT month so the reversal (date == now) is rejected.
      await _closeCurrentMonthPeriod(db);

      // The delete must FAIL LOUD (rethrow), not swallow-and-commit.
      await expectLater(
        db.deleteExpenseTransaction(txnId),
        throwsA(isA<Object>()),
      );

      // Fully rolled back:
      // 1) voucher NOT soft-deleted.
      expect((await _voucher(db, txnId)).deletedAt, isNull,
          reason: 'delete must roll back — the voucher stays live');
      // 2) safe balance unchanged (the +amount adjust was rolled back).
      expect(await _safeBal(db, safeId), closeTo(500, 1e-9));
      // 3) no reversal JE was persisted.
      expect(await _reversalsOf(db, 'payment_voucher_void', txnId), isEmpty);
      // 4) the original JE is still intact (balance still off zero).
      expect(await _bal(db, expenseId), closeTo(100, 1e-9));
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

Future<int> _seedAccount(AppDatabase db, String code, String name, String type) {
  return db.into(db.accounts).insert(
        AccountsCompanion.insert(
          code: code,
          name: name,
          accountType: type,
          balance: const Value(0.0),
          isActive: const Value(true),
        ),
      );
}

Future<int> _seedSafe(AppDatabase db, {required double balance}) {
  return db.into(db.safes).insert(
        SafesCompanion.insert(
          name: 'خزينة اختبار',
          safeType: const Value('cash'),
          balance: Value(balance),
        ),
      );
}

Future<int> _seedVoucher(
  AppDatabase db, {
  required int safeId,
  required String transactionType,
  required double amount,
  required String globalId,
  required String voucherNumber,
  DateTime? createdAt,
}) {
  return db.into(db.safeTransactions).insert(
        SafeTransactionsCompanion.insert(
          voucherNumber: voucherNumber,
          safeId: safeId,
          transactionType: transactionType,
          category: 'expense',
          amount: amount,
          balanceAfter: 0.0,
          globalId: Value(globalId),
          createdAt:
              createdAt == null ? const Value.absent() : Value(createdAt),
        ),
      );
}

/// Posts a balanced 2-line JE exactly as the voucher producers do
/// (referenceType + referenceId = safe_transaction.id).
///
/// [isAutoPosted] must match the REAL producer:
///   • autoPostReceipt/autoPostPayment ('receipt'/'payment') → true
///   • inline _createVoucherJournalEntry ('receipt_voucher'/'payment_voucher')
///     → FALSE  (createJournalEntry is called WITHOUT isAutoPosted →
///     it defaults to false). Seeding the inline path with `true` was a
///     forged-flag tautology: the reversal used to filter is_auto_posted=1,
///     so a `true` seed made it pass while the real (false) row was skipped.
Future<int> _postVoucherJe(
  AppDatabase db, {
  required String referenceType,
  required int txnId,
  required int debitAccountId,
  required int creditAccountId,
  required double amount,
  DateTime? date,
  bool isAutoPosted = true,
}) {
  return db.createJournalEntry(
    description: 'قيد سند اختبار',
    date: date ?? DateTime.now(),
    lines: [
      JournalLine(accountId: debitAccountId, debit: amount),
      JournalLine(accountId: creditAccountId, credit: amount),
    ],
    referenceType: referenceType,
    referenceId: txnId,
    isAutoPosted: isAutoPosted,
  );
}

Future<double> _bal(AppDatabase db, int accountId) async {
  final a =
      await (db.select(db.accounts)..where((x) => x.id.equals(accountId)))
          .getSingle();
  return a.balance;
}

Future<double> _safeBal(AppDatabase db, int safeId) async {
  final s = await (db.select(db.safes)..where((x) => x.id.equals(safeId)))
      .getSingle();
  return s.balance;
}

Future<SafeTransactionData> _voucher(AppDatabase db, int txnId) {
  return (db.select(db.safeTransactions)..where((t) => t.id.equals(txnId)))
      .getSingle();
}

Future<List<JournalEntryData>> _reversalsOf(
    AppDatabase db, String voidType, int txnId) {
  return (db.select(db.journalEntries)
        ..where((e) =>
            e.referenceType.equals(voidType) & e.referenceId.equalsNullable(txnId)))
      .get();
}

Future<List<JournalEntryLine>> _linesOf(AppDatabase db, int entryId) {
  return (db.select(db.journalEntryLines)
        ..where((l) => l.entryId.equals(entryId)))
      .get();
}

void _expectBalanced(List<JournalEntryLine> lines) {
  final d = lines.fold<double>(0, (s, l) => s + l.debit);
  final c = lines.fold<double>(0, (s, l) => s + l.credit);
  expect(d, closeTo(c, 1e-9), reason: 'the reversal entry itself must balance');
}

Future<void> _clearDatabase(AppDatabase db) async {
  // forTesting() runs the full startup seed; wipe to a known baseline.
  // Children before parents so FK enforcement (if on) doesn't block.
  await db.delete(db.journalEntryLines).go();
  await db.delete(db.journalEntries).go();
  await db.delete(db.safeTransactions).go();
  await db.delete(db.safes).go();
  await db.delete(db.accountingPeriods).go();
  await db.delete(db.fiscalYears).go();
  await db.delete(db.accountMappings).go();
  // J3 — the seeded system parties («عميل نقدي»/«مورد نقدي») point at accounts.
  await db.update(db.parties).write(const PartiesCompanion(accountId: Value(null)));
  await db.delete(db.accounts).go();
  await db.delete(db.settings).go();
}

/// Fiscal year keyed off DateTime.now().year — the reversal posts with
/// date: DateTime.now(), so the seeded year must cover "today".
Future<int> _seedFiscalYear(AppDatabase db) {
  final now = DateTime.now();
  return db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          name: '${now.year}',
          startDate: DateTime(now.year, 1, 1),
          endDate: DateTime(now.year, 12, 31),
          isClosed: const Value(false),
        ),
      );
}

/// Seals the current calendar month so any JE dated now() is rejected by
/// validateFinancialPeriod — the injection point for the fail-loud test.
Future<void> _closeCurrentMonthPeriod(AppDatabase db) async {
  final now = DateTime.now();
  final fy = await db.select(db.fiscalYears).getSingle();
  await db.into(db.accountingPeriods).insert(
        AccountingPeriodsCompanion.insert(
          fiscalYearId: fy.id,
          name: 'فترة مغلقة ${now.month}/${now.year}',
          month: now.month,
          year: now.year,
          startDate: DateTime(now.year, now.month, 1),
          endDate: DateTime(now.year, now.month, 28),
          isClosed: const Value(true),
        ),
      );
}
