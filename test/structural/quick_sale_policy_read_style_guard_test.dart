// حارسُ العقد: قراءةُ السياسة الباردةُ لا تُتَّخذ قراراً مالياً عليها.
//
// ═══ فئةُ العطب — بلاغُ المالك 2026-08-30 ═══
//
// `quickSalePolicyProvider` مزوِّدٌ مستقبليّ. و`ref.read(p).asData?.value`
// ترجع **`null`** ما لم يكن الجلبُ قد اكتمل سلفاً — لا لأنّ المفتاحَ غائب،
// بل لأنّ المزوِّدَ لم يُسخَّن بعد. والكودُ يفسّر `null` بأنّها «السلوكُ
// القائم»، فيسقط إلى الافتراض بصمت.
//
// وشاشةُ الإعدادات تستدعي `ref.invalidate` بعد الحفظ ⇒ المزوِّدُ يعود بارداً
// **في اللحظة التي يجرّب فيها المديرُ الإعدادَ**. ولهذا بدا الإعدادُ ميّتاً
// تماماً لا متقطّعاً: «أحدّد وسيلة الدفع ولا تُنفَّذ».
//
// ⚠️ **ولم يمسكه اختبارُ الشاشة** لأنّه يتجاوز المزوِّدَ بـ`overrideWith`:
// يقيس أنّ الشاشةَ تعرض ما يُعطى، لا أنّ القيمَ **تصل**. والسلوكُ المقيسُ
// في `quick_sale_policy_reaches_pos_test.dart`.
//
// ═══ القاعدةُ التي يفرضها هذا الملفّ ═══
//
//   • في سياقٍ غيرِ متزامنٍ (‏مسارُ الدفع، الخصمُ، الإغلاق) ⇒ **`await`**.
//   • في سياقٍ متزامنٍ لا مفرَّ منه (‏`build`، إعادةُ تركيز الماسح) ⇒ يُسمح
//     بالقراءة الباردة **بشرط** أن تراقب الشجرةُ المزوِّدَ فتُبقيه ساخناً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _ops =
    'lib/presentation/pos_picpos/screens/picpos_pos_operations.dart';
const _screen = 'lib/presentation/pos_picpos/screens/picpos_pos_screen.dart';
const _perms =
    'lib/presentation/pos_picpos/widgets/picpos_cart_permissions.dart';
const _closing = 'lib/presentation/shift_close_picpos/widgets/'
    'picpos_cashier_closing_dialog.dart';

String _read(String p) {
  final f = File(p);
  expect(f.existsSync(), isTrue, reason: 'الملفُّ «$p» اختفى');
  return f.readAsStringSync();
}

/// عددُ القراءات الباردة (`ref.read(quickSalePolicyProvider).asData`).
int _coldReads(String src) =>
    RegExp(r'read\(\s*quickSalePolicyProvider\s*\)\s*\.asData')
        .allMatches(src)
        .length;

/// عددُ القراءات المنتظِرة (`await ref.read(...future)`).
int _awaitedReads(String src) =>
    RegExp(r'quickSalePolicyProvider\.future').allMatches(src).length;

void main() {
  group('أسلوبُ قراءة سياسة البيع السريع', () {
    test('المرساة: المسارات ما زالت تقرأ السياسةَ أصلاً', () {
      // ⚠️ بلا هذه المرساةِ يمرُّ الحارسُ أخضرَ لو حُذف التوصيلُ كلُّه:
      // «صفرُ قراءاتٍ باردة» تتحقّق في ملفٍّ لا يقرأ السياسةَ إطلاقاً.
      final total = _awaitedReads(_read(_ops)) + _coldReads(_read(_ops));
      expect(total, greaterThanOrEqualTo(8),
          reason: 'مسارُ الكاشير يجب أن يقرأ السياسةَ في مواضعَ عدّة — '
              'وُجد $total، فإمّا حُذف التوصيلُ وإمّا تغيّر اسمُ المزوِّد.');
    });

    test('مسارُ الكاشير لا يبني قراراً مالياً على قراءةٍ باردة', () {
      final cold = _coldReads(_read(_ops));
      expect(
        cold,
        lessThanOrEqualTo(1),
        reason: 'وُجدت $cold قراءةً باردةً في مسار الكاشير. المسموحُ واحدةٌ '
            'فقط: `_refocusScanner` — مسارٌ ساخنٌ يلمسه كلُّ مسحةٍ ولا يحتمل '
            'إطارَ انتظار، وأثرُه بصريٌّ لا ماليّ. وكلُّ ما عداه (‏الدفعُ، '
            'الطباعةُ، حدُّ المدير) يقع في دالّةٍ غيرِ متزامنةٍ أصلاً فلا '
            'عذرَ لعدم `await`.',
      );
    });

    test('وبوّابةُ الخصم والسعر تنتظر السياسةَ لا تخمّنها', () {
      final cold = _coldReads(_read(_perms));
      expect(cold, 0,
          reason: 'وُجدت $cold قراءةً باردةً في بوّابة الصلاحيات. سقفُ الخصم '
              'ومنعُ تعديل السعر قراران ماليّان — و`null` فيهما تعني '
              '«بلا سقف» و«مسموح»، أي أشدَّ الاحتمالات تساهلاً.');
    });

    test('والقراءةُ الباردةُ الباقيةُ مسنودةٌ بمراقبةٍ تُبقي المزوِّدَ ساخناً',
        () {
      // شاشةُ الكاشير: القراءةُ الباردةُ الوحيدةُ المسموحة تحتاج ضامناً.
      expect(
        _read(_screen),
        contains('ref.watch(quickSalePolicyProvider)'),
        reason: 'لا شيءَ في شجرة شاشة الكاشير يراقب المزوِّدَ، فيبقى بارداً '
            'وترجع القراءةُ المتزامنةُ `null` أبداً — وهو بلاغُ المالك بعينه.',
      );

      // حوارُ الإغلاق: قراءةٌ باردةٌ واحدةٌ مسموحةٌ — `_blindClose` تُنادى من
      // `build` فلا تحتمل `await`. وما عداها (`diffmax`) في دالّةٍ غيرِ
      // متزامنةٍ فتنتظر.
      expect(_coldReads(_read(_closing)), lessThanOrEqualTo(1),
          reason: 'قراءةٌ باردةٌ ثانيةٌ في حوار الإغلاق: الفرقُ يمرّ بلا سبب '
              'قبل أن يسخن المزوِّد.');

      expect(
        _read(_closing),
        contains('ref.watch(quickSalePolicyProvider)'),
        reason: '`_blindClose` تُقرأ في البناء، فبلا مراقبةٍ يظهر المتوقَّعُ '
            'للكاشير قبل العدّ ولو كان الإغلاقُ الأعمى مضاءً.',
      );
    });
  });
}
