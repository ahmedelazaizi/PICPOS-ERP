// صلاحياتُ سلّة البيع في شاشة PicPos.
//
// ── البلاغ الميدانيّ (2026-08-11) ────────────────────────────────────────
// «رفعتُ التحديد عن حذف صنف من السلة وتفريغ السلة، ودخلتُ بالكاشير، وأضفتُ
// أصنافاً، وحذفتُ صنفاً — فحُذف، ولم يظهر حوارُ إدخال كلمة مرور المسؤول.»
//
// ── الجذر ────────────────────────────────────────────────────────────────
// الصلاحيتان محروستان حراسةً صحيحة — في `pos/widgets/cart_item_tile.dart`
// و`cart_view.dart`. وشاشةُ PicPos توأمٌ كُتب من جديدٍ **ولا يستوردهما**،
// فنُقل السلوكُ ولم تُنقل الحراسة. فلم يكن ثمّة تجاوزٌ للصلاحية بل **غيابُ
// نقطةِ فحصٍ من الأساس**، والحوارُ لا يظهر لأن لا شيءَ يستدعيه.
//
// ── ما يقيسه هذا الملفّ ──────────────────────────────────────────────────
// دوالُّ القرار الخالصة وحدَها (‏`can…`) — هي ما يُبنى عليه الفحصُ في نقطة
// الاستدعاء. ووصلُها بالمعالِجات محروسٌ بنيوياً في
// `picpos_permission_parity_test`، وسلوكُ الحوار نفسِه مقيسٌ في
// `permission_guard_override_fallback_test`.
//
// والنمطُ يطابق `canOpenPosWeightDialog` المجاور في نفس الملفّ: مديرُ النظام
// يمرّ بلا كودٍ صريحٍ لأن هذه ليست عملياتٍ ماليةً حرجة.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/presentation/pos_picpos/screens/picpos_pos_screen.dart'
    as picpos;
import 'package:picpos_erp/presentation/pos_picpos/widgets/picpos_cart_permissions.dart'
    as shared;

void main() {
  // (اسمُ الصلاحية، الدالّة) — جدولٌ واحدٌ يمنع أن يُضاف فعلٌ بلا اختبار.
  final cases = <String, bool Function(List<String>)>{
    PermissionCodes.posRemoveItem: picpos.canRemoveCartItem,
    PermissionCodes.posClearCart: picpos.canClearCart,
    PermissionCodes.posPriceEdit: picpos.canEditCartPrice,
    PermissionCodes.posQuantityEdit: picpos.canEditCartQuantity,
    // دفعة ٢ — ما يمسّ المال.
    PermissionCodes.posOpenDrawer: shared.canOpenCashDrawerCodes,
    PermissionCodes.posTaxToggle: shared.canToggleTaxCodes,
    // دفعة ٣.
    PermissionCodes.posCustomerSelect: shared.canSelectCustomerCodes,
    PermissionCodes.posPreviousInvoices: shared.canViewPreviousInvoicesCodes,
    // ── دفعة ٤ (2026-08-13): ثقوبٌ كشفها الحارسُ بعد أن صار محافظاً ──────
    // الثلاثةُ كانت محروسةً في النظير القديم وحدَه، وأفعالُها تجري في PicPos
    // بلا فحصٍ إطلاقاً — مقيسٌ لا مفترَض:
    //   · `pos_discount` — ثلاثةُ أبوابٍ مفتوحة: خليةُ «الخصم ٪» في
    //     `picpos_items_table.dart`، وفرعُ الخصم في حوار «تعديل الصنف»،
    //     وخصمُ الفاتورة كلِّها. وجارتا الخليةِ (الكميةُ والسعر) محروستان
    //     في نفس الملفّ — فالنمطُ كان موجوداً ولم يُطبَّق عليها.
    //   · `pos_hold_order` — `_holdOrder` بلا فحصٍ إطلاقاً.
    //   · `pos_expense` — `_showExpenses` يفتح حوارَ المصاريف بلا فحص،
    //     وفيه زرُّ «إضافة مصروف» ⇒ مالٌ يخرج من الدرج.
    PermissionCodes.posDiscount: shared.canApplyDiscountCodes,
    PermissionCodes.posHoldOrder: shared.canHoldOrderCodes,
    PermissionCodes.posExpense: shared.canAddExpenseCodes,
    //   · `pos_delivery` — شريحةُ «توصيل» في لوحة الدفع. حسمها المالكُ
    //     2026-08-13: هي ميزةُ التوصيل في PicPos، فتُحرَس. وكانت مخفيّةً عن
    //     الحارس لأن `FeatureKey.posDelivery` يحمل نفسَ الاسم.
    PermissionCodes.posDelivery: shared.canSetDeliveryOrderCodes,
  };

  cases.forEach((code, can) {
    group(code, () {
      test('مرفوضٌ بلا الكود — وهو البلاغُ نفسُه', () {
        expect(can(const []), isFalse,
            reason: 'بلا هذا الفحص يمضي الفعلُ بلا أثرٍ ولا حوار');
      });

      test('مسموحٌ مع الكود', () {
        expect(can([code]), isTrue);
      });

      test('ومديرُ النظام يمرّ — ليست عمليةً ماليةً حرجة', () {
        expect(can(const ['system_admin']), isTrue);
        expect(can(const ['*']), isTrue);
      });

      test('وكودٌ آخرُ لا يفتحه', () {
        // ضابط: لولاه لمرّ حلٌّ يرجع `true` لأيّ قائمةٍ غيرِ فارغة.
        expect(can(const ['pos_access']), isFalse);
      });
    });
  });

  test('الأكوادُ الاثنا عشرَ متمايزة', () {
    // تكرارُ كودٍ في جدول الحالات كان سيُخفي دالّةً بلا اختبار.
    expect(cases.keys.toSet(), hasLength(12));
  });
}
