// مجاميعُ إغلاق الوردية تشمل القنوات الثلاث — لا نقداً وبطاقةً فحسب.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// المالُ يتحرّك صحيحاً: `_closeShiftSafes` يكنس كلَّ خزنةٍ إلى صندوق
// الكاشير بطرفٍ مقابل (مقيسٌ ميدانياً 2026-08-12: ١٠+٣٠+١٥ ⇒ ٥٥). لكنّ
// ثلاثةَ **سجلّات** كانت تجمع `actualCash + actualCard` وحدَهما، و
// `actualCardAmount` أصلاً اسمٌ قديمٌ مُموِّهٌ لحقل البنك:
//
//   · لوجُ `[SHIFT-CLOSE]` التشخيصيّ — طبع `actualCash=10 actualCard=30`
//     لورديةٍ أُغلقت على ٥٥.
//   · ملاحظةُ سجلّ تدقيق الخزينة — «بطاقة: X» بلا كليك.
//   · `logShiftClose` في سجلّ النشاط — expected/actual ناقصان قناةً كاملة.
//
// فمن يطابق من السجلّ يرى ٤٠ ويجد في الخزائن ٥٥، فيطارد فرقاً لا وجودَ له
// — أو يفوّته لو كان حقيقياً. الحسابُ في مِقبضٍ واحدٍ مقيسٍ بدل ثلاثِ
// جمعاتٍ مكرَّرة، فأيُّ قناةٍ رابعةٍ لاحقاً تُضاف مرّةً واحدة.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/presentation/pos/providers/pos_closing_controller.dart';

void main() {
  // نفسُ أرقام التشغيلة الميدانية: نقد ١٠ · بنك ٣٠ · كليك ١٥.
  // `system*` مشتقّةٌ لا مُمرَّرة: نقدٌ = الافتتاحيُّ + المبيعات − المرتجع
  // − المصروفات. فبلا مصروفاتٍ ولا مرتجعاتٍ تساوي المبيعات.
  const aggregates = ShiftClosingAggregates(
    salesCash: 10,
    salesBank: 30,
    salesClick: 15,
    salesCount: 3,
    counterSalesCount: 3,
    counterSalesTotal: 55,
  );

  const state = PosClosingState(
    aggregates: aggregates,
    actualCashAmount: 10,
    actualBankAmount: 30,
    actualClickAmount: 15,
  );

  test('المتوقَّعُ يشمل كليك', () {
    expect(state.systemTotal, 55);
    expect(
      state.systemTotal,
      state.systemCash + state.systemCard + state.systemClick,
    );
  });

  test('الفعليُّ يشمل كليك', () {
    expect(state.actualTotal, 55);
    expect(
      state.actualTotal,
      state.actualCashAmount + state.actualBankAmount + state.actualClickAmount,
    );
  });

  test('الجمعُ القديم (نقد + بطاقة) كان يُسقط القناة', () {
    // ضابطٌ يثبّت حجمَ الخطأ: لو عاد أحدٌ للجمع الثنائيّ سقط هذا.
    expect(state.actualCashAmount + state.actualCardAmount, 40);
    expect(state.actualTotal - 40, 15);
  });

  test('المجموعُ يطابق الفرقَ الكلّيَّ صفراً حين لا فرق', () {
    expect(state.totalVariance, 0);
    expect(state.actualTotal - state.systemTotal, state.totalVariance);
  });
}
