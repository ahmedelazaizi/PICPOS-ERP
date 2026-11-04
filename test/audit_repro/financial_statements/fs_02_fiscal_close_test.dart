// تدقيق القوائم المالية (2026-10-31) — إقفال السنة المالية والأرباح المحتجزة.
//
// C1..C3 ضوابط يُتوقَّع نجاحها؛ X1..X3 مخالفات (فشلُ الاختبار = المخالفة).
// تشغيل: flutter test --run-skipped --concurrency=1 --dart-define=APP_BRAND=picpos <الملف>
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';
import 'package:picpos_erp/core/permissions/fiscal_permission_codes.dart';

import '_fs_world.dart';

void main() {
  late ScenarioWorld w;
  late int product;

  double n(Object? v) => (v as num).toDouble();

  /// سنة 2025 بنهاية [end]، فتراتها الشهرية، مخزون افتتاحي بتاريخ 2025-01-02.
  Future<int> setupYear(DateTime end) async {
    final fy = await w.db.createFiscalYear(
        name: 'السنة المالية 2025', startDate: DateTime(2025, 1, 1), endDate: end);
    await w.db.generatePeriodsForYear(fy, DateTime(2025, 1, 1), end);
    product = await w.addProduct('FY1', price: 100, cost: 60);
    await w.db.adjustStock(
        productId: product,
        warehouseId: w.warehouseId,
        quantity: 10,
        type: 'opening_stock',
        unitCost: 60,
        movementDate: DateTime(2025, 1, 2));
    return fy;
  }

  Future<void> closeAllPeriods(int fy) async {
    await (w.db.update(w.db.accountingPeriods)
          ..where((p) => p.fiscalYearId.equals(fy)))
        .write(const AccountingPeriodsCompanion(isClosed: Value(true)));
  }

  Future<double> netOf(String code, DateTime from, DateTime to) async {
    final r = await w.db.customSelect(
        'select coalesce(sum(l.debit - l.credit),0) n from journal_entry_lines l '
        'join journal_entries e on e.id = l.entry_id join accounts a on a.id = l.account_id '
        'where e.is_posted = 1 and e.is_deleted = 0 and a.code = ? and e.entry_date between ? and ?',
        variables: [
          Variable<String>(code),
          Variable<int>(from.millisecondsSinceEpoch ~/ 1000),
          Variable<int>(to.millisecondsSinceEpoch ~/ 1000)
        ]).getSingle();
    return n(r.data['n']);
  }

  setUp(() async => w = await ScenarioWorld.create());
  tearDown(() => w.dispose());

  group('سنة تنتهي 23:59:59', () {
    late int fy;
    late double preCloseProfit;
    final end = DateTime(2025, 12, 31, 23, 59, 59);

    setUp(() async {
      fy = await setupYear(end);
      await w.sell([w.line(product, 2, 100)], date: DateTime(2025, 6, 15, 10));
      await w.sell([w.line(product, 1, 100)], date: DateTime(2025, 12, 31, 15));
      preCloseProfit =
          n((await w.db.getIncomeStatement(DateTime(2025, 1, 1), end))['netProfit']);
      await closeAllPeriods(fy);
      await w.grant(FiscalPermissionCodes.fiscalYearClose);
      await w.db.closeFiscalYear(fy, w.userId);
    });

    test('C1 صافي الربح قبل الإقفال = المرحَّل إلى الأرباح المحتجزة (313)', skip: auditSkip,
        () async {
      expect(preCloseProfit, closeTo(300 - 180, kEps));
      final close = await w.db.customSelect(
          "select coalesce(sum(l.credit - l.debit),0) n from journal_entry_lines l "
          "join journal_entries e on e.id = l.entry_id join accounts a on a.id = l.account_id "
          "where e.reference_type = 'fiscal_close' and a.code = '313'").getSingle();
      expect(n(close.data['n']), closeTo(preCloseProfit, kEps));
    });

    test('C2 حسابات النتيجة مُصفَّرة للسنة بعد الإقفال', skip: auditSkip, () async {
      expect(await netOf('4121', DateTime(2025, 1, 1), end), closeTo(0, kEps));
      expect(await netOf('5211', DateTime(2025, 1, 1), end), closeTo(0, kEps));
    });

    test('C3 المركز المالي في 2026 متوازن بعد الإقفال', skip: auditSkip, () async {
      final bs = await w.db.getBalanceSheet(DateTime(2026, 6, 30));
      expect(bs['isBalanced'], isTrue);
    });

    test('X1 قائمة الدخل للسنة المقفلة تبقى تعرض صافي الربح الفعلي (لا صفراً)',
        skip: auditSkip, () async {
      final after = await w.db.getIncomeStatement(DateTime(2025, 1, 1), end);
      // ignore: avoid_print
      print('X1 pre=$preCloseProfit post=${after['netProfit']} rev=${after['totalRevenue']}');
      expect(n(after['netProfit']), closeTo(preCloseProfit, kEps));
    });
  });

  group('سنة تنتهي 2025-12-31 00:00 (كما يُنشئها حوار السنوات/معالج الإعداد)', () {
    test('X2 بيع بتاريخ 2025-12-31 15:00 مقبول (آخر يوم في السنة)', skip: auditSkip,
        () async {
      await setupYear(DateTime(2025, 12, 31));
      final r = await w.sellRaw([w.line(product, 1, 100)],
          date: DateTime(2025, 12, 31, 15));
      // ignore: avoid_print
      print('X2 isSuccess=${r.isSuccess} error=${r.errorMessage}');
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
    });

    test('X3 قيد يوم 31/12 (بعد 00:00) يُقفَل مع السنة ولا يبقى يتيماً', skip: auditSkip,
        () async {
      final fy = await setupYear(DateTime(2025, 12, 31));
      await w.sell([w.line(product, 2, 100)], date: DateTime(2025, 6, 15, 10));
      // قيد يدوي بتاريخ 31/12 الساعة 15:00 (opening_balance مستثنى من بوابة الفترة)
      final cash = (await w.db.getAccountByCode('1111'))!;
      final sales = (await w.db.getAccountByCode('4121'))!;
      await w.db.createJournalEntry(
          description: 'إيراد آخر يوم',
          date: DateTime(2025, 12, 31, 15),
          referenceType: 'opening_balance',
          lines: [
            JournalLine(accountId: cash.id, debit: 50),
            JournalLine(accountId: sales.id, credit: 50),
          ]);
      await closeAllPeriods(fy);
      await w.grant(FiscalPermissionCodes.fiscalYearClose);
      await w.db.closeFiscalYear(fy, w.userId);
      final orphan =
          await netOf('4121', DateTime(2025, 12, 31), DateTime(2025, 12, 31, 23, 59, 59));
      final bs = await w.db.getBalanceSheet(DateTime(2026, 6, 30));
      // ignore: avoid_print
      print('X3 orphan4121=$orphan bsBalanced=${bs['isBalanced']} '
          'A=${bs['totalAssets']} L=${bs['totalLiabilities']} E=${bs['totalEquity']}');
      expect(bs['isBalanced'], isTrue);
      expect(await netOf('4121', DateTime(2025, 1, 1), DateTime(2025, 12, 31, 23, 59, 59)),
          closeTo(0, kEps));
    });
  });
}
