// ترجمةُ خيارات السياسة إلى حدودٍ رقميّة — الجسرُ بين الشاشة والمحرّك.
//
// ═══ لماذا دوالُّ خالصةٌ لا شروطٌ داخلَ الودجت ═══
//
// الخيارُ في الشاشة نصٌّ («٩,٩٩٩» · «بلا حد»)، والمحرّكُ يحتاج رقماً أو
// `null`. وهذه الترجمةُ هي **عينُ الموضع الذي يقع فيه العطب**: فهرسٌ يُقرأ
// خطأً يعني سقفاً مختلفاً تماماً — «بلا حد» بدل «٥» يفتح باباً لا يُراجَع.
//
// ووضعُها في `domain/models` يجعلها تُقاس بلا ضخِّ شاشةٍ ولا قاعدةِ بيانات،
// وهو ما يطلبه حارسُ المستودع للحساب الخالص.
//
// ⚠️ **و`null` تعني «بلا حد» لا «صفر»**: الخلطُ بينهما يقلب أكثرَ الإعدادات
// تساهلاً إلى أشدِّها تقييداً.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/quick_sale_policy.dart';

QuickSalePolicyValues _v(Map<String, String> m) => QuickSalePolicyValues(m);

void main() {
  group('سقفُ الفواتير المعلّقة', () {
    test('الخياراتُ الأربعةُ تُترجَم ٥ · ١٠ · ٢٠ · بلا حد', () {
      expect(quickSaleHoldCap(_v({'pos_hold_max_orders': '0'})), 5);
      expect(quickSaleHoldCap(_v({'pos_hold_max_orders': '1'})), 10);
      expect(quickSaleHoldCap(_v({'pos_hold_max_orders': '2'})), 20);
      expect(quickSaleHoldCap(_v({'pos_hold_max_orders': '3'})), isNull,
          reason: '«بلا حد» تعني `null` لا صفراً — وصفرٌ كان سيمنع كلَّ تعليق.');
    });

    test('والافتراضُ ١٠ كما في التصميم', () {
      expect(quickSaleHoldCap(const QuickSalePolicyValues({})), 10);
    });

    test('والحكمُ نفسُه يقارن العددَ الحاليَّ بالسقف', () {
      expect(quickSaleCanHoldMore(current: 9, cap: 10), isTrue);
      expect(quickSaleCanHoldMore(current: 10, cap: 10), isFalse,
          reason: 'الوصولُ للحدّ يمنع تعليقَ فاتورةٍ جديدة — «الوصول» لا '
              '«التجاوز».');
      expect(quickSaleCanHoldMore(current: 999, cap: null), isTrue);
    });
  });

  group('أقصى كميّةٍ في السطر', () {
    test('تُترجَم ٩٩ · ٩٩٩ · ٩٩٩٩ · بلا حد', () {
      expect(quickSaleMaxLineQty(_v({'pos_max_line_quantity': '0'})), 99);
      expect(quickSaleMaxLineQty(_v({'pos_max_line_quantity': '1'})), 999);
      expect(quickSaleMaxLineQty(_v({'pos_max_line_quantity': '2'})), 9999);
      expect(quickSaleMaxLineQty(_v({'pos_max_line_quantity': '3'})), isNull);
    });

    test('والافتراضُ ٩٩٩', () {
      expect(quickSaleMaxLineQty(const QuickSalePolicyValues({})), 999);
    });
  });

  group('حدُّ تأكيد المدير', () {
    test('يُترجَم ١٠٠٠ · ٢٥٠٠ · ٥٠٠٠ · بلا حد', () {
      expect(quickSaleManagerConfirmAbove(_v({'pos_manager_confirm_above': '0'})),
          1000);
      expect(quickSaleManagerConfirmAbove(_v({'pos_manager_confirm_above': '1'})),
          2500);
      expect(quickSaleManagerConfirmAbove(_v({'pos_manager_confirm_above': '2'})),
          5000);
      expect(quickSaleManagerConfirmAbove(_v({'pos_manager_confirm_above': '3'})),
          isNull);
    });

    test('والافتراضُ ٥٠٠٠ — وهو الفهرسُ الثالثُ في التصميم', () {
      expect(quickSaleManagerConfirmAbove(const QuickSalePolicyValues({})), 5000);
    });
  });

  group('سقفُ الخصم اليدويّ', () {
    test('يُقرأ رقماً لا فهرساً', () {
      expect(quickSaleDiscountCap(_v({'pos_manual_discount_cap': '30'})), 30);
      expect(quickSaleDiscountCap(const QuickSalePolicyValues({})), 15);
    });

    test('والحكمُ يقارن نسبةَ الخصم بالسقف', () {
      expect(quickSaleDiscountAllowed(percent: 15, cap: 15), isTrue,
          reason: 'المساواةُ مسموحةٌ — السقفُ حدٌّ أعلى شاملٌ لا حاجزٌ دونه.');
      expect(quickSaleDiscountAllowed(percent: 15.01, cap: 15), isFalse);
      expect(quickSaleDiscountAllowed(percent: 100, cap: 0), isFalse);
    });
  });

  group('فرقُ الوردية المسموح', () {
    test('يُترجَم ٥ · ٢٠ · ٥٠ · بلا حد، والافتراضُ ٢٠', () {
      expect(quickSaleShiftDiffLimit(_v({'pos_shift_diff_threshold': '0'})), 5);
      expect(quickSaleShiftDiffLimit(const QuickSalePolicyValues({})), 20);
      expect(quickSaleShiftDiffLimit(_v({'pos_shift_diff_threshold': '3'})),
          isNull);
    });

    test('والفرقُ يُقاس بقيمته المطلقة', () {
      expect(quickSaleShiftDiffNeedsReason(difference: -25, limit: 20), isTrue,
          reason: 'العجزُ ٢٥ يحتاج سبباً كما تحتاجه الزيادةُ ٢٥ — '
              'وإهمالُ الإشارة يُعفي العجزَ وهو الأخطر.');
      expect(quickSaleShiftDiffNeedsReason(difference: 25, limit: 20), isTrue);
      expect(quickSaleShiftDiffNeedsReason(difference: -20, limit: 20), isFalse);
      expect(quickSaleShiftDiffNeedsReason(difference: 9999, limit: null),
          isFalse);
    });
  });

  group('عددُ نسخ الإيصال', () {
    test('يُترجَم ١ · ٢ · ٣ ولا يكون صفراً أبداً', () {
      expect(quickSaleReceiptCopies(_v({'pos_receipt_copies': '0'})), 1);
      expect(quickSaleReceiptCopies(_v({'pos_receipt_copies': '1'})), 2);
      expect(quickSaleReceiptCopies(_v({'pos_receipt_copies': '2'})), 3);
      expect(quickSaleReceiptCopies(const QuickSalePolicyValues({})), 1);
    });
  });
}
