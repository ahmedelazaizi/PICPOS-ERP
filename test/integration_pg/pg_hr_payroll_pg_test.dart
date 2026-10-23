// ═══════════════════════════════════════════════════════════════════════════
// J4 (v193) — الرواتبُ والسلفُ والعمولات على PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════
//
// الجداولُ التسعةُ **SQL خامٌّ بلا صنفِ drift**، فيُنشئها
// `ensureHrPayrollSchema` على PG بصيغتها (`SERIAL` · `BIGINT` ·
// `DOUBLE PRECISION`). وهنا يُقاس أنّها موجودةٌ بأعمدة الدلتا، وأنّ الكتابةَ
// بقيمٍ فارغةٍ في أعمدةٍ رقميّة (‏PG يرفض NULL غيرَ مُنمَّط) تعمل: الإعدادات،
// والبنود، والسلفةُ بسند صرف، والمسيّرُ بدورته حتى القيد والصرف والعكس،
// والنقلُ من الشاشة القديمة.
//
// ⚠️ يعمل عبر `dart run scripts/run_pg_tests.dart` وحدَه.

@Tags(['pg'])
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/models/hr_employee_file.dart';
import 'package:picpos_erp/domain/models/hr_payroll.dart';

import '_support/pg_fixture.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    final fx = await bootPgTestSchema();
    addTearDown(fx.tearDown);
    db = fx.db;
    await db.select(db.accounts).get(); // يُجبر الهجرةَ ومسارَ الإقلاع
    await db.syncDefaultAccounts();
  });

  Future<Set<String>> columnsOf(String table) async {
    final rows = await db
        .customSelect(
          "SELECT column_name FROM information_schema.columns "
          "WHERE table_name = '$table'",
        )
        .get();
    return rows.map((r) => r.data['column_name'] as String).toSet();
  }

  test('الجداولُ التسعةُ موجودةٌ على PG بأعمدة الدلتا', () async {
    for (final t in [
      'hr_payroll_settings',
      'hr_salary_components',
      'hr_commission_plans',
      'hr_employee_advances',
      'hr_advance_repayments',
      'hr_payroll_adjustments',
      'hr_payroll_runs',
      'hr_payroll_lines',
      'hr_payroll_items',
    ]) {
      expect(
          await columnsOf(t),
          containsAll(const [
            'global_id',
            'last_modified_at',
            'deleted_at',
            'origin_client_id',
            'row_version',
          ]),
          reason: t);
    }
  });

  test('السلفةُ والمسيّرُ بدورته والقيدُ والصرفُ والعكسُ والنقل', () async {
    for (final (code, name, type) in [
      ('621', 'رواتب', 'expense'),
      ('2131', 'رواتب مستحقة', 'liability'),
      ('2132', 'مستحقات', 'liability'),
      ('2123', 'ضريبة رواتب', 'liability'),
      ('1146', 'سلف', 'asset'),
    ]) {
      if (await db.getAccountByCode(code) == null) {
        await db.into(db.accounts).insert(
            AccountsCompanion.insert(code: code, name: name, accountType: type));
      }
    }
    for (var y = 2025; y <= DateTime.now().year + 1; y++) {
      final has = await (db.select(db.fiscalYears)
            ..where((f) => f.name.equals('$y')))
          .get();
      if (has.isNotEmpty) continue;
      await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(
            name: '$y',
            startDate: DateTime(y, 1, 1),
            endDate: DateTime(y, 12, 31),
            isClosed: const Value(false),
          ));
    }
    final safe = await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'خزنة PG', safeType: const Value('cash')));
    final e = await db.saveEmployeeProfile(EmployeeProfile(
        name: 'عامل PG', basicSalary: 3000, hireDate: DateTime(2020)));
    await db.savePayrollRules(const PayrollRules(
      insuranceEnabled: true,
      insuranceEmployeePct: 5,
      insuranceEmployerPct: 10,
    ));
    expect((await db.payrollRules()).insuranceEmployeePct, 5);
    await db.saveSalaryComponent(const SalaryComponent(name: 'بدل', amount: 100));
    await db.saveCommissionPlan(const CommissionPlan(name: 'خطة', salesRatePct: 1));
    await db.createEmployeeAdvance(
        employeeId: e, amount: 300, safeId: safe, date: DateTime(2025, 5, 2));
    await db.createPayrollAdjustment(PayrollAdjustment(
        employeeId: e, kind: AdjustmentKind.bonus, amount: 50, year: 2025,
        month: 6, reason: 'تميز'));

    final r = await db.createPayrollRun(year: 2025, month: 6, now: DateTime(2026));
    final line = (await db.listPayrollLines(runId: r)).single;
    expect(line.gross, 3100);
    expect(line.items.where((i) => i.code == PayItemCode.advance).single.amount,
        300);
    await db.addPayrollManualItem(
        runId: r,
        employeeId: e,
        kind: PayItemKind.deduction,
        amount: 10,
        reason: 'تسوية');
    await db.reviewPayrollRun(r);
    await db.approvePayrollRun(r);
    final entry = await db.postPayrollRun(r);
    expect(entry, greaterThan(0));
    expect(await db.employeeAdvanceBalance(e), 0);
    final reversal = await db.reversePayrollRun(r, reason: 'PG');
    expect(reversal, greaterThan(0));
    expect(await db.employeeAdvanceBalance(e), 300);

    final r2 = await db.createPayrollRun(year: 2025, month: 6, now: DateTime(2026));
    await db.reviewPayrollRun(r2);
    await db.approvePayrollRun(r2);
    await db.postPayrollRun(r2);
    expect(await db.payPayrollRun(r2, safeId: safe, bulk: true), hasLength(1));
    expect((await db.getPayrollRun(r2)).status, PayrollRunStatus.paid);

    await db.into(db.salaryPayments).insert(SalaryPaymentsCompanion.insert(
        employeeId: e,
        amount: 2800,
        paymentDate: DateTime(2025, 3, 30),
        period: const Value('2025-03')));
    await db.migrateLegacyPayroll();
    await db.migrateLegacyPayroll();
    final legacy = (await db.listPayrollRuns()).where((x) => x.legacy).toList();
    expect(legacy, hasLength(1));
    expect(legacy.single.net, 2800);
  });
}
