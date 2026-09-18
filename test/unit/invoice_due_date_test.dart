// «تاريخ الاستحقاق» **مرآةٌ مشتقّة** — قرارُ المالك 2026-09-18 على تصميمَي
// فاتورة المشتريات وفاتورة المبيعات، وقاعدةُ ح‑١.
//
// ═══ ما يحرسه هذا الملفّ ═══
//
// التصميمُ يرسم الاستحقاقَ حقلَ تاريخٍ يُكتَب بنجمةِ إلزام، والمحرّكُ
// يشتقّه من مهلة الطرف ولا يقرأ ما يكتبه المستخدم. فحقلٌ يُملأ ويُتجاهَل
// يعد بأجلٍ لا يقع.
//
// 🔴 **و`null` ليست «يُستحقُّ اليوم».** عمودُ `due_date` يقرأ فراغَه على
// أنّه «بلا مهلة» فيرجع إلى `invoice_date` في حساب التقادم
// (`COALESCE(due_date, invoice_date)`). فكتابةُ تاريخ الفاتورة نفسِه تُنتج
// نفسَ رقم التقادم اليومَ، لكنّها تمحو التفرقةَ بين «فاتورةٍ بلا أجل»
// و«فاتورةٍ أجلُها صفر» على كلّ صفٍّ قديم — وأيُّ تقريرٍ يفرّق بينهما لاحقاً
// يقرأ الماضيَ خطأً.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/invoice_due_date.dart';

void main() {
  final issued = DateTime(2026, 9, 8);

  test('مهلةٌ موجبةٌ تُضاف إلى تاريخ الفاتورة', () {
    expect(
      resolveDueDateFromTerms(invoiceDate: issued, paymentTermsDays: 30),
      DateTime(2026, 10, 8),
    );
  });

  test('وتعبر آخرَ الشهر وآخرَ السنة', () {
    expect(
      resolveDueDateFromTerms(
          invoiceDate: DateTime(2026, 12, 20), paymentTermsDays: 30),
      DateTime(2027, 1, 19),
    );
  });

  test('وبلا مهلةٍ ⇒ `null` لا تاريخُ الفاتورة', () {
    expect(resolveDueDateFromTerms(invoiceDate: issued, paymentTermsDays: 0),
        isNull);
    expect(resolveDueDateFromTerms(invoiceDate: issued, paymentTermsDays: null),
        isNull);
  });

  test('وسالبٌ يُقرأ «بلا مهلة» لا استحقاقاً في الماضي', () {
    // مهلةٌ سالبةٌ صفٌّ تالف، واستحقاقٌ قبل الإصدار يجعل الفاتورةَ متأخّرةً
    // لحظةَ إنشائها ويطلقُ تنبيهَ تأخّرٍ كاذباً.
    expect(resolveDueDateFromTerms(invoiceDate: issued, paymentTermsDays: -10),
        isNull);
  });

  test('والوقتُ يُحفظ كما هو — لا يُقرَّب إلى منتصف الليل', () {
    // `invoice_date` يحمل وقتاً، وطرحُ تاريخَين في التقادم يقع بالثواني.
    final at = DateTime(2026, 9, 8, 14, 35);
    expect(
      resolveDueDateFromTerms(invoiceDate: at, paymentTermsDays: 1),
      DateTime(2026, 9, 9, 14, 35),
    );
  });
}
