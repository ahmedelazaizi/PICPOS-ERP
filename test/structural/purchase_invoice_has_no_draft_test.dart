// حارسُ العقد: فاتورةُ المشتريات **خطوةٌ واحدة** — لا زرَّ مسوّدةٍ خلفَه لا
// شيء.
//
// ═══ ما كان ═══
//
// زرُّ «حفظ كمسودة» كان ينادي `_handleSavePurchaseSimple(isDraft: true)`،
// و`isDraft` **مُعلَنٌ في ثلاث دوالَّ ومُمرَّرٌ في اثنتَين ولا يُقرأ في
// موضعٍ واحد**. فالمسوّدةُ كانت تسلك عينَ مسار الحفظ:
//
//   ‏• المخزونُ يتحرّك · القيدُ يُرحَّل · ذمّةُ المورّد تُقيَّد
//   ‏• بـ`paymentMethod: 'credit'` و`paid: 0` ⇒ **فاتورةٌ آجلةٌ قائمة**
//   ‏• 🔴 و`warehouseId: null` ⇒ `resolveAssignedWarehouseId` يرجع **أوّلَ
//     مخزنٍ في النطاق**، فتُختَم الفاتورةُ على مخزنٍ غيرِ الذي اختاره
//     المستخدمُ في النموذج، ويخرج المخزونُ من مكانٍ آخر.
//
// و`flutter analyze` لا يشكو معاملاً غيرَ مقروء، فالثلاثةُ عاشت صامتة.
//
// ═══ والقرار ═══
//
// قرارُ المالك 2026-09-19: **يُحذَف الزرّ** — خطوةٌ واحدةٌ كما في مردود
// المشتريات حرفاً («ترحيلٌ بخطوةٍ واحدة، لا دورةَ مسوّدة»).
//
// ⚠️ **والمبيعاتُ تحتفظ بزرّها**: «حفظ كعرض سعر» هناك ينادي `_saveQuotation`
// — مستندٌ آخرُ حقيقيٌّ له تبويبُه، لا اسمٌ على نفس المسار.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// نصُّ الملفّ بلا أسطر التعليق وبلا `\r` — أغلبُ الملفّات هنا CRLF.
String _code(String path) => [
      for (final line in File(path).readAsStringSync().split('\n'))
        if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
    ].join('\n');

const _purchasePath =
    'lib/presentation/purchases_picpos/screens/purchases_picpos_crud.dart';
const _salesPath =
    'lib/presentation/sales_invoices_picpos/screens/sales_invoice_dialogs.dart';
const _formPath =
    'lib/presentation/invoice_form_picpos/picpos_invoice_form.dart';
const _moneyPath =
    'lib/presentation/invoice_form_picpos/picpos_invoice_money.dart';

void main() {
  test('شاشةُ المشتريات لا توصّل فعلَ مسوّدةٍ إطلاقاً', () {
    expect(_code(_purchasePath).contains('onSaveDraft'), isFalse,
        reason: 'الزرُّ عاد — ومسارُه يرحّل فاتورةً آجلةً كاملةً على أوّل '
            'مخزنٍ في النطاق');
  });

  test('ولا يصل `isDraft` إلى مسار الحفظ — ولا يُمرَّر', () {
    // 🔴 معاملٌ يُمرَّر ولا يُقرأ لا يشكو منه `analyze`، وبقاؤه في السلسلة
    // يدعو إلى إعادة توصيله يوماً بنفس العطب. فيُقطَع عند **المصبّ**.
    //
    // ⚠️ **ويبقى في توقيعَي ردِّ نداءِ `PurchaseInvoiceForm` القديم** (٤٨
    // و٣٠٦): توقيعُهما يمليه ذلك النموذجُ المشترك، وحذفُه منه يمسّ ودجتاً
    // تستعملها شاشةُ UralCash أيضاً — ورعايةُ ح‑٣ أن تُنسَخ لا أن تُشارَك.
    // فالمقيسُ هنا أنّ القيمةَ **لا تغادرهما**.
    final code = _code(_purchasePath);

    expect(code.contains('isDraft: isDraft'), isFalse,
        reason: 'القيمةُ ما زالت تُمرَّر إلى مسار الحفظ');
    expect(code.contains('isDraft: true'), isFalse,
        reason: 'منادٍ ما زال يطلب مسوّدةً — وهي فاتورةٌ آجلةٌ مرحَّلة');
    expect(code.contains('isDraft: false'), isFalse,
        reason: 'المعاملُ حُذف من `_handleSavePurchaseSimple` فلا معنى '
            'لتمريره');

    final at = code.indexOf('Future<void> _handleSavePurchaseSimple({');
    expect(at, greaterThan(0), reason: 'لم أجد دالّةَ الحفظ');
    final end = code.indexOf('}) async {', at);
    expect(end, greaterThan(at));
    expect(code.substring(at, end).contains('isDraft'), isFalse,
        reason: 'مسارُ الحفظ ما زال يعلن معاملاً لا يقرؤه أحد');
  });

  test('والمبيعاتُ تحتفظ بعرض السعر — وهو مستندٌ آخرُ حقيقيّ', () {
    final sales = _code(_salesPath);
    expect(sales.contains('onSaveDraft'), isTrue,
        reason: 'عرضُ السعر سقط مع المسوّدة — وهو مسارٌ قائمٌ له تبويبُه');
    expect(sales.contains('_saveQuotation('), isTrue,
        reason: 'زرُّ عرض السعر ما عاد يذهب إلى مساره الخاصّ');
  });

  test('والنموذجُ يرفض فعلَ مسوّدةٍ في نمط المشتريات بنيويّاً', () {
    // لا يكفي ألّا يوصّله المنادي اليوم: التوكيدُ يجعل عودتَه خطأً يُرى
    // عند أوّل فتحٍ للشاشة في التطوير، لا رقماً خاطئاً في الدفاتر.
    final code = _code(_formPath);
    expect(
        code.contains(
            'assert(onSaveDraft == null || kind == PicPosInvoiceKind.sales'),
        isTrue,
        reason: 'لا حارسَ في النموذج — فأيُّ منادٍ جديدٍ يُعيد الزرَّ بصمت');
  });

  test('ولا نصَّ «مسودة» في زرّ الأفعال — الاسمُ يقول ما يحدث', () {
    final money = _code(_moneyPath);
    expect(money.contains('حفظ كمسودة'), isFalse,
        reason: 'نصٌّ يعد بمسوّدةٍ لا وجودَ لها — ولو كان فرعاً لا يُبلَغ');
    expect(money.contains('حفظ كعرض سعر'), isTrue,
        reason: 'اسمُ الفعل الحقيقيّ اختفى');
  });
}
