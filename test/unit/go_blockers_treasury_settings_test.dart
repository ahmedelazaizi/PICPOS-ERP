// ═══════════════════════════════════════════════════════════════════════════
// موانعُ Go — الدفعةُ ٣: أثرٌ مقيسٌ على الخزنة وعلى «إجمالي المرتجعات»
// وعلى ذرّيّة حفظ الإعدادات.
// ═══════════════════════════════════════════════════════════════════════════
//
// كلُّ اختبارٍ هنا يقيس **الأثر** لا يقرأ الكود: رصيدَ خزنةٍ، أو رقماً
// تُظهره الشاشة، أو صفوفاً في القاعدة. وكلُّ قيمةٍ متوقَّعةٍ **مثبَّتةٌ
// رقماً** — لا `greaterThan(0)` — لأنّ نصفَ إصلاحٍ قد يُنتج رقماً موجباً
// خاطئاً فيمرّ.
//
// والقيمةُ التي كان الكودُ المعطوبُ يُنتجها مكتوبةٌ بجانب كلِّ توكيد، فمن
// أعاد العطبَ يرى ما كان.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
  });

  tearDown(() => db.close());

  // ═════════════════════════════════════════════════════════════════════════
  // ٢‑١١ — حذفُ سندِ قبضٍ كان يَزيد الرصيدَ بدل أن ينقصه (٢× المبلغ)
  // ═════════════════════════════════════════════════════════════════════════
  group('٢‑١١ — إشارةُ عكسِ حذف السند تتبع نوعَه', () {
    test('حذفُ سند قبضٍ يُنقص الرصيدَ بمقدارِ السند بالضبط', () async {
      final safe = await db.getDefaultSafeByType('cash');
      expect(safe, isNotNull, reason: 'forTesting يزرع خزنةً نقديّةً افتراضيّة');
      final opening = safe!.balance;

      final voucherId = await db.createReceiptVoucher(
        amount: 500.0,
        category: 'other',
        description: 'قبضٌ لاختبار إشارة الحذف',
        safeId: safe.id,
        userId: 1,
      );

      final afterCreate = await db.getSafeById(safe.id);
      expect(afterCreate!.balance, closeTo(opening + 500.0, 0.001),
          reason: 'القبضُ يزيد الرصيد — شرطٌ مسبقٌ للاختبار');

      await db.deleteExpenseTransaction(voucherId);

      final afterDelete = await db.getSafeById(safe.id);
      // 🔴 الكودُ المعطوب: `adjustSafeBalance(safe.id, +tx.amount)` دائماً
      //    ⇒ opening + 1000 (‏زيادةٌ مضاعفة). الصحيحُ العودةُ إلى الافتتاح.
      expect(afterDelete!.balance, closeTo(opening, 0.001),
          reason: 'حذفُ القبض يعكسه: الرصيدُ يعود إلى ما كان، لا يقفز ٢×');
    });

    test('حذفُ سند صرفٍ ما زال يُعيد المبلغ — لم يُكسَر المسارُ السليم',
        () async {
      final safe = await db.getDefaultSafeByType('cash');
      final opening = safe!.balance;

      final voucherId = await db.createPaymentVoucher(
        amount: 300.0,
        category: 'other',
        description: 'صرفٌ لاختبار عدم الانحدار',
        safeId: safe.id,
        userId: 1,
      );

      final afterCreate = await db.getSafeById(safe.id);
      expect(afterCreate!.balance, closeTo(opening - 300.0, 0.001));

      await db.deleteExpenseTransaction(voucherId);

      final afterDelete = await db.getSafeById(safe.id);
      expect(afterDelete!.balance, closeTo(opening, 0.001),
          reason: 'مسارُ الصرفِ كان سليماً ويجب أن يبقى');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ٣‑٣ — مرتجعٌ مُلغًى بقي محسوباً في «إجمالي المرتجعات» وفي «المتبقي»
  // ═════════════════════════════════════════════════════════════════════════
  group('٣‑٣ — حركةُ مرتجعٍ محذوفةٌ ناعماً لا تُحتسَب', () {
    test('المرتجعُ يُحتسَب، وبعد حذفِ حركته يسقط إلى صفر', () async {
      final safe = await db.getDefaultSafeByType('cash');

      // حركةُ ردٍّ مرتبطةٌ بالفاتورة رقم ٩٩ — نفسُ الشكل الذي يكتبه
      // `process_sales_return_usecase` و`returns_repository_impl`.
      final refundId = await db.into(db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: 'RET-TEST-1',
              safeId: safe!.id,
              transactionType: 'payment',
              category: 'sales_return',
              amount: 800.0,
              balanceAfter: safe.balance - 800.0,
              referenceType: const Value('sales_return'),
              referenceId: const Value(99),
            ),
          );

      var amounts = await db.getReturnedAmountsForInvoices([99]);
      expect(amounts[99], closeTo(800.0, 0.001),
          reason: 'شرطٌ مسبق: المرتجعُ الحيُّ يُحتسَب');

      // حذفٌ ناعم — عينُ ما يفعله `deleteExpenseTransaction`، وهو ما
      // يبلغه `DELETE /api/expenses/{id}` بأيِّ مُعرِّف.
      await (db.update(db.safeTransactions)
            ..where((t) => t.id.equals(refundId)))
          .write(SafeTransactionsCompanion(deletedAt: Value(DateTime.now())));

      amounts = await db.getReturnedAmountsForInvoices([99]);
      // 🔴 الكودُ المعطوب: الاستعلامُ بلا `deleted_at IS NULL` ⇒ يبقى ٨٠٠
      //    إلى الأبد، فـ«المتبقي» على الفاتورة يُطرَح منه ما لم يُردَّ.
      expect(amounts[99] ?? 0.0, closeTo(0.0, 0.001),
          reason: 'المرتجعُ المحذوفُ لا يُحتسَب — لا في المتبقي ولا في البطاقة');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ٦‑٥ — `saveSettings` كانت حلقةً بلا معاملة
  // ═════════════════════════════════════════════════════════════════════════
  group('٦‑٥ — حفظُ الإعدادات ذرّيّ', () {
    test('الحفظُ الناجح يكتب كلَّ المفاتيح', () async {
      await db.saveSettings({
        'go_test_a': '1',
        'go_test_b': '2',
        'go_test_c': '3',
      });
      expect(await db.getSettingValue('go_test_a'), '1');
      expect(await db.getSettingValue('go_test_b'), '2');
      expect(await db.getSettingValue('go_test_c'), '3');
    });

    test('خريطةٌ فارغةٌ لا تفتح معاملةً ولا تُغيّر شيئاً', () async {
      await db.saveSettings(const {});
      expect(await db.getSettingValue('go_test_a'), isNull);
    });

    test('الفشلُ في منتصف الدفعة لا يترك نصفَ سياسةٍ محفوظاً', () async {
      await db.saveSettings({'go_policy_x': 'old', 'go_policy_y': 'old'});

      // مِشْغَلٌ يُسقط مفتاحاً بعينه — طريقةٌ مضمونةٌ لإحداث فشلٍ **في منتصف
      // الحلقة**. بلا هذا لا سبيلَ لإسقاط `setSetting` (‏كتابةُ مفتاحٍ ونصٍّ
      // لا تنتهك شيئاً)، وبلا فشلٍ في المنتصف لا يقيس الاختبارُ الذرّيّةَ
      // أصلاً — يمرّ لسببٍ خاطئ.
      await db.customStatement(
        "CREATE TRIGGER go_settings_boom BEFORE UPDATE ON settings "
        "WHEN NEW.key = 'go_policy_y' "
        "BEGIN SELECT RAISE(ABORT, 'go-boom'); END",
      );
      addTearDown(() async {
        await db.customStatement('DROP TRIGGER IF EXISTS go_settings_boom');
      });

      Object? thrown;
      try {
        // ترتيبُ الخريطة في Dart ترتيبُ الإدراج: `x` تُكتَب أوّلاً ثمّ `y`
        // تُسقط الدفعة.
        await db.saveSettings({'go_policy_x': 'new', 'go_policy_y': 'new'});
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isNotNull,
          reason: 'شرطٌ مسبق: المفتاحُ الثاني يُسقط الدفعة');

      // 🔴 بلا معاملة: `go_policy_x` كان يصير `new` بينما `go_policy_y`
      //    يبقى `old` — نصفُ سياسةٍ، ثمّ تُبَثُّ إلى كلِّ الأجهزة عبر
      //    `POST /api/settings` الذي يبثّ `settings` بعد الحفظ مباشرةً.
      expect(await db.getSettingValue('go_policy_x'), 'old',
          reason: 'المعاملةُ تُرجِع الكتابةَ الأولى مع سقوطِ الثانية');
      expect(await db.getSettingValue('go_policy_y'), 'old');
    });
  });
}
