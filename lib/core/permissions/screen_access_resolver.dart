// lib/core/permissions/screen_access_resolver.dart
//
// قاعدةُ «فتحِ الشاشة» — موضعٌ واحدٌ تقرؤه القائمةُ الجانبيّة ومزوِّدُ الشاشات
// المسموحة وقائمةُ «الشاشة الافتراضية».
//
// ── القاعدة (قرارُ المالك 2026-10-18، F.2) ─────────────────────────────────
//   canOpenScreen = تجاوزُ مدير النظام  ||  أيُّ كودٍ من مجموعة الشاشة.
//
// مجموعةُ الشاشة = كودُها في `screenPermissionMap` (يبقى حرفيّاً في
// `auth_providers.dart` لأنّ حرّاساً بنيويّةً تقرؤه بـregex) ∪ أكوادُ أفعالها
// في [screenActionCodes] أدناه. فمن أُسندت إليه «تعديل صنف» فقط **يرى**
// شاشةَ الأصناف ليتابع عملَه، لكنّ كلَّ زرٍّ داخلَها يبقى محكوماً بكوده هو.
//
// ── ما لا تفعله هذه القاعدة ─────────────────────────────────────────────────
// لا تمنح قراءةً ولا فعلاً: الأعمدةُ الحسّاسةُ (`products_cost_view`…)،
// ونطاقُ الفرع (`user_branch_access`)، والصلاحيّةُ المشروطةُ (`cond:<code>` ⇒
// موافقةُ مدير)، وسقفُ الخصم لكلّ مستخدم — كلُّها تُفحَص عند الفعل، وهذا
// الملفُّ لا يمسّها.
//
// ── الاستثناءات ─────────────────────────────────────────────────────────────
// [strictPermissionScreens]: الإعداداتُ والمستخدمون والأدوارُ تبقى على كودها
// الوحيد (F.2) — فتحُها بكود فعلٍ فرعيٍّ كان سيكشف أسطحَ إدارةٍ كاملة.
//
// ⚠️ هذا الملفُّ **ملفُّ تعريف** لا موضعُ إنفاذ: كلُّ كودٍ مذكورٌ هنا بالحرف
// ويُعدّ في `permission_enforcement_coverage_test` من ملفات التعريف، فلا
// يُحتسب ذكرُه إنفاذاً لزرٍّ.
import 'package:ural_erp/core/navigation/screen_id.dart';

import 'permission_codes.dart';

/// شاشاتٌ تبقى على كودها الوحيد (قرارُ المالك F.2).
const strictPermissionScreens = <ScreenId>{
  ScreenId.settings,
  ScreenId.users,
  ScreenId.rolesAndPermissions,
};

/// أكوادُ **الأفعال** الإضافيّة التي تفتح كلَّ شاشة (فوق كودها في
/// `screenPermissionMap`). كلُّ كودٍ لا بدّ أن يكون في `masterList`
/// (يقيسه `screen_access_resolver_test`).
///
/// ⚠️ مقصودٌ ألّا تدخل هنا: الأكوادُ `nonToggleable` (لا تفعل شيئاً)،
/// وأكوادُ تقييد العرض (`*_cost_view`/`*_price_view`/`*_stock_view`) لأنّها
/// تُخفي أعمدةً لا تعمل عملاً، والأكوادُ الحرجةُ ماليّاً.
const screenActionCodes = <ScreenId, List<String>>{
  ScreenId.offers: [
    'offers_view',
    'offers_create',
    'offers_edit',
    'offers_delete',
  ],
  ScreenId.tables: [
    'tables_view',
    'tables_manage',
    'tables_pos_access',
    'tables_add_items',
    'tables_checkout',
    'tables_transfer',
    'tables_cancel',
    'tables_print_bill',
    'tables_discount',
    'tables_merge',
    'tables_split_bill',
    'tables_reserve',
  ],
  ScreenId.bookings: [
    'bookings_view',
    'bookings_add',
    'bookings_edit',
    'bookings_cancel',
    'bookings_status',
    'bookings_assign',
    'bookings_deposit',
    'bookings_services_manage',
    'bookings_resources_manage',
    'bookings_reports',
    'bookings_settings',
  ],
  ScreenId.products: [
    'products_add',
    'products_edit',
    'products_delete',
    'products_import',
    'products_export',
    'products_barcode',
    'products_units',
  ],
  ScreenId.categories: [
    'categories_add',
    'categories_edit',
    'categories_delete',
  ],
  ScreenId.customers: [
    'customers_view',
    'customers_add',
    'customers_edit',
    'customers_delete',
    'customer_message_send',
  ],
  ScreenId.parties: [
    'customers_view',
    'customers_add',
    'customers_edit',
    'customers_delete',
  ],
  ScreenId.suppliers: [
    'suppliers_add',
    'suppliers_edit',
    'suppliers_delete',
  ],
  ScreenId.salesInvoices: [
    'sales_view',
    'sales_create',
    'sales_edit',
    'sales_delete',
    'sales_print',
  ],
  ScreenId.salesReturns: [
    'sales_return_view',
    'sales_return_create',
    'sales_return_delete',
    'sales_return_approve',
    'sales_return_print',
  ],
  ScreenId.purchases: [
    'purchases_create',
    'purchases_edit',
    'purchases_delete',
    'purchases_print',
  ],
  ScreenId.purchaseReturns: [
    'purchases_return_view',
    'purchases_return_create',
    'purchases_return_edit',
    'purchases_return_approve',
    'purchases_return_print',
  ],
  ScreenId.inventory: ['inventory_view', 'inventory_edit'],
  ScreenId.kitchen: ['kitchen_view', 'kitchen_manage'],
  ScreenId.loyalty: ['loyalty_view', 'loyalty_manage'],
  ScreenId.distribution: ['distribution_view', 'distribution_manage'],
  ScreenId.manufacturing: ['manufacturing_view', 'manufacturing_manage'],
  ScreenId.fixedAssets: [
    'assets_view',
    'assets_manage',
    'assets_depreciation',
  ],
  ScreenId.eInvoice: ['einvoice_view', 'einvoice_submit', 'einvoice_cancel'],
};

/// مجموعةُ الأكواد التي يفتح أيٌّ منها الشاشةَ [id].
///
/// [primaryCode] هو كودُها في `screenPermissionMap` (يُمرَّر لأنّ الخريطة
/// تعيش في طبقة المزوّدات، وهذا الملفُّ في `core` فلا يستورد منها).
Set<String> screenPermissionSet(ScreenId id, String? primaryCode) => {
      ?primaryCode,
      if (!strictPermissionScreens.contains(id))
        ...?screenActionCodes[id],
    };

/// هل يفتح المستخدمُ ذو [permissions] الشاشةَ [id]؟
///
/// - [bypass]: تجاوزُ مدير النظام (`hasSystemAdminBypass`).
/// - [primaryCode]: كودُ الشاشة في `screenPermissionMap`؛ `null` ⇒ شاشةٌ
///   بلا بوّابة (مفتوحةٌ).
/// - [strict]: يعيد السلوكَ القديمَ (كودٌ واحدٌ بالضبط) — مخرجُ تراجعٍ.
///
/// الصلاحيةُ **المشروطةُ** (`grant_mode=conditional`) صفُّها موجودٌ في
/// القائمة فتفتح الشاشة؛ والموافقةُ تُطلَب عند الفعل لا عند الفتح.
bool canOpenScreen(
  Iterable<String> permissions,
  ScreenId id, {
  required String? primaryCode,
  required bool bypass,
  bool strict = false,
}) {
  if (bypass) return true;
  if (primaryCode == null) return true;
  final held = permissions is Set<String> ? permissions : permissions.toSet();
  if (strict) return held.contains(primaryCode);
  return screenPermissionSet(id, primaryCode).any(held.contains);
}

/// هل [code] ممنوحٌ **مشروطاً** (يحتاج موافقةَ مدير عند الفعل)؟
bool isConditional(Iterable<String> permissions, String code) =>
    PermissionCodes.isConditionalIn(permissions.toList(), code);
