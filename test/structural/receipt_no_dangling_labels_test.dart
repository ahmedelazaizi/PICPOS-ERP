// §٥-٣ — الإيصالُ لا يطبع تسميةً معلَّقةً، ولا رقمين بدقّتين.
//
// ── لماذا حارسٌ بنيويٌّ لا سلوكيّ ─────────────────────────────────────────
// `TemplatedInvoiceService.printWithTemplate` يبني مستندَ `pw.Document` ثم
// يدفعه للطابعة مباشرةً — لا يُرجع الوثيقةَ ولا البايتات، فلا مِقبضَ يقيس به
// اختبارٌ ما طُبع. وبناءُ مِقبضٍ لذلك تغييرٌ في التصميم أوسعُ من البلاغ.
//
// فالمقيسُ هنا **القرارُ في المصدر**، والسلوكُ يُتحقَّق منه ميدانياً بإيصالٍ
// مطبوع. وهذا يُعلَن لا يُخفى: حارسٌ يمنع العودةَ ولا يثبت الخروج.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// إيصالٌ مرصودٌ ميدانياً (2026-08-11) طبع:
//   · «الكاشير:» و«المخزن:» — تسمياتٌ بلا قيم
//   · «طريقة الدفع: cash» — كودٌ إنجليزيٌّ في مستندٍ عربيّ
//   · خانتين عشريتين في الجدول وثلاثاً في الإجماليات — في نفس الورقة

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _servicePath = 'lib/services/templated_invoice_service.dart';

void main() {
  final src = File(_servicePath).readAsStringSync();

  test('ملفُّ الطابعة الحيّة موجود', () {
    // §٦-٥: `template_based_printer.dart` **لا يناديه شيء**. أيُّ إصلاحٍ
    // يُكتب هناك لا يصل إلى ورقة. الحيُّ هو هذا.
    expect(File(_servicePath).existsSync(), isTrue);
  });

  test('عنصرٌ بلا قيمةٍ لا يُطبع — ولو كانت له تسمية', () {
    // كان `if (label.isEmpty && value.isEmpty)`، فتسميةٌ معروفةٌ بقيمةٍ
    // فارغةٍ تُطبع معلَّقة. والحقولُ التي ترجع `''` مقصودةٌ ومعلومةٌ بنصِّ
    // التعليق في `_getDataValue`: «Fields where data is not yet passed
    // through to the print service».
    expect(
      src.contains('if (label.isEmpty && value.isEmpty)'),
      isFalse,
      reason: 'عودةُ `&&` تعيد «الكاشير:» و«المخزن:» بلا قيمٍ إلى الإيصال. '
          'تسميةٌ وحدَها أسوأُ من لا شيء: القارئُ يظنّ البيانَ ناقصاً لا '
          'الحقلَ غيرَ مفعَّل.',
    );
    expect(src.contains('if (value.isEmpty) {'), isTrue,
        reason: 'الشرطُ على القيمة وحدَها هو ما يمنع التسميةَ المعلَّقة');
  });

  test('طريقةُ الدفع تمرّ بالمحوِّل في **موضعَي** العرض', () {
    // موضعان يطبعان `payment_method`: العنصرُ الصريح (‏`case
    // 'payment_method'` في بناء العنصر) والافتراضيُّ عبر `_getDataValue`.
    // إصلاحُ أحدهما يترك الآخرَ يطبع «cash» — وهو ما رُصد.
    final calls = 'mapPaymentMethodLabel('.allMatches(src).length;
    expect(calls, greaterThanOrEqualTo(3),
        reason: 'التعريفُ + موضعا العرض. أقلُّ من ذلك يعني مساراً ما زال '
            'يطبع الكودَ خاماً (الموجود: $calls)');
  });

  test('دقّةُ الجدول والإجماليات من مصدرٍ واحد', () {
    // «خانتان عشريتان في الجدول وثلاثٌ في الإجماليات» في نفس المستند:
    // الجدولُ كان يبدأ من `2` مكتوبةً، والإجمالياتُ من
    // `AppConstants.decimalPlaces` (‏٣).
    expect(
      src.contains('int decimalPlaces = 2;'),
      isFalse,
      reason: 'رقمٌ مكتوبٌ هنا يفترق عن `AppConstants.decimalPlaces` الذي '
          'تُنسَّق به الإجماليات، فيظهر رقمان بدقّتين في ورقةٍ واحدة',
    );
    expect(src.contains('int decimalPlaces = AppConstants.decimalPlaces;'),
        isTrue);
  });
}
