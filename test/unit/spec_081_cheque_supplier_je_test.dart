// ═══════════════════════════════════════════════════════════════════════════
// SPEC 081 — Supplier cheque payment: single JE, no duplicate AP debit
// ═══════════════════════════════════════════════════════════════════════════
//
// Pins the three defects fixed in commit 1e2e1dd:
//
//   Defect A — `paperType` must reach the server in the /api/expenses POST
//              body. Pre-fix it was stored in the outbox replay payload but
//              never on the wire, so the server posted a phantom Dr AP /
//              Cr Cash JE on top of the correct CP-side entry. Verified by
//              a source-string grep guard (cheaper than spinning up HTTP).
//
//   Defect B — server-side postExpense must pass `skipSafeTransaction` to
//              the DAO when paperType is cheque. Grep guard on the handler
//              source pins this.
//
//   Defect C — DAO's `adjustPartyBalance` call must live INSIDE the
//              `if (!skipSafeTransaction)` block. Two real-DB tests verify
//              both branches (cheque skips it, cash still runs it).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  group('Spec 081 — DAO: skipSafeTransaction also skips party balance (Defect C)', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting();
      await _clearDatabase(db);
      await _seedAccounts(db);
      await _seedFiscalYear(db);
      await _seedDefaultSafe(db, balance: 1000.0);
      await _seedSupplier(db, id: 1, balance: 0.0);
    });

    tearDown(() async {
      await db.close();
    });

    test('cheque path: skipSafeTransaction=true → no safe_tx, no JE, '
        'no party balance change', () async {
      await db.createPaymentVoucher(
        amount: 3.0,
        category: 'supplier_payment',
        description: 'تجريبي شيك',
        partyId: 1,
        safeId: 1,
        skipJournalEntry: true,
        skipSafeTransaction: true,
      );

      final txs = await db.select(db.safeTransactions).get();
      expect(txs, isEmpty,
          reason: 'Cheque path must not create a safe_transactions row');

      final jes = await db.select(db.journalEntries).get();
      expect(jes, isEmpty,
          reason: 'Cheque path must not create a payment-voucher JE — '
              'the commercial papers pipeline owns it');

      final supplier = await (db.select(db.parties)
            ..where((p) => p.id.equals(1)))
          .getSingle();
      expect(supplier.balance, 0.0,
          reason: 'parties.balance must stay untouched on cheque path. '
              'Pre-fix it was decremented here AND again by '
              '_cpApplyBalanceSideEffects, producing a 2× drift.');

      final safe = await (db.select(db.safes)..where((s) => s.id.equals(1)))
          .getSingle();
      expect(safe.balance, 1000.0,
          reason: 'No cash leaves a safe when a cheque is issued — '
              'clearing happens later (Spec 082).');
    });

    test('cash path: defaults intact — safe_tx + JE + party balance all run',
        () async {
      await db.createPaymentVoucher(
        amount: 100.0,
        category: 'supplier_payment',
        description: 'تجريبي نقدي',
        partyId: 1,
        safeId: 1,
        // No skip flags — full cash path.
      );

      final txs = await db.select(db.safeTransactions).get();
      expect(txs.length, 1,
          reason: 'Cash path must create the safe_transactions row');
      expect(txs.single.transactionType, 'payment');
      expect(txs.single.amount, 100.0);

      final jes = await db.select(db.journalEntries).get();
      expect(jes.length, 1,
          reason: 'Cash path must create the Dr AP / Cr Cash JE');

      final supplier = await (db.select(db.parties)
            ..where((p) => p.id.equals(1)))
          .getSingle();
      expect(supplier.balance, -100.0,
          reason: 'Cash path still reduces the supplier balance by the '
              'voucher amount — the move into the skip block must not '
              'regress non-cheque callers.');

      final safe = await (db.select(db.safes)..where((s) => s.id.equals(1)))
          .getSingle();
      expect(safe.balance, 900.0,
          reason: 'Cash path debits the safe by the voucher amount');
    });
  });

  group('Spec 081 — wire format grep guards (Defects A + B)', () {
    test('ServerProxy.submitExpense includes paperType in POST body '
        '(Defect A)', () {
      final src = File('lib/services/server_proxy.dart').readAsStringSync();

      // Locate the submitExpense method body — match its signature start to
      // the next blank-line break.
      final methodStart = src.indexOf('Future<int?> submitExpense({');
      expect(methodStart, isNot(-1),
          reason: 'submitExpense not found in server_proxy.dart');
      // 2000 chars is generous; the whole method is ~40 lines.
      final methodBody = src.substring(methodStart, methodStart + 2000);

      expect(methodBody, contains('String? paperType'),
          reason: 'submitExpense must accept a paperType parameter so the '
              'caller can flag cheque payments. Pre-Spec-081 this was '
              'missing and the server treated cheques as cash.');
      expect(methodBody, contains("'paperType': paperType"),
          reason: "The POST body must include 'paperType' so the server's "
              'postExpense handler can read it and skip the cash JE.');
    });

    test('cwi_commerce.createExpense forwards paperType to submitExpense '
        '(Defect A continued)', () {
      final src =
          File('lib/services/interceptor/cwi_commerce.dart').readAsStringSync();

      final methodStart = src.indexOf('static Future<int?> createExpense({');
      expect(methodStart, isNot(-1));
      // Bound by the next method (`deleteExpense`) so the window covers
      // the full body regardless of comment growth.
      final remaining = src.substring(methodStart);
      final methodEnd = remaining.indexOf('static Future<bool> deleteExpense(');
      expect(methodEnd, isNot(-1),
          reason: 'Could not bound createExpense — structure changed');
      final methodBody = remaining.substring(0, methodEnd);

      // Inside the serverCall closure we must pass paperType through.
      final serverCallIdx = methodBody.indexOf('serverCall:');
      expect(serverCallIdx, isNot(-1));

      expect(methodBody, contains('paperType: paperType'),
          reason: 'The serverCall closure must forward paperType to '
              'ServerProxy.submitExpense. Pre-fix it lived only in the '
              'outbox replay payload — never on the live wire.');
    });

    test('api_data_handler.postExpense passes skipSafeTransaction for cheque '
        '(Defect B)', () {
      final src = File('lib/services/api/api_data_handler.dart')
          .readAsStringSync();

      final methodStart = src.indexOf('Future<Response> postExpense(');
      expect(methodStart, isNot(-1));
      // The whole method is ~140 lines and rich with comments — use a
      // generous window so we cover every line until the matching `}`.
      final remaining = src.substring(methodStart);
      final methodEnd = remaining.indexOf('Future<Response> deleteExpense(');
      expect(methodEnd, isNot(-1),
          reason: 'Could not bound postExpense — handler structure changed');
      final methodBody = remaining.substring(0, methodEnd);

      expect(methodBody, contains('skipJournalEntry: isCheckPayment'),
          reason: 'Existing skip-JE behaviour must remain wired');
      expect(methodBody, contains('skipSafeTransaction: isCheckPayment'),
          reason: 'Without this, the server still inserts a phantom '
              'safe_transactions row for a cheque and decrements the '
              'safe balance, even though no cash physically leaves.');
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _clearDatabase(AppDatabase db) async {
  await db.delete(db.safeTransactions).go();
  await db.delete(db.journalEntryLines).go();
  await db.delete(db.journalEntries).go();
  await db.delete(db.accountingPeriods).go();
  await db.delete(db.fiscalYears).go();
  await db.delete(db.accountMappings).go();
  await db.delete(db.accounts).go();
  await db.delete(db.parties).go();
  await db.delete(db.safes).go();
}

Future<void> _seedAccounts(AppDatabase db) async {
  // Codes match AccountingDao.accountPurposes — needed even though the
  // cheque test asserts NO JE, because the cash regression test does
  // resolve the AP/Cash purpose pair when generating the voucher JE.
  final accounts = [
    {'code': '1111', 'name': 'الصندوق', 'type': 'asset'},
    {'code': '1113', 'name': 'البنك', 'type': 'asset'},
    {'code': '1121', 'name': 'ذمم مدينة', 'type': 'asset'},
    {'code': '1123', 'name': 'أوراق قبض', 'type': 'asset'},
    {'code': '2111', 'name': 'ذمم دائنة', 'type': 'liability'},
    {'code': '2113', 'name': 'أوراق دفع', 'type': 'liability'},
  ];
  for (final a in accounts) {
    await db.into(db.accounts).insert(
          AccountsCompanion.insert(
            code: a['code']!,
            name: a['name']!,
            accountType: a['type']!,
            balance: const Value(0.0),
          ),
        );
  }
}

Future<void> _seedFiscalYear(AppDatabase db) async {
  await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          id: const Value(1),
          name: '2026',
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 12, 31),
        ),
      );
  for (int m = 1; m <= 12; m++) {
    await db.into(db.accountingPeriods).insert(
          AccountingPeriodsCompanion.insert(
            fiscalYearId: 1,
            name: 'شهر $m - 2026',
            month: m,
            year: 2026,
            startDate: DateTime(2026, m, 1),
            endDate: DateTime(2026, m + 1, 0, 23, 59, 59),
          ),
        );
  }
}

Future<void> _seedDefaultSafe(AppDatabase db, {required double balance}) async {
  await db.into(db.safes).insert(
        SafesCompanion.insert(
          id: const Value(1),
          name: 'خزينة تجريبية',
          safeType: const Value('cash'),
          balance: Value(balance),
          isDefault: const Value(true),
          isActive: const Value(true),
        ),
      );
}

Future<void> _seedSupplier(AppDatabase db,
    {required int id, required double balance}) async {
  await db.into(db.parties).insert(
        PartiesCompanion.insert(
          id: Value(id),
          name: 'مورد تجريبي',
          isCustomer: const Value(false),
          isSupplier: const Value(true),
          balance: Value(balance),
        ),
      );
}
