// حارسُ العقد: خصمُ الصنف يعبر **من العمود إلى صفّ المستند** — بلا حلقةٍ
// مفقودة.
//
// ═══ فئةُ العطب ═══
//
// `PurchaseInvoiceItems.discount` عمودٌ قائمٌ **بلا كاتبٍ وله قارئ**:
// `getPurchaseReturnItemDetails` يقسّطه بنسبة المرتجَع ويطبعه على مستند
// المرتجع — صفراً منذ وُجد. وهي عينُ عائلةِ `PurchaseReturns.reason`:
// قائمةٌ تُملأ ولا تغادر الودجت.
//
// 🔴 **وأسوأُ الأشكال حقلٌ يُعرَض ويبتلع.** المستخدمُ يكتب خصماً، ويراه في
// «الإجمالي» على الشاشة، ثمّ يُحفَظ بلا خصم: تكلفةٌ أعلى من الحقيقة في
// متوسّط التكلفة، وربحٌ أقلُّ في كلّ بيعةٍ تالية، ومرتجعٌ يردّ أكثرَ ممّا
// دُفع. ولا رسالةَ ولا استثناء.
//
// والسلسلةُ **سبعُ حلقات**، وكسرُ أيِّها يُنتج ذلك بالضبط:
//
//   ‏١ — بوّابةٌ واحدةٌ: `PicPosInvoiceKind.supportsLineDiscount`
//   ‏٢ — العمودُ يُرسَم بها في `picpos_invoice_lines.dart`
//   ‏٣ — وخريطةُ الحفظ تكتب المفتاحَ بها نفسِها
//   ‏٤ — والشاشةُ تقرأ المفتاحَ إلى `PurchaseItemParams`
//   ‏٥ — والمستودعُ يمرّره إلى `PurchaseInvoiceItemsCompanion` (إنشاءً
//       وتحريراً ومرآةً) وإلى حمولةِ الخادم
//   ‏٦ — ومعالجُ الـAPI يقرؤه من الحمولة
//   ‏٧ — والمحرّكُ يوزّعه بـ`resolvePurchaseLineNets` في **المسارَين**
//
// ⚠️ **والبوّابةُ رمزٌ واحدٌ عمداً.** لو قرأ العمودُ شرطَه وقرأت خريطةُ
// الحفظ شرطاً آخرَ لانفصلا يوماً — وهذا الحارسُ يمنع ذلك بالاسم.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// نصُّ الملفّ بلا أسطر التعليق وبلا `\r` — أغلبُ الملفّات هنا CRLF.
String _code(String path) => [
      for (final line in File(path).readAsStringSync().split('\n'))
        if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
    ].join('\n');

const _kindPath = 'lib/domain/models/picpos_invoice_draft.dart';
const _linesPath =
    'lib/presentation/invoice_form_picpos/picpos_invoice_lines.dart';
const _crudPath =
    'lib/presentation/purchases_picpos/screens/purchases_picpos_crud.dart';
const _paramsPath = 'lib/domain/repositories/purchases_repository.dart';
const _repoPath = 'lib/data/repositories/purchases_repository_impl.dart';
const _apiPath = 'lib/services/api/api_purchase_handler.dart';
const _daoPath = 'lib/data/database/daos/purchase_dao.dart';
const _formulaPath = 'lib/domain/models/purchase_line_discount.dart';

/// جسمُ دالّةٍ بعينها — فحصُ وجودِ رمزٍ في ملفٍّ كاملٍ يكذب متى ظهر مرّتَين.
String _body(String code, String start, String end) {
  final at = code.indexOf(start);
  expect(at, greaterThan(0), reason: 'لم أجد `$start`');
  final to = code.indexOf(end, at);
  expect(to, greaterThan(at), reason: 'لم أجد نهايةَ `$start`');
  return code.substring(at, to);
}

void main() {
  test('‏١ — البوّابةُ موجودةٌ ومقصورةٌ على المشتريات', () {
    final code = _code(_kindPath);
    expect(code.contains('bool get supportsLineDiscount'), isTrue,
        reason: 'البوّابةُ اختفت — فلا لُحمةَ تُحرَس');
    expect(
      code.contains(
          'supportsLineDiscount => this == PicPosInvoiceKind.purchase'),
      isTrue,
      reason: 'البوّابةُ فُتحت للمبيعات ومسارُ حفظها لا يقرأ خصمَ سطر — '
          'حقلٌ يبتلع ما يُكتَب فيه',
    );
  });

  test('‏٢ — العمودُ لا يُرسَم إلّا بها — رأساً وخليّةً', () {
    // 🔴 **ولا يُعَدُّ ظهورُ الرمز.** أوّلُ صياغةٍ عدّت `supportsLineDiscount`
    // في الملفّ واشترطت اثنتَين، فنجت طفرةٌ نزعت البوّابةَ عن **الرأس**:
    // القارئُ الثالثُ `_nameW` أبقى العدَّ عند اثنتَين. والمقيسُ الآن
    // التركيبُ نفسُه في كلّ موضعٍ على حدة.
    final code = _code(_linesPath);

    expect(code.contains("cell('الخصم'"), isTrue,
        reason: 'عنوانُ العمود اختفى');
    expect(code.contains("ValueKey('discount_"), isTrue,
        reason: 'حقلُ الخصم اختفى من الصفّ');

    expect(
      RegExp(r"supportsLineDiscount\)\s*cell\('الخصم'").hasMatch(code),
      isTrue,
      reason: 'عنوانُ «الخصم» يُرسَم بلا بوّابة — يظهر في المبيعات فوق '
          'عمودٍ لا وجودَ له',
    );
    // خليّةُ الصفّ: البوّابةُ يليها `Expanded` بنسبة عمود الخصم.
    // (‏`\s` في Dart يشمل السطرَ الجديد، فالنمطُ يعبر الأسطر بلا زيادة.)
    expect(
      RegExp(r'supportsLineDiscount\)\s*Expanded\(\s*flex: _kDiscW')
          .hasMatch(code),
      isTrue,
      reason: 'خليّةُ الخصم تُرسَم بلا بوّابةٍ أو بعرضٍ مفروضٍ لا بنسبة',
    );
    // وعرضُ الصنف يُطرَح منه عرضُ الخصم — وإلّا سُحق كلُّ جار.
    expect(code.contains('33 - _kDiscW'), isTrue,
        reason: 'عمودُ الصنف ما عاد يتحمّل ثمنَ العمود الثامن، فيُقتَطع من '
            'كلّ جارٍ بنسبته — وحقلُ الكمّيّة ينزل إلى ٩ بكسلاً عند ١٢٠٠');
  });

  test('‏٣ — وخريطةُ الحفظ تكتب المفتاحَ بالبوّابة نفسِها', () {
    final save = _body(
      _code(_kindPath),
      'Map<String, dynamic> toSaveMap(',
      '\n}',
    );
    expect(save.contains('kind.supportsLineDiscount'), isTrue,
        reason: 'خريطةُ الحفظ تقرأ شرطاً آخرَ غيرَ الذي يقرؤه العمود — '
            'ينفصلان يوماً بلا ما يكسر بناءً');
    expect(save.contains("base['discount']"), isTrue,
        reason: 'المفتاحُ لا يُكتَب أصلاً — العمودُ يُعرَض ولا يُحفَظ');
  });

  test('‏٤ — والشاشةُ تقرأ المفتاحَ إلى معاملات المستودع', () {
    final code = _code(_crudPath);
    expect(code.contains("item['discount']"), isTrue,
        reason: 'الشاشةُ تتجاهل المفتاحَ — تصل الخريطةُ ويسقط الرقم');
    expect(code.contains('discount:'), isTrue);

    final params = _code(_paramsPath);
    expect(params.contains('final double discount;'), isTrue,
        reason: '`PurchaseItemParams` بلا حقلٍ للخصم — لا وعاءَ يحمله');
    expect(params.contains('double get appliedDiscount'), isTrue,
        reason: 'الحصرُ اختفى: خصمٌ أكبرُ من قيمة السطر يُنتج `total` سالباً');
  });

  test('‏٥ — والمستودعُ يمرّره في المسارات الأربعة', () {
    final code = _code(_repoPath);
    // ثلاثةُ صفوفٍ تُبنى (مرآةٌ · إنشاءٌ · تحرير) + حمولةُ الخادم.
    expect('Value(it.appliedDiscount)'.allMatches(code).length +
            'Value(i.appliedDiscount)'.allMatches(code).length,
        greaterThanOrEqualTo(3),
        reason: 'أحدُ مسارات الكتابة الثلاثة يُسقط الخصمَ — والتحريرُ أخطرُها: '
            'تُعرَض الخصومُ وتُمحى بحفظٍ بلا تغييرِ حرف');
    expect(code.contains("'discount': it.appliedDiscount"), isTrue,
        reason: 'حمولةُ العميل بلا خصم — فالخادمُ يخزّن تكلفةً أعلى من '
            'تكلفة نسخة العميل لنفس الفاتورة');
  });

  test('‏٦ — ومعالجُ الـAPI يقرؤه في الموضعَين', () {
    final code = _code(_apiPath);
    expect("parseDouble(m['discount'])".allMatches(code).length, 2,
        reason: 'الإنشاءُ أو التحريرُ على الخادم يُسقط الخصم — وهما يقرآن '
            'نفسَ الحمولة');
  });

  test('‏٧ — والمحرّكُ يوزّعه في مسارَي الإنشاء والتحرير', () {
    final code = _code(_daoPath);
    expect('resolvePurchaseLineNets('.allMatches(code).length, 2,
        reason: 'مسارٌ واحدٌ يقرأ الصيغةَ والآخرُ يكتبها بيده — والتحريرُ '
            'كان يُعيد توزيعَ الخصوم نسبيّاً ويمحو ما كتبه المستخدم');
    expect(code.contains('editDiscountFactor'), isFalse,
        reason: 'المعاملُ النسبيُّ المكتوبُ بيده عاد إلى مسار التحرير');
  });

  test('ولا معاملَ توزيعٍ يدويٌّ ثانٍ في المستودع كلِّه', () {
    // ⚠️ **النمطُ على القسمة لا على `discount`**: الكلمةُ تتكرّر في المستودع
    // لأغراضٍ كثيرة، والمقصودُ هنا معاملُ التوزيع النسبيّ:
    // `(subtotal - discount) / subtotal`.
    final bad = RegExp(
      r'\(\s*\w*[Ss]ubtotal\s*-\s*\w*[Dd]iscount\s*\)\s*/\s*\w*[Ss]ubtotal',
    );
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/');
      if (path == _formulaPath) continue;
      if (bad.hasMatch(_code(f.path))) offenders.add(path);
    }
    expect(offenders, isEmpty,
        reason: 'توزيعٌ مكتوبٌ بيده خارجَ `resolvePurchaseLineNets`: '
            '${offenders.join(", ")}. ونسختان تُجيبان سؤالاً واحداً '
            'تنحرفان يوماً.');
  });

  test('ومرساةُ النمط — يمسك المعاملَ اليدويَّ لو عاد', () {
    // بلا هذه المرساة يمرّ الفحصُ أعلاه أخضرَ لأنّ نمطَه صار لا يطابق شيئاً
    // إطلاقاً، لا لأنّ المستودعَ نظيف.
    const planted =
        'final f = (grossSubtotal - effectiveDiscount) / grossSubtotal;';
    final bad = RegExp(
      r'\(\s*\w*[Ss]ubtotal\s*-\s*\w*[Dd]iscount\s*\)\s*/\s*\w*[Ss]ubtotal',
    );
    expect(bad.hasMatch(planted), isTrue,
        reason: 'النمطُ ما عاد يطابق المعاملَ اليدويَّ نفسَه');
  });

  test('وخصمُ المستند المُمرَّرُ يشمل خصومَ السطور', () {
    // 🔴 المحرّكُ يقرأ خصمَ المستند على أنّه **المجموع** ويحفر منه الصريح.
    // فتمريرُ حقل الترويسة وحدَه يجعل الترويسةَ تقول «بلا خصم» وسطورَها
    // مخصومة — ذمّةٌ على المورّد لا يقابلها مخزونٌ دخل.
    final form = _code(
        'lib/presentation/invoice_form_picpos/picpos_invoice_form.dart');
    expect(form.contains('discount: t.headerDiscount'), isFalse,
        reason: 'النموذجُ يمرّر حقلَ الترويسة وحدَه');
    expect('discount: t.discountTotal'.allMatches(form).length, 2,
        reason: 'الحفظُ أو المسوّدةُ ما زال يمرّر حقلَ الترويسة وحدَه');

    final draft = _code(_kindPath);
    expect(
      draft.contains(
          'discountTotal =>\n      FinancialUtils.round(headerDiscount + lineDiscount)'),
      isTrue,
      reason: 'المجموعُ ما عاد يجمع الطرفَين',
    );
  });
}
