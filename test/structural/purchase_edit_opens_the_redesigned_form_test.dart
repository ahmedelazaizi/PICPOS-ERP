// حارسُ العقد: تعديلُ فاتورة المشتريات يفتح **الشاشةَ المُعاد تصميمُها**.
//
// ═══ ما كان ═══
//
// `createNewInvoicePicPos` تفتح `PicPosInvoiceForm`، و`editInvoice` تفتح
// `PurchaseInvoiceForm` **القديم**. فكلُّ ما أُعيد تصميمُه — عمودُ الخصم
// لكلّ صنف، ومرآةُ تاريخ الاستحقاق، وقشرةُ الشاشة — **لا يُرى عند فتح
// فاتورةٍ للتعديل**.
//
// وأسوأُ من الاختلاف أنّ النموذجَ القديمَ يحمل:
//
//   ‏• زرَّ «مسودة» بسلوكه القديم — فاتورةٌ آجلةٌ مرحَّلةٌ كاملة
//   ‏• 🔴 وملءَ التكلفة من المخزَّن **صافيةً** مع الخصم **كاملاً**: فيُعاد
//     توزيعُ الخصم على تكلفةٍ وُزِّع عليها أصلاً، **وكلُّ حفظٍ يخفّضها
//     ثانيةً** ولو لم يُغيَّر حرف. ١٠٠ ← ٩٠ ← ٨١ … ولا يظهر على الشاشة،
//     إنّما في متوسّط تكلفة الصنف.
//
// ═══ والعقدُ المحروس ═══
//
// شاشةٌ واحدةٌ للفعلَين، وحالةُ البدء تُبنى بـ**عكسَين** مقابلَين لتخزينَين:
// الإجماليُّ من الصافي (`resolvePurchaseLineGross`)، وحقلُ الترويسة من
// المجموع (بطرح خصوم السطور).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// نصُّ الملفّ بلا أسطر التعليق وبلا `\r` — أغلبُ الملفّات هنا CRLF.
String _code(String path) => [
      for (final line in File(path).readAsStringSync().split('\n'))
        if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
    ].join('\n');

const _crudPath =
    'lib/presentation/purchases_picpos/screens/purchases_picpos_crud.dart';
const _screenPath =
    'lib/presentation/purchases_picpos/screens/purchases_picpos_screen.dart';
const _formulaPath = 'lib/domain/models/purchase_line_discount.dart';

String _body(String code, String start, String end) {
  final at = code.indexOf(start);
  expect(at, greaterThan(0), reason: 'لم أجد `$start`');
  final to = code.indexOf(end, at);
  expect(to, greaterThan(at), reason: 'لم أجد نهايةَ `$start`');
  return code.substring(at, to);
}

void main() {
  test('الشاشةُ لا تفتح النموذجَ القديم إطلاقاً', () {
    // ⚠️ والنموذجُ نفسُه يبقى لشاشة `purchase_invoice_crud.dart` الأصليّة —
    // قاعدةُ ح‑٣: يُنسَخ ولا يُشارَك. المحروسُ هنا فرعُ PicPos وحدَه.
    expect(_code(_crudPath).contains('PurchaseInvoiceForm('), isFalse,
        reason: 'مسارٌ في فرع PicPos ما زال يفتح النموذجَ القديم — بزرّ '
            'مسوّدةٍ يرحّل فاتورةً، وبتكلفةٍ تنزل مع كلّ حفظ');
  });

  test('وتعديلُ فاتورةٍ يمرّ بالشاشة الجديدة', () {
    final edit = _body(
      _code(_crudPath),
      'void editInvoice(InvoiceEntity invoice) async {',
      // ⚠️ مرساةُ النهاية **شيفرةٌ لا تعليق**: `_code` يُسقط أسطرَ التعليق،
      // فمرساةٌ على `///` تعطي `-1` ويسقط الفحصُ لسببٍ لا علاقةَ له بما يُقاس.
      'Future<void> _handleSavePurchaseSimple({',
    );
    expect(edit.contains('openPicPosInvoiceForm('), isTrue,
        reason: 'التحريرُ لا يفتح الشاشةَ المُعاد تصميمُها');
    expect(edit.contains('editing: invoice'), isTrue,
        reason: 'الشاشةُ لا تعرف أنّها على فاتورةٍ قائمة — فتُنشئ ثانية');
    expect(edit.contains('_initialFromInvoice('), isTrue,
        reason: 'حالةُ البدء لا تُبنى — تُفتَح الشاشةُ فارغةً على فاتورةٍ '
            'قائمة');
  });

  test('ومدخلا الشاشة يقودان إلى نفس الدالّة', () {
    final screen = _code(_screenPath);
    expect('openPicPosInvoiceForm'.allMatches(screen).length, 2,
        reason: 'زرُّ «جديد» أو اختصارُه انفصل عن الشاشة الجديدة');
    expect(screen.contains('createNewInvoicePicPos'), isFalse,
        reason: 'اسمٌ قديمٌ باقٍ — ومنادٍ لا يعرف أنّ الدالّةَ تخدم الفعلَين');
  });

  test('🔴 وحالةُ البدء تعكس التخزينَ عكسَين لا واحداً', () {
    final fn = _body(
      _code(_crudPath),
      'PicPosInvoiceInitial _initialFromInvoice(',
      'Future<void> openPicPosInvoiceForm(',
    );
    // العكسُ الأوّل: الإجماليُّ من الصافي.
    expect(fn.contains('resolvePurchaseLineGross('), isTrue,
        reason: 'التكلفةُ تُملأ من المخزَّن صافيةً — فيُعاد توزيعُ الخصم '
            'عليها وتنزل مع كلّ حفظ');
    expect(fn.contains('netPerLine:'), isTrue);
    // العكسُ الثاني: حقلُ الترويسة من المجموع.
    expect(fn.contains('invoice.discount - explicitSum'), isTrue,
        reason: '`invoice.discount` هو **مجموعُ** الخصم، والنموذجُ يجمع '
            'خصومَ السطور عليه ثانيةً — فيُحسَب مرّتَين');
  });

  test('والصيغتان متقابلتان — أمامٌ وعكس', () {
    final code = _code(_formulaPath);
    expect(code.contains('List<double> resolvePurchaseLineNets('), isTrue);
    expect(code.contains('List<double> resolvePurchaseLineGross('), isTrue,
        reason: 'العكسُ اختفى — فلا سبيلَ لملء شاشة التحرير بما يقبله '
            'المحرّك');
  });

  test('ولا ربطَ أمرِ شراءٍ على فاتورةٍ قائمة', () {
    // 🔴 `updatePurchaseInvoice` لا يستهلك أمراً، فزرٌّ هنا يسحب بنوداً
    // ويترك الأمرَ مفتوحاً — ثمّ يحوّله أحدٌ فتدخل البضاعةُ مرّتَين.
    expect(
      _code(_crudPath).contains('if (editing == null &&'),
      isTrue,
      reason: 'قائمةُ الأوامر تُحمَّل في وضع التحرير — زرُّ ربطٍ لا يستهلك',
    );
  });

  test('والمسدَّدُ لا تُعيد التهيئةُ كتابتَه على فاتورةٍ قائمة', () {
    // `picPosAutoPaid` تملأ الصافيَ ما لم يكتبه المستخدم. وعلى فاتورةٍ
    // قائمةٍ يعني ذلك أن يصير المسدَّدُ كاملاً بمجرّد فتحها — فيُنشأ سندُ
    // صرفٍ لم يُصدره أحد.
    final init = _body(
      _code('lib/presentation/invoice_form_picpos/picpos_invoice_form.dart'),
      'final init = widget.initial;',
      '_discountController.addListener',
    );
    expect(init.contains('_paidTouched = true'), isTrue,
        reason: 'التهيئةُ التلقائيّةُ تدهس المسدَّدَ المخزَّن');
    expect(init.contains('init.paid'), isTrue,
        reason: 'المسدَّدُ لا يُملأ أصلاً — يعود صفراً على فاتورةٍ مسدَّدة');
  });

  test('وتسميةُ الفعل تقول ما يحدث', () {
    final money = _code(
        'lib/presentation/invoice_form_picpos/picpos_invoice_money.dart');
    expect(money.contains("state.widget.isEdit"), isTrue,
        reason: 'زرٌّ يقول «حفظ الفاتورة» على تحريرٍ يوهم بإنشاء ثانية');
    expect(money.contains('حفظ التعديلات'), isTrue);
  });
}
