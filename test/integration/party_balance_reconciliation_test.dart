/// Day-17 Integration Tests — getPartyBalanceMismatches()
///
/// Verifies per-party reconciliation between `parties.balance` (the card
/// balance updated by adjustPartyBalance / createSalesInvoice) and the
/// true GL balance computed as SUM(debit) − SUM(credit) across all posted,
/// non-deleted journal-entry lines on the party's dedicated sub-account.
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;
  late int counterpartAccountId; // cash / equity stand-in for JE balancing

  setUp(() async {
    db = AppDatabase.forTesting();

    // Insert a fiscal year so createJournalEntry works.
    await db.into(db.fiscalYears).insert(
      FiscalYearsCompanion.insert(
        name: '2026',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
      ),
    );

    // Insert a plain counterpart account (equity / cash stand-in).
    counterpartAccountId = await db.into(db.accounts).insert(
      AccountsCompanion.insert(
        code: 'TEST-CASH',
        name: 'Test Cash',
        accountType: 'asset',
        normalBalance: const Value('debit'),
      ),
    );
  });

  tearDown(() async => db.close());

  // ─────────────────────────────────────────────────────────────────────────
  // Helper: create a customer via insertParty (auto-creates sub-account)
  // ─────────────────────────────────────────────────────────────────────────
  Future<Party> createCustomer(String name) async {
    final id = await db.insertParty(
      PartiesCompanion.insert(
        name: name,
        isCustomer: const Value(true),
        isSupplier: const Value(false),
      ),
    );
    return (await (db.select(db.parties)
          ..where((p) => p.id.equals(id)))
        .getSingleOrNull())!;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helper: post a simple JE — DR partyAccount / CR counterpart
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> postDebitJe(int partyAccountId, double amount) async {
    await db.createJournalEntry(
      description: 'Test debit',
      date: DateTime(2026, 3, 1),
      lines: [
        JournalLine(accountId: partyAccountId, debit: amount),
        JournalLine(accountId: counterpartAccountId, credit: amount),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Test 1 — No mismatches when party is perfectly balanced
  // ─────────────────────────────────────────────────────────────────────────

  test('returns empty list when card balance matches GL balance', () async {
    final customer = await createCustomer('Balanced Customer');
    final accountId = customer.accountId!;

    // Post JE for 300 on the party sub-account
    await postDebitJe(accountId, 300);

    // Adjust card balance to match GL (300)
    await db.adjustPartyBalance(customer.id, 300);

    final mismatches = await db.getPartyBalanceMismatches();
    expect(mismatches, isEmpty,
        reason: 'card == GL — no mismatch expected');
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Test 2 — Mismatch detected when card balance drifts from GL
  // ─────────────────────────────────────────────────────────────────────────

  test('detects mismatch when card balance differs from GL', () async {
    final customer = await createCustomer('Drifted Customer');
    final accountId = customer.accountId!;

    // GL shows 500 (JE posted)
    await postDebitJe(accountId, 500);

    // Card shows only 300 — the 200 gap is the mismatch
    await db.adjustPartyBalance(customer.id, 300);

    final mismatches = await db.getPartyBalanceMismatches();
    expect(mismatches.length, 1);
    expect(mismatches.first.partyId, customer.id);
    expect(mismatches.first.cardBalance, closeTo(300, 0.01));
    expect(mismatches.first.glBalance,   closeTo(500, 0.01));
    expect(mismatches.first.delta,       closeTo(-200, 0.01),
        reason: 'delta = card − GL = 300 − 500 = −200');
    expect(mismatches.first.isBalanced,  false);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Test 3 — Party without linked accountId is excluded
  // ─────────────────────────────────────────────────────────────────────────

  test('excludes parties that have no linked GL account', () async {
    // Direct insert bypasses insertParty — no sub-account is created.
    await db.into(db.parties).insert(
      PartiesCompanion.insert(
        name: 'No-Account Party',
        isCustomer: const Value(true),
        isSupplier: const Value(false),
      ),
    );

    final mismatches = await db.getPartyBalanceMismatches();
    // The no-account party is not linked to any GL account so it cannot
    // appear in results regardless of its card balance.
    expect(mismatches, isEmpty,
        reason: 'party without accountId must be excluded');
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Test 4 — Deleted JEs are excluded from GL balance
  // ─────────────────────────────────────────────────────────────────────────

  test('excludes deleted journal entries from GL balance computation', () async {
    final customer = await createCustomer('Partial Delete Customer');
    final accountId = customer.accountId!;

    // Post two JEs: 100 (active) + 50 (then soft-deleted)
    await postDebitJe(accountId, 100);
    final deletedEntryId = await db.createJournalEntry(
      description: 'Will be deleted',
      date: DateTime(2026, 3, 2),
      lines: [
        JournalLine(accountId: accountId, debit: 50),
        JournalLine(accountId: counterpartAccountId, credit: 50),
      ],
    );

    // Soft-delete the second JE
    await (db.update(db.journalEntries)
          ..where((je) => je.id.equals(deletedEntryId)))
        .write(const JournalEntriesCompanion(isDeleted: Value(true)));

    // Card balance = 100 — matches only the live JE
    await db.adjustPartyBalance(customer.id, 100);

    final mismatches = await db.getPartyBalanceMismatches();
    expect(mismatches, isEmpty,
        reason: 'card (100) matches live GL (100) — deleted JE must be ignored');
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Test 5 — Multiple parties: only mismatched ones are returned
  // ─────────────────────────────────────────────────────────────────────────

  test('returns only the mismatched party when one is balanced and one is not',
      () async {
    // Party A — balanced
    final partyA = await createCustomer('Party A OK');
    await postDebitJe(partyA.accountId!, 200);
    await db.adjustPartyBalance(partyA.id, 200);

    // Party B — mismatched (GL=400, card=150)
    final partyB = await createCustomer('Party B BAD');
    await postDebitJe(partyB.accountId!, 400);
    await db.adjustPartyBalance(partyB.id, 150);

    final mismatches = await db.getPartyBalanceMismatches();
    expect(mismatches.length, 1);
    expect(mismatches.first.partyId, partyB.id);
    expect(mismatches.first.delta, closeTo(-250, 0.01));
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Test 6 — Custom tolerance parameter
  // ─────────────────────────────────────────────────────────────────────────

  test('tolerance parameter controls whether a specific party is surfaced',
      () async {
    final customer = await createCustomer('Gap Tolerance Customer');
    await postDebitJe(customer.accountId!, 200); // GL = 200
    await db.adjustPartyBalance(customer.id, 199); // card = 199, gap = 1.0

    // gap = 1.0 is ABOVE tolerance 0.5 → customer IS returned
    final above = await db.getPartyBalanceMismatches(tolerance: 0.5);
    expect(above.any((m) => m.partyId == customer.id), true,
        reason: 'gap 1.0 > tolerance 0.5 → must appear in results');

    // gap = 1.0 is BELOW tolerance 1.5 → customer is NOT returned
    final below = await db.getPartyBalanceMismatches(tolerance: 1.5);
    expect(below.any((m) => m.partyId == customer.id), false,
        reason: 'gap 1.0 < tolerance 1.5 → must not appear in results');
  });
}
