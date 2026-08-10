// حارسٌ بنيويّ — تقريرُ الخزينة يعرض رصيداً **جارياً** لا لقطةً مخزَّنة.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// عمودٌ يعرض قيمةً مخزَّنةً صحيحةً **وقتَ كتابتها** وخاطئةً وقتَ عرضها.
//
// `safe_transactions.balanceAfter` لقطةٌ تُحسب لحظةَ الإدراج:
//   · تحت التصفية (مدىً/خزنة) لا تصف النافذةَ المعروضة — أوّلُ صفٍّ يبدأ من
//     رقمٍ لا علاقةَ له بما فوقه، فالعمودُ يقفز بلا تفسير.
//   · وبعد إلغاء حركةٍ سابقةٍ (حذفٌ ناعم) تبقى لقطاتُ ما بعدها على حالها
//     فتصير كلُّها خاطئة — **بلا أيّ إشارة**: أرقامٌ موجودةٌ ومعقولةٌ وغلط.
//     مقيسٌ في `test/integration/treasury_running_balance_test.dart`: اللقطةُ
//     تقول ١٣٠ بينما الرصيدُ الحقيقيُّ ٣٠.
//
// حارسٌ بنيويٌّ لا سلوكيّ: الحسابُ مقيسٌ في
// `test/unit/safe_running_balance_test.dart` وقاعدةُ الإشارة مقيسةٌ ضدّ
// `safes.balance` نفسِه في اختبار التكامل أعلاه.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _screenPath =
    'lib/presentation/screens/reports/treasury_report_screen.dart';

bool _isCode(String line) {
  final t = line.trimLeft();
  return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
}

bool _isCall(String line, String name) =>
    _isCode(line) && line.contains('$name(');

void main() {
  final screen = File(_screenPath);

  test('الشاشةُ لا تعرض `balanceAfter` المخزَّن إطلاقاً', () {
    expect(screen.existsSync(), isTrue, reason: 'مسارُ شاشة الخزينة تغيّر');

    final offenders = screen
        .readAsLinesSync()
        .where((l) => _isCode(l) && l.contains('balanceAfter'))
        .toList();

    expect(
      offenders,
      isEmpty,
      reason: 'اللقطةُ المخزَّنةُ لا تصف النافذةَ المفلترة، وتصير خاطئةً '
          'صامتةً بعد أيّ إلغاء. الصوابُ `runningBalances` فوق رصيدٍ '
          'افتتاحيّ. المخالف: $offenders',
    );
  });

  test('وتبني العمودَ من رصيدٍ افتتاحيٍّ ومشيٍ فوقه', () {
    final lines = screen.readAsLinesSync();
    expect(
      lines.any((l) => _isCall(l, 'getSafeOpeningBalance')),
      isTrue,
      reason: 'بلا مرساةٍ للنافذة يبدأ العمودُ من صفرٍ فيكذب على كلّ مدىً '
          'لا يبدأ من أوّل يومٍ في عمر الخزنة.',
    );
    expect(
      lines.any((l) => _isCall(l, 'runningBalances')),
      isTrue,
      reason: 'المشيُ هو ما يجعل العمودَ يتّسق مع عمود المبلغ سطراً بسطر.',
    );
  });

  test('ضابط: قاعدةُ الإشارة في مصدرٍ واحدٍ يشترك فيه الاستعلامُ والشاشة', () {
    // لو نُسخت القاعدةُ داخل `CASE` في SQL لانحرفت النسختان بأوّل نوعٍ
    // جديدٍ يُضاف، وعادت فئةُ «رقمٌ معقولٌ وغلط» من الباب الخلفي.
    final dao = File('lib/data/database/daos/treasury_reports_dao.dart');
    expect(dao.existsSync(), isTrue);
    expect(
      dao.readAsLinesSync().any((l) => _isCall(l, 'signedSafeDelta')),
      isTrue,
      reason: 'الاستعلامُ يجمع في SQL ويطبّق الإشارةَ بـ`signedSafeDelta` '
          'نفسِها التي تستعملها الشاشة.',
    );
  });
}
