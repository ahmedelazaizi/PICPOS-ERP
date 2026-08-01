// lib/core/permissions/permission_enforcement_registry.dart
//
// الأكواد اللي معروفة إنها لسه بلا نقطة إنفاذ في التطبيق.
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
// القايمة دي **بتتقلّص وما تكبرش**. `permission_enforcement_coverage_test`
// بيفشل لو كود جديد اتضاف لـ`masterList` من غير إنفاذ ومن غير ما يتكتب هنا
// بسبب صريح.
class PermissionEnforcementRegistry {
  PermissionEnforcementRegistry._();

  static const Set<String> knownUnenforced = {
    // ── نقطة البيع (دفعة ٥) ──
    'pos_work_order', 'pos_expense_description', 'pos_daily_closing',
    'pos_cancel_invoice', 'pos_payment_methods', 'pos_split_payment',
    'pos_customer_add', 'pos_view_cost', 'pos_view_profit', 'pos_note_add',
    'pos_weight_dialog', 'pos_grid_toggle', 'pos_notifications',
    'pos_low_stock_alert',
    // ── لوحة التحكم (دفعة ٦) ──
    // 'dashboard_access' اتشال — بقى منفَّذ فعلياً بعد إعادة توصيل
    // screenPermissionMap في auth_providers.dart (4a032a22 وما بعدها).
    'dashboard_sales_today', 'dashboard_sales_total',
    'dashboard_customers', 'dashboard_chart', 'dashboard_top_products',
    'dashboard_alerts', 'dashboard_pending_orders',
    // ── الأصناف والتصنيفات (دفعة ٧) ──
    'products_image', 'products_expiry', 'products_lock',
    'products_price_view', 'products_cost_view', 'products_stock_view',
    'products_scale_upload', 'categories_view', 'categories_scale_upload',
    // ── المستندات: طباعة/تعديل/حذف (دفعة ٨) ──
    // 'purchases_return_view' و'sales_return_view' اتشالوا — بقوا منفَّذين
    // فعلياً بعد إعادة توصيل screenPermissionMap (4a032a22 وما بعدها).
    // 'suppliers_view' لسه من غيرهم بلا إنفاذ حقيقي رغم التشابه الاسمي.
    'suppliers_view', 'purchases_print',
    'purchases_return_delete', 'purchases_return_print', 'sales_print',
    'sales_amounts_view', 'sales_return_edit',
    'sales_return_delete', 'sales_return_print',
    // ── العروض والتوصيل والطاولات والمطبخ (دفعة ٩) ──
    // 'offers_view' و'tables_view' و'kitchen_view' اتشالوا — بقوا منفَّذين
    // فعلياً بعد إعادة توصيل screenPermissionMap (4a032a22 وما بعدها).
    'offers_create', 'offers_edit', 'offers_delete',
    'delivery_view', 'tables_manage', 'tables_print_bill',
    'kitchen_manage', 'treasury_transactions_view',
    // ── التقارير (دفعة ١٠) ──
    'reports_export', 'reports_purchases', 'reports_inventory',
    'reports_customers', 'reports_suppliers', 'reports_profit',
    'reports_products', 'reports_shifts', 'reports_delivery_recon',
    // ── الإعدادات والنظام (دفعة ١١) ──
    'settings_company', 'settings_receipt', 'settings_restore',
    'settings_tax', 'settings_currency', 'settings_pos_edit',
    'system_audit_log', 'system_database', 'system_license',
    'system_updates',
    // ── وحدات فرعية (دفعة ١٢) ──
    // 'manufacturing_view' و'assets_view' اتشالوا — بقوا منفَّذين فعلياً
    // بعد إعادة توصيل screenPermissionMap (4a032a22 وما بعدها).
    'loyalty_manage', 'distribution_manage', 'einvoice_submit',
    'einvoice_cancel', 'manufacturing_manage',
    'assets_manage', 'assets_depreciation',
    'modifiers_manage',
    // ── حرجة ماليّاً — أولوية أمنية (دفعة ١٣) ──
    'audit_shift_blind', 'audit_invoice_unlock',
    'parties_credit_limit_bypass', 'delete_posted_journal',
    'delete_fiscal_year', 'modify_closed_period',
  };
}
