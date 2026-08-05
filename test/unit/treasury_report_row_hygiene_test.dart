// ═══════════════════════════════════════════════════════════════════════════
// تقرير الخزينة — الكارت والجدول لازم يقيسوا نفس المجموعة.
// ═══════════════════════════════════════════════════════════════════════════
//
// شاشة تقرير الخزينة بتقرا الصفوف من `ReportingRepositoryImpl` (بتبني
// استعلامها بنفسها — ما بتفوّضش للـDAO)، بينما بطاقات الفترة بتيجي من
// `getTreasuryReportAnalytics` ⇒ `_dateRangeWhere` في الـDAO. تلات فروق
// مقيسة بين المسارين كانت بتخلّي الرقمين ما يتصالحوش:
//
//   ١. الحذف الناعم: `_dateRangeWhere` فيها `deleted_at IS NULL`
//      (treasury_reports_dao.dart:485) والتوأم في المستودع مفيهاش. سند صرف
//      ملغي ⇒ الكارت بيستبعده والجدول بيعرضه والتصدير بيحمله.
//
//   ٢. نافذة التاريخ: الاتنين كانوا بيعملوا `end.add(Duration(days: 1))`.
//      والشاشة بتمرّر `DateRangeFilter.normalizeRange` ⇒ النهاية أصلاً
//      23:59:59.999، فالنافذة كانت بتمتد على اليوم التالي **بالكامل**.
//      العقد الصحيح موثَّق في `dayWindowFor` (sales_invoices_controller.dart:180):
//      نافذة نصف-مفتوحة [بداية يوم البداية، بداية اليوم التالي للنهاية).
//      لاحظ إن شاشة المبيعات بتمرّر النهاية كمنتصف ليل، فالإصلاح لازم يفضل
//      محايد لها — عشان كده التطبيع بيتم داخل الدالة لا بحذف الإضافة.
//
//   ٣. القائمة الفارغة: `safeIds != null && safeIds.isNotEmpty` ⇒ فرع بلا
//      خزائن (`[]`) كان الشرط يُتخطّى ⇒ **كل** الخزائن. العُرف المثبَّت في
//      باقي المنظومة عكس ده صراحةً: null = الكل، [] = لا شيء
//      (sales_analytics_dao.dart:182, inventory_dao.dart:1219).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/reporting_repository_impl.dart';

void main() {
  late AppDatabase db;
  late ReportingRepositoryImpl repo;
  late int safeId;

  // المستخدم اختار «١٠ مايو» — والشاشة بتطبّعه لنهاية اليوم زي ما بيحصل إنتاجياً.
  final from = DateTime(2025, 5, 10);
  final toEndOfDay = DateTime(2025, 5, 10, 23, 59, 59, 999);
  final toMidnight = DateTime(2025, 5, 10);

  Future<int> insertTxn({
    required String voucher,
    required String type,
    required double amount,
    required DateTime at,
    DateTime? deletedAt,
  }) =>
      db.into(db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: voucher,
              safeId: safeId,
              transactionType: type,
              category: 'other',
              amount: amount,
              balanceAfter: 0,
              userId: const Value(1),
              createdAt: Value(at),
              deletedAt: Value(deletedAt),
            ),
          );

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = ReportingRepositoryImpl(db);
    safeId = await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'صندوق',
        balance: const Value(0),
        globalId: const Value('gid-safe-hygiene')));
  });

  tearDown(() => db.close());

  group('الحذف الناعم — الجدول لازم يستبعد اللي الكارت بيستبعده', () {
    setUp(() async {
      await insertTxn(
          voucher: 'LIVE', type: 'receipt', amount: 10000,
          at: DateTime(2025, 5, 10, 12));
      await insertTxn(
          voucher: 'VOID', type: 'receipt', amount: 50000,
          at: DateTime(2025, 5, 10, 13),
          deletedAt: DateTime(2025, 5, 11));
    });

    test('السند الملغي ما بيظهرش في صفوف الجدول', () async {
      final rows = await repo.getTransactionsByDateRange(from, toEndOfDay);
      expect(rows.map((r) => r.voucherNumber), ['LIVE'],
          reason: 'سند ملغي بـ٥٠٬٠٠٠ كان بيتعرض في الجدول ويتحمّل في التصدير');
    });

    test('مجموع الجدول == بطاقة الفترة (الرقمان يتصالحان)', () async {
      final rows = await repo.getTransactionsByDateRange(from, toEndOfDay);
      final tableTotal = rows
          .where((r) => r.transactionType == 'receipt')
          .fold<double>(0, (s, r) => s + r.amount);
      final card = await db.getTreasuryReportAnalytics(from, toEndOfDay);
      expect(tableTotal, card.periodIncome,
          reason: 'الكارت كان ١٠٬٠٠٠ والجدول ٦٠٬٠٠٠');
    });
  });

  group('نافذة اليوم — نصف مفتوحة ومطابقة لعقد dayWindowFor', () {
    setUp(() async {
      await insertTxn(
          voucher: 'TODAY', type: 'receipt', amount: 100,
          at: DateTime(2025, 5, 10, 23, 59, 59));
      await insertTxn(
          voucher: 'TOMORROW-MIDNIGHT', type: 'receipt', amount: 700,
          at: DateTime(2025, 5, 11));
      await insertTxn(
          voucher: 'TOMORROW-NOON', type: 'receipt', amount: 900,
          at: DateTime(2025, 5, 11, 12));
    });

    test('نهاية مُطبَّعة (23:59:59.999) ما بتفتحش اليوم التالي', () async {
      final rows = await repo.getTransactionsByDateRange(from, toEndOfDay);
      expect(rows.map((r) => r.voucherNumber), ['TODAY'],
          reason: '«اليوم» كان بيشمل بكرة بالكامل');
    });

    test('نهاية منتصف الليل بتدي نفس النافذة بالظبط (لا قص ليوم)', () async {
      final rows = await repo.getTransactionsByDateRange(from, toMidnight);
      expect(rows.map((r) => r.voucherNumber), ['TODAY'],
          reason: 'شاشة المبيعات بتمرّر منتصف الليل — يوم النهاية يفضل مشمولاً');
    });

    test('الكارت بيتبع نفس النافذة', () async {
      final card = await db.getTreasuryReportAnalytics(from, toEndOfDay);
      expect(card.periodIncome, 100);
      final cardMidnight = await db.getTreasuryReportAnalytics(from, toMidnight);
      expect(cardMidnight.periodIncome, 100,
          reason: 'النافذتان لازم تتطابقا مهما كانت صيغة النهاية');
    });
  });

  group('safeIds الفارغة = لا شيء (لا «كل الخزائن»)', () {
    setUp(() async {
      await insertTxn(
          voucher: 'R', type: 'receipt', amount: 100,
          at: DateTime(2025, 5, 10, 12));
    });

    test('صفوف الجدول: [] بتفشل مقفولة', () async {
      final rows =
          await repo.getTransactionsByDateRange(from, toEndOfDay, safeIds: []);
      expect(rows, isEmpty,
          reason: 'فرع بلا خزائن كان بيشوف كل خزائن الشركة');
    });

    test('الكارت: [] بتفشل مقفولة', () async {
      final card =
          await db.getTreasuryReportAnalytics(from, toEndOfDay, safeIds: []);
      expect(card.periodIncome, 0);
    });

    test('null لسه معناها الكل (سلوك غير متغيّر)', () async {
      final rows = await repo.getTransactionsByDateRange(from, toEndOfDay);
      expect(rows.length, 1);
    });
  });
}
