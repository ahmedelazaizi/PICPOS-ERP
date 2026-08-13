// صلاحياتُ تعديل السلة — نقطةٌ واحدةٌ يشترك فيها مسارا التعديل.
//
// ── لماذا ملفٌّ مستقلّ ─────────────────────────────────────────────────────
// لتعديل الكمية والسعر **مساران** في شاشة PicPos: حوارُ «تعديل الصنف» في
// `picpos_pos_operations.dart`، والتعديلُ المباشرُ في خلايا
// `picpos_items_table.dart`. والملفّان مكتبتان مختلفتان (‏`part of` جذور
// مختلفة) فلا يرى أحدُهما دوالَّ الآخر.
//
// وحراسةُ أحدِ المسارين وحدَه تترك البابَ الآخرَ مفتوحاً — وهو **بعينه** ما
// جعل الحراسةَ القائمة في `pos/widgets/` بلا أثرٍ في PicPos: الحراسةُ كانت
// موجودةً في مسارٍ لا يُسلَك. فالمشتركُ هنا كي لا يفترق الطرفان بأوّل تعديل.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// بلاغٌ ميدانيّ (2026-08-11): «رفعتُ التحديد عن حذف صنف من السلة، ودخلتُ
// بالكاشير، فحذف الصنفَ ولم يظهر حوارُ كلمة المرور» — لم يكن تجاوزاً
// للصلاحية بل **غيابُ نقطةِ فحصٍ من الأساس**.
//
// واختيارُ المالك (2026-08-12): حوارُ كلمة المرور على **كلّ** رفض، لا على
// المالية الحرجة وحدَها. و`requestManagerApproval` يشترط أن المسؤولَ الموافقَ
// يملك الصلاحيةَ بنفسه، ويمنح إذناً وحيدَ الاستعمال لا يُصعّد الجلسة.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../data/providers/auth_providers.dart';
import '../../../services/manager_approval_cache.dart';
import '../../widgets/permission_guard.dart';

bool _isAdmin(List<String> p) =>
    p.contains('system_admin') || p.contains('*');

/// تعديلُ كميةِ صنفٍ في السلة (`pos_quantity_edit`).
bool canEditCartQuantityCodes(List<String> permissions) =>
    _isAdmin(permissions) ||
    permissions.contains(PermissionCodes.posQuantityEdit);

/// تعديلُ سعر صنفٍ في البيع (`pos_price_edit`).
bool canEditCartPriceCodes(List<String> permissions) =>
    _isAdmin(permissions) || permissions.contains(PermissionCodes.posPriceEdit);

Future<bool> _ensure(
  WidgetRef ref,
  BuildContext context,
  bool Function(List<String>) can,
  String permission,
  String actionName,
) async {
  // ⚠️ استهلاكُ موافقةٍ سابقةٍ **قبل** أيّ سؤال — وإلا سأل مرّتين.
  //
  // منذ صار الحقلُ يستأذن **قبل** الكتابة (‏«إظهارٌ وإخفاء»، طلبُ المالك
  // 2026-08-12) صار للفعل الواحد بوّابتان: لمسةُ الخانة، ثم `onSubmitted`
  // بعد إدخال الرقم. وبلا الاستهلاك هنا كان المسؤولُ يكتب كلمةَ السرّ
  // مرّتين لتعديلٍ واحد — وهو بعينه العطبُ الذي وُجدت له هذه الذاكرةُ في
  // `_userHasPermissionFresh`. والموافقةُ تبقى وحيدةَ الاستعمال وعمرُها ٦٠
  // ثانية، فلا تُصعّد الجلسة.
  if (ManagerApprovalCache.instance.consume(permission)) return true;
  final perms =
      ref.read(currentUserPermissionsProvider).asData?.value ?? const <String>[];
  if (can(perms)) return true;
  if (!context.mounted) return false;
  return requestManagerApproval(
    context,
    actionName: actionName,
    permission: permission,
  );
}

/// يسمح بتعديل الكمية، أو يطلب موافقةَ مسؤولٍ يملكها.
Future<bool> ensureCartQuantityPermission(
  WidgetRef ref,
  BuildContext context,
) =>
    _ensure(ref, context, canEditCartQuantityCodes,
        PermissionCodes.posQuantityEdit, 'تعديل الكمية');

/// يسمح بتعديل السعر، أو يطلب موافقةَ مسؤولٍ يملكها.
Future<bool> ensureCartPricePermission(
  WidgetRef ref,
  BuildContext context,
) =>
    _ensure(ref, context, canEditCartPriceCodes, PermissionCodes.posPriceEdit,
        'تعديل سعر الصنف');

// ── دفعة ٢: ما يمسّ المال ──────────────────────────────────────────────────

/// فتحُ درج النقدية **يدوياً** (`pos_open_drawer`).
///
/// ⚠️ الفتحُ اليدويُّ وحدَه. والركلةُ التلقائيةُ بعد البيع مسارٌ آخر
/// (`_openCashDrawerQuietly`) **لا يُحرَس عن قصد**: هي جزءٌ من إتمام بيعةٍ
/// مأذونةٍ سلفاً، وحراستُها كانت ستوقف الكاشيرَ في منتصف كلّ فاتورة.
///
/// والفتحُ اليدويُّ هو الذي يفتح الدرجَ **بلا بيعة** — وهو ما يُراقَب.
bool canOpenCashDrawerCodes(List<String> permissions) =>
    _isAdmin(permissions) ||
    permissions.contains(PermissionCodes.posOpenDrawer);

/// تغييرُ حالة الضريبة على الفاتورة (`pos_tax_toggle`).
///
/// يغيّر إجماليَّ ما يدفعه العميلُ وما يُرحَّل ضريبةً في الدفاتر.
bool canToggleTaxCodes(List<String> permissions) =>
    _isAdmin(permissions) || permissions.contains(PermissionCodes.posTaxToggle);

/// يسمح بفتح الدرج يدوياً، أو يطلب موافقةَ مسؤولٍ يملكها.
Future<bool> ensureOpenCashDrawerPermission(
  WidgetRef ref,
  BuildContext context,
) =>
    _ensure(ref, context, canOpenCashDrawerCodes,
        PermissionCodes.posOpenDrawer, 'فتح درج النقدية');

/// يسمح بتغيير حالة الضريبة، أو يطلب موافقةَ مسؤولٍ يملكها.
Future<bool> ensureTaxTogglePermission(
  WidgetRef ref,
  BuildContext context,
) =>
    _ensure(ref, context, canToggleTaxCodes, PermissionCodes.posTaxToggle,
        'تغيير حالة الضريبة');

// ── دفعة ٣ ────────────────────────────────────────────────────────────────

/// اختيارُ عميلٍ للفاتورة (`pos_customer_select`).
bool canSelectCustomerCodes(List<String> permissions) =>
    _isAdmin(permissions) ||
    permissions.contains(PermissionCodes.posCustomerSelect);

/// عرضُ الفواتير السابقة (`pos_previous_invoices`).
///
/// ليست عرضاً بريئاً: تكشف مبيعاتِ الورديات الأخرى وأسعارَها وعملاءَها.
bool canViewPreviousInvoicesCodes(List<String> permissions) =>
    _isAdmin(permissions) ||
    permissions.contains(PermissionCodes.posPreviousInvoices);

/// يسمح باختيار عميل، أو يطلب موافقةَ مسؤولٍ يملكها.
Future<bool> ensureSelectCustomerPermission(
  WidgetRef ref,
  BuildContext context,
) =>
    _ensure(ref, context, canSelectCustomerCodes,
        PermissionCodes.posCustomerSelect, 'اختيار عميل للفاتورة');

/// يسمح بعرض الفواتير السابقة، أو يطلب موافقةَ مسؤولٍ يملكها.
Future<bool> ensurePreviousInvoicesPermission(
  WidgetRef ref,
  BuildContext context,
) =>
    _ensure(ref, context, canViewPreviousInvoicesCodes,
        PermissionCodes.posPreviousInvoices, 'عرض الفواتير السابقة');

// ── دفعة ٤ (2026-08-13) — ثقوبٌ كشفها الحارسُ بعد أن صار محافظاً ──────────
//
// الثلاثةُ كانت محروسةً في النظير القديم وحدَه (`pos/widgets/cart_view.dart`
// و`pos_header.dart` و`cart/cart_totals_panel.dart`) — ملفاتٌ لا تبلغها شاشةُ
// PicPos. ولم يكشفها الحارسُ البنيويُّ لأنه كان يَعُدّ **أيَّ ذكرٍ** للكود في
// `lib/` إنفاذاً واصلاً: `pos_discount` أسكتَه لونٌ اسمُه `AppColors.
// posDiscount`، و`pos_hold_order` أسكتَه `api_sales_handler.dart` (سطحُ HTTP
// لا شاشة) وقائمةُ منحٍ في `migrations/epoch_3.dart`.

/// خصمٌ على صنفٍ أو على الفاتورة (`pos_discount`).
///
/// ⚠️ ثلاثةُ أبوابٍ لنفس الفعل، وكلُّها كانت مفتوحة: خليةُ «الخصم ٪» في
/// `picpos_items_table.dart`، وفرعُ الخصم في حوار «تعديل الصنف»، وخصمُ
/// الفاتورة كلِّها. حراسةُ بابٍ وترك الآخرَين هي بعينها علّةُ البلاغ الأصليّ.
bool canApplyDiscountCodes(List<String> permissions) =>
    _isAdmin(permissions) || permissions.contains(PermissionCodes.posDiscount);

/// تعليقُ الفاتورة للاسترجاع لاحقاً (`pos_hold_order`).
bool canHoldOrderCodes(List<String> permissions) =>
    _isAdmin(permissions) || permissions.contains(PermissionCodes.posHoldOrder);

/// فتحُ لوح المصاريف السريعة (`pos_expense`).
///
/// ليس عرضاً بريئاً: الحوارُ فيه زرُّ «إضافة مصروف» ⇒ مالٌ يخرج من الدرج.
bool canAddExpenseCodes(List<String> permissions) =>
    _isAdmin(permissions) || permissions.contains(PermissionCodes.posExpense);

/// يسمح بتطبيق خصم، أو يطلب موافقةَ مسؤولٍ يملكها.
Future<bool> ensureCartDiscountPermission(
  WidgetRef ref,
  BuildContext context,
) =>
    _ensure(ref, context, canApplyDiscountCodes, PermissionCodes.posDiscount,
        'تطبيق خصم');

/// يسمح بتعليق الفاتورة، أو يطلب موافقةَ مسؤولٍ يملكها.
Future<bool> ensureHoldOrderPermission(
  WidgetRef ref,
  BuildContext context,
) =>
    _ensure(ref, context, canHoldOrderCodes, PermissionCodes.posHoldOrder,
        'تعليق الفاتورة');

/// يسمح بفتح لوح المصاريف، أو يطلب موافقةَ مسؤولٍ يملكها.
Future<bool> ensureAddExpensePermission(
  WidgetRef ref,
  BuildContext context,
) =>
    _ensure(ref, context, canAddExpenseCodes, PermissionCodes.posExpense,
        'المصاريف السريعة');

/// وسمُ الفاتورة طلبَ توصيل (`pos_delivery`).
///
/// قرارُ المالك 2026-08-13: شريحةُ «توصيل» في لوحة الدفع هي ميزةُ التوصيل في
/// PicPos، فتُحرَس. وليست وسماً بريئاً — تغيّر مسارَ التحصيل ورسومَ التوصيل.
bool canSetDeliveryOrderCodes(List<String> permissions) =>
    _isAdmin(permissions) || permissions.contains(PermissionCodes.posDelivery);

/// يسمح بوسم الفاتورة توصيلاً، أو يطلب موافقةَ مسؤولٍ يملكها.
Future<bool> ensureDeliveryPermission(
  WidgetRef ref,
  BuildContext context,
) =>
    _ensure(ref, context, canSetDeliveryOrderCodes, PermissionCodes.posDelivery,
        'طلب توصيل');
