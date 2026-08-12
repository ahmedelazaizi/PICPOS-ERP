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
