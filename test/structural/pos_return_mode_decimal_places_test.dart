// حارسٌ بنيويّ — `PosReturnMode.refundTotal` يجب أن يمرّر
// `decimalPlaces: AppConstants.decimalPlaces` صراحةً إلى
// `calculateReturnRefundTotal`، لا أن يسكت على افتراضيّها الخاص (`3`).
//
// `ReturnsRepositoryImpl._calculateReturnTotal` (الصرفُ الفعليّ من الدرج)
// يمرّر `decimalPlaces: AppConstants.decimalPlaces` صراحةً
// (`returns_repository_impl.dart`). لو تُرك هذا الوسيطُ فارغاً في
// `refundTotal` (المعروضُ للكاشير) فهو يعتمد على افتراضيّ
// `calculateReturnRefundTotal` الخاصّ (`= 3`) بدل الثابت المشترك.
//
// متساويان اليوم بالصدفة (`AppConstants.decimalPlaces == 3` —
// `app_constants.dart:25`)، لكنّ تغييرَ الثابت وحدَه — بلا أيّ تعديلٍ آخر —
// يُعيد فتحَ الفجوةَ بين المعروض والمصروف فعلياً في الخانة الثالثة. وهو
// تحديداً الافتراقُ الذي أرادت مراجعةُ 2026-08-16 جعلَه مستحيلاً باستخراج
// الصيغة إلى دالّةٍ واحدة.
//
// ⚠️ اختبارٌ سلوكيٌّ (يقارن قيمتَين) لا يميّز الحالتَين: كلتاهما تُنتجان ٣
// خاناتٍ اليوم فتتطابق النتائج رقمياً رغم اختلاف المصدر. فهذا الحارسُ نصّيٌّ
// عمداً — يقرأ استدعاءَ `calculateReturnRefundTotal` داخل
// [PosReturnMode.refundTotal] ويؤكّد أنه يذكر `AppConstants.decimalPlaces`
// حرفياً، فيفشل فوراً لو أُعيد الإغفال بصرف النظر عن قيمة الثابت.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _relPath = 'lib/presentation/pos_picpos/state/pos_return_mode.dart';

/// نصُّ الملفّ بلا تعليقات. نسخةٌ محليّةٌ متعمَّدةٌ — راجع نفس القرار في
/// `return_refund_required_fields_test.dart` المجاور.
String _stripComments(String src) {
  final out = StringBuffer();
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
      i += 2;
      while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) {
        i++;
      }
      i += 2;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

void main() {
  late String source;
  late String stripped;

  setUpAll(() {
    final file = File(_relPath);
    expect(file.existsSync(), isTrue,
        reason: 'الملفُّ المتوقَّعُ غير موجودٍ: $_relPath — حدّث هذا الحارس');
    source = file.readAsStringSync();
    expect(source, isNotEmpty,
        reason: 'الملفُّ قُرئ فارغاً — الحارسُ سيمرّ بلا فحصٍ فعليّ');
    stripped = _stripComments(source);
  });

  test('الاستيرادُ اللازمُ لِـAppConstants موجودٌ', () {
    expect(
      source.contains("import '../../../core/constants/app_constants.dart';"),
      isTrue,
      reason: 'بلا استيرادٍ صريح، الإشارةُ إلى AppConstants.decimalPlaces '
          'لن تُترجَم',
    );
  });

  test('refundTotal يمرّر decimalPlaces: AppConstants.decimalPlaces صراحةً',
      () {
    final getterIndex = stripped.indexOf('double get refundTotal =>');
    expect(getterIndex, greaterThan(0),
        reason: 'موقعُ refundTotal تغيّر — أعِد اشتقاق هذا الفحص');

    final callIndex =
        stripped.indexOf('calculateReturnRefundTotal(', getterIndex);
    expect(callIndex, greaterThan(getterIndex),
        reason: 'refundTotal لم يعد يستدعي calculateReturnRefundTotal '
            'مباشرةً — أعِد اشتقاق هذا الفحص');

    // استخراجُ جسم النداء حتى القوس المطابق (عدٌّ بسيطٌ للأقواس؛ يكفي هنا).
    const opener = 'calculateReturnRefundTotal(';
    var depth = 1;
    var k = callIndex + opener.length;
    final start = k;
    while (k < stripped.length && depth > 0) {
      if (stripped[k] == '(') depth++;
      if (stripped[k] == ')') depth--;
      k++;
    }
    final args = stripped.substring(start, k - 1);

    expect(
      args.contains('decimalPlaces: AppConstants.decimalPlaces'),
      isTrue,
      reason: 'refundTotal يجب أن يمرّر decimalPlaces: '
          'AppConstants.decimalPlaces صراحةً — نفسُ ما يفعله '
          'ReturnsRepositoryImpl._calculateReturnTotal. إغفالُه يُسكت اليوم '
          '(كلاهما ينتج ٣) ويفترق الطرفان يومَ يتغيّر الثابتُ وحدَه.\n'
          'نصُّ النداء المرصود: $args',
    );
  });

  test('ضابط: الاستدعاءُ المستهدَفُ موجودٌ فعلاً — لا صفرَ فحص', () {
    expect(stripped.contains('calculateReturnRefundTotal('), isTrue);
    expect(stripped.contains('AppConstants.decimalPlaces'), isTrue);
  });

  test('التعليقُ ليس مصدراً للفحص — يُجرَّد قبل القياس', () {
    const commented = '// decimalPlaces: AppConstants.decimalPlaces\n'
        'final x = 1;';
    final result = _stripComments(commented);
    expect(result.contains('decimalPlaces'), isFalse);
    expect(result.contains('final x = 1;'), isTrue);
  });
}
