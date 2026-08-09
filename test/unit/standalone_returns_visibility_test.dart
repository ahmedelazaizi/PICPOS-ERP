// ═══════════════════════════════════════════════════════════════════════════
// مرتجعُ التنصيب المستقلّ كان غيرَ مرئيّ — ويُحتسب بيعاً.
// ═══════════════════════════════════════════════════════════════════════════
//
// بلاغان ميدانيان جذرُهما واحد:
//   ١. «تقرير المرتجع في نظام مستقل لا يظهر».
//   ٢. «تقرير فواتير المبيعات يُظهر المرتجعات الجزئية أو الكاملة فواتيرَ بيع».
//
// ── لماذا ─────────────────────────────────────────────────────────────────
// في المسار المستقلّ لا يُكتب **مستندُ مرتجعٍ إطلاقاً**. `processSalesReturn`
// يُولّد رقم `SRET-` لسندات الخزينة والقيد فقط، وأثرُه الوحيد على البيانات:
//   • قلبُ حالة الفاتورة الأصلية إلى `returned`/`partial_return`، و
//   • صفٌّ في `safe_transactions` بـ`reference_type='sales_return'`
//     و`reference_id` = معرّفُ الفاتورة الأصلية، يحمل **المبلغ المرتجَع
//     وتاريخَه الحقيقي**.
// فالفاتورةُ الأصلية هي السجلّ الوحيد.
//
// ── العطلان بالضبط ────────────────────────────────────────────────────────
// ١. `getSalesReturnHistoryEntries` يفلتر «الشكل أ» بـ`invoiceDate` — تاريخِ
//    **البيع** لا المرتجع. فبيعُ يوليو المرتجَع في أغسطس يختفي من تقرير
//    أغسطس، والمدى الافتراضي للشاشة (أوّل الشهر → اليوم) يعني أن أيّ مرتجعٍ
//    لفاتورةٍ أقدم غيرُ مرئيّ.
//
// ٢. `getSalesInvoiceSummary` يجمع «إجمالي المرتجعات» من صفوف
//    `sale_type='return'` وحدَها — وهي **معدومةٌ** في المستقلّ — فيخرج صفراً
//    دائماً بينما الفاتورةُ المرتجَعة تدخل «إجمالي المبيعات» بقيمتها الكاملة:
//    مبيعاتٌ منتفخة · مرتجعاتٌ صفر · صافٍ = المجمل.
//    وتعليقُ الدالة كان يدّعي أنه «يعكس مصدرَي `getReturnedAmountsForInvoices`»
//    وهو لا يفعل — فالبطاقةُ تخالف «المتبقي» في الصفوف تحتها.
//
// ── الدلالةُ المعتمدة ─────────────────────────────────────────────────────
//   مجملٌ بالقيمة الكاملة (باستثناء مستندات المرتجع) − المرتجعُ الفعلي = صافٍ
// ولا تُحذَف الفاتورةُ المرتجَعة من المجمل: حذفُها **مع** عدّها في المرتجعات
// يخصم المبلغَ مرتين (‏١٠٠٠ مرتجعة ⇒ صفر − ١٠٠٠ = سالب ١٠٠٠). وهي دلالةُ
// قائمة الدخل: المردوداتُ حسابٌ مقابلٌ للإيراد لا حذفٌ منه.
//
// ⚠️ ولا يكشف هذا الاختبارَ `client_issue_m6_sales_summary_test`: فيه ستُّ
//    حالاتٍ و**صفرُ** إشارةٍ إلى `safe_transactions` — كلُّها تكتب الشكل ب.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;
  late int safeId;
  var seq = 0;

  setUp(() async {
    db = AppDatabase.forTesting();
    warehouseId = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(
            name: 'مخزن ر', globalId: const Value('gid-wh-sr')));
    userId = await db.into(db.users).insert(UsersCompanion.insert(
          username: 'sr_user',
          passwordHash: 'x',
          displayName: 'SR',
          roleId: const Value(1),
        ));
    safeId = await db
        .into(db.safes)
        .insert(SafesCompanion.insert(name: 'خزنة ر'));
  });

  tearDown(() async => db.close());

  Future<int> sale(double total, DateTime date, {int? whId}) =>
      db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: 'SR-${++seq}',
            warehouseId: whId ?? warehouseId,
            userId: userId,
            invoiceDate: date,
            total: Value(total),
            paid: Value(total),
          ));

  /// يكتب ما يكتبه المسارُ المستقلّ **بالضبط**: قلبُ الحالة + صفُّ خزينةٍ
  /// بالمبلغ المرتجَع وتاريخِ المرتجع. ولا مستندَ مرتجعٍ إطلاقاً.
  Future<void> standaloneReturn(
    int invoiceId,
    double amount,
    DateTime returnedAt, {
    bool partial = false,
  }) async {
    await db.updateSalesInvoiceStatus(
        invoiceId, partial ? 'partial_return' : 'returned');
    await db.into(db.safeTransactions).insert(SafeTransactionsCompanion.insert(
          voucherNumber: 'SRET-${++seq}',
          safeId: safeId,
          transactionType: 'payment',
          category: 'sales',
          amount: amount,
          balanceAfter: 0,
          referenceType: const Value('sales_return'),
          referenceId: Value(invoiceId),
          createdAt: Value(returnedAt),
        ));
  }

  final julyDate = DateTime(2026, 7, 15);
  final augWindowStart = DateTime(2026, 8, 1);
  final augWindowEnd = DateTime(2026, 8, 31);
  final augReturnDate = DateTime(2026, 8, 9, 11, 30);

  group('سجلّ المرتجعات يُفلتر بتاريخ المرتجع لا بتاريخ البيع', () {
    test('بيعُ يوليو المرتجَع في أغسطس يظهر في تقرير أغسطس', () async {
      final inv = await sale(1000, julyDate);
      await standaloneReturn(inv, 1000, augReturnDate);

      final rows =
          await db.getSalesReturnHistoryEntries(augWindowStart, augWindowEnd);
      expect(rows.map((e) => e.originalInvoiceId), [inv],
          reason: 'الفلترةُ بـinvoiceDate تُخفي كلَّ مرتجعٍ لفاتورةٍ أقدم — '
              'والمدى الافتراضي للشاشة هو الشهرُ الجاري');
    });

    test('مرتجعٌ جزئيّ لفاتورةٍ أقدم يظهر كذلك', () async {
      final inv = await sale(500, julyDate);
      await standaloneReturn(inv, 300, augReturnDate, partial: true);

      final rows =
          await db.getSalesReturnHistoryEntries(augWindowStart, augWindowEnd);
      expect(rows.map((e) => e.originalInvoiceId), [inv]);
    });

    test('ضابط: مرتجعٌ خارج المدى لا يظهر', () async {
      final inv = await sale(1000, julyDate);
      await standaloneReturn(inv, 1000, DateTime(2026, 5, 20));

      expect(
          await db.getSalesReturnHistoryEntries(augWindowStart, augWindowEnd),
          isEmpty,
          reason: 'التوسعةُ إضافيةٌ لا إلغاءٌ للمدى');
    });

    test('ضابط: بيعٌ بلا مرتجعٍ لا يظهر', () async {
      await sale(700, DateTime(2026, 8, 5));

      expect(
          await db.getSalesReturnHistoryEntries(augWindowStart, augWindowEnd),
          isEmpty);
    });

    test('ضابط: بيعُ أغسطس المرتجَع في أغسطس لا يتكرّر صفَّين', () async {
      final inv = await sale(400, DateTime(2026, 8, 3));
      await standaloneReturn(inv, 400, augReturnDate);

      final rows =
          await db.getSalesReturnHistoryEntries(augWindowStart, augWindowEnd);
      expect(rows, hasLength(1),
          reason: 'الفاتورةُ تطابق الشرطين معاً — الـOR لا يضاعفها');
    });
  });

  group('«إجمالي المرتجعات» يقرأ المصدرَين لا مستنداتِ المرتجع وحدها', () {
    test('مرتجعٌ كاملٌ وجزئيّ في نفس النافذة', () async {
      final full = await sale(1000, DateTime(2026, 8, 5));
      final part = await sale(500, DateTime(2026, 8, 6));
      await sale(200, DateTime(2026, 8, 7)); // بلا مرتجع
      await standaloneReturn(full, 1000, augReturnDate);
      await standaloneReturn(part, 300, augReturnDate, partial: true);

      final s = await db.getSalesInvoiceSummary(
          from: augWindowStart, to: augWindowEnd);

      expect(s.invoiceCount, 3,
          reason: 'الفاتورةُ المرتجَعة تبقى في القائمة معلَّمةً بشارة');
      expect(s.totalAmount, closeTo(1700, 0.001),
          reason: 'المجملُ بالقيمة الكاملة — حذفُها منه مع عدّها في '
              'المرتجعات يخصم مرتين');
      expect(s.totalReturns, closeTo(1300, 0.001),
          reason: 'كانت صفراً: المصدرُ الوحيد المقروء كان sale_type=return');
      expect(s.netSales, closeTo(400, 0.001));
    });

    test('البطاقةُ توافق «المتبقي» في الصفوف — نفسُ المصدرَين', () async {
      final inv = await sale(1000, DateTime(2026, 8, 5));
      await standaloneReturn(inv, 400, augReturnDate, partial: true);

      final s = await db.getSalesInvoiceSummary(
          from: augWindowStart, to: augWindowEnd);
      final perRow = await db.getReturnedAmountsForInvoices([inv]);

      expect(s.totalReturns, closeTo(perRow[inv] ?? 0, 0.001),
          reason: 'تعليقُ الدالة كان يدّعي هذا التوافقَ ولا يحقّقه');
    });

    test('ضابط: مرتجعٌ خارج النافذة لا يُخصَم منها', () async {
      final inv = await sale(1000, DateTime(2026, 8, 5));
      await standaloneReturn(inv, 1000, DateTime(2026, 9, 2));

      final s = await db.getSalesInvoiceSummary(
          from: augWindowStart, to: augWindowEnd);
      expect(s.totalReturns, closeTo(0, 0.001));
      expect(s.netSales, closeTo(1000, 0.001));
    });

    test('ضابط: حصرُ المخزن يُطبَّق على الفاتورة الأصلية', () async {
      // ‏`safe_transactions` لا تحمل مخزناً ولا فرعاً، فالحصرُ لا بدّ أن يمرّ
      // عبر الفاتورة الأصلية وإلا خُصم مرتجعُ مخزنٍ آخر من هذا المخزن.
      final other = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
              name: 'مخزن آخر', globalId: const Value('gid-wh-sr2')));
      final mine = await sale(1000, DateTime(2026, 8, 5));
      final theirs = await sale(800, DateTime(2026, 8, 5), whId: other);
      await standaloneReturn(mine, 100, augReturnDate, partial: true);
      await standaloneReturn(theirs, 800, augReturnDate);

      final s = await db.getSalesInvoiceSummary(
        from: augWindowStart,
        to: augWindowEnd,
        warehouseIds: [warehouseId],
      );
      expect(s.totalAmount, closeTo(1000, 0.001));
      expect(s.totalReturns, closeTo(100, 0.001),
          reason: 'مرتجعُ المخزن الآخر (٨٠٠) ليس من هذا المخزن');
    });
  });
}
