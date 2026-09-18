// حارسُ العقد: شاشةُ مردود المشتريات تتبع قرارات المالك لا صورةَ التصميم.
//
// ═══ ولماذا الفرقُ مهمّ ═══
//
// الصورةُ تعرض ما **رسمه المصمّم**، والقرارُ يقول ما **يعمل به النظام**.
// وثلاثةُ مواضعَ تفترق فيهما هنا، وكلُّها نسخٌ حرفيٌّ من الصورة يُنتج وعداً
// كاذباً:
//
//   ١ — **وسمُ «مسودة»** في الترويسة. وقرارُ المالك: **ترحيلٌ بخطوةٍ واحدةٍ
//       كما اليوم — لا دورةَ مسوّدة**. فوسمٌ لحالةٍ لا وجودَ لها يعد المستخدمَ
//       بحفظٍ مؤقّتٍ لا يقع.
//   ٢ — **زرُّ «حفظ مسودة»** بجوار «مراجعة واعتماد». ولا دورةَ حياةٍ خلفَه.
//   ٣ — **«طريقة التسوية» قائمةً منسدلة**. والمحرّكُ لا يستشيرها: يقسم
//       آليّاً بين ذمّة المورّد والنقد. فقائمةٌ تُعرَض ولا تُقرأ أسوأُ من
//       غيابها.
//
// ⚠️ **ورقمُ المستند لا يُعرَض قبل الحفظ**: يُولَّد داخلَ المعاملة
// (`generateInvoiceNumber('PRET-')`)، فرقمٌ مُخمَّنٌ يُطبَع على مستندٍ ماليّ.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _detailsPath = 'lib/presentation/purchase_returns_picpos/screens/'
    'purchase_returns_picpos_details.dart';

/// نصُّ الملفّ بلا أسطر التعليق وبلا `\r` — الملفّاتُ هنا CRLF.
String _code(String path) => [
      for (final line in File(path).readAsStringSync().split('\n'))
        if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
    ].join('\n');

/// جسمُ دالّةٍ بعينها — فحصُ وجودِ رمزٍ في ملفٍّ كاملٍ يكذب متى ظهر مرّتَين.
String _body(String code, String start, String end) {
  final at = code.indexOf(start);
  expect(at, greaterThan(0), reason: 'لم أجد `$start`');
  final to = code.indexOf(end, at);
  expect(to, greaterThan(at), reason: 'لم أجد نهايةَ `$start`');
  return code.substring(at, to);
}

void main() {
  test('الترويسةُ لبِنةُ القشرة — بلا وسمِ حالةٍ وبلا رقمٍ مُخمَّن', () {
    final code = _code(_detailsPath);
    final header = _body(
      code,
      'Widget _buildInvoiceHeader(',
      '\n  Widget _buildItemsList(',
    );
    expect(header.contains('PicPosDocumentHeader('), isTrue,
        reason: 'الترويسةُ ما زالت مبنيّةً يدوياً — والقشرةُ وُحِّدت لهذا');
    expect(header.contains('PicPosDocStatus'), isFalse,
        reason: 'وسمُ حالةٍ على شاشةٍ بلا دورةِ مسوّدة — وعدٌ بحفظٍ لا يقع');
    expect(header.contains('number:'), isFalse,
        reason: 'رقمُ المرتجع يُولَّد في المعاملة — فأيُّ رقمٍ هنا مُخمَّن');
  });

  test('وفعلٌ واحدٌ لا فعلان — لا دورةَ مسوّدة', () {
    final footer = _body(
      _code(_detailsPath),
      'Widget _buildReturnFooter(',
      '\n}',
    );
    expect(footer.contains('PicPosFormActionBar('), isTrue,
        reason: 'شريطُ الأفعال ما زال مبنيّاً يدوياً');
    expect(footer.contains('draft:'), isFalse,
        reason: 'زرُّ مسوّدةٍ لا دورةَ حياةٍ خلفَه — قرارُ المالك خطوةٌ واحدة');
    expect(footer.contains('primary:'), isTrue,
        reason: 'لا فعلَ مرحِّلاً أصلاً');
  });

  test('والإجماليّاتُ ثلاثةٌ — والضريبةُ ليست خفيّة', () {
    // ⚠️ الضريبةُ تدخل تسويةَ المورّد إجماليّاً، فعرضُ الصافي وحدَه يُظهر
    // «١٠٠» بينما يُخصَم من الذمّة «١١٤».
    final footer = _body(
      _code(_detailsPath),
      'Widget _buildReturnFooter(',
      '\n}',
    );
    expect(footer.contains('PicPosTotalsBar('), isTrue);
    expect(footer.contains('calculateReturnVat()'), isTrue,
        reason: 'الضريبةُ غائبةٌ عن العرض وهي داخلةٌ في التسوية');
  });

  test('ولا قائمةَ لـ«طريقة التسوية» — المحرّكُ لا يستشيرها', () {
    final mirror = _body(
      _code(_detailsPath),
      'Widget _buildSettlementMirror(',
      '\n  Widget _buildReturnFooter(',
    );
    expect(mirror.contains('DropdownButton'), isFalse,
        reason: 'قائمةٌ تُعرَض ولا تُقرأ: يختار «استرداد نقدي» فيُخفَّض '
            'رصيدُ الذمّة ولا يصله شيء');
    expect(mirror.contains('notifier.settlement'), isTrue,
        reason: 'المرآةُ لا تقرأ القسمةَ التي ينفّذها المحرّك');
  });

  test('ومرساةٌ — القائمةُ المشروعةُ الوحيدةُ هي سببُ المردود', () {
    // بلا هذه المرساة يمرّ الفحصُ أعلاه أخضرَ لو حُذفت كلُّ القوائم من
    // الشاشة — لا لأنّ التسويةَ صارت مشتقّة.
    final footer = _body(
      _code(_detailsPath),
      'Widget _buildReturnFooter(',
      '\n}',
    );
    expect(footer.contains('AppConstants.purchaseReturnReasons'), isTrue,
        reason: 'قائمةُ السبب اختفت — والقرارُ أنّها إلزاميّة');
  });
}
