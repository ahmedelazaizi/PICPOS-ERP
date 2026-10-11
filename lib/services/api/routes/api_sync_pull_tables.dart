// ApiHandler - delta-pull allowlists (tables, branch columns, transactional set).
part of '../api_handler.dart';

/// Static allowlists used by [ApiHandlerSyncPull]. Kept as static const so
/// source-grep guards keep finding them by name.
extension ApiHandlerSyncPullTables on ApiHandler {
  /// Allowlist of tables a client can pull via `/api/sync/pull`.
  /// Must match [DeltaPullService.pullTables] on the client. High-volume
  /// transaction tables are intentionally excluded — they flow via the
  /// client's outbox, not delta pull.
  /// Allowlist of tables a client can pull via `/api/sync/pull`.
  /// Mirrors [DeltaPullService.pullTables] on the client (a list, because the
  /// client pulls in FK-dependency order; here a set, because we only
  /// validate membership). All 40 sync-hardened tables — transactional data
  /// flows via delta pull as well, so a long-offline client can catch up
  /// without a full dump.
  static const _syncPullTables = <String>{
    // Tier 0
    'fiscal_years', 'cost_centers', 'accounts', 'roles', 'currencies',
    'categories', 'units', 'regions', 'party_groups', 'safes',
    // Tier 1
    'accounting_periods', 'branches', 'warehouses', 'price_lists',
    'users', 'shifts',
    // v175 / المرحلة ٦ — دفترُ الشيكات. يقابل الإدراجَ نفسَه في
    // [DeltaPullService.pullTables]؛ بدونه لا يسلّم الخادمُ صفوفَه فيفتح
    // الجهازُ الثاني دفتراً بنفس المدى.
    'cheque_books',
    // v176 / 2026-09-21 — الإضافاتُ والخيارات. يقابل الإدراجَ نفسَه في
    // [DeltaPullService.pullTables]؛ بدونه لا يسلّم الخادمُ صفوفَها
    // فيبقى منتقي الكاشير فارغاً مهما عرّف المديرُ.
    'modifier_groups', 'modifier_items', 'product_modifier_groups',
    // Tier 2
    'parties', 'products', 'price_list_items', 'product_barcodes',
    'product_units',
    // Tier 3 — transactional headers
    'sales_invoices', 'purchase_invoices', 'held_orders',
    'sales_orders', 'purchase_orders', 'quotations', 'payments',
    'journal_entries', 'safe_transactions', 'commercial_papers',
    'stock_movements',
    'voucher_books', 'voucher_book_leaves_cancelled', // v184
    // Tier 4 — transactional items
    'sales_invoice_items', 'purchase_invoice_items', 'held_order_items',
    'sales_order_items', 'purchase_order_items', 'quotation_items',
    'payment_allocations',
    // Tier 5 — v166 / المرحلة ٢: مستنداتُ الأثر المحاسبيّ.
    // تقابل الكتلةَ نفسَها في [DeltaPullService.pullTables]؛ هنا مجموعةٌ
    // فالترتيبُ لا يعني شيئاً، والقائمةُ هناك مرتّبةٌ بالمفاتيح.
    'asset_categories', 'op_expense_categories', 'bill_of_materials',
    'fixed_assets', 'manufacturing_orders', 'bom_components',
    ...manufacturingV180SyncTables,
    'op_expenses', 'asset_depreciations', 'mfg_order_costs',
    'landed_cost_sheets', 'landed_cost_items', 'landed_cost_allocations',
    // v175 / المرحلة ٧ — طلبُ استبعاد أصل. يقابل الإدراجَ نفسَه في
    // [DeltaPullService.pullTables].
    'asset_disposals',
    // v174 / المرحلة ٨ — وسمُ الاستيراد. يقابل الإدراجَ نفسَه في
    // [DeltaPullService.pullTables]؛ بدونه لا يسلّم الخادمُ صفوفَه فتظهر
    // فاتورةُ الاستيراد محلّيّةً على كلّ جهازٍ لم يُنشئها.
    'import_purchase_details',
    // §٦‑٢ (v172) — مستندُ مرتجع الشراء. يقابل الإدراجَ نفسَه في
    // [DeltaPullService.pullTables]؛ بدونه لا يسلّم الخادمُ صفوفَه فتُقارن
    // تسويةُ ض.ق.م على العميل أستاذاً كاملاً بمستنداتٍ ناقصة.
    'purchase_returns',
    // Tier 6 — v167 / المرحلة ٣: الفئةُ التشغيليّة.
    // تقابل الكتلةَ نفسَها في [DeltaPullService.pullTables]؛ هنا مجموعةٌ
    // فالترتيبُ لا يعني شيئاً، والقائمةُ هناك مرتّبةٌ بالمفاتيح.
    // و`employees` منها — خمسةٌ من جداول الفئة تشير إليها وثلاثةٌ بإشارةٍ
    // غيرِ قابلةٍ للإفراغ.
    'employees',
    'table_sections', 'restaurant_tables', 'floor_plan_items',
    'table_orders',
    'table_order_items', 'table_reservations', 'table_order_payments',
    'kitchen_stations', 'category_station_mappings',
    'work_orders', 'work_order_items',
    'booking_resources', 'booking_services', 'bookings', 'booking_reminders',
    'sales_routes', 'route_visits', 'sales_rep_targets',
    'sales_rep_collections',
    // v185 — نموذجُ التوزيع (المرحلة و).
    'distribution_areas', 'route_customers', 'route_rep_history',
    'rep_resources',
    'warehouse_locations', 'location_stock',
    'return_drafts', // v189 — J2
    'hr_departments', 'hr_job_titles', 'employee_allowances', // v191 — J4
    'employee_documents', 'employee_history',
    'hr_shifts', 'hr_shift_assignments', 'hr_public_holidays', // v192
    'hr_leave_types', 'hr_leave_requests', 'hr_leave_entitlements',
    'hr_attendance_days',
    'hr_payroll_settings', 'hr_salary_components', 'hr_commission_plans', // v193
    'hr_employee_advances', 'hr_advance_repayments', 'hr_payroll_adjustments',
    'hr_payroll_runs', 'hr_payroll_lines', 'hr_payroll_items',
    // Tier 7 — v173 / المرحلة ٤: السجلُّ الرقابيُّ والتشغيلُ العابر.
    // تقابل الكتلةَ نفسَها في [DeltaPullService.pullTables]. و
    // `e_invoice_configs` ليست هنا عمداً (تحمل `client_secret`).
    'loyalty_programs', 'delivery_companies', 'couriers',
    'customer_loyalty_points', 'loyalty_transactions',
    'warehouse_prices',
    'cycle_count_plans', 'cycle_count_tasks', 'cycle_count_items',
    'stock_audits', 'stock_audit_items',
    'stock_requisitions', 'stock_requisition_items',
    'bank_reconciliations', 'bank_statement_lines',
    'e_invoice_submissions', 'e_invoice_status_log',
    'field_audit_logs', 'failed_autoposts',
    'approval_workflows', 'approval_steps', 'approval_requests',
    'approval_decisions', 'sod_conflicts', 'sod_violations',
    'compliance_checks',
    // v176 / §٨ — وصفُ المرفق وحدَه؛ و`attachment_blobs` خارجٌ عمداً.
    'attachments',
  };

  /// Phase 5A.1 (Issue 5) — per-table branch column for the `/api/sync/pull`
  /// scope filter. Tables in this map have their rows filtered to the
  /// caller's `?branch_id=` (when provided) plus rows where the column is
  /// NULL (legacy data without a branch link must remain visible to keep
  /// historical reports intact).
  ///
  /// Tables NOT in this map are universal master data — every paired client
  /// needs the full set (chart of accounts, products, parties, units, etc.)
  /// regardless of which branch they're physically in. Adding a table here
  /// must be done together with confirming the column exists in the schema
  /// — an unknown column produces a SQL error at request time.
  ///
  /// `safe_transactions` and `*_lines/items` rows have no direct branch
  /// column; they inherit scope through their parent (safe.branch_id,
  /// invoice.branch_id, etc.). Filtering them at this layer would need a
  /// JOIN. For now they pass through and the client-side branch scope (5C)
  /// handles the visual filter. The server-side cleanup helper (5A.4)
  /// removes any cross-branch rows that may have already landed locally.
  // Feature 011 / Issue PG-SCHEMA — only list tables whose Drift schema
  // ACTUALLY declares a `branch_id` column. The previous map (Spec 008
  // FR-005 era) included `sales_orders`, `purchase_orders`, `quotations`,
  // `commercial_papers` based on an aspirational migration plan that
  // never landed: those tables exist in Drift WITHOUT a branchId field
  // (sales_purchase_tables.dart:325-346, 376-397; quotation_tables.dart:6-30;
  // commercial_finance_tables.dart:11-36). On a PostgreSQL server the
  // column genuinely does not exist, so DeltaPull blew up every minute
  // with `column "branch_id" does not exist` (server_errors.log dated
  // 2026-05-05) and clients couldn't sync ANY of those four tables.
  //
  // Removing the four bad entries means: branch-scoped clients now see
  // ALL rows from these tables (no server-side branch filter). That is
  // the correct fallback — until a migration adds a real branchId column
  // to each, the client-side branch scope (5C) handles the visual
  // narrowing. The orders/quotations/papers volume is low enough that
  // the unscoped sync isn't a perf problem.
  // Spec 029 / corrective patch (2026-05-10) — `held_orders` removed.
  // Same root cause as the Feature 011 / PG-SCHEMA fix: the table's
  // Drift schema (sales_purchase_tables.dart:282-300) does NOT declare
  // a `branchId` column, so on PostgreSQL the column genuinely does
  // not exist. Every DeltaPull from a branch-scoped client failed
  // with `column "branch_id" does not exist` at api_handler.dart:1925.
  // The frontend kept retrying, masquerading as products/inventory
  // screen lag. Removing the entry means held_orders flows unscoped
  // to all clients — held orders are short-lived and per-cashier
  // anyway, so the cross-branch visibility is harmless.
  static const _syncPullBranchColumn = <String, String>{
    'sales_invoices': 'branch_id',
    'purchase_invoices': 'branch_id',
    'journal_entries': 'branch_id',
    'stock_movements': 'branch_id',
    // المرحلة ١ / G1 — البيانات الأساسية. بلا هذين المدخلين كان
    // `/api/sync/pull` يعيد كل الصفوف، وDeltaPull يعيد ملء قاعدة العميل
    // ببيانات الشركة كل دورة، مُلغياً حصر المزامنة الكاملة الذي يعمل
    // بشكل صحيح في `sync_service.dart:594-601`.
    //
    // ⚠️ العمود موجود ومتحقَّق منه في drift — `Warehouses.branchId`
    // (inventory_tables.dart:48) و`Safes.branchId`
    // (treasury_settings_tables.dart:16). لا تُضف جدولاً هنا بلا التحقّق:
    // عمود مفقود يقتل DeltaPull كل دقيقة بـ`column "branch_id" does not
    // exist` متنكّراً في صورة بطء الشاشات (حادثة 2026-05-05 أعلاه).
    'warehouses': 'branch_id',
    'safes': 'branch_id',
    // `branches` يرتبط بالفرع بمفتاحه الأساسي، لا بعمود `branch_id`.
    // الشرط العام (`api_handler.dart:2242`) ينتج
    // `(id = ? OR id IS NULL)` — والذراع الثانية ميتة لأن `id` مفتاح
    // أساسي. مقصود ومتروك: تخصيص المُنشئ لجدول واحد يكلّف أكثر مما
    // يوفّر، والذراع الميتة بلا أثر على الخطة التنفيذية.
    'branches': 'id',
  };

  /// Spec 151 P1-8b — TRANSACTIONAL delta-pull tables (Tier 3 + Tier 4 +
  /// shift/audit movement tables). These carry per-branch business data and
  /// MUST NOT be served to a caller with no verified identity (no session
  /// token). The per-column scoping above only covers the 5 tables that have a
  /// `branch_id`; the rest (orders, quotations, payments, commercial papers,
  /// held orders, safe transactions, and every *_items child) have no branch
  /// column, so without this denylist they would return in FULL to a tokenless
  /// caller — the omission leak this closes. A logged-in user still pulls them
  /// (scoped by branch where a column exists; full otherwise — pre-existing).
  /// DENYLIST (not allowlist) so a *new* reference table is never accidentally
  /// blocked from tokenless provisioning; a new TRANSACTIONAL table must be
  /// added here.
  static const _transactionalPullTables = <String>{
    'sales_invoices', 'purchase_invoices', 'held_orders', 'sales_orders',
    'purchase_orders', 'quotations', 'payments', 'journal_entries',
    'safe_transactions', 'commercial_papers', 'stock_movements', 'shifts',
    'voucher_books', 'voucher_book_leaves_cancelled', // v184
    // `activity_logs` أُسقط مع إخراجه من المزامنة (قرارُ مالك 2026-08-31):
    // مدخلٌ في قائمةِ منعٍ لجدولٍ لا يُسمَح بسحبه أصلاً يوهم بحمايةٍ قائمة.
    'sales_invoice_items', 'purchase_invoice_items',
    'held_order_items', 'sales_order_items', 'purchase_order_items',
    'quotation_items', 'payment_allocations',
    // v166 / المرحلة ٢ — مستنداتُ الأثر المحاسبيّ. بياناتُ عملٍ لا
    // بياناتٌ مرجعيّة: سجلُّ أصولِ الشركة وتكاليفُها ومصروفاتُها لا
    // يُسلَّم لمستدعٍ بلا هويّةٍ متحقَّقة. والفئاتُ وقوائمُ المكوّنات
    // (`asset_categories` · `op_expense_categories` · `bill_of_materials`
    // · `bom_components`) مرجعيّةٌ عمداً فتبقى خارجَ هذه القائمة ليعمل
    // التزويدُ قبلَ الدخول.
    'landed_cost_sheets', 'landed_cost_items', 'landed_cost_allocations',
    'fixed_assets', 'asset_depreciations', 'op_expenses',
    ...manufacturingV180TransactionalTables,
    // v175 / المرحلة ٧ — طلبُ استبعاد أصل. تقابل الإدراجَ نفسَه في
    // `DeltaPullService.branchScopedPullTables` حرفاً.
    'asset_disposals',
    // v174 / المرحلة ٨ — وسمُ الاستيراد. تقابل الإدراجَ نفسَه في
    // `DeltaPullService.branchScopedPullTables` حرفاً (وحارسٌ يثبّت
    // تطابقَ القائمتَين).
    'import_purchase_details',

    // v167 / المرحلة ٣ — الفئةُ التشغيليّة.
    //
    // 🔴 و`employees` هنا **لسببٍ أمنيٍّ لا لسببِ مفاتيح**: الجدولُ يحمل
    //    `salary` و`salary_type`. والقائمةُ **قائمةُ منعٍ لا سماح**، فجدولٌ
    //    جديدٌ يُسلَّم كاملاً لمستدعٍ بلا توكن ما لم يُذكَر هنا — أي أنّ
    //    إغفالَ `employees` كان سيُسلّم رواتبَ الموظّفين قبلَ الدخول.
    //
    // والمرجعيُّ عمداً — `table_sections` · `restaurant_tables` ·
    // `kitchen_stations` · `category_station_mappings` ·
    // `booking_services` — خارجَ القائمة ليعمل التزويدُ قبل الدخول.
    'employees',
    'booking_resources',
    'table_orders', 'table_order_items', 'table_reservations',
    'table_order_payments',
    'work_orders', 'work_order_items',
    'bookings', 'booking_reminders',
    'sales_routes', 'route_visits', 'sales_rep_targets',
    'sales_rep_collections',
    // v185 — نموذجُ التوزيع. تقابل `branchScopedPullTables` حرفاً.
    'distribution_areas', 'route_customers', 'route_rep_history',
    'rep_resources',
    'warehouse_locations', 'location_stock',
    'return_drafts', // v189 — J2
    'hr_departments', 'hr_job_titles', 'employee_allowances', // v191 — J4
    'employee_documents', 'employee_history',
    'hr_shifts', 'hr_shift_assignments', 'hr_public_holidays', // v192
    'hr_leave_types', 'hr_leave_requests', 'hr_leave_entitlements',
    'hr_attendance_days',
    'hr_payroll_settings', 'hr_salary_components', 'hr_commission_plans', // v193
    'hr_employee_advances', 'hr_advance_repayments', 'hr_payroll_adjustments',
    'hr_payroll_runs', 'hr_payroll_lines', 'hr_payroll_items',

    // v173 / المرحلة ٤ — بياناتُ عملٍ لا تُسلَّم لمستدعٍ بلا هويّة. تقابل
    // الكتلةَ نفسَها في `DeltaPullService.branchScopedPullTables` حرفاً.
    // والمرجعيُّ عمداً — `loyalty_programs` · `delivery_companies` ·
    // `couriers` · `warehouse_prices` · `approval_workflows` ·
    // `approval_steps` · `sod_conflicts` — خارجَ القائمة ليعمل التزويدُ
    // قبل الدخول.
    'customer_loyalty_points', 'loyalty_transactions',
    'cycle_count_plans', 'cycle_count_tasks', 'cycle_count_items',
    'stock_audits', 'stock_audit_items',
    'stock_requisitions', 'stock_requisition_items',
    'bank_reconciliations', 'bank_statement_lines',
    'e_invoice_submissions', 'e_invoice_status_log',
    'field_audit_logs', 'failed_autoposts',
    'approval_requests', 'approval_decisions',
    'sod_violations', 'compliance_checks',
    // v176 / §٨ — تقابل الكتلةَ نفسَها في `branchScopedPullTables`.
    'attachments',
  };

  /// Rows per `/api/sync/pull` page when the caller does not ask for a size.
  /// Sized so a page JSON-encodes in tens of milliseconds on the server's
  /// isolate rather than blocking it for seconds.
  static const int _syncPullDefaultLimit = 500;

  /// Hard ceiling on the `limit` query parameter — a client cannot ask the
  /// server to materialise an unbounded result set again.
  static const int _syncPullMaxLimit = 2000;
}
