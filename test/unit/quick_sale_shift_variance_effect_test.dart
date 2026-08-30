// `diffmax` على حالةِ الإغلاق الحقيقيّة — لا على رقمٍ مخترَع.
//
// ═══ لماذا `PosClosingState` لا رقمٌ مباشر ═══
//
// السؤالُ ليس «هل تعمل `quickSaleShiftDiffNeedsReason`؟» — تلك ثلاثةُ
// أسطر. السؤالُ: **أيُّ رقمٍ يُغذّيها؟** وحالةُ الإغلاق تعرض رقمَين
// مختلفَين تماماً:
//
//   • `totalVariance` = مجموعُ القنوات الثلاث — **يُقاصّ**.
//   • أكبرُ القنوات بالقيمة المطلقة — لا يُقاصّ.
//
// وبينهما ورديةٌ يخرج منها ٣٠٠ نقداً بلا سطرِ تفسيرٍ واحد.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart' show ShiftClosingAggregates;
import 'package:ural_erp/domain/models/quick_sale_policy.dart';
import 'package:ural_erp/presentation/pos/providers/pos_closing_controller.dart';

void main() {
  /// وردية: نقدٌ متوقَّعٌ [cash] وبنكٌ [bank] وكليك [click]، والكاشير
  /// يعدّ [countedCash] و[countedBank] و[countedClick].
  PosClosingState shift({
    required double expectedCash,
    required double expectedBank,
    required double expectedClick,
    required double countedCash,
    required double countedBank,
    required double countedClick,
  }) =>
      PosClosingState(
        aggregates: ShiftClosingAggregates(
          salesCash: expectedCash,
          salesBank: expectedBank,
          salesClick: expectedClick,
        ),
        actualCashAmount: countedCash,
        actualBankAmount: countedBank,
        actualClickAmount: countedClick,
      );

  group('الرقمُ الحاكمُ — أكبرُ القنوات لا مجموعُها', () {
    test('عجزٌ نقديٌّ ٣٠٠ وفائضُ بنكٍ ٣٠٠: المجموعُ صفرٌ والحاكمُ ٣٠٠',
        () {
      final s = shift(
        expectedCash: 1000,
        expectedBank: 500,
        expectedClick: 0,
        countedCash: 700,
        countedBank: 800,
        countedClick: 0,
      );

      expect(s.cashVariance, -300);
      expect(s.bankVariance, 300);
      expect(s.totalVariance, 0,
          reason: 'هذا هو الفخُّ: الرقمُ المعروضُ في الترويسة **يُقاصّ**');

      final governing = quickSaleGoverningShiftDiff(
        cash: s.cashVariance,
        bank: s.bankVariance,
        click: s.clickVariance,
      );
      expect(governing, 300);
    });

    test('وحدٌّ ٢٠ يمسك الحاكمَ ولا يمسك المجموعَ — الفرقُ ورديةٌ كاملة', () {
      final s = shift(
        expectedCash: 1000,
        expectedBank: 500,
        expectedClick: 0,
        countedCash: 700,
        countedBank: 800,
        countedClick: 0,
      );
      const limit = 20.0;

      expect(
        quickSaleShiftDiffNeedsReason(
            difference: s.totalVariance, limit: limit),
        isFalse,
        reason: 'بالمجموع: يمرّ الإغلاقُ بلا سبب — وهذا هو العطب',
      );
      expect(
        quickSaleShiftDiffNeedsReason(
          difference: quickSaleGoverningShiftDiff(
            cash: s.cashVariance,
            bank: s.bankVariance,
            click: s.clickVariance,
          ),
          limit: limit,
        ),
        isTrue,
        reason: 'وبالحاكم: يُسأل الكاشيرُ — وهو الصواب، لأنّ قيدَ الفرق '
            'يُرحّل النقديَّ وحدَه',
      );
    });

    test('والحاكمُ يختار كليك حين تكون هي الأكبر', () {
      expect(quickSaleGoverningShiftDiff(cash: -5, bank: 3, click: -40), 40);
      expect(quickSaleGoverningShiftDiff(cash: 0, bank: 0, click: 0), 0);
      expect(quickSaleGoverningShiftDiff(cash: -7, bank: 7, click: 7), 7);
    });
  });

  group('القيمةُ المطلقة — العجزُ كالزيادة', () {
    test('عجزُ ٢٥ يطلب سبباً كما تطلبه زيادةُ ٢٥ عند حدِّ ٢٠', () {
      final short = shift(
        expectedCash: 1000,
        expectedBank: 0,
        expectedClick: 0,
        countedCash: 975,
        countedBank: 0,
        countedClick: 0,
      );
      final over = shift(
        expectedCash: 1000,
        expectedBank: 0,
        expectedClick: 0,
        countedCash: 1025,
        countedBank: 0,
        countedClick: 0,
      );

      expect(short.cashVariance, -25);
      expect(over.cashVariance, 25);

      for (final s in [short, over]) {
        expect(
          quickSaleShiftDiffNeedsReason(
              difference: s.cashVariance, limit: 20),
          isTrue,
          reason: 'إهمالُ الإشارة يُعفي العجزَ — وهو الأخطرُ محاسبيّاً',
        );
      }
    });

    test('وحدٌّ ٥٠ يمرّر العجزَ ٢٥ بلا سبب', () {
      expect(quickSaleShiftDiffNeedsReason(difference: -25, limit: 50),
          isFalse);
    });

    test('«بلا حد» تمرّر أيَّ فرقٍ — والمطلوبُ ألّا تُقرأ صفراً', () {
      expect(
        quickSaleShiftDiffNeedsReason(difference: -99999, limit: null),
        isFalse,
        reason: 'null تعني «بلا حد»؛ وصفرٌ كان سيسأل عن كلّ قرش',
      );
    });
  });

  group('حدودُ التصميم الأربعة', () {
    test('٥ · ٢٠ · ٥٠ · بلا حد — بالترتيب', () {
      QuickSalePolicyValues v(String i) =>
          QuickSalePolicyValues({'pos_shift_diff_threshold': i});
      expect(quickSaleShiftDiffLimit(v('0')), 5);
      expect(quickSaleShiftDiffLimit(v('1')), 20);
      expect(quickSaleShiftDiffLimit(v('2')), 50);
      expect(quickSaleShiftDiffLimit(v('3')), isNull);
    });

    test('والافتراضُ ٢٠ في قاعدةٍ بكر', () {
      expect(quickSaleShiftDiffLimit(const QuickSalePolicyValues({})), 20);
    });

    test('فهرسٌ فاسدٌ يعود للافتراض لا يُسقط الحوار', () {
      for (final bad in ['9', '-1', 'نص', '']) {
        expect(
          quickSaleShiftDiffLimit(
              QuickSalePolicyValues({'pos_shift_diff_threshold': bad})),
          20,
          reason: 'قيمةُ «$bad» أسقطت الترجمةَ — وحوارُ الإغلاق لا يحتمل رمية',
        );
      }
    });
  });
}
