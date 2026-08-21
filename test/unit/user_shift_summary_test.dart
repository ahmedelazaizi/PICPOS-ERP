// تلخيصُ الورديات حسب المستخدم — الحسابُ الخالص.
//
// ── طلبُ المالك (2026-08-14) ────────────────────────────────────────────────
// «تقريرٌ خاصٌّ باسم المستخدم مع الإغلاق والطباعة، أوضحُ من تقرير المبيعات
// حسب المستخدم — لأنه للأسف غيرُ دقيق.»
//
// وأوضحُ ما يريده مديرٌ يجرد: **مَن عليه عجزٌ ومَن له زيادة**. والفرقُ
// الصافي وحدَه يخفي ذلك: كاشيرٌ عجز ١٠٠ في وردية وزاد ١٠٠ في أخرى يظهر
// صفراً كأنه منضبط. فالعجزُ والزيادةُ يُجمعان **منفصلَين** ثم يُعرض
// الصافي — ثلاثةُ أرقامٍ لا رقم.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/user_shift_summary.dart';

ShiftSummaryInput _row({
  required String userName,
  String status = 'closed',
  double opening = 0,
  double? expected,
  double? actual,
  double? variance,
}) =>
    ShiftSummaryInput(
      userName: userName,
      status: status,
      openingBalance: opening,
      expectedCash: expected,
      actualCash: actual,
      variance: variance,
    );

void main() {
  test('يجمع ورديات المستخدم الواحد في صفٍّ واحد', () {
    final out = summarizeShiftsByUser([
      _row(userName: 'أحمد', variance: -50),
      _row(userName: 'أحمد', variance: -30),
    ]);

    expect(out, hasLength(1));
    expect(out.single.userName, equals('أحمد'));
    expect(out.single.shiftCount, equals(2));
  });

  test('ويفصل العجزَ عن الزيادة بدل صافٍ يخفيهما', () {
    // ١٠٠ عجزاً و١٠٠ زيادةً ليست انضباطاً — هي خطآن يتقاصّان.
    final out = summarizeShiftsByUser([
      _row(userName: 'سمير', variance: -100),
      _row(userName: 'سمير', variance: 100),
    ]);

    final s = out.single;
    expect(s.shortageTotal, equals(100), reason: 'العجزُ يُجمع موجباً');
    expect(s.surplusTotal, equals(100));
    expect(s.varianceTotal, equals(0), reason: 'والصافي يبقى معروضاً كذلك');
  });

  test('والوردياتُ المفتوحةُ تُعدّ ولا تدخل الفروق', () {
    // وردية مفتوحة بلا `variance` — عدُّها صفراً يكذب، وإسقاطُها يخفي أن
    // للمستخدم ورديةً لم تُجرد بعد.
    final out = summarizeShiftsByUser([
      _row(userName: 'ليلى', status: 'closed', variance: -20),
      _row(userName: 'ليلى', status: 'open', variance: null),
    ]);

    final s = out.single;
    expect(s.shiftCount, equals(2));
    expect(s.openCount, equals(1));
    expect(s.closedCount, equals(1));
    expect(s.shortageTotal, equals(20));
  });

  test('ويجمع النقديَّ المتوقَّعَ والفعليَّ ورصيدَ الافتتاح', () {
    final out = summarizeShiftsByUser([
      _row(userName: 'نور', opening: 100, expected: 500, actual: 480,
          variance: -20),
      _row(userName: 'نور', opening: 50, expected: 300, actual: 300,
          variance: 0),
    ]);

    final s = out.single;
    expect(s.openingTotal, equals(150));
    expect(s.expectedCashTotal, equals(500 + 300));
    expect(s.actualCashTotal, equals(480 + 300));
  });

  test('والترتيبُ بالاسم — ثابتٌ كي تطابق الورقةُ الشاشة', () {
    // حارسُ `report_export_matches_screen_test` يقارن التصديرَ بالمعروض،
    // فترتيبٌ غيرُ ثابتٍ يجعله يسقط عشوائياً.
    final out = summarizeShiftsByUser([
      _row(userName: 'ياسر'),
      _row(userName: 'أحمد'),
      _row(userName: 'سمير'),
    ]);

    expect(out.map((e) => e.userName).toList(),
        equals(['أحمد', 'سمير', 'ياسر']));
  });

  test('ولا صفوفَ من لا شيء', () {
    expect(summarizeShiftsByUser(const []), isEmpty);
  });
}
