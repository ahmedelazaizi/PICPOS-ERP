-- ═══════════════════════════════════════════════════════════════════════════════
-- UralCash ERP — System Data Reset Script (PostgreSQL)
-- ═══════════════════════════════════════════════════════════════════════════════
-- 
-- هذا السكريبت يقوم بتصفير جميع بيانات الحركات والعمليات مع الحفاظ على:
--   ✅ دليل الحسابات (accounts, account_mappings)
--   ✅ الفروع (branches)
--   ✅ المخازن (warehouses)
--   ✅ مراكز التكلفة (cost_centers)
--   ✅ المستخدمين والصلاحيات (users, roles, permissions, role_permissions)
--   ✅ الإعدادات (settings, receipt_settings, printers)
--   ✅ الخزن (safes)
--   ✅ السنوات المالية (fiscal_years, accounting_periods)
--   ✅ ملفات الأنشطة (activity_profiles)
--
-- ⚠️  تحذير: هذا السكريبت لا يمكن التراجع عنه! خذ نسخة احتياطية أولاً
-- ═══════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. تصفير مخزن الترحيل (Sync Outbox)
-- ─────────────────────────────────────────────────────────────────────────────
TRUNCATE TABLE sync_outbox RESTART IDENTITY CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. تصفير المبيعات (Sales)
-- ─────────────────────────────────────────────────────────────────────────────
TRUNCATE TABLE sales_invoice_items RESTART IDENTITY CASCADE;
TRUNCATE TABLE sales_invoices RESTART IDENTITY CASCADE;
TRUNCATE TABLE held_order_items RESTART IDENTITY CASCADE;
TRUNCATE TABLE held_orders RESTART IDENTITY CASCADE;
TRUNCATE TABLE sales_order_items RESTART IDENTITY CASCADE;
TRUNCATE TABLE sales_orders RESTART IDENTITY CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. تصفير المشتريات (Purchases)
-- ─────────────────────────────────────────────────────────────────────────────
TRUNCATE TABLE purchase_invoice_items RESTART IDENTITY CASCADE;
TRUNCATE TABLE purchase_invoices RESTART IDENTITY CASCADE;
TRUNCATE TABLE purchase_order_items RESTART IDENTITY CASCADE;
TRUNCATE TABLE purchase_orders RESTART IDENTITY CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. تصفير عروض الأسعار (Quotations)
-- ─────────────────────────────────────────────────────────────────────────────
TRUNCATE TABLE quotation_items RESTART IDENTITY CASCADE;
TRUNCATE TABLE quotations RESTART IDENTITY CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. تصفير المدفوعات والتخصيصات (Payments)
-- ─────────────────────────────────────────────────────────────────────────────
TRUNCATE TABLE payment_allocations RESTART IDENTITY CASCADE;
TRUNCATE TABLE payments RESTART IDENTITY CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. تصفير الخزينة (Treasury)
-- ─────────────────────────────────────────────────────────────────────────────
TRUNCATE TABLE safe_transactions RESTART IDENTITY CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. تصفير الأوراق التجارية (Commercial Papers)
-- ─────────────────────────────────────────────────────────────────────────────
TRUNCATE TABLE paper_status_history RESTART IDENTITY CASCADE;
TRUNCATE TABLE commercial_papers RESTART IDENTITY CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. تصفير القيود المحاسبية (Journal Entries) - مع الحفاظ على دليل الحسابات
-- ─────────────────────────────────────────────────────────────────────────────
TRUNCATE TABLE journal_entry_lines RESTART IDENTITY CASCADE;
TRUNCATE TABLE journal_entries RESTART IDENTITY CASCADE;

-- إعادة تصفير أرصدة الحسابات
UPDATE accounts SET balance = 0;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. تصفير المخزون (Inventory)
-- ─────────────────────────────────────────────────────────────────────────────
TRUNCATE TABLE stock_movements RESTART IDENTITY CASCADE;
TRUNCATE TABLE inventory_balances RESTART IDENTITY CASCADE;
TRUNCATE TABLE inventory_bond_items RESTART IDENTITY CASCADE;
TRUNCATE TABLE inventory_bonds RESTART IDENTITY CASCADE;
TRUNCATE TABLE stock_audit_items RESTART IDENTITY CASCADE;
TRUNCATE TABLE stock_audits RESTART IDENTITY CASCADE;
TRUNCATE TABLE stock_requisition_items RESTART IDENTITY CASCADE;
TRUNCATE TABLE stock_requisitions RESTART IDENTITY CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. تصفير الأصناف (Products) - مع الحفاظ على الوحدات والتصنيفات
-- ─────────────────────────────────────────────────────────────────────────────
TRUNCATE TABLE warehouse_prices RESTART IDENTITY CASCADE;
TRUNCATE TABLE product_batches RESTART IDENTITY CASCADE;
TRUNCATE TABLE product_barcodes RESTART IDENTITY CASCADE;
TRUNCATE TABLE product_units RESTART IDENTITY CASCADE;
TRUNCATE TABLE products RESTART IDENTITY CASCADE;
-- ملاحظة: التصنيفات (categories) والوحدات (units) لم تُحذف

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. تصفير العملاء/الموردين (Parties)
-- ─────────────────────────────────────────────────────────────────────────────
TRUNCATE TABLE parties RESTART IDENTITY CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. تصفير الورديات (Shifts)
-- ─────────────────────────────────────────────────────────────────────────────
TRUNCATE TABLE shifts RESTART IDENTITY CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 13. تصفير المطبخ والمطعم (Kitchen & Restaurant)
-- ─────────────────────────────────────────────────────────────────────────────
TRUNCATE TABLE table_order_items RESTART IDENTITY CASCADE;
TRUNCATE TABLE table_orders RESTART IDENTITY CASCADE;
TRUNCATE TABLE table_reservations RESTART IDENTITY CASCADE;
TRUNCATE TABLE work_order_items RESTART IDENTITY CASCADE;
TRUNCATE TABLE work_orders RESTART IDENTITY CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 14. تصفير العروض (Offers)
-- ─────────────────────────────────────────────────────────────────────────────
TRUNCATE TABLE offer_items RESTART IDENTITY CASCADE;
TRUNCATE TABLE offers RESTART IDENTITY CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 15. تصفير الفواتير الإلكترونية (E-Invoicing)
-- ─────────────────────────────────────────────────────────────────────────────
TRUNCATE TABLE e_invoice_submissions RESTART IDENTITY CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 16. تصفير سجل النشاط (Activity Log)
-- ─────────────────────────────────────────────────────────────────────────────
TRUNCATE TABLE activity_logs RESTART IDENTITY CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 17. تصفير التصنيع والأصول (Manufacturing & Assets)
-- ─────────────────────────────────────────────────────────────────────────────
TRUNCATE TABLE asset_depreciations RESTART IDENTITY CASCADE;
TRUNCATE TABLE fixed_assets RESTART IDENTITY CASCADE;
TRUNCATE TABLE manufacturing_orders RESTART IDENTITY CASCADE;
TRUNCATE TABLE bom_components RESTART IDENTITY CASCADE;
TRUNCATE TABLE bill_of_materials RESTART IDENTITY CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 18. تصفير التسلسلات (Document Sequences)
-- ─────────────────────────────────────────────────────────────────────────────
-- إعادة تعيين جميع العدادات للتسلسلات
UPDATE document_sequences SET next_value = 1;

-- ─────────────────────────────────────────────────────────────────────────────
-- 19. تصفير أرصدة الخزن
-- ─────────────────────────────────────────────────────────────────────────────
UPDATE safes SET balance = 0;

-- ─────────────────────────────────────────────────────────────────────────────
-- 20. تصفير التقارير المحفوظة
-- ─────────────────────────────────────────────────────────────────────────────
TRUNCATE TABLE saved_report_runs RESTART IDENTITY CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 21. تصفير الموارد البشرية (HR)
-- ─────────────────────────────────────────────────────────────────────────────
TRUNCATE TABLE employee_leaves RESTART IDENTITY CASCADE;
TRUNCATE TABLE salary_payments RESTART IDENTITY CASCADE;
TRUNCATE TABLE employee_attendance RESTART IDENTITY CASCADE;
TRUNCATE TABLE employee_transactions RESTART IDENTITY CASCADE;

-- (delivery tables kept as master data)

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════════
-- ✅ تم التصفير بنجاح
-- 
-- ما تم الحفاظ عليه:
--   • دليل الحسابات (accounts) + ربط الحسابات (account_mappings)
--   • الفروع (branches) + المخازن (warehouses)
--   • مراكز التكلفة (cost_centers)
--   • المستخدمين (users) + الأدوار (roles) + الصلاحيات
--   • الخزن (safes) - تم تصفير الأرصدة
--   • الإعدادات (settings, receipt_settings, printers)
--   • السنوات المالية (fiscal_years, accounting_periods)
--   • التصنيفات (categories) + الوحدات (units)
--   • طاولات المطعم (restaurant_tables, table_sections)
--   • التقارير المخصصة (custom_reports)
--   • العملات (currencies, exchange_rates)
-- ═══════════════════════════════════════════════════════════════════════════════
