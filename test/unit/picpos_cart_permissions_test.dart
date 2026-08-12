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
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/presentation/pos_picpos/screens/picpos_pos_screen.dart'
    as picpos;
import 'package:ural_erp/presentation/pos_picpos/widgets/picpos_cart_permissions.dart'
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

  test('الأكوادُ الثمانيةُ متمايزة', () {
    // تكرارُ كودٍ في جدول الحالات كان سيُخفي دالّةً بلا اختبار.
    expect(cases.keys.toSet(), hasLength(8));
  });
}
