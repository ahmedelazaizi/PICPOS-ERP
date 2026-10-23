// Audit B ACC-006 — manual journal entries touching cash are classified by the
// nature of the counter-account (IAS 7), not dumped into operating.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;
  final from = DateTime(2026, 8, 1);
  final to = DateTime(2026, 8, 31, 23, 59, 59);

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
  });
  tearDown(() => db.close());

  Future<void> manual(String counterCode, double cashDebit, double cashCredit,
      {String cashCode = '1111'}) async {
    final cash = (await db.getAccountByCode(cashCode))!;
    final other = (await db.getAccountByCode(counterCode))!;
    await db.createJournalEntry(
      description: 'manual',
      date: DateTime(2026, 8, 10),
      lines: [
        JournalLine(accountId: cash.id, debit: cashDebit, credit: cashCredit),
        JournalLine(accountId: other.id, debit: cashCredit, credit: cashDebit),
      ],
    );
  }

  Future<Map<String, dynamic>> cf() => db.getCashFlowStatement(from, to);
  double n(Object? v) => (v as num).toDouble();

  test('capital injection (equity) is financing, not operating', () async {
    await manual('311', 500, 0);
    final r = await cf();
    expect(n((r['operating'] as Map)['totalInflow']), 0);
    expect(n((r['financing'] as Map)['otherInflows']), 500);
    expect(n((r['financing'] as Map)['net']), 500);
    expect(n(r['closingBalance']), 500);
  });

  test('long-term loan proceeds are financing', () async {
    await manual('2211', 800, 0);
    final r = await cf();
    expect(n((r['financing'] as Map)['otherInflows']), 800);
    expect(n((r['operating'] as Map)['net']), 0);
  });

  test('cash to bank transfer nets out and has no gross operating flow',
      () async {
    await manual('311', 1000, 0); // seed cash via capital
    await manual('1113', 0, 300); // cash -> bank (cash credit)
    final r = await cf();
    final op = r['operating'] as Map;
    expect(n(op['totalInflow']), 0);
    expect(n(op['totalOutflow']), 0);
    expect(n(r['netChange']), 1000);
  });

  test('manual cash purchase of a fixed asset is investing', () async {
    await manual('1213', 0, 400);
    final r = await cf();
    expect(n((r['investing'] as Map)['assetPurchases']), 400);
    expect(n((r['operating'] as Map)['totalOutflow']), 0);
  });

  test('manual cash expense stays operating (counter is not equity/LT)',
      () async {
    await manual('623', 0, 90);
    final r = await cf();
    expect(n((r['operating'] as Map)['totalOutflow']), 90);
    expect(n((r['operating'] as Map)['otherOperatingPayments']), 90);
  });
}
