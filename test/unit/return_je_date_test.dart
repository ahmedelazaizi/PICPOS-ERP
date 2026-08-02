// قيد المرتجع كان بيتسجّل **بتاريخ الفاتورة الأصلية**.
//
// ── العطل ────────────────────────────────────────────────────────────────────
// `autoPostSalesReturn` كان بيمرّر `date: originalInvoice.invoiceDate`،
// والمستدعي (`returns_repository_impl.dart:525`) بيبعت **الفاتورة الأصلية**.
// نفس الشيء في `autoPostPurchaseReturn`.
//
// ── أثرين منفصلين ───────────────────────────────────────────────────────────
// ١. **إعادة تشكيل فترة منتهية:** مرتجع أغسطس بيقلّل إيراد **مارس** ويعكس
//    تكلفة مارس. قائمة دخل مارس اللي اتطبعت واتقدّمت للضرايب بتتغيّر بأثر
//    رجعي، وأغسطس بيظهر مبيعات بلا مرتجعات.
//
// ٢. **قفل كامل للمرتجعات:** `createJournalEntry` بينادي
//    `validateFinancialPeriod(date)`. فأول ما تقفل الشهر القديم، أي مرتجع
//    لفواتيره **بيترفض تماماً** — والمستدعي كان عكس المخزون والخزنة جوه نفس
//    الترانزاكشن، فالعملية كلها بترجع والكاشير مش قادر يعمل مرتجع مشروع.
//
// ── الصح محاسبياً ───────────────────────────────────────────────────────────
// المرتجع **حدث لاحق** له فترته الخاصة، مش تعديل على المستند الأصلي. ترحيله
// في فترة حدوثه هو المعالجة السليمة، وهو كمان اللي بيخلّي قفل الفترات يشتغل
// بدل ما يمنع عملية مشروعة.
//
// > مسار المرتجع السريع في POS (`sales_mutations_dao.dart:461`) كان **سليم
// > أصلاً**: بيمرّر فاتورة المرتجع نفسها (تاريخ النهاردة). المشكلة كانت في
// > ديالوج المرتجعات العادي بس.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  group('resolveReturnPostingDate — تاريخ قيد المرتجع', () {
    final invoiceDate = DateTime(2026, 3, 10);
    final returnDate = DateTime(2026, 8, 2);

    test('بيستعمل تاريخ المرتجع مش تاريخ الفاتورة الأصلية', () {
      expect(
        resolveReturnPostingDate(
            returnDate: returnDate, originalInvoiceDate: invoiceDate),
        returnDate,
      );
    });

    test('لو تاريخ المرتجع مش متحدد بيقع على تاريخ الفاتورة', () {
      // المسارات القديمة اللي لسه ما بتمرّرش تاريخ لازم تفضل شغّالة بالسلوك
      // القديم بدل ما ترمي — الانتقال بيبقى تدريجي مش كسر.
      expect(
        resolveReturnPostingDate(
            returnDate: null, originalInvoiceDate: invoiceDate),
        invoiceDate,
      );
    });

    test('مرتجع في نفس يوم الفاتورة بيدي نفس التاريخ', () {
      expect(
        resolveReturnPostingDate(
            returnDate: invoiceDate, originalInvoiceDate: invoiceDate),
        invoiceDate,
      );
    });

    test('مرتجع بتاريخ أقدم من الفاتورة بيتاخد زي ما هو', () {
      // إدخال بأثر رجعي بقرار محاسب — الدالة ما بتصححش نية المستخدم،
      // `validateFinancialPeriod` هي اللي بترفض لو الفترة مقفولة.
      final earlier = DateTime(2026, 2, 1);
      expect(
        resolveReturnPostingDate(
            returnDate: earlier, originalInvoiceDate: invoiceDate),
        earlier,
      );
    });
  });
}
