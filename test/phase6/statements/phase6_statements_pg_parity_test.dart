// ignore_for_file: avoid_print
@Tags(['pg'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';

import '../../integration_pg/_support/pg_fixture.dart';

void main() {
  test('PG matches SQLite depreciation, cash flow and soft-delete balance',
      skip: 'requires isolated PostgreSQL fixture', () async {
    final fixture = await bootPgTestSchema();
    addTearDown(fixture.tearDown);
    final db = fixture.db;
    await db.syncDefaultAccounts();

    Future<int> account(String code) async =>
        (await db.getAccountByCode(code))!.id;
    final depreciationAccount = await account('6213');
    final depreciationEntry = await db.createJournalEntry(
      description: 'Phase 6C depreciation parity',
      date: DateTime(2026, 6, 15),
      referenceType: 'depreciation',
      lines: [
        JournalLine(accountId: depreciationAccount, debit: 100),
        JournalLine(accountId: await account('1219'), credit: 100),
      ],
    );
    final receiptEntry = await db.createJournalEntry(
      description: 'Phase 6C customer receipt parity',
      date: DateTime(2026, 6, 15),
      referenceType: 'receipt_voucher',
      lines: [
        JournalLine(accountId: await account('1111'), debit: 40),
        JournalLine(accountId: await account('1121'), credit: 40),
      ],
    );

    final income = await db.getIncomeStatement(
      DateTime(2026, 1, 1), DateTime(2026, 12, 31, 23, 59, 59),
    );
    final cashFlow = await db.getCashFlowStatement(
      DateTime(2026, 1, 1), DateTime(2026, 12, 31, 23, 59, 59),
    );
    final operating = cashFlow['operating'] as Map;
    final financing = cashFlow['financing'] as Map;
    expect((income['totalDepreciation'] as num).toDouble(), closeTo(100, 0.005));
    expect((operating['receiptsFromCustomers'] as num).toDouble(), closeTo(40, 0.005));
    expect((financing['checksCollected'] as num).toDouble(), closeTo(0, 0.005));
    expect(
      (operating['net'] as num).toDouble() +
          ((cashFlow['investing'] as Map)['net'] as num).toDouble() +
          (financing['net'] as num).toDouble(),
      closeTo((cashFlow['netChange'] as num).toDouble(), 0.005),
    );

    DeltaPullService.instance.initialize(db);
    await DeltaPullService.instance.upsertRowForTest(
      'journal_entries',
      {
        'id': depreciationEntry,
        'deleted_at': DateTime.now().toIso8601String(),
      },
    );
    final repository = DriftAccountingRepository(db);
    expect(
      await repository.getCalculatedAccountBalance(depreciationAccount),
      closeTo(0, 0.005),
    );
    expect(receiptEntry, greaterThan(0));
  });
}
