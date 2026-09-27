import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';
import 'package:ural_erp/domain/repositories/settings_repository.dart';
import 'package:ural_erp/services/inventory_service.dart';

class _StubSettingsRepo implements ISettingsRepository {
  @override
  Future<String?> getSetting(String key) async => null;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late int actorId;
  late int partyId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    final user = await (db.select(db.users)..limit(1)).getSingleOrNull();
    actorId = user?.id ?? await db.into(db.users).insert(
      UsersCompanion.insert(
        username: 'phase3-user-${DateTime.now().microsecondsSinceEpoch}',
        passwordHash: 'phase3-hash-a',
        displayName: 'Phase 3',
      ),
    );
    final party = await (db.select(db.parties)..limit(1)).getSingleOrNull();
    partyId = party?.id ?? await db.into(db.parties).insert(
      PartiesCompanion.insert(name: 'Phase 3 party'),
    );
  });

  tearDown(() => db.close());

  Future<int> account(String code, String name, String type) async {
    final existing = await db.getAccountByCode(code);
    return existing?.id ?? db.createAccount(
      code: code,
      name: name,
      accountType: type,
    );
  }

  Future<void> unmap(String purpose, String fallbackCode) async {
    await (db.delete(db.accountMappings)
          ..where((m) => m.purpose.equals(purpose) & m.costCenterId.isNull()))
        .go();
    final fallback = await db.getAccountByCode(fallbackCode);
    if (fallback != null) {
      await (db.update(db.accounts)..where((a) => a.id.equals(fallback.id))).write(
        AccountsCompanion(code: Value('X-$purpose')),
      );
    }
  }

  Future<List<JournalEntryData>> activeEntries(String type, int id) =>
      (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals(type) &
                e.referenceId.equals(id) &
                e.isPosted.equals(true) &
                e.isDeleted.equals(false)))
          .get();

  test('same paper status is a no-op without history or reposting', () async {
    final paperId = await db.into(db.commercialPapers).insert(
      CommercialPapersCompanion.insert(
        paperNumber: 'PHASE3-NOOP', type: 'cheque', direction: 'received',
        partyId: partyId, amount: 100, issueDate: DateTime.now(),
        dueDate: DateTime.now(), status: const Value('cashed'),
      ),
    );
    await db.changePaperStatus(
        paperId: paperId, newStatus: 'cashed', changedBy: actorId);
    final history = await (db.select(db.paperStatusHistory)
          ..where((h) => h.paperId.equals(paperId)))
        .get();
    expect(history, isEmpty);
  });

  test('cashed paper cannot move back to deposited', () async {
    final paperId = await db.into(db.commercialPapers).insert(
      CommercialPapersCompanion.insert(
        paperNumber: 'PHASE3-INVALID', type: 'cheque', direction: 'received',
        partyId: partyId, amount: 100, issueDate: DateTime.now(),
        dueDate: DateTime.now(), status: const Value('cashed'),
      ),
    );
    await expectLater(
      db.changePaperStatus(
          paperId: paperId, newStatus: 'deposited', changedBy: actorId),
      throwsA(isA<StateError>()),
    );
  });

  test('unmapped inventory account rejects bond without changing stock or cost', () async {
    final warehouse = (await db.getDefaultWarehouse())!;
    final productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'PH3-INV-${DateTime.now().microsecondsSinceEpoch}',
      name: 'Phase 3 inventory',
      costPrice: const Value(7),
      trackInventory: const Value(true),
    ));
    await unmap('inventory', '1136');
    await expectLater(
      InventoryService(db, _StubSettingsRepo()).createAddingBond(
        warehouseId: warehouse.id,
        items: [InventoryBondItemsCompanion.insert(
          bondId: 0, productId: productId, quantity: 2, unitCost: const Value(10),
        )],
      ),
      throwsA(isA<StateError>()),
    );
    final product = await db.getProductById(productId);
    expect(product!.currentStock, 0);
    expect(product.costPrice, 7);
    expect(await (db.select(db.inventoryBalances)
          ..where((b) => b.productId.equals(productId)))
        .get(), isEmpty);
  });

  test('negative issue bond credits inventory account', () async {
    final warehouse = (await db.getDefaultWarehouse())!;
    final productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'PH3-ISSUE-${DateTime.now().microsecondsSinceEpoch}',
      name: 'Phase 3 issue', trackInventory: const Value(true),
    ));
    await InventoryService(db, _StubSettingsRepo()).createAddingBond(
      warehouseId: warehouse.id,
      items: [InventoryBondItemsCompanion.insert(
        bondId: 0, productId: productId, quantity: 2, unitCost: const Value(10),
      )],
    );
    final bondId = await InventoryService(db, _StubSettingsRepo()).createAddingBond(
      warehouseId: warehouse.id,
      items: [InventoryBondItemsCompanion.insert(
        bondId: 0, productId: productId, quantity: -2, unitCost: const Value(10),
      )],
    );
    final inventory = (await db.getAccountByPurpose('inventory'))!;
    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.isInQuery(db.selectOnly(db.journalEntries)
            ..addColumns([db.journalEntries.id])
            ..where(db.journalEntries.referenceType.equals('inventory_bond') &
                db.journalEntries.referenceId.equals(bondId)))))
        .get();
    expect(lines.any((l) => l.accountId == inventory.id && l.credit == 20), isTrue);
  });

  test('shift close posts variance, closes, and unmapped shortage reopens', () async {
    final safe = (await db.getDefaultSafeByType('cash'))!;
    await db.setSetting('pos_cash_safe_id', '${safe.id}');
    final shiftId = await db.openShift(actorId, 100);
    await db.closeShiftWithAudit(shiftId, 90);
    var shift = await (db.select(db.shifts)..where((s) => s.id.equals(shiftId))).getSingle();
    expect(shift.status, 'closed');
    expect(shift.variance, -10);
    final entries = await activeEntries('shift_close', shiftId);
    expect(entries, hasLength(1));
    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(entries.single.id))).get();
    expect(lines.fold<double>(0, (s, l) => s + l.debit), 10);
    expect(lines.fold<double>(0, (s, l) => s + l.credit), 10);

    final failedShiftId = await db.openShift(actorId, 100);
    await unmap('cash_shortage', '6217');
    await expectLater(db.closeShiftWithAudit(failedShiftId, 90), throwsA(anything));
    shift = await (db.select(db.shifts)..where((s) => s.id.equals(failedShiftId))).getSingle();
    expect(shift.status, 'open');
  });

  test('issued to cashed is allowed and bounced deposited cashed stays balanced', () async {
    final issuedId = await db.into(db.commercialPapers).insert(
      CommercialPapersCompanion.insert(
        paperNumber: 'PH3-ISSUED', type: 'cheque', direction: 'issued',
        partyId: partyId, amount: 25, issueDate: DateTime.now(),
        dueDate: DateTime.now(), status: const Value('issued'),
      ),
    );
    await db.changePaperStatus(paperId: issuedId, newStatus: 'cashed', changedBy: actorId);
    final receivedId = await db.into(db.commercialPapers).insert(
      CommercialPapersCompanion.insert(
        paperNumber: 'PH3-BOUNCED', type: 'cheque', direction: 'received',
        partyId: partyId, amount: 25, issueDate: DateTime.now(),
        dueDate: DateTime.now(), status: const Value('bounced'),
      ),
    );
    await db.changePaperStatus(paperId: receivedId, newStatus: 'deposited', changedBy: actorId);
    await db.changePaperStatus(paperId: receivedId, newStatus: 'cashed', changedBy: actorId);
    final result = await db.customSelect(
      'SELECT SUM(l.debit) AS debit, SUM(l.credit) AS credit '
      'FROM journal_entry_lines l JOIN journal_entries e ON e.id=l.entry_id '
      'WHERE e.is_posted=1 AND e.is_deleted=0',
      readsFrom: {db.journalEntryLines, db.journalEntries},
    ).getSingle();
    expect((result.data['debit'] as num).toDouble(), closeTo((result.data['credit'] as num).toDouble(), 0.01));
  });

  test('endorsement JE uses endorsed-to party account', () async {
    final originalAccount = await account('PH3-ORIG', 'Original party', 'asset');
    final endorsedAccount = await account('PH3-END', 'Endorsed party', 'liability');
    final originalParty = await db.into(db.parties).insert(PartiesCompanion.insert(
      name: 'Original', accountId: Value(originalAccount),
    ));
    final endorsedParty = await db.into(db.parties).insert(PartiesCompanion.insert(
      name: 'Endorsed', accountId: Value(endorsedAccount),
    ));
    final paperId = await db.into(db.commercialPapers).insert(
      CommercialPapersCompanion.insert(
        paperNumber: 'PH3-ENDORSE', type: 'cheque', direction: 'received',
        partyId: originalParty, amount: 30, issueDate: DateTime.now(),
        dueDate: DateTime.now(), status: const Value('pending'),
      ),
    );
    await db.changePaperStatus(
      paperId: paperId, newStatus: 'endorsed', changedBy: actorId,
      endorsedToPartyId: endorsedParty,
    );
    final entries = await activeEntries('commercial_paper', paperId);
    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(entries.last.id))).get();
    expect(lines.any((l) => l.accountId == endorsedAccount), isTrue);
    expect(lines.any((l) => l.accountId == originalAccount), isFalse);
  });

  test('reconciliation requires adjustment account and posts absolute difference', () async {
    final bankId = await account('PH3-BANK', 'Phase 3 bank', 'asset');
    final adjustmentId = await account('PH3-ADJ', 'Phase 3 adjustment', 'expense');
    final missingId = await db.createReconciliation(
      bankAccountId: bankId, periodStart: DateTime(2026, 1, 1),
      periodEnd: DateTime(2026, 1, 31), statementBalance: 40,
    );
    await expectLater(db.completeReconciliation(missingId), throwsA(isA<StateError>()));
    final stillOpen = await (db.select(db.bankReconciliations)..where((r) => r.id.equals(missingId))).getSingle();
    expect(stillOpen.status, isNot('completed'));

    final reconId = await db.createReconciliation(
      bankAccountId: bankId, periodStart: DateTime(2026, 2, 1),
      periodEnd: DateTime(2026, 2, 28), statementBalance: 40,
    );
    await db.completeReconciliation(reconId, adjustmentAccountId: adjustmentId);
    final recon = await (db.select(db.bankReconciliations)..where((r) => r.id.equals(reconId))).getSingle();
    expect(recon.status, 'completed');
    final entry = (await activeEntries('bank_reconciliation', reconId)).single;
    final lines = await (db.select(db.journalEntryLines)..where((l) => l.entryId.equals(entry.id))).get();
    expect(lines.fold<double>(0, (s, l) => s + l.debit + l.credit) / 2, 40);
  });

  test('unmatching a statement line in completed reconciliation throws', () async {
    final bankId = await account('PH3-BANK-2', 'Phase 3 bank 2', 'asset');
    final statementId = await db.importBankStatementLines(
      bankAccountId: bankId, batchId: 'PH3', lines: [
        {'date': DateTime(2026, 3, 10), 'reference': 'R', 'credit': 10.0, 'balance': 10.0},
      ],
    ).then((_) async => (await db.getStatementLines(
      bankAccountId: bankId, from: DateTime(2026, 3, 1), to: DateTime(2026, 3, 31))).single.id);
    final reconId = await db.createReconciliation(
      bankAccountId: bankId, periodStart: DateTime(2026, 3, 1),
      periodEnd: DateTime(2026, 3, 31), statementBalance: 0,
    );
    await (db.update(db.bankStatementLines)..where((l) => l.id.equals(statementId))).write(
      const BankStatementLinesCompanion(isMatched: Value(true)));
    await db.completeReconciliation(reconId);
    await expectLater(db.unmatchStatement(statementId), throwsA(isA<StateError>()));
  });

  test('auto-match prefers exact reference over nearer date', () async {
    final bankId = await account('PH3-BANK-3', 'Phase 3 bank 3', 'asset');
    final cashId = await account('PH3-CASH-3', 'Phase 3 cash', 'asset');
    await db.createJournalEntry(description: 'other', date: DateTime(2026, 4, 10), lines: [
      JournalLine(accountId: bankId, debit: 50), JournalLine(accountId: cashId, credit: 50),
    ]);
    await db.createJournalEntry(description: 'EXACT-REF', date: DateTime(2026, 4, 12), lines: [
      JournalLine(accountId: bankId, debit: 50), JournalLine(accountId: cashId, credit: 50),
    ]);
    await db.importBankStatementLines(bankAccountId: bankId, batchId: 'PH3-AUTO', lines: [
      {'date': DateTime(2026, 4, 10), 'reference': 'EXACT-REF', 'credit': 50.0, 'balance': 50.0},
    ]);
    expect(await db.autoMatchStatementLines(bankId), 1);
    final stmt = (await db.getUnmatchedStatementLines(bankId));
    expect(stmt, isEmpty);
    final matched = await (db.select(db.bankStatementLines)
          ..where((l) => l.bankAccountId.equals(bankId))).getSingle();
    final line = await (db.select(db.journalEntryLines)
          ..where((l) => l.id.equals(matched.matchedJournalLineId!))).getSingle();
    final entry = await (db.select(db.journalEntries)..where((e) => e.id.equals(line.entryId))).getSingle();
    expect(entry.description, startsWith('EXACT-REF'));
  });
}
