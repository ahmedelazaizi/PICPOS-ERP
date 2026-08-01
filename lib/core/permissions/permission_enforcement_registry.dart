// lib/core/permissions/permission_enforcement_registry.dart
//
// الأكواد اللي معروفة إنها لسه محتاجة إنفاذ حقيقي في التطبيق.
//
// ── ليه الملف ده موجود ────────────────────────────────────────────────────
// سويب على `lib/` كله (2026-08-01) طلّع ٨٨ كود من ٢١٩ بصفر مراجع خارج
// السجل والسيدر والمصفوفة والكتالوج. وشاشة الصلاحيات بتعرض الـ٢١٩ كلهم من
// قاعدة البيانات مباشرة — فالمدير بيقلّب ٤٠٪ من المفاتيح على الفاضي. ده كان
// بلاغ «بغيّر صلاحية ومش بيحصل حاجة».
//
// نفس الـ٨٨ موجودين في UralCash بالحرف (٨٩ هناك، الزيادة `pos_edit_invoice`)
// — مشكلة محرك مشتركة، مش انحراف في براند.
//
// ── ٣٣ كود اتنقلوا لـ`PermissionCodes.nonToggleable` (Task 5, 2026-08-01) ──
// من الـ٨٠ اللي كانت هنا (٨٨ ناقص ٨ اتحلّوا بإعادة توصيل screenPermissionMap
// قبل كده)، تريّاج فصّل الباقي: ٣٣ كود يستحيل حلّهم بإضافة إنفاذ — إما
// محميين فعلاً بكود/آلية تانية، أو الميزة مش موجودة أصلاً، أو أثر داخلي جوه
// عملية تانية. دول اتوثّقوا بسبب كل واحد فيهم في `PermissionCodes.
// nonToggleable` واتشالوا من هنا عشان الـ٤٧ الباقيين هنا يبقوا مقياس تقدّم
// حقيقي — مش قايمة فيها أكواد مستحيل تتصلّح أصلاً.
//
// القايمة دي **بتتقلّص وما تكبرش**. `permission_enforcement_coverage_test`
// بيفشل لو كود جديد اتضاف لـ`masterList` من غير إنفاذ، ومن غير ما يتكتب هنا
// أو في `PermissionCodes.nonToggleable` بسبب صريح.
class PermissionEnforcementRegistry {
  PermissionEnforcementRegistry._();

  static const Set<String> knownUnenforced = {
    // ── نقطة البيع (دفعة ٥) ──
    'pos_work_order', 'pos_expense_description',
    'pos_customer_add', 'pos_note_add',
    'pos_weight_dialog', 'pos_grid_toggle', 'pos_notifications',
    'pos_low_stock_alert',
    // ── لوحة التحكم (دفعة ٦) ──
    // 'dashboard_access' اتشال — بقى منفَّذ فعلياً بعد إعادة توصيل
    // screenPermissionMap في auth_providers.dart (4a032a22 وما بعدها).
    'dashboard_sales_today', 'dashboard_sales_total',
    'dashboard_chart', 'dashboard_alerts',
    // ── الأصناف والتصنيفات (دفعة ٧) ──
    'products_image', 'products_expiry', 'products_lock',
    'products_price_view', 'products_cost_view', 'products_stock_view',
    // ── المستندات: طباعة/تعديل/حذف (دفعة ٨) ──
    // 'purchases_return_view' و'sales_return_view' اتشالوا — بقوا منفَّذين
    // فعلياً بعد إعادة توصيل screenPermissionMap (4a032a22 وما بعدها).
    'purchases_print',
    'purchases_return_print', 'sales_print',
    'sales_amounts_view',
    'sales_return_delete', 'sales_return_print',
    // ── العروض والتوصيل والطاولات والمطبخ (دفعة ٩) ──
    // 'offers_view' و'tables_view' و'kitchen_view' اتشالوا — بقوا منفَّذين
    // فعلياً بعد إعادة توصيل screenPermissionMap (4a032a22 وما بعدها).
    'offers_create', 'offers_edit', 'offers_delete',
    'tables_manage',
    'kitchen_manage',
    // ── التقارير (دفعة ١٠) ──
    'reports_export', 'reports_suppliers', 'reports_delivery_recon',
    // ── الإعدادات والنظام (دفعة ١١) ──
    'settings_company',
    'settings_tax', 'settings_currency', 'settings_pos_edit',
    'system_database', 'system_license',
    // ── وحدات فرعية (دفعة ١٢) ──
    // 'manufacturing_view' و'assets_view' اتشالوا — بقوا منفَّذين فعلياً
    // بعد إعادة توصيل screenPermissionMap (4a032a22 وما بعدها).
    'loyalty_manage', 'distribution_manage', 'einvoice_submit',
    'einvoice_cancel', 'manufacturing_manage',
    'assets_manage', 'assets_depreciation',
    'modifiers_manage',
    // ── حرجة ماليّاً — أولوية أمنية (دفعة ١٣) ──
    'modify_closed_period',
  };
}
