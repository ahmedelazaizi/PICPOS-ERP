-- ═══════════════════════════════════════════════════════════════
-- ZERO DATA - حذف بيانات الفواتير والحركات مع الحفاظ على البيانات الأساسية
-- (العملاء والموردين والأصناف والتصنيفات والمستخدمين والإعدادات)
-- ═══════════════════════════════════════════════════════════════
-- تنبيه: هذا السكربت يحذف جميع الفواتير والمعاملات المالية!
-- يجب عمل نسخة احتياطية قبل التنفيذ
-- ═══════════════════════════════════════════════════════════════

-- ===== 1. حذف بنود الفواتير أولاً (بسبب المفاتيح الأجنبية) =====
DELETE FROM sales_invoice_items;
DELETE FROM purchase_invoice_items;

-- ===== 2. حذف الفواتير =====
DELETE FROM sales_invoices;
DELETE FROM purchase_invoices;

-- ===== 3. حذف الطلبات المعلقة =====
DELETE FROM held_order_items;
DELETE FROM held_orders;

-- ===== 4. حذف طلبات المطاعم =====
DELETE FROM table_order_items;
DELETE FROM table_orders;

-- ===== 5. حذف أوامر التشغيل (المطبخ) =====
DELETE FROM work_order_items;
DELETE FROM work_orders;

-- ===== 6. حذف حركات المخزون والجرد =====
DELETE FROM stock_movements;
DELETE FROM inventory_balances;
DELETE FROM stock_audit_items;
DELETE FROM stock_audits;
DELETE FROM product_batches;

-- ===== 7. حذف حركات الخزينة =====
DELETE FROM safe_transactions;

-- ===== 8. حذف القيود المحاسبية =====
DELETE FROM journal_entry_lines;
DELETE FROM journal_entries;

-- ===== 9. حذف سجل العمليات =====
DELETE FROM activity_logs;

-- ===== 10. حذف حركات الموظفين (سلف وخصومات) =====
DELETE FROM employee_transactions;
DELETE FROM salary_payments;

-- ===== 11. إعادة ترقيم الفواتير من 1 =====
DELETE FROM sqlite_sequence WHERE name = 'sales_invoices';
DELETE FROM sqlite_sequence WHERE name = 'sales_invoice_items';
DELETE FROM sqlite_sequence WHERE name = 'purchase_invoices';
DELETE FROM sqlite_sequence WHERE name = 'purchase_invoice_items';
DELETE FROM sqlite_sequence WHERE name = 'held_orders';
DELETE FROM sqlite_sequence WHERE name = 'held_order_items';
DELETE FROM sqlite_sequence WHERE name = 'table_orders';
DELETE FROM sqlite_sequence WHERE name = 'table_order_items';
DELETE FROM sqlite_sequence WHERE name = 'work_orders';
DELETE FROM sqlite_sequence WHERE name = 'work_order_items';
DELETE FROM sqlite_sequence WHERE name = 'stock_movements';
DELETE FROM sqlite_sequence WHERE name = 'inventory_balances';
DELETE FROM sqlite_sequence WHERE name = 'stock_audits';
DELETE FROM sqlite_sequence WHERE name = 'stock_audit_items';
DELETE FROM sqlite_sequence WHERE name = 'safe_transactions';
DELETE FROM sqlite_sequence WHERE name = 'journal_entries';
DELETE FROM sqlite_sequence WHERE name = 'journal_entry_lines';
DELETE FROM sqlite_sequence WHERE name = 'activity_logs';
DELETE FROM sqlite_sequence WHERE name = 'product_batches';
DELETE FROM sqlite_sequence WHERE name = 'employee_transactions';
DELETE FROM sqlite_sequence WHERE name = 'salary_payments';

-- ===== 12. إعادة تعيين رصيد الخزينة =====
UPDATE safes SET balance = 0;

-- ===== 13. إعادة تعيين أرصدة الحسابات المحاسبية =====
UPDATE accounts SET balance = 0;

-- ═══════════════════════════════════════════════════════════════
-- ✅ تم! البيانات الأساسية (أصناف، عملاء، موردين، مستخدمين، إعدادات) لم تتأثر
-- ✅ ترقيم الفواتير يبدأ من 1 
-- ═══════════════════════════════════════════════════════════════
