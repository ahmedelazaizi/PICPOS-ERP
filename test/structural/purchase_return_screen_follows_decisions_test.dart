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
//
// ═══ المرحلة C2 (البند ٣) — تصميمُ المالك الجديد ═══
//
// الاستمارةُ أُعيد تصميمُها (`purchase_returns_picpos_form.dart` بدل
// `purchase_returns_picpos_details.dart`)، والتصميمُ الجديدُ **يتقدّم على
// القرارات أعلاه حيث يُظهر العنصرَ فقط**، وبلا وعدٍ كاذب:
//   ١ — شارةُ الحالة عادت لأنّ التصميمَ يعرضها، **بنصّ «جديد» لا «مسودة»**.
//   ٢ — «حفظ مسودة» **لا يعود**: لا منطقَ مسوّدةٍ خلفَه — يبقى كما هو.
//   ٣ — «طريقة التسوية» تُعرَض لأنّ التصميمَ يعرضها، **حقلاً مقروءاً لا
//       قائمة**: المحرّكُ بطريقةٍ واحدةٍ ثابتة.
//   ورقمُ المستند: «يُولَّد تلقائياً» لا رقمٌ مُخمَّن — كما هو.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _detailsPath = 'lib/presentation/purchase_returns_picpos/screens/'
    'purchase_returns_picpos_form.dart';

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
  test('الترويسةُ لبِنةُ الاستمارة — شارةُ «جديد» لا «مسودة» وبلا رقمٍ مُخمَّن',
      () {
    final code = _code(_detailsPath);
    final header = _body(
      code,
      'Widget _buildInvoiceHeader(',
      '\n  Widget _buildItemsList(',
    );
    expect(header.contains('PicPosDocPageHeader('), isTrue,
        reason: 'الترويسةُ ما زالت مبنيّةً يدوياً — واللبِنةُ وُحِّدت لهذا');
    // C2 ثمّ J2 (قرارُ المالك): «مسودة» صارت حالةً حقيقيّةً (`return_drafts`)
    // — فالشارةُ «جديد» قبل الحفظ و«مسودة» **متى وُجدت مسوّدةٌ محفوظةٌ فقط**،
    // لا وعداً بحفظٍ لا يقع.
    expect(header.contains("tr('جديد')"), isTrue,
        reason: 'شارةُ الحالة غائبةٌ أو لا تقول «جديد» قبل الحفظ');
    expect(
        RegExp(r"_draftId != null \? tr\('مسودة'\) : tr\('جديد'\)")
            .hasMatch(header),
        isTrue,
        reason: '«مسودة» بلا مسوّدةٍ محفوظة — وعدٌ بحفظٍ لا يقع');
    // ⚠️ والرقمُ «يُولَّد تلقائياً» نصّاً — لا تخمينٌ ولا توليدٌ هنا؛
    // والمسوّدةُ تُعرَّف بمعرّفها (`D-`) لا برقمٍ من التسلسل.
    expect(header.contains("tr('يُولَّد تلقائياً')"), isTrue,
        reason: 'رقمُ المرتجع يُولَّد في المعاملة — فأيُّ رقمٍ هنا مُخمَّن');
    expect(header.contains('generateInvoiceNumber'), isFalse);
    expect(header.contains("'PRET-"), isFalse,
        reason: 'رقمٌ مُركَّبٌ باليد في الترويسة — مُخمَّنٌ لا محالة');
  });

  test('J2: «حفظ مسودة» زرٌّ خلفَه دورةُ حياة، و«اعتماد» بالمعالج القائم',
      () {
    // قرارُ المالك (J2) نسخ «خطوةً واحدة»: المسوّدةُ صارت حالةً محفوظة. فيبقى
    // روحُ الحارس — **لا زرَّ بلا معالجٍ قائمٍ خلفَه** — ويُقاس على المعالج.
    final footer = _body(
      _code(_detailsPath),
      'Widget _buildReturnFooter(',
      '\n}',
    );
    expect(footer.contains('PicPosReturnActionBar('), isTrue,
        reason: 'شريطُ الأفعال ما زال مبنيّاً يدوياً');
    expect(footer.contains("secondaryLabel: tr('حفظ مسودة')"), isTrue,
        reason: 'قرارُ المالك (J2): «حفظ مسودة» في شريط الأفعال');
    expect(footer.contains('_screen.saveDraft()'), isTrue,
        reason: 'زرُّ مسوّدةٍ لا ينادي حفظَ المسوّدة — وعدٌ بحفظٍ لا يقع');
    expect(footer.contains('onPrimary:'), isTrue,
        reason: 'لا فعلَ مرحِّلاً أصلاً');
    expect(footer.contains('approveReturn'), isTrue,
        reason: '«مراجعة واعتماد» لا يمرّ بدورة المسوّدة');
    expect(footer.contains('canApprove'), isTrue,
        reason: '«مراجعة واعتماد» بلا صلاحيته المستقلّة');

    // والحفظُ مسوّدةٌ حقيقيّة، والاعتمادُ ينادي المعالجَ القائمَ نفسَه.
    final drafts = _code('lib/presentation/purchase_returns_picpos/screens/'
        'purchase_returns_picpos_drafts.dart');
    expect(drafts.contains('returnDraftsRepositoryProvider'), isTrue);
    expect(drafts.contains('processReturn(beforePost:'), isTrue,
        reason: 'الاعتمادُ يجب أن يمرّ بالمعالج القائم (J1: الوردية)');
    expect(drafts.contains('PermissionCodes.purchasesReturnApprove'), isTrue);
  });

  test('والإجماليّاتُ ثلاثةٌ — والضريبةُ ليست خفيّة', () {
    // ⚠️ الضريبةُ تدخل تسويةَ المورّد إجماليّاً، فعرضُ الصافي وحدَه يُظهر
    // «١٠٠» بينما يُخصَم من الذمّة «١١٤».
    final totals = _body(
      _code(_detailsPath),
      'Widget _buildReturnTotals(',
      '\n  Widget _buildSettlementMirror(',
    );
    expect(totals.contains('PicPosTotalsBar('), isTrue);
    expect(totals.contains('calculateReturnVat()'), isTrue,
        reason: 'الضريبةُ غائبةٌ عن العرض وهي داخلةٌ في التسوية');
    expect(
      _code(_detailsPath).contains('_buildReturnTotals(notifier)'),
      isTrue,
      reason: 'شريطُ الإجماليّات مبنيٌّ ولا يُعرَض',
    );
  });

  test('ولا قائمةَ لـ«طريقة التسوية» — حقلٌ مقروءٌ بما سيفعله المحرّك', () {
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
    // C2: التصميمُ يعرض الطريقة — فتُعرَض مشتقّةً من القسمة نفسِها.
    expect(mirror.contains('method: tr(s.methodLabel)'), isTrue,
        reason: '«طريقة التسوية» غائبةٌ أو غيرُ مشتقّةٍ من القسمة');
    final kit = _code('lib/presentation/picpos_shell/picpos_return_form_kit.dart');
    final card = _body(
      kit,
      'class PicPosSettlementCard ',
      '\n}',
    );
    expect(card.contains('DropdownButton'), isFalse,
        reason: 'كتلةُ التسوية المشتركة صارت تعرض قائمةً للطريقة');
  });

  test('ومرساةٌ — القائمةُ المشروعةُ الوحيدةُ هي سببُ المردود', () {
    // بلا هذه المرساة يمرّ الفحصُ أعلاه أخضرَ لو حُذفت كلُّ القوائم من
    // الشاشة — لا لأنّ التسويةَ صارت مشتقّة. (C2: السببُ انتقل إلى بطاقة
    // الترويسة كما في التصميم.)
    final header = _body(
      _code(_detailsPath),
      'Widget _buildInvoiceHeader(',
      '\n  Widget _buildItemsList(',
    );
    expect(header.contains('AppConstants.purchaseReturnReasons'), isTrue,
        reason: 'قائمةُ السبب اختفت — والقرارُ أنّها إلزاميّة');
    expect(header.contains('notifier.updateReturnReason'), isTrue,
        reason: 'الاختيارُ لا يصل المزوّد');
  });
}
