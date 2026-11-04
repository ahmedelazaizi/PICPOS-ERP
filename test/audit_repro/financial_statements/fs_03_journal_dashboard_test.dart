// تدقيق القوائم المالية (2026-10-31) — دورة حياة القيد، أداة المطابقة، ونوافذ لوحة القيادة.
// J* ضوابط يُتوقَّع نجاحها؛ Y* مخالفات (فشلُ الاختبار = المخالفة)؛ O* ملاحظات رقمية.
// تشغيل: flutter test --run-skipped --concurrency=1 --dart-define=APP_BRAND=picpos <الملف>
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';

import '_fs_world.dart';

void main() {
  late ScenarioWorld w;
  double n(Object? v) => (v as num).toDouble();

  setUp(() async => w = await ScenarioWorld.create());
  tearDown(() => w.dispose());

  Future<int> approver() async {
    final roleId = await w.db.into(w.db.roles).insert(
        RolesCompanion.insert(name: 'معتمد', isSystemRole: const Value(false)));
    final p = await (w.db.select(w.db.permissions)
          ..where((x) => x.code.equals(PermissionCodes.accountingJournalApprove))
          ..limit(1))
        .getSingle();
    await w.db.addPermissionToRole(roleId, p.id);
    return w.db.createUser(
        username: 'approver', password: 'approver-pw-1', displayName: 'معتمد', roleId: roleId);
  }

  List<JournalLine> rentLines(int cash, int rent) => [
        JournalLine(accountId: rent, debit: 70),
        JournalLine(accountId: cash, credit: 70),
      ];

  test('J1 قيد مسودة لا يدخل الميزان ولا قائمة الدخل ولا الرصيد المخزَّن، ويُعتمَد من غير منشئه',
      skip: auditSkip, () async {
    final cash = (await w.db.getAccountByCode('1111'))!;
    final rent = (await w.db.getAccountByCode('623'))!;
    final id = await w.db.createDraftJournalEntry(
        description: 'إيجار مسودة',
        date: DateTime.now(),
        lines: rentLines(cash.id, rent.id),
        createdBy: w.userId);
    final inc0 = await w.db.getIncomeStatement(winFrom, winTo);
    expect(n(inc0['totalExpenses']), closeTo(0, kEps));
    expect((await w.db.getAccountByCode('623'))!.balance, closeTo(0, kEps));
    await expectLater(w.db.approveJournalEntry(id, w.userId), throwsA(anything),
        reason: 'المنشئ لا يعتمد (أو لا يملك الصلاحية)');
    final ap = await approver();
    await w.db.approveJournalEntry(id, ap);
    final inc1 = await w.db.getIncomeStatement(winFrom, winTo);
    expect(n(inc1['totalExpenses']), closeTo(70, kEps));
    expect((await w.db.getAccountByCode('623'))!.balance, closeTo(70, kEps));
    final st = await w.db.customSelect(
        'select status, is_posted, needs_approval, approved_at from journal_entries where id = ?',
        variables: [Variable<int>(id)]).getSingle();
    // ignore: avoid_print
    print('J1 after approve: ${st.data} (approved_at بالملّي ثانية بينما entry_date بالثواني)');
  });

  test('J2 العكس: الأثر صفري، ومكرَّر العكس لا يُنشئ قيداً ثانياً؛ تاريخ العكس = الآن',
      skip: auditSkip, () async {
    await w.grant(PermissionCodes.accountingJournal);
    final cash = (await w.db.getAccountByCode('1111'))!;
    final rent = (await w.db.getAccountByCode('623'))!;
    final orig = DateTime.now().subtract(const Duration(days: 3));
    final id = await w.db.createJournalEntry(
        description: 'إيجار', date: orig, lines: rentLines(cash.id, rent.id), createdBy: w.userId);
    final rev = await w.db.reverseJournalEntryById(entryId: id);
    expect(rev, greaterThan(0));
    expect(await w.db.reverseJournalEntryById(entryId: id), 0);
    expect(await w.accountNet('623'), closeTo(0, kEps));
    expect((await w.db.getAccountByCode('623'))!.balance, closeTo(0, kEps));
    final d = await w.db.customSelect('select entry_date from journal_entries where id = ?',
        variables: [Variable<int>(rev)]).getSingle();
    // ignore: avoid_print
    print('O-J2 original=${orig.millisecondsSinceEpoch ~/ 1000} reversal=${d.data['entry_date']}');
  });

  test('Y1 أداة مطابقة الأرصدة (reconcileAccounts) تستثني القيود المحذوفة كالتقارير '
      '[محاكاة حذف ناعم عبر المزامنة]', skip: auditSkip, () async {
    final cash = (await w.db.getAccountByCode('1111'))!;
    final rent = (await w.db.getAccountByCode('623'))!;
    final id = await w.db.createJournalEntry(
        description: 'إيجار', date: DateTime.now(), lines: rentLines(cash.id, rent.id));
    // محاكاة: قيد وصله حذفٌ ناعم من المزامنة (journal_sync_strategy)
    await w.db.customStatement('update journal_entries set is_deleted = 1 where id = ?', [id]);
    final repo = w.container.read(accountingRepositoryProvider);
    final calc = await repo.getCalculatedAccountBalance(rent.id);
    final inc = await w.db.getIncomeStatement(winFrom, winTo);
    // ignore: avoid_print
    print('Y1 calculated=$calc income.totalExpenses=${inc['totalExpenses']} cached=${(await w.db.getAccountByCode('623'))!.balance}');
    expect(calc, closeTo(n(inc['totalExpenses']), kEps));
  });

  test('Y2 المركز المالي متوازن وفيه ربح سنة سابقة غير مُقفلة', skip: auditSkip, () async {
    await w.db.createFiscalYear(
        name: 'السنة المالية 2025',
        startDate: DateTime(2025, 1, 1),
        endDate: DateTime(2025, 12, 31, 23, 59, 59));
    final p = await w.addProduct('PY1', price: 100, cost: 60);
    await w.db.adjustStock(
        productId: p,
        warehouseId: w.warehouseId,
        quantity: 5,
        type: 'opening_stock',
        unitCost: 60,
        movementDate: DateTime(2025, 1, 2));
    await w.sell([w.line(p, 2, 100)], date: DateTime(2025, 6, 15, 10));
    final bs = await w.db.getBalanceSheet(DateTime(2026, 6, 30));
    // ignore: avoid_print
    print('Y2 A=${bs['totalAssets']} L=${bs['totalLiabilities']} E=${bs['totalEquity']} balanced=${bs['isBalanced']}');
    expect(bs['isBalanced'], isTrue);
  });

  test('O1 لوحة القيادة «اليوم»: مرتجع اليوم على فاتورة أمس + سند صرف بخصم مكتسب',
      skip: auditSkip, () async {
    final cy = FsCycle(w);
    await cy.run(payroll: false, assets: false);
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final inc = await w.db.getIncomeStatement(from, to);
    final sa = await w.db.getSalesAnalytics(from, to);
    final rev = n(inc['totalRevenue']);
    // ignore: avoid_print
    print('O1 today: صافي الإيراد=$rev صافي الربح=${inc['netProfit']} '
        'هامش=${rev == 0 ? 0 : n(inc['netProfit']) / rev * 100}% عدد الفواتير=${sa.invoiceCount} '
        'المرتجعات(GL)=${inc['salesReturns']}');
    expect(sa.invoiceCount, 0);
    // Net sales return = 100 - (20 / 3) = 93.333; the supplier discount
    // of 10 posts to 4316 (other income), so it must not offset sales revenue.
    expect(rev, closeTo(-93.333, 0.01));
  });
}
