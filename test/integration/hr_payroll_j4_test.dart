// J4 (الجزء ٣) — الرواتبُ والسلفُ والعمولاتُ على قاعدةٍ حقيقيّة.
//
// Proves:
//  * pro-rata basic and allowances for a mid-month hire / termination;
//  * attendance-driven deductions read from `attendanceSummary`: recorded
//    absence, lateness (per minute and tiers), unpaid leave, overtime — and
//    that an unrecorded past day is not deducted unless the rule says so;
//  * rep commissions from STAMPED documents: sales net of returns,
//    collections (receipt vouchers + field collections), target tiers and
//    per-category rates; the commission enters the payroll as an earning;
//  * an advance paid through a payment voucher (book leaf, JE Dr advances /
//    Cr cash), installments deducted by payroll on posting, balance, early
//    settlement by a receipt voucher;
//  * employee / employer insurance and progressive tax;
//  * the run workflow with permissions, ONE balanced JE on the mapped
//    accounts with the department cost center, payment vouchers per employee
//    and in bulk, and the reversal of a posted run;
//  * manual adjustments with a reason survive a recompute and are logged;
//    approved bonuses / penalties are consumed on posting;
//  * the legacy screen's payroll is copied as read-only history (idempotent);
//  * the nine v193 tables ride every sync list and cross a `SELECT *` copy.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/core/utils/financial_utils.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/extensions/distribution_dao.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/domain/models/hr_attendance.dart';
import 'package:picpos_erp/domain/models/hr_employee_file.dart';
import 'package:picpos_erp/domain/models/hr_payroll.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';
import 'package:picpos_erp/services/id_namespace_service.dart';

const _newTables = [
  'hr_payroll_settings',
  'hr_salary_components',
  'hr_commission_plans',
  'hr_employee_advances',
  'hr_advance_repayments',
  'hr_payroll_adjustments',
  'hr_payroll_runs',
  'hr_payroll_lines',
  'hr_payroll_items',
];

/// يونيو ٢٠٢٥: ٣٠ يوماً، والأوّلُ أحد.
DateTime _d(int day, [int h = 0, int m = 0]) => DateTime(2025, 6, day, h, m);
final _now = DateTime(2026, 1, 1);

const _dayShift = WorkShift(
  name: 'صباحي',
  startMinute: 9 * 60,
  endMinute: 17 * 60,
  breakMinutes: 60,
  graceLateMinutes: 10,
  overtimeAfterMinutes: 30,
  daysOff: {DateTime.friday, DateTime.saturday},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late int safeId;

  Future<void> ensureAccount(String code, String name, String type) async {
    if (await db.getAccountByCode(code) != null) return;
    await db.into(db.accounts).insert(AccountsCompanion.insert(
        code: code, name: name, accountType: type));
  }

  setUp(() async {
    SyncInterceptor.instance = null;
    db = AppDatabase.forTesting();
    await db.customSelect('SELECT 1').get();
    await db.syncDefaultAccounts();
    for (final (code, name, type) in [
      ('621', 'رواتب وأجور', 'expense'),
      ('612', 'عمولات المبيعات', 'expense'),
      ('2131', 'رواتب مستحقة', 'liability'),
      ('2132', 'مصروفات مستحقة', 'liability'),
      ('2123', 'ضريبة رواتب', 'liability'),
      ('1146', 'سلف الموظفين', 'asset'),
      ('1111', 'الصندوق', 'asset'),
    ]) {
      await ensureAccount(code, name, type);
    }
    safeId = await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'الخزنة', safeType: const Value('cash')));
    // Payroll JEs are dated in 2025; vouchers are dated today.
    for (var y = 2025; y <= DateTime.now().year + 1; y++) {
      await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(
            name: '$y',
            startDate: DateTime(y, 1, 1),
            endDate: DateTime(y, 12, 31),
            isClosed: const Value(false),
          ));
    }
  });
  tearDown(() async {
    await db.close();
    SyncInterceptor.instance = null;
  });

  Future<int> employee(String name,
          {double basic = 3000,
          DateTime? hire,
          DateTime? termination,
          String status = EmployeeStatus.active,
          int? department,
          Set<String> roles = const {},
          List<EmployeeAllowance> allowances = const [],
          double? hours = 8}) =>
      db.saveEmployeeProfile(
        EmployeeProfile(
          name: name,
          basicSalary: basic,
          hireDate: hire ?? DateTime(2020),
          terminationDate: termination,
          status: status,
          departmentId: department,
          roleTags: roles,
          hoursPerDay: hours,
        ),
        allowances: allowances,
      );

  Future<PayrollLine> lineOf(int run, int emp) async =>
      (await db.listPayrollLines(runId: run))
          .singleWhere((l) => l.employeeId == emp);

  double item(PayrollLine l, String code) => l.items
      .where((i) => i.code == code)
      .fold<double>(0, (a, i) => a + i.amount);

  Future<int> run({int month = 6}) =>
      db.createPayrollRun(year: 2025, month: month, now: _now);

  Future<Map<String, (double, double)>> jeByCode(int entryId) async {
    final out = <String, (double, double)>{};
    for (final r in await db.customSelect(
      'SELECT a.code, l.debit, l.credit FROM journal_entry_lines l '
      'JOIN accounts a ON a.id = l.account_id WHERE l.entry_id = ?',
      variables: [Variable<int>(entryId)],
    ).get()) {
      final code = r.data['code'] as String;
      final prev = out[code] ?? (0.0, 0.0);
      out[code] = (
        prev.$1 + (r.data['debit'] as num).toDouble(),
        prev.$2 + (r.data['credit'] as num).toDouble(),
      );
    }
    return out;
  }

  group('الاحتساب', () {
    test('النسبيّةُ لتعيينٍ وإنهاءٍ في منتصف الشهر، والبدلُ معها', () async {
      final hired = await employee('معيَّن', hire: _d(16), allowances: const [
        EmployeeAllowance(name: 'بدل نقل', amount: 300),
      ]);
      final left = await employee('منتهي',
          termination: _d(10), status: EmployeeStatus.terminated);
      final gone = await employee('قديم',
          termination: DateTime(2025, 5, 20), status: EmployeeStatus.terminated);
      final full = await employee('كامل');
      final r = await run();
      final h = await lineOf(r, hired);
      expect(item(h, PayItemCode.basic), 1500);
      expect(item(h, PayItemCode.allowance), 150);
      expect(h.paidDays, 15);
      expect(item(await lineOf(r, left), PayItemCode.basic), 1000);
      expect(item(await lineOf(r, full), PayItemCode.basic), 3000);
      expect((await db.listPayrollLines(runId: r)).map((l) => l.employeeId),
          isNot(contains(gone)));
      // A second run for the same month and scope is refused.
      await expectLater(run(), throwsA(isA<HrException>()));
    });

    test('خصوماتُ الحضور والإضافيُّ من `attendanceSummary`', () async {
      final e = await employee('عامل');
      final shift = await db.saveWorkShift(_dayShift);
      await db.assignShift(employeeId: e, shiftId: shift, from: DateTime(2025));
      for (final day in [2, 3]) {
        await db.saveAttendanceEntry(
            employeeId: e, day: _d(day), mark: AttendanceMark.absent, reason: 'غياب');
      }
      await db.saveAttendanceEntry(
          employeeId: e, day: _d(4), checkIn: _d(4, 9, 20), checkOut: _d(4, 17), reason: 'متأخر');
      await db.saveAttendanceEntry(
          employeeId: e, day: _d(5), checkIn: _d(5, 9), checkOut: _d(5, 19), reason: 'إضافي');
      await db.saveAttendanceEntry(
          employeeId: e, day: _d(9), mark: AttendanceMark.unpaidLeave, reason: 'بدون أجر');
      final summary =
          await db.attendanceSummary(e, _d(1), _d(30), now: _now);
      expect(summary.lateMinutes, 20);
      expect(summary.overtimeMinutes, 120);

      final r = await run();
      var l = await lineOf(r, e);
      // daily = 3000 / 30 = 100, hourly = 12.5
      expect(item(l, PayItemCode.absence), 200,
          reason: 'only the two recorded absences — an unpunched past day is '
              'not deducted by default (legacy owner decision)');
      expect(item(l, PayItemCode.unpaidLeave), 100);
      // 20 minutes × 12.5 / 60, rounded to the currency's minor units.
      expect(item(l, PayItemCode.lateness),
          FinancialUtils.round(20 * 12.5 / 60));
      expect(item(l, PayItemCode.overtime), 31.25);
      expect(
          l.net,
          closeTo(
              3000 + 31.25 - 200 - 100 - FinancialUtils.round(20 * 12.5 / 60),
              0.0001));

      // Tiers: 15+ minutes late ⇒ a quarter day; unrecorded days counted.
      await db.savePayrollRules(const PayrollRules(
        latenessMode: LatenessMode.tiers,
        latenessTiers: [
          LatenessTier(fromMinutes: 15, dayFraction: 0.25),
          LatenessTier(fromMinutes: 60, dayFraction: 0.5),
        ],
        deductUnrecordedAbsence: true,
      ));
      await db.recomputePayrollRun(r, now: _now);
      l = await lineOf(r, e);
      expect(item(l, PayItemCode.lateness), 25);
      expect(l.items.singleWhere((i) => i.code == PayItemCode.absence).quantity,
          summary.absentDays);
    });

    test('التأميناتُ بالحصّتين والضريبةُ التصاعديّة', () async {
      await db.savePayrollRules(const PayrollRules(
        insuranceEnabled: true,
        insuranceEmployeePct: 7.5,
        insuranceEmployerPct: 14.25,
        taxEnabled: true,
        taxBrackets: [
          TaxBracket(upTo: 1000, ratePct: 0),
          TaxBracket(ratePct: 10),
        ],
      ));
      final e = await employee('مؤمَّن');
      final l = await lineOf(await run(), e);
      expect(item(l, PayItemCode.insuranceEmployee), 225);
      expect(item(l, PayItemCode.insuranceEmployer), 427.5);
      expect(item(l, PayItemCode.tax), 177.5);
      expect(l.net, 2597.5);
      expect(l.employerCost, 427.5);
    });

    test('بنودُ الراتب: ثابتٌ ونسبةٌ وصيغة، ومرفوضٌ صيغةٌ معطوبة', () async {
      final e = await employee('بنود');
      await db.saveSalaryComponent(const SalaryComponent(
          name: 'بدل سكن', calc: ComponentCalc.percentBasic, amount: 10));
      await db.saveSalaryComponent(const SalaryComponent(
          name: 'حافز', calc: ComponentCalc.formula, formula: 'basic * 0.05 + 10'));
      await db.saveSalaryComponent(const SalaryComponent(
          name: 'نقابة', kind: PayItemKind.deduction, amount: 20));
      await expectLater(
          db.saveSalaryComponent(const SalaryComponent(
              name: 'خطأ', calc: ComponentCalc.formula, formula: 'basic *')),
          throwsA(isA<HrException>()));
      final l = await lineOf(await run(), e);
      expect(item(l, PayItemCode.component), 300 + 160 + 20);
      expect(l.net, 3000 + 300 + 160 - 20);
    });
  });

  group('العمولات', () {
    late int rep;
    late int warehouse;
    late int customer;

    setUp(() async {
      rep = await employee('مندوب', roles: {HrRoleTag.rep});
      warehouse = (await db.select(db.warehouses).get()).first.id;
      customer = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'عميل', isCustomer: const Value(true)));
    });

    Future<int> invoice(String number, double total, DateTime date,
        {String saleType = 'default'}) async {
      final id = await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
              invoiceNumber: number,
              warehouseId: warehouse,
              userId: 1,
              invoiceDate: date,
              customerId: Value(customer),
              saleType: Value(saleType),
              total: Value(total)));
      await db.customStatement(
          'UPDATE sales_invoices SET rep_employee_id = ? WHERE id = ?',
          [rep, id]);
      return id;
    }

    Future<void> stampedSales() async {
      await invoice('S-1', 10000, _d(3));
      await invoice('S-2', 5000, _d(10));
      await invoice('S-OUT', 9999, DateTime(2025, 7, 1));
      await invoice('R-1', 1000, _d(12), saleType: 'return');
      final unstamped = await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
              invoiceNumber: 'S-X',
              warehouseId: warehouse,
              userId: 1,
              invoiceDate: _d(4),
              total: const Value(7777)));
      expect(unstamped, greaterThan(0));
      final receipt = await db.createReceiptVoucher(
          amount: 4000, category: 'customer_payment', safeId: safeId);
      await db.customStatement(
          'UPDATE safe_transactions SET rep_employee_id = ?, created_at = ? '
          'WHERE id = ?',
          [rep, _d(15).millisecondsSinceEpoch ~/ 1000, receipt]);
      await db.createCollection(SalesRepCollectionsCompanion.insert(
          salesRepId: rep,
          customerId: customer,
          amount: 1000,
          createdAt: Value(_d(20))));
    }

    test('صافي المبيعات بعد المرتجع والتحصيلاتُ وشرائحُ الهدف، وفي المسيّر',
        () async {
      await db.saveCommissionPlan(const CommissionPlan(
        name: 'افتراضية',
        salesRatePct: 2,
        collectionsRatePct: 1,
        tiers: [CommissionTier(minAchievementPct: 100, salesRatePct: 3)],
      ));
      await stampedSales();
      var s = await db.commissionStatement(rep, _d(1), _d(30));
      expect(s.sales, 15000);
      expect(s.returns, 1000);
      expect(s.netSales, 14000);
      expect(s.collections, 5000);
      expect(s.target, isNull);
      expect(s.salesCommission, 280);
      expect(s.collectionsCommission, 50);
      expect(s.docs.map((d) => d.number),
          containsAll(['S-1', 'S-2', 'R-1']));
      expect(s.docs.map((d) => d.number), isNot(contains('S-X')));

      await db.setSalesRepTarget(
          salesRepId: rep, year: 2025, month: 6, targetAmount: 12000);
      s = await db.commissionStatement(rep, _d(1), _d(30));
      expect(s.achievementPct, closeTo(116.67, 0.01));
      expect(s.appliedSalesRatePct, 3);
      expect(s.total, 420 + 50);

      final l = await lineOf(await run(), rep);
      expect(item(l, PayItemCode.commission), 470);
      expect(l.items.singleWhere((i) => i.code == PayItemCode.commission)
          .accountKey, PayAccountKey.commissionsExpense);

      // Only one active default plan.
      await expectLater(
          db.saveCommissionPlan(const CommissionPlan(name: 'ثانية')),
          throwsA(isA<HrException>()));
    });

    test('نسبُ الفئات من بنود الفاتورة، وخطّةُ المندوب أولى من الافتراضيّة',
        () async {
      await db.saveCommissionPlan(
          const CommissionPlan(name: 'افتراضية', salesRatePct: 1));
      final cat = await db.into(db.categories)
          .insert(CategoriesCompanion.insert(name: 'أجهزة'));
      await db.saveCommissionPlan(CommissionPlan(
        name: 'خاصة',
        employeeId: rep,
        salesRatePct: 2,
        categoryRates: {cat: 5},
      ));
      final pA = await db.into(db.products).insert(ProductsCompanion.insert(
          code: 'P-A', name: 'جهاز', categoryId: Value(cat)));
      final pB = await db.into(db.products)
          .insert(ProductsCompanion.insert(code: 'P-B', name: 'عادي'));
      final inv = await invoice('S-C', 1000, _d(5));
      for (final (p, total) in [(pA, 600.0), (pB, 400.0)]) {
        await db.into(db.salesInvoiceItems).insert(
            SalesInvoiceItemsCompanion.insert(
                invoiceId: inv,
                productId: p,
                quantity: 1,
                unitPrice: total,
                total: total));
      }
      final s = await db.commissionStatement(rep, _d(1), _d(30));
      expect(s.plan?.name, 'خاصة');
      expect(s.salesCommission, 600 * 0.05 + 400 * 0.02);
    });
  });

  group('السلف والمسيّر والقيود', () {
    test('سلفةٌ بسند صرفٍ من دفتر، وأقساطٌ في المسيّر، ورصيدٌ وتسديدٌ مبكّر',
        () async {
      final e = await employee('مستلف');
      final book = await db.createVoucherBook(
          type: 'payment', rangeFrom: 100, rangeTo: 150);
      final adv = await db.createEmployeeAdvance(
        employeeId: e,
        amount: 1200,
        installments: 3,
        safeId: safeId,
        date: DateTime(2025, 5, 15),
        bookId: book,
      );
      final a = (await db.listEmployeeAdvances(employeeId: e)).single;
      expect(a.id, adv);
      expect(a.startMonth, 6);
      expect(a.installmentAmount, 400);
      final txn = await (db.select(db.safeTransactions)
            ..where((t) => t.id.equals(a.safeTransactionId!)))
          .getSingle();
      expect(txn.transactionType, 'payment');
      expect(txn.amount, 1200);
      final leaf = await db.customSelect(
          'SELECT book_number, employee_id FROM safe_transactions WHERE id = ?',
          variables: [Variable<int>(txn.id)]).getSingle();
      expect(leaf.data['book_number'], 100);
      expect(leaf.data['employee_id'], e);
      final je = await jeByCode(a.journalEntryId!);
      expect(je['1146'], (1200.0, 0.0));
      expect(je.values.fold<double>(0, (s, v) => s + v.$2), 1200);

      final r = await run();
      expect(item(await lineOf(r, e), PayItemCode.advance), 400);
      expect(await db.employeeAdvanceBalance(e), 1200,
          reason: 'a draft run does not repay anything yet');
      await db.reviewPayrollRun(r);
      await db.approvePayrollRun(r);
      await db.postPayrollRun(r);
      expect(await db.employeeAdvanceBalance(e), 800);

      await db.settleEmployeeAdvance(adv, safeId: safeId);
      expect(await db.employeeAdvanceBalance(e), 0);
      expect((await db.listEmployeeAdvances(employeeId: e)).single.status,
          AdvanceStatus.settled);
      final repayments = await db.listAdvanceRepayments(adv);
      expect(repayments.map((x) => x.source),
          [RepaymentSource.payroll, RepaymentSource.earlySettlement]);
    });

    test('الدورةُ بالصلاحيّات، وقيدٌ واحدٌ متوازنٌ بمركز تكلفة القسم، والصرف',
        () async {
      await db.savePayrollRules(const PayrollRules(
        insuranceEnabled: true,
        insuranceEmployeePct: 5,
        insuranceEmployerPct: 10,
        taxEnabled: true,
        taxBrackets: [TaxBracket(ratePct: 10)],
      ));
      final dept = await db.saveHrDepartment(name: 'المبيعات');
      final cc = await db.into(db.costCenters).insert(
          CostCentersCompanion.insert(code: 'CC-S', name: 'مبيعات'));
      await db.saveDepartmentCostCenters({dept: cc});
      final e = await employee('أ', department: dept, allowances: const [
        EmployeeAllowance(name: 'بدل', amount: 500),
      ]);
      final e2 = await employee('ب', basic: 2000);
      await db.createEmployeeAdvance(
          employeeId: e2, amount: 300, safeId: safeId, date: DateTime(2025, 5, 2));
      await db.syncAllPermissions();
      final clerkRole =
          await db.into(db.roles).insert(RolesCompanion.insert(name: 'محرر'));
      final clerk = await db.into(db.users).insert(UsersCompanion.insert(
          username: 'clerk', passwordHash: 'x', displayName: 'محرر',
          roleId: Value(clerkRole)));
      Future<int> perm(String code) async => (await (db.select(db.permissions)
                ..where((p) => p.code.equals(code)))
              .getSingle())
          .id;
      await db.addPermissionToRole(
          clerkRole, await perm(PermissionCodes.hrPayrollEdit));

      final r = await db.createPayrollRun(
          year: 2025, month: 6, userId: clerk, now: _now);
      await db.addPayrollManualItem(
          runId: r,
          employeeId: e,
          kind: PayItemKind.earning,
          amount: 100,
          reason: 'مكافأة استثنائية',
          userId: clerk);
      await db.recomputePayrollRun(r, userId: clerk, now: _now);
      final la = await lineOf(r, e);
      expect(item(la, PayItemCode.manual), 100,
          reason: 'a manual adjustment survives the recompute');
      expect(
          (await db.listEmployeeHistory(e)).map((h) => h.eventType),
          contains(HrEventType.payroll));
      await db.reviewPayrollRun(r, userId: clerk);
      await expectLater(db.approvePayrollRun(r, userId: clerk),
          throwsA(isA<HrException>()));
      await db.approvePayrollRun(r);
      await expectLater(db.addPayrollManualItem(
              runId: r,
              employeeId: e,
              kind: PayItemKind.deduction,
              amount: 1,
              reason: 'متأخر'),
          throwsA(isA<HrException>()));
      final entry = await db.postPayrollRun(r);
      final run1 = await db.getPayrollRun(r);
      expect(run1.status, PayrollRunStatus.posted);
      expect(run1.journalEntryId, entry);

      // a: basic 3000 + allowance 500 + manual 100 = 3600;
      //    insurance base = basic 3000 ⇒ 150 / 300; tax 10% of 3450 = 345.
      // b: basic 2000; insurance 100 / 200; tax 190; advance 300.
      final lines = await db.customSelect(
          'SELECT a.code, l.debit, l.credit, l.cost_center_id '
          'FROM journal_entry_lines l JOIN accounts a ON a.id = l.account_id '
          'WHERE l.entry_id = ?',
          variables: [Variable<int>(entry)]).get();
      final debit = lines.fold<double>(
          0, (s, l) => s + (l.data['debit'] as num).toDouble());
      final credit = lines.fold<double>(
          0, (s, l) => s + (l.data['credit'] as num).toDouble());
      expect(debit, closeTo(credit, 0.001));
      expect(debit, 3600 + 300 + 2000 + 200);
      final je = await jeByCode(entry);
      expect(je['621']!.$1, 3600 + 300 + 2000 + 200,
          reason: 'basic, allowances and employer insurance default to 621');
      expect(je['2132']!.$2, 150 + 300 + 100 + 200);
      expect(je['2123']!.$2, 345 + 190);
      expect(je['1146']!.$2, 300);
      expect(je['2131']!.$2, (3600 - 150 - 345) + (2000 - 100 - 190 - 300));
      expect(
          lines
              .where((l) => l.data['cost_center_id'] == cc)
              .fold<double>(0, (s, l) => s + (l.data['debit'] as num).toDouble()),
          3600 + 300,
          reason: 'the department cost center rides its expense lines');

      // Payment: one voucher per employee (Dr salaries payable / Cr cash).
      final vouchers = await db.payPayrollRun(r, safeId: safeId);
      expect(vouchers, hasLength(2));
      final pay = await db.customSelect(
          "SELECT id FROM journal_entries WHERE reference_type = 'payment_voucher' "
          'AND reference_id = ?',
          variables: [Variable<int>(vouchers.first)]).getSingle();
      final payJe = await jeByCode((pay.data['id'] as num).toInt());
      expect(payJe['2131']!.$1, greaterThan(0));
      final paid = await db.getPayrollRun(r);
      expect(paid.status, PayrollRunStatus.paid);
      expect(paid.paid, paid.net);
      await expectLater(db.reversePayrollRun(r, reason: 'خطأ'),
          throwsA(isA<HrException>()),
          reason: 'a paid run is not reversed');
    });

    test('الصرفُ الجماعيُّ بسندٍ واحد، والعكسُ يعيد الأقساطَ والجزاءات', () async {
      final e = await employee('ج');
      final adv = await db.createEmployeeAdvance(
          employeeId: e, amount: 500, safeId: safeId, date: DateTime(2025, 5, 2));
      final pen = await db.createPayrollAdjustment(PayrollAdjustment(
          employeeId: e, kind: AdjustmentKind.penalty, amount: 50, year: 2025,
          month: 6, reason: 'تأخير متكرر'));
      final bonus = await db.createPayrollAdjustment(PayrollAdjustment(
          employeeId: e, kind: AdjustmentKind.bonus, amount: 200, year: 2025,
          month: 6, reason: 'تميز'));
      await db.decidePayrollAdjustment(pen, approve: true);
      // bonus left pending ⇒ not in payroll.
      final r = await run();
      var l = await lineOf(r, e);
      expect(item(l, PayItemCode.penalty), 50);
      expect(item(l, PayItemCode.bonus), 0);
      await db.decidePayrollAdjustment(bonus, approve: true);
      await db.recomputePayrollRun(r, now: _now);
      l = await lineOf(r, e);
      expect(item(l, PayItemCode.bonus), 200);
      await db.reviewPayrollRun(r);
      await db.approvePayrollRun(r);
      final entry = await db.postPayrollRun(r);
      expect((await db.listPayrollAdjustments(employeeId: e))
          .every((a) => a.payrollRunId == r), isTrue);
      expect(await db.employeeAdvanceBalance(e), 0);
      await expectLater(db.decidePayrollAdjustment(pen, approve: false),
          throwsA(isA<HrException>()));

      final reversal = await db.reversePayrollRun(r, reason: 'إعادة احتساب');
      expect(reversal, isNot(entry));
      expect(reversal, greaterThan(0));
      expect((await db.getPayrollRun(r)).status, PayrollRunStatus.reversed);
      expect(await db.employeeAdvanceBalance(e), 500);
      expect((await db.listEmployeeAdvances(employeeId: e)).single.id, adv);
      expect((await db.listPayrollAdjustments(employeeId: e))
          .every((a) => a.payrollRunId == null), isTrue);
      final rev = await jeByCode(reversal);
      final orig = await jeByCode(entry);
      for (final code in orig.keys) {
        expect(rev[code]!.$1, orig[code]!.$2, reason: code);
      }

      // A fresh run for the month is allowed after the reversal; bulk pay.
      final r2 = await run();
      await db.reviewPayrollRun(r2);
      await db.approvePayrollRun(r2);
      await db.postPayrollRun(r2);
      final v = await db.payPayrollRun(r2, safeId: safeId, bulk: true);
      expect(v, hasLength(1));
      final txn = await (db.select(db.safeTransactions)
            ..where((t) => t.id.equals(v.single)))
          .getSingle();
      expect(txn.amount, (await db.getPayrollRun(r2)).net);
      expect((await db.getPayrollRun(r2)).status, PayrollRunStatus.paid);
    });
  });

  group('النقلُ من الشاشة القديمة والصلاحيّات والمزامنة', () {
    test('رواتبُ الشاشة القديمة وسلفُها وخصوماتُها تُنسخ تاريخاً للقراءة', () async {
      final e = await employee('قديم');
      await db.into(db.salaryPayments).insert(SalaryPaymentsCompanion.insert(
          employeeId: e,
          amount: 2800,
          paymentDate: DateTime(2025, 3, 30),
          period: const Value('2025-03')));
      await db.into(db.salaryPayments).insert(SalaryPaymentsCompanion.insert(
          employeeId: e,
          amount: 100,
          paymentDate: DateTime(2025, 3, 30),
          period: const Value('2025-03'),
          type: const Value('bonus')));
      await db.into(db.employeeTransactions).insert(
          EmployeeTransactionsCompanion.insert(
              employeeId: e,
              transactionType: 'advance',
              amount: 600,
              transactionDate: DateTime(2025, 4, 3)));
      await db.into(db.employeeTransactions).insert(
          EmployeeTransactionsCompanion.insert(
              employeeId: e,
              transactionType: 'deduction',
              amount: 40,
              transactionDate: DateTime(2025, 3, 10)));
      await db.migrateLegacyPayroll();
      await db.migrateLegacyPayroll();
      final runs = await db.listPayrollRuns();
      expect(runs, hasLength(1));
      final legacy = runs.single;
      expect(legacy.legacy, isTrue);
      expect(legacy.period, '2025-03');
      expect(legacy.status, PayrollRunStatus.paid);
      final l = await lineOf(legacy.id, e);
      expect(l.gross, 2900);
      expect(l.isPaid, isTrue);
      expect(l.items, hasLength(2));
      final adv = (await db.listEmployeeAdvances(employeeId: e)).single;
      expect(adv.legacy, isTrue);
      expect(adv.balance, 600);
      expect(adv.safeTransactionId, isNull);
      final pen = (await db.listPayrollAdjustments(employeeId: e)).single;
      expect(pen.kind, AdjustmentKind.penalty);
      expect(pen.payrollRunId, legacy.id,
          reason: 'a deduction of a month the legacy screen paid is consumed');
      await expectLater(db.reviewPayrollRun(legacy.id),
          throwsA(isA<HrException>()));
      await expectLater(db.recomputePayrollRun(legacy.id),
          throwsA(isA<HrException>()));
    });

    test('الأدوارُ تُمنَح أكوادَ الرواتب مرّةً، والمديرُ يملكها', () async {
      await db.syncAllPermissions();
      Future<int> perm(String code) async => (await (db.select(db.permissions)
                ..where((p) => p.code.equals(code)))
              .getSingle())
          .id;
      final hr =
          await db.into(db.roles).insert(RolesCompanion.insert(name: 'شؤون'));
      final payroll =
          await db.into(db.roles).insert(RolesCompanion.insert(name: 'رواتب'));
      await db.addPermissionToRole(hr, await perm(PermissionCodes.hrManage));
      await db.addPermissionToRole(
          payroll, await perm(PermissionCodes.hrPayrollProcess));
      await db.customStatement(
          "DELETE FROM settings WHERE key = 'hr_payroll_perm_backfill_done'");
      await db.backfillHrPayrollPermissionsOnce();
      await db.backfillHrPayrollPermissionsOnce();
      Future<Set<String>> codes(int role) async =>
          {for (final p in await db.getPermissionsForRole(role)) p.code};
      expect(await codes(hr), contains(PermissionCodes.hrPayrollView));
      expect(await codes(hr), isNot(contains(PermissionCodes.hrPayrollPost)));
      expect(
          await codes(payroll),
          containsAll([
            PermissionCodes.hrPayrollView,
            PermissionCodes.hrPayrollEdit,
            PermissionCodes.hrPayrollApprove,
            PermissionCodes.hrPayrollPost,
          ]));
      final admin = await (db.select(db.roles)
            ..where((r) => r.name.equals('مدير النظام'))
            ..orderBy([(r) => OrderingTerm.asc(r.id)])
            ..limit(1))
          .getSingle();
      expect(
          await codes(admin.id),
          containsAll([
            PermissionCodes.hrPayrollView,
            PermissionCodes.hrPayrollEdit,
            PermissionCodes.hrPayrollApprove,
            PermissionCodes.hrPayrollPost,
            PermissionCodes.hrAdvancesManage,
            PermissionCodes.hrCommissionsManage,
          ]));
    });

    test('الجداولُ التسعةُ في قوائم المزامنة، وتعبر نسخةَ SELECT *', () async {
      for (final t in _newTables) {
        expect(DeltaPullService.pullTables, contains(t));
        expect(DeltaPullService.deltaOnlyTables, contains(t));
        expect(DeltaPullService.branchScopedPullTables, contains(t));
        expect(IdNamespaceService.namespacedTables, contains(t));
        expect(AppDatabase.syncHardenedTablesForTest, contains(t));
        final cols = {
          for (final c in await db.customSelect('PRAGMA table_info($t)').get())
            c.data['name'] as String,
        };
        expect(
            cols,
            containsAll(<String>[
              'global_id',
              'last_modified_at',
              'deleted_at',
              'origin_client_id',
              'row_version',
            ]),
            reason: t);
      }
      final e = await employee('منقول');
      await db.savePayrollRules(const PayrollRules(overtimeRate: 1.5));
      await db.saveSalaryComponent(const SalaryComponent(name: 'بدل', amount: 100));
      await db.saveCommissionPlan(const CommissionPlan(name: 'خطة', salesRatePct: 1));
      await db.createEmployeeAdvance(
          employeeId: e, amount: 300, safeId: safeId, date: DateTime(2025, 5, 2));
      await db.createPayrollAdjustment(PayrollAdjustment(
          employeeId: e, kind: AdjustmentKind.bonus, amount: 10, year: 2025,
          month: 6, reason: 'ب'));
      final r = await run();
      final before = await lineOf(r, e);

      final other = AppDatabase.forTesting();
      addTearDown(other.close);
      await other.customSelect('SELECT 1').get();
      for (final table in ['employees', ..._newTables]) {
        for (final row in await db.customSelect('SELECT * FROM $table').get()) {
          final cols = row.data.keys.toList();
          await other.customStatement(
            'INSERT OR REPLACE INTO $table (${cols.join(', ')}) '
            'VALUES (${List.filled(cols.length, '?').join(', ')})',
            [for (final col in cols) row.data[col]],
          );
        }
      }
      final after = (await other.listPayrollLines(runId: r))
          .singleWhere((l) => l.employeeId == e);
      expect(after.net, before.net);
      expect(after.items.length, before.items.length);
      expect((await other.payrollRules()).overtimeRate, 1.5);
      expect((await other.listEmployeeAdvances()).single.balance, 300);
      expect((await other.listCommissionPlans()).single.salesRatePct, 1);
    });
  });
}
