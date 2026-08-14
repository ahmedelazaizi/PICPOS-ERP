// تلخيصُ الورديات حسب المستخدم — حسابٌ خالصٌ بلا قاعدةٍ ولا ودجت.
//
// طلبُ المالك 2026-08-14: «تقريرٌ خاصٌّ باسم المستخدم مع الإغلاق والطباعة،
// أوضحُ من تقرير المبيعات حسب المستخدم.»
//
// ── لماذا مدخلٌ بدائيٌّ لا `ShiftReportDto` ───────────────────────────────
// الـDTO يعيش في `data/database/daos/treasury_dao.dart`، واستيرادُه هنا يقلب
// اتّجاهَ الطبقات (‏`domain` تعتمد على `data`). فالمدخلُ حقولٌ بدائيّة،
// والشاشةُ — وهي في `presentation` وتستورد الـDTO أصلاً — تحوّل.

/// صفُّ ورديةٍ كما يحتاجه التلخيص.
class ShiftSummaryInput {
  final String userName;

  /// `'open'` أو `'closed'`.
  final String status;
  final double openingBalance;
  final double? expectedCash;
  final double? actualCash;

  /// `expected - actual`. `null` للورديات المفتوحة — لم تُجرد بعد.
  final double? variance;

  const ShiftSummaryInput({
    required this.userName,
    required this.status,
    required this.openingBalance,
    this.expectedCash,
    this.actualCash,
    this.variance,
  });
}

/// سطرُ مستخدمٍ في التقرير.
class UserShiftSummary {
  final String userName;
  final int shiftCount;
  final int closedCount;
  final int openCount;
  final double openingTotal;
  final double expectedCashTotal;
  final double actualCashTotal;

  /// مجموعُ العجز **موجباً** (الفروقُ السالبة).
  final double shortageTotal;

  /// مجموعُ الزيادة (الفروقُ الموجبة).
  final double surplusTotal;

  /// الصافي — يبقى معروضاً، لكنه لا يُغني عن الاثنَين فوقَه.
  final double varianceTotal;

  const UserShiftSummary({
    required this.userName,
    required this.shiftCount,
    required this.closedCount,
    required this.openCount,
    required this.openingTotal,
    required this.expectedCashTotal,
    required this.actualCashTotal,
    required this.shortageTotal,
    required this.surplusTotal,
    required this.varianceTotal,
  });
}

/// يلخّص الوردياتِ في سطرٍ لكلّ مستخدم، مرتَّباً بالاسم.
///
/// ── لماذا العجزُ والزيادةُ منفصلان ───────────────────────────────────────
/// كاشيرٌ عجز ١٠٠ في وردية وزاد ١٠٠ في أخرى يظهر صافيه صفراً — فيُقرأ
/// منضبطاً وهو خطآن يتقاصّان. والمديرُ الذي يجرد يحتاج الرقمَين.
///
/// والورديةُ المفتوحةُ تُعدّ ولا تدخل الفروق: عدُّ `null` صفراً يكذب،
/// وإسقاطُها يخفي أن للمستخدم ورديةً لم تُجرد.
///
/// والترتيبُ بالاسم لأن `report_export_matches_screen_test` يقارن التصديرَ
/// بالمعروض — وترتيبٌ غيرُ ثابتٍ يُسقطه عشوائياً.
List<UserShiftSummary> summarizeShiftsByUser(
  Iterable<ShiftSummaryInput> rows,
) {
  final byUser = <String, List<ShiftSummaryInput>>{};
  for (final r in rows) {
    byUser.putIfAbsent(r.userName, () => []).add(r);
  }

  final names = byUser.keys.toList()..sort();
  return [
    for (final name in names)
      () {
        final list = byUser[name]!;
        var shortage = 0.0;
        var surplus = 0.0;
        var variance = 0.0;
        var opening = 0.0;
        var expected = 0.0;
        var actual = 0.0;
        var open = 0;
        var closed = 0;

        for (final r in list) {
          opening += r.openingBalance;
          expected += r.expectedCash ?? 0;
          actual += r.actualCash ?? 0;
          if (r.status == 'open') {
            open++;
          } else {
            closed++;
          }
          final v = r.variance;
          if (v == null) continue;
          variance += v;
          if (v < 0) {
            shortage += -v;
          } else if (v > 0) {
            surplus += v;
          }
        }

        return UserShiftSummary(
          userName: name,
          shiftCount: list.length,
          closedCount: closed,
          openCount: open,
          openingTotal: opening,
          expectedCashTotal: expected,
          actualCashTotal: actual,
          shortageTotal: shortage,
          surplusTotal: surplus,
          varianceTotal: variance,
        );
      }(),
  ];
}
