// تدقيق القوائم المالية (2026-10-31) — توافق PostgreSQL لتقارير القوائم والإقفال.
// يتطلّب PG_TEST_DSN لحاوية خاصة (لا قاعدة المالك):
//   $env:PG_TEST_DSN='postgres://postgres:auditpw@127.0.0.1:<port>/postgres'
//   flutter test --run-skipped --concurrency=1 --dart-define=APP_BRAND=picpos <الملف>
@Tags(['pg'])
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';
import 'package:picpos_erp/core/permissions/fiscal_permission_codes.dart';

import '../../integration_pg/_support/pg_fixture.dart';

const _skip = 'audit repro — pending owner approval';

void main() {
  double n(Object? v) => (v as num).toDouble();

  test('PG1 القوائم + إقفال السنة على PostgreSQL',
      skip: _skip, timeout: const Timeout(Duration(minutes: 4)), () async {
    // الإقلاع داخل الاختبار (لا setUpAll) كي لا يُطلَب PG_TEST_DSN حين يُتخطّى.
    final fx = await bootPgTestSchema();
    addTearDown(fx.tearDown);
    final AppDatabase db = fx.db;
    await db.customSelect('SELECT 1').get();
    await db.syncDefaultAccounts();
     final accountant = await (db.select(db.roles)
       ..where((r) => r.name.equals('محاسب'))
       ..orderBy([(r) => OrderingTerm.asc(r.id)])
       ..limit(1)).getSingle();
     final roleId = accountant.id;
     await db.syncAllPermissions();
     await db.syncAllPermissions();
     final grants = await db.customSelect(
       'SELECT r.id, r.name, p.code FROM role_permissions rp JOIN roles r ON r.id=rp.role_id JOIN permissions p ON p.id=rp.permission_id WHERE p.code = ?',
       variables: [const Variable<String>(FiscalPermissionCodes.fiscalYearClose)],
     ).get();
     expect(grants.any((r) => r.read<int>('id') == roleId), isTrue,
       reason: 'Role $roleId missing fiscal-year close permission; rows=${grants.map((r) => r.data).toList()}');
     final userId = await db.createUser(username: 'phase2_close',
       password: 'phase2-test-pass', displayName: 'Phase 2', roleId: roleId);
     expect(await db.userHasPermission(
       userId, FiscalPermissionCodes.fiscalYearClose), isTrue);
    final end = DateTime(2025, 12, 31, 23, 59, 59);
    final fy = await db.createFiscalYear(
        name: 'السنة المالية 2025', startDate: DateTime(2025, 1, 1), endDate: end);
    await db.generatePeriodsForYear(fy, DateTime(2025, 1, 1), end);
    Future<int> acc(String c) async => (await db.getAccountByCode(c))!.id;
    await db.createJournalEntry(
        description: 'بيع', date: DateTime(2025, 6, 15, 10), lines: [
      JournalLine(accountId: await acc('1111'), debit: 342),
      JournalLine(accountId: await acc('4121'), credit: 300),
      JournalLine(accountId: await acc('2121'), credit: 42),
    ]);
    await db.createJournalEntry(
        description: 'تكلفة', date: DateTime(2025, 6, 15, 10), lines: [
      JournalLine(accountId: await acc('5211'), debit: 180),
      JournalLine(accountId: await acc('1136'), credit: 180),
    ]);
    await db.createJournalEntry(
        description: 'مخزون افتتاحي',
        date: DateTime(2025, 1, 2),
        referenceType: 'opening_balance',
        lines: [
          JournalLine(accountId: await acc('1136'), debit: 600),
          JournalLine(accountId: await acc('313'), credit: 600),
        ]);
    final inc = await db.getIncomeStatement(DateTime(2025, 1, 1), end);
    final tb = await db.getTrialBalance(DateTime(2025, 1, 1), end);
    final bs = await db.getBalanceSheet(end);
    final tax = await db.getTaxReport(DateTime(2025, 1, 1), end);
    final cf = await db.getCashFlowStatement(DateTime(2025, 1, 1), end);
    // ignore: avoid_print
    print('PG1 net=${inc['netProfit']} rev=${inc['totalRevenue']} vat=${tax['salesTax']} '
        'bs=${bs['isBalanced']} cf.net=${cf['netChange']} tb=${tb.last}');
    expect(n(inc['netProfit']), closeTo(120, 0.005));
    expect(bs['isBalanced'], isTrue);
    expect(n(tax['salesTax']), closeTo(42, 0.005));

    // literal «is_posted = 1» كما في purchase_payments_dao.dart:60 — هل يمرّ على PG؟
    Object? literalErr;
    try {
      await db.customSelect(
          'SELECT COUNT(*) c FROM journal_entries je WHERE je.is_posted = 1').get();
    } catch (e) {
      literalErr = e;
    }
    // ignore: avoid_print
    print('PG1 literal is_posted=1 error: $literalErr');

    await (db.update(db.accountingPeriods)..where((p) => p.fiscalYearId.equals(fy)))
        .write(const AccountingPeriodsCompanion(isClosed: Value(true)));
    Object? closeErr;
    try {
      await db.closeFiscalYear(fy, userId);
    } catch (e) {
      closeErr = e;
    }
    // ignore: avoid_print
    print('PG1 closeFiscalYear error: $closeErr');
    expect(closeErr, isNull);
    final re = await db.customSelect(
        "SELECT COALESCE(SUM(l.credit - l.debit),0) n FROM journal_entry_lines l "
        "JOIN journal_entries e ON e.id = l.entry_id JOIN accounts a ON a.id = l.account_id "
        "WHERE e.reference_type = 'fiscal_close' AND a.code = '313'").getSingle();
    // ignore: avoid_print
    print('PG1 closing→313 = ${re.data['n']}');
    expect(n(re.data['n']), closeTo(120, 0.005));
  });
}
