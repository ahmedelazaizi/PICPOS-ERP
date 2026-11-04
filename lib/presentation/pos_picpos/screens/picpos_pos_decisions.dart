part of 'picpos_pos_screen.dart';

/// فحص صريح قبل فتح ديالوج الميزان — نفس الفحص الموجود في
/// `pos_main_operations.dart` (`canOpenPosWeightDialog`)، لكن مكرَّر هنا بدل
/// ما يتشارك، لأن الملفين مكتبتين مختلفتين (`part of` جذور مختلفة) ومفيش
/// نقطة مشتركة موجودة أصلاً بينهم غير النسخ الصريح المقصود لهذا الفورك (زي
/// ما موثّق في تعليق رأس الملف).
@visibleForTesting
bool canOpenPosWeightDialog(List<String> permissions) {
  final isAdmin =
      permissions.contains('system_admin') || permissions.contains('*');
  return isAdmin || permissions.contains(PermissionCodes.posWeightDialog);
}

/// نسخة أعلى مستوى بتقرا الصلاحيات من `ref` وتعرض توست الرفض — سطر واحد
/// في نقطة الاستدعاء (زي `pos_main_operations.dart`).
@visibleForTesting
Future<bool> ensurePosWeightDialogPermission(
  WidgetRef ref,
  BuildContext context,
) async {
  final permissions =
      ref.read(currentUserPermissionsProvider).asData?.value ??
          const <String>[];
  if (canOpenPosWeightDialog(permissions)) return true;
  if (context.mounted) {
    showPosToast(context, ref, tr('ليس لديك صلاحية استخدام الميزان'),
        type: PosNotificationType.error);
  }
  return false;
}

// ── صلاحياتُ السلّة ────────────────────────────────────────────────────────
//
// بلاغٌ ميدانيّ (2026-08-11): «رفعتُ التحديد عن حذف صنف من السلة، ودخلتُ
// بالكاشير، فحذف الصنفَ ولم يظهر حوارُ كلمة المرور».
//
// الأربعةُ محروسةٌ في `pos/widgets/cart_item_tile.dart` و`cart_view.dart` —
// وهذه الشاشةُ توأمٌ كُتب من جديدٍ **ولا يستوردهما** (‏السببُ موثَّقٌ في
// `picpos_payment_panel.dart:11`). فنُقل السلوكُ ولم تُنقل الحراسة: لم يكن
// ثمّة تجاوزٌ للصلاحية بل **غيابُ نقطةِ فحصٍ من الأساس**.
//
// دوالُّ قرارٍ خالصةٌ قصداً — تُختبر بلا شجرةِ ودجت، والوصلُ محروسٌ في
// `picpos_permission_parity_test`. ومديرُ النظام يمرّ بلا كودٍ صريحٍ لأن هذه
// ليست عملياتٍ ماليةً حرجة، تماماً كـ`canOpenPosWeightDialog` فوق.

bool _isAdmin(List<String> p) =>
    p.contains('system_admin') || p.contains('*');

/// حذفُ صنفٍ من السلة (`pos_remove_item`).
@visibleForTesting
bool canRemoveCartItem(List<String> permissions) =>
    _isAdmin(permissions) ||
    permissions.contains(PermissionCodes.posRemoveItem);

/// تفريغُ السلة بالكامل (`pos_clear_cart`).
@visibleForTesting
bool canClearCart(List<String> permissions) =>
    _isAdmin(permissions) || permissions.contains(PermissionCodes.posClearCart);

/// تعديلُ سعر صنفٍ في البيع (`pos_price_edit`).
@visibleForTesting
bool canEditCartPrice(List<String> permissions) =>
    _isAdmin(permissions) || permissions.contains(PermissionCodes.posPriceEdit);

/// تعديلُ كميةِ صنفٍ في السلة (`pos_quantity_edit`).
@visibleForTesting
bool canEditCartQuantity(List<String> permissions) =>
    _isAdmin(permissions) ||
    permissions.contains(PermissionCodes.posQuantityEdit);

// ── وضعُ المرتجع: دوالُّ قرارٍ خالصة (المهمّة ٧، جولةُ إصلاح ١) ─────────────
//
// خالصةٌ عمداً — بلا `BuildContext` ولا `WidgetRef` — كي تُختبر بلا شجرة
// ودجت ولا `ProviderContainer`، نفسُ نمط `canOpenPosWeightDialog` أعلاه.

/// «مرتجعٌ كامل» فقط حين استُنفد المتاحُ الحاليّ (`ReturnableLine.availableQty`)
/// على كلّ سطرٍ في [mode]؛ السطرُ المستبعَدُ عمداً يبقي الفاتورةَ جزئيةً.
///
@visibleForTesting
bool computeIsFullReturn(PosReturnMode mode) =>
    mode.linesByItemId.values.every((line) {
      final requested = mode.requestedQty[line.invoiceItemId] ?? 0;
      return (requested - line.availableQty).abs() < 0.001;
    });

/// Distributes product-level base-unit returns in invoice order so duplicate
/// product lines do not each subtract the full historical return.
Map<int, double> distributeReturnedBaseQtyToSaleLines({
  required Iterable<({
    int invoiceItemId,
    int productId,
    double saleQuantity,
    double quantityInBase,
  })> invoiceLines,
  required Map<int, double> returnedBaseByProduct,
}) {
  final remainingBaseByProduct = Map<int, double>.from(returnedBaseByProduct);
  final returnedSaleQtyByLine = <int, double>{};
  for (final line in invoiceLines) {
    final factor = line.quantityInBase > 0 ? line.quantityInBase : 1.0;
    final soldBaseQuantity = line.saleQuantity * factor;
    final returnedBaseQuantity =
        (remainingBaseByProduct[line.productId] ?? 0)
            .clamp(0.0, soldBaseQuantity)
            .toDouble();
    returnedSaleQtyByLine[line.invoiceItemId] =
        returnedBaseQuantity / factor;
    remainingBaseByProduct[line.productId] =
        (remainingBaseByProduct[line.productId] ?? 0) - returnedBaseQuantity;
  }
  return returnedSaleQtyByLine;
}

/// يبحث عن أوّل سطرٍ في [mode] يخصّ [productId] ولا يزال له متاحٌ فوق ما
/// طُلِب منه فعلاً — نقطةُ القرار الخالصة وراء حقل البحث/الباركود في
/// `_QuickReturnLinesEditorDialog`. يرجع `null` حين يكون الصنفُ خارجَ
/// الفاتورة أصلاً (‏`PosReturnMode.canAcceptProduct` ترفضه) أو حين تكون كلُّ
/// أسطره المطابقة قد بلغت سقفَها.
///
/// فاتورةٌ فيها نفسُ الصنف على أكثرَ من سطر: يرجع أوّلَ سطرٍ لسه له مكانٌ —
/// فمسحةٌ متكرّرةٌ لنفس الباركود تملأ الأسطرَ واحداً تلو الآخر بدل أن تتكدّس
/// كلّها على أوّل سطرٍ وترفضَ بلا سببٍ ظاهر بعد استنفاده.
@visibleForTesting
ReturnableLine? findReturnableLineForProduct(PosReturnMode mode, int productId) {
  if (!mode.canAcceptProduct(productId)) return null;
  for (final line in mode.linesByItemId.values) {
    if (line.productId != productId) continue;
    final requested = mode.requestedQty[line.invoiceItemId] ?? 0;
    if (requested < line.availableQty - 0.0005) return line;
  }
  return null;
}

/// يحسب الكميّةَ التاليةَ عند زيادة سطرٍ خطوةً واحدة (‏[step])، **محدودةً
/// بالمتاح فلا تتجاوزه أبداً** — القلبُ الحسابيُّ وراء زرّ «+» وحقلِ
/// البحث/الباركود في `_QuickReturnLinesEditorDialog` (المتطلَّبُ ٥، جولةُ
/// إصلاح ٢). يرجع `null` حين لا مجالَ للزيادة إطلاقاً (‏الكميةُ الحاليّةُ
/// بلغت المتاحَ أصلاً).
///
/// ⚠️ بلا هذا القصّ: سطرٌ متاحُه كسريّ (‏٢٫٥ لصنفٍ موزون) عند `current=2`
/// يطلب `2+1=3` فترفضها `PosReturnMode.setQty` **بلا أثرٍ ولا رسالة** — وهو
/// بالضبط ما كان يحدث قبل هذا الاستخراج.
@visibleForTesting
double? nextIncrementedQty(
  ReturnableLine line,
  double currentQty, {
  double step = 1,
}) {
  final available = line.availableQty;
  if (currentQty >= available - 0.0005) return null;
  return (currentQty + step <= available + 0.0005)
      ? currentQty + step
      : available;
}

/// وضعُ المرتجع يمنع أيَّ مدخلٍ يكتب على سلّة البيع أو يحذف بياناتٍ لا رجعةَ
/// فيها — نقطةُ القرارِ الموحَّدة وراء حرّاس `_handleProductTap`
/// (‏شبكةُ الأصناف)، `_searchBarcode` (‏حقلُ الباركود الرئيسيّ)، و
/// `_showHeldOrders` (‏الفواتيرُ المعلَّقة، جولةُ إصلاح ٢ — مانعٌ ١: استرجاعُ
/// طلبٍ معلَّقٍ يحذفه من القاعدة نهائياً، وحفظُ المرتجع يمحو السلّةَ بعده).
///
/// دالّةٌ واحدةٌ خالصةٌ لثلاثتها كي تفشل معاً وتُصلَح معاً: طفرةٌ على هذا
/// الشرط تُسقِط اختبارَ الثلاثة، لا واحداً ينساه إعادةُ كتابةٍ لاحقة.
@visibleForTesting
bool blocksCartMutation(PosReturnMode? mode) => mode != null;

/// ── فتحُ الدرج عند قبض النقد (قرار 2026-10-30) ───────────────────────────
///
/// القرارُ تابعٌ لـ«قبض نقدٍ» لا لـ«طُبع إيصال»: أمرُ الدرج مهمّةٌ خامٌّ مستقلّة
/// تُرسَل للطابعة الموصول بها الدرج، فيصحّ في الحفظ F2 وفي إطفاء الطباعة.
/// يُفتح عند الإعداد `drawer` مضاءً **و**: دفعٍ نقديٍّ، أو مختلطٍ (`mixed`)
/// جزؤه النقديّ أكبر من صفر. بطاقةٌ/آجلٌ/تحويلٌ خالصٌ لا يفتحه.
@visibleForTesting
bool shouldKickDrawer(
  QuickSalePolicyValues policy, {
  required String method,
  double? cashAmount,
}) {
  if (!policy.isOn(kQuickSaleRows.firstWhere((r) => r.id == 'drawer'))) {
    return false;
  }
  if (method == 'cash') return true;
  return method == 'mixed' && (cashAmount ?? 0) > 0;
}

/// ── الإضافةُ السريعة لصنفٍ غير مسجَّل ─────────────────────────────────────
///
/// بلاغُ مالكٍ (2026-08-17): «ديالوج الإضافة السريعة كان عامله في Ural بس
/// انت مجبتهوش معاك كمنطق عمل». الديالوج نفسُه (`QuickAddProductDialog`)
/// موجودٌ ومكتملٌ من قبل — الناقصُ كان توصيلُه بمسار مسح الباركود في هذه
/// الشاشة (‏`_searchBarcode` تحت)، لا بناءٌ من الصفر.
///
/// دالّةُ قرارٍ خالصةٌ عمداً — نفسُ نمط `blocksCartMutation` فوق — كي تُختبر
/// بلا شجرة ودجت. الشروطُ تطابق `pos_main_operations.dart:380-382` زائدَ
/// حراسةَ وضع المرتجع الخاصّة بهذه الشاشة:
///  1. الباركودُ غيرُ مسجَّلٍ فعلاً (`errorKind == notFound`) — لا صنفٌ
///     معطَّل (`inactive`)، ولا باركودُ ميزانٍ فشل تحليلُه (`invalidScale`،
///     القيد الخامس من بلاغ المالك)، ولا خطأٌ آخر (`general`).
///  2. ليس في وضع مرتجع — `blocksCartMutation` نفسُها التي تحرس
///     `_handleProductTap`/`_showHeldOrders` فوق، فلا يفتح الديالوجُ
///     ويكتب على سلّة بيعٍ أثناء تحرير مرتجع.
@visibleForTesting
bool shouldOfferQuickAdd(PicposBarcodeSearchErrorKind? errorKind, PosReturnMode? mode) =>
    errorKind == PicposBarcodeSearchErrorKind.notFound && !blocksCartMutation(mode);
