import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';
import 'package:picpos_erp/core/permissions/fiscal_permission_codes.dart';
import '../audit_repro/financial_statements/_fs_world.dart';

void main() {
  late ScenarioWorld w;
  late int product;

  double n(Object? value) => (value as num).toDouble();

  Future<int> year(DateTime end) async {
    final id = await w.db.createFiscalYear(
      name: 'FY 2025', startDate: DateTime(2025), endDate: end,
    );
    await w.db.generatePeriodsForYear(id, DateTime(2025), end);
    product = await w.addProduct('P2', price: 100, cost: 60);
    await w.db.adjustStock(productId: product, warehouseId: w.warehouseId,
      quantity: 10, type: 'opening_stock', unitCost: 60,
      movementDate: DateTime(2025, 1, 2));
    return id;
  }

  setUp(() async => w = await ScenarioWorld.create());
  tearDown(() => w.dispose());

  test('close permission backfill is repeatable for the accountant role', () async {
    var role = await (w.db.select(w.db.roles)
      ..where((r) => r.name.equals('محاسب'))..limit(1)).getSingleOrNull();
    role ??= (await w.db.into(w.db.roles).insertReturning(
      RolesCompanion.insert(name: 'محاسب')));
    await w.db.syncAllPermissions();
    final first = (await w.db.getPermissionsForRole(role.id))
      .where((p) => FiscalPermissionCodes.closeDefaults.contains(p.code)).length;
    await w.db.syncAllPermissions();
    final second = (await w.db.getPermissionsForRole(role.id))
      .where((p) => FiscalPermissionCodes.closeDefaults.contains(p.code)).length;
    expect(first, FiscalPermissionCodes.closeDefaults.length);
    expect(second, first);
  });

  test('period close requires the explicit close permission', () async {
    final id = await year(DateTime(2025, 12, 31));
    final period = await (w.db.select(w.db.accountingPeriods)
      ..where((p) => p.fiscalYearId.equals(id))..limit(1)).getSingle();
    await expectLater(w.db.closeAccountingPeriod(period.id, w.userId),
      throwsA(isA<Exception>()));
    final unchanged = await (w.db.select(w.db.accountingPeriods)
      ..where((p) => p.id.equals(period.id))).getSingle();
    expect(unchanged.isClosed, isFalse);
  });

  test('31/12 is covered for the entire day and close includes late entries', () async {
    final id = await year(DateTime(2025, 12, 31));
    final sale = await w.sellRaw([w.line(product, 1, 100)],
      date: DateTime(2025, 12, 31, 15));
    expect(sale.isSuccess, isTrue, reason: sale.errorMessage);
    final cash = (await w.db.getAccountByCode('1111'))!;
    final revenue = (await w.db.getAccountByCode('4121'))!;
    await w.db.createJournalEntry(description: 'late', date: DateTime(2025, 12, 31, 23, 59),
      referenceType: 'opening_balance', lines: [
        JournalLine(accountId: cash.id, debit: 50),
        JournalLine(accountId: revenue.id, credit: 50),
      ]);
    await (w.db.update(w.db.accountingPeriods)..where((p) => p.fiscalYearId.equals(id)))
      .write(const AccountingPeriodsCompanion(isClosed: Value(true)));
    await w.grant(FiscalPermissionCodes.fiscalYearClose);
    await w.db.closeFiscalYear(id, w.userId);
    final audit = await (w.db.select(w.db.activityLogs)
      ..where((a) => a.entityType.equals('fiscal_year') &
        a.entityId.equals(id) & a.userId.equals(w.userId))).get();
    expect(audit, isNotEmpty);
    final left = await w.db.customSelect("SELECT coalesce(sum(l.debit-l.credit),0) n FROM journal_entry_lines l JOIN journal_entries e ON e.id=l.entry_id JOIN accounts a ON a.id=l.account_id WHERE a.code='4121' AND e.entry_date BETWEEN ? AND ?",
      variables: [Variable<int>(DateTime(2025).millisecondsSinceEpoch ~/ 1000), Variable<int>(DateTime(2025,12,31,23,59,59).millisecondsSinceEpoch ~/ 1000)]).getSingle();
    expect(n(left.data['n']), closeTo(0, 0.005));
  });

  test('01/01 00:00 remains outside the previous year close', () async {
    final id = await year(DateTime(2025, 12, 31));
    final next = await w.db.getFiscalYearByDate(DateTime(2026));
    if (next == null) {
      final nextId = await w.db.createFiscalYear(name: 'FY 2026',
        startDate: DateTime(2026), endDate: DateTime(2026, 12, 31));
      await w.db.generatePeriodsForYear(nextId, DateTime(2026), DateTime(2026, 12, 31));
    }
    final cash = (await w.db.getAccountByCode('1111'))!;
    final revenue = (await w.db.getAccountByCode('4121'))!;
    await w.db.createJournalEntry(description: 'next year',
      date: DateTime(2026), referenceType: 'opening_balance', lines: [
        JournalLine(accountId: cash.id, debit: 50),
        JournalLine(accountId: revenue.id, credit: 50),
      ]);
    await (w.db.update(w.db.accountingPeriods)..where((p) => p.fiscalYearId.equals(id)))
      .write(const AccountingPeriodsCompanion(isClosed: Value(true)));
    await w.grant(FiscalPermissionCodes.fiscalYearClose);
    await w.db.closeFiscalYear(id, w.userId);
    final remains = await w.db.customSelect(
      "SELECT sum(l.credit-l.debit) amount FROM journal_entry_lines l JOIN journal_entries e ON e.id=l.entry_id JOIN accounts a ON a.id=l.account_id WHERE a.code='4121' AND e.entry_date >= ? AND e.entry_date < ?",
      variables: [Variable<DateTime>(DateTime(2026)), Variable<DateTime>(DateTime(2026, 1, 2))],
    ).getSingle();
    expect(n(remains.data['amount']), closeTo(50, 0.005));
  });

  test('income statement excludes year-close entry', () async {
    final id = await year(DateTime(2025, 12, 31, 23, 59, 59));
    await w.sell([w.line(product, 2, 100)], date: DateTime(2025, 6, 15, 10));
    final before = await w.db.getIncomeStatement(DateTime(2025), DateTime(2025,12,31,23,59,59));
    await (w.db.update(w.db.accountingPeriods)..where((p) => p.fiscalYearId.equals(id)))
      .write(const AccountingPeriodsCompanion(isClosed: Value(true)));
    await w.grant(FiscalPermissionCodes.fiscalYearClose);
    await w.db.closeFiscalYear(id, w.userId);
    final after = await w.db.getIncomeStatement(DateTime(2025), DateTime(2025,12,31,23,59,59));
    expect(n(after['netProfit']), closeTo(n(before['netProfit']), 0.005));
  });

  test('balance sheet reports prior unclosed-year earnings in equity', () async {
    await year(DateTime(2025, 12, 31, 23, 59, 59));
    await w.sell([w.line(product, 2, 100)], date: DateTime(2025, 6, 15, 10));
    final existing2026 = await w.db.getFiscalYearByDate(DateTime(2026));
    final fy2026 = existing2026?.id ?? await w.db.createFiscalYear(name: 'FY 2026',
      startDate: DateTime(2026), endDate: DateTime(2026,12,31,23,59,59));
    await w.db.generatePeriodsForYear(fy2026, DateTime(2026), DateTime(2026,12,31,23,59,59));
    await w.sell([w.line(product, 1, 100)], date: DateTime(2026, 3, 2));
    final bs = await w.db.getBalanceSheet(DateTime(2026, 6, 30));
    expect(bs['isBalanced'], isTrue);
    expect((bs['equityDetails'] as List).any((e) => (e as Map)['name'] == 'أرباح/خسائر سنوات سابقة غير مُقفلة'), isTrue);
  });
}
