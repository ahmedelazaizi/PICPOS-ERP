// Feature 048 (v130) — Commercial-paper status change honours the
// caller-chosen contra-leg account.
//
// Field report (2026-05-13): cashier deposited a cheque via the status-
// change dialog, picked "1115 - البنك التجاري - ودائع" from the
// "الحساب المقابل" autocomplete, and saved. The cheque flipped to
// `deposited` correctly BUT دفتر الأستاذ on "1115 - البنك التجاري"
// showed nothing — the JE had silently landed on the default `bank`
// purpose account instead. Root cause was in
// `commercial_papers_dialogs.dart`: the selected account was appended
// to the notes string only; `updatePaperStatus` never received it; the
// DAO's `_autoPostPaperStatusChange` used hardcoded purposes-map
// `'cash'` / `'bank'` lookups for the contra leg.
//
// v130 threads `counterAccountId` end-to-end:
//   dialog → controller → repo.updatePaperStatus → DAO.changePaperStatus
//          → DAO._autoPostPaperStatusChange → JournalLine.accountId
// This test pins the DAO contract.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int customerPartyId;
  late int defaultBankAccountId;
  late int defaultCashAccountId;
  late int chosenBankAccountId;
  late int paperId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    // paper_status_history.changed_by FKs to users. These tests attribute the
    // change to a placeholder actor id 0; seed it so the FK resolves (the DAO's
    // _ensureValidActor guard now rejects an actor with no matching user).
    await db.into(db.users).insert(UsersCompanion.insert(
        id: const Value(0), username: 'usr0', passwordHash: 'x', displayName: 'U0'));

    customerPartyId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'عميل اختبار 048',
            isCustomer: const Value(true),
            globalId: const Value('gid-party-048'),
          ),
        );

    // Default bank account from the seeded chart (code 1113 per the
    // accountPurposes map's 'bank' entry).
    final defaultBank = await db.getAccountByCode('1113');
    defaultBankAccountId = defaultBank!.id;

    // Default cash account (code 1111 per the accountPurposes map's 'cash'
    // entry). Spec 136 (cf13866) made a DIRECT collection (pending→cashed)
    // clear to CASH, so the no-override / stale-override fallbacks land here.
    final defaultCash = await db.getAccountByCode('1111');
    defaultCashAccountId = defaultCash!.id;

    // The user-chosen "غير الافتراضي" bank account — mirror what the
    // field operator would pick from the autocomplete.
    chosenBankAccountId = await db.into(db.accounts).insert(
          AccountsCompanion.insert(
            code: '1115',
            name: 'البنك التجاري - ودائع',
            accountType: 'asset',
            globalId: const Value('gid-acct-048-chosen'),
          ),
        );

    paperId = await db.into(db.commercialPapers).insert(
          CommercialPapersCompanion.insert(
            paperNumber: 'CHK-048',
            type: 'cheque',
            direction: 'received',
            partyId: customerPartyId,
            amount: 100,
            issueDate: DateTime(2026, 5, 13, 10),
            dueDate: DateTime(2026, 6, 13),
            status: const Value('pending'),
            globalId: const Value('gid-paper-048'),
          ),
        );
  });

  tearDown(() => db.close());

  Future<JournalEntryLine?> findBankLegFor(int paperId) async {
    final je = await (db.select(db.journalEntries)
          ..where((j) =>
              j.referenceType.equals('commercial_paper') &
              j.referenceId.equals(paperId))
          ..orderBy([(j) => OrderingTerm.desc(j.id)])
          ..limit(1))
        .getSingleOrNull();
    if (je == null) return null;
    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(je.id)))
        .get();
    // The "cashed" transition's debit leg is the collection account
    // (bank/cash, paper.amount); the credit leg is notes_receivable.
    return lines.firstWhere(
      (l) => l.debit > 0,
      orElse: () => lines.first,
    );
  }

  // Spec 136 (cf13866) redefined 'deposited' as an intermediate "برسم التحصيل"
  // state that posts NO JE/safe movement — the treasury account is hit ONCE at
  // 'cashed'. These tests therefore exercise the counterAccountId contract on
  // the 'cashed' transition (where the override is honoured). A DIRECT
  // collection (pending→cashed, no deposit) clears to CASH, so the no-override /
  // stale-override fallbacks land on the default CASH account (1111).
  test('cashed transition without counterAccountId falls back to default '
      'cash purpose account (legacy behaviour preserved)', () async {
    await db.changePaperStatus(
      paperId: paperId,
      newStatus: 'cashed',
      changedBy: 0,
    );

    final cashLeg = await findBankLegFor(paperId);
    expect(cashLeg, isNotNull,
        reason: 'JE must be posted — DAO silently skipping was an '
            'earlier symptom (pre-purposes-map fix)');
    expect(cashLeg!.accountId, defaultCashAccountId,
        reason: 'no override → falls back to the purposes-map cash '
            'default (code 1111) for a direct counter collection');
    expect(cashLeg.debit, 100);
  });

  test('cashed transition WITH counterAccountId posts the JE on the '
      'chosen account, NOT the default — the v130 fix', () async {
    await db.changePaperStatus(
      paperId: paperId,
      newStatus: 'cashed',
      changedBy: 0,
      counterAccountId: chosenBankAccountId, // user picked "1115"
    );

    final bankLeg = await findBankLegFor(paperId);
    expect(bankLeg, isNotNull);
    expect(bankLeg!.accountId, chosenBankAccountId,
        reason: 'Feature 048 (v130) — JE contra leg honours the '
            'caller-chosen counterAccountId so دفتر الأستاذ on that '
            'account reflects the collection');
    expect(bankLeg.accountId, isNot(defaultBankAccountId),
        reason: 'override MUST replace the default, not append');
    expect(bankLeg.debit, 100);
  });

  test('cashed transition WITH counterAccountId posts on the chosen '
      'cash safe (not the default 1111)', () async {
    // Set up a non-default cash account the user might pick.
    final chosenCashId = await db.into(db.accounts).insert(
          AccountsCompanion.insert(
            code: '1112',
            name: 'صندوق العهد والمصروفات',
            accountType: 'asset',
            globalId: const Value('gid-acct-048-cash'),
          ),
        );

    await db.changePaperStatus(
      paperId: paperId,
      newStatus: 'cashed',
      changedBy: 0,
      counterAccountId: chosenCashId,
    );

    final cashLeg = await findBankLegFor(paperId);
    expect(cashLeg, isNotNull);
    expect(cashLeg!.accountId, chosenCashId);
  });

  test('stale counterAccountId silently falls back to default '
      '(robust against deleted/synced-away accounts)', () async {
    // Use an id that definitely does not exist in the local DB.
    const ghostId = 999999;

    await db.changePaperStatus(
      paperId: paperId,
      newStatus: 'cashed',
      changedBy: 0,
      counterAccountId: ghostId,
    );

    final cashLeg = await findBankLegFor(paperId);
    expect(cashLeg, isNotNull,
        reason: 'a stale counterAccountId must not block the JE from '
            'posting — fall back to the purposes default instead');
    expect(cashLeg!.accountId, defaultCashAccountId,
        reason: 'stale override → purposes-map default; a direct counter '
            'collection (pending→cashed) clears to CASH (1111)');
  });
}
