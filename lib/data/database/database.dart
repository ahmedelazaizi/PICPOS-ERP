import '../../core/constants/payment_methods.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:drift/drift.dart';
import 'package:rxdart/rxdart.dart' show DebounceExtensions; // Spec 115 L2 — debounceTime
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
// Import treasury_repository.dart for DAO types (SafeData, TreasurySummaryData, etc.)
import '../../domain/repositories/treasury_repository.dart';
import '../../domain/models/receipt_qr_decision.dart'
    show kEInvoiceEnabledSettingKey;
import 'connection.dart';
import 'pg_compat_sql.dart';
import 'wal_checkpoint.dart';
import '../../domain/models/return_original_link.dart';
import '../../domain/models/invoice_due_date.dart';
import '../../domain/models/account_facts.dart';
import '../../domain/models/asset_movement_types.dart';
import '../../domain/models/journal_balance.dart';
import '../../domain/models/document_record.dart';
import '../../domain/models/voucher_book.dart';
import '../../domain/models/return_draft.dart';
import '../../domain/models/distribution_model.dart';
import '../../domain/models/hr_employee_file.dart';
import '../../domain/models/hr_attendance.dart';
import '../../domain/models/hr_attendance_import.dart';
import '../../domain/models/hr_leave.dart';
import '../../domain/models/hr_payroll.dart';
import '../../domain/models/hr_payroll_engine.dart';
import '../../domain/models/purchase_line_discount.dart';
import '../../domain/models/cheque_book_plan.dart';
import '../../domain/models/asset_disposal_plan.dart';
import '../../domain/models/floor_plan_layout.dart';
import '../../domain/models/import_purchase_plan.dart';
import '../../services/security_service.dart';
import '../../core/auth/admin_password_heal.dart';
import '../../domain/models/quick_sale_policy.dart'
    show kQuickSaleReceiptTemplateKey, quickSaleReceiptTemplateFile;
import '../../services/printing/template_resolver.dart';
import '../../services/printing/paper_compatibility.dart';
import '../../services/password_collision_scanner.dart';
import '../../services/journal_entry_diagnostics.dart';
import '../../services/audit_log_integrity_service.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/stock_movement_types.dart';
import '../../core/auth/bootstrap_admin.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../core/permissions/permission_codes.dart';
import '../../core/tax/effective_item_tax_rate.dart';
import '../../core/tax/einvoice_exempt_codes.dart';
import '../../core/utils/arabic_utils.dart';
// Spec 139 — deterministic JE balancing uses FinancialUtils' minor-unit helpers
// and the single balance-tolerance source of truth. `show` avoids importing its
// UnbalancedJournalException (a different type lives in journal_entry_factory).
import '../../core/utils/date_utils.dart' show DateUtils;
import '../../core/utils/financial_utils.dart' show FinancialUtils;
import '../../core/utils/sales_payment_calculator.dart';
import '../../core/utils/uuid_v7.dart';
import '../../core/utils/journal_entry_gid.dart';
// Replaced license_service with trial_state to break cycles.
import '../../core/trial/trial_state.dart';
import '../../domain/entities/product_entity.dart';
import '../../services/invoice_integrity_service.dart';
import '../../services/role_grant_preflight_service.dart';
import '../../domain/entities/accounting_entities.dart';
import 'sync_interceptor.dart';
import '../../services/sync/mirror_settings_keys.dart';
// Removing error_handler to break cycle
import 'daos/audit_dashboard_dao.dart';
// Feature 004 (US1): Exception types for the auto-account-linkage path.
import 'daos/account_linkage_exceptions.dart';
export 'daos/account_linkage_exceptions.dart';
// Feature 004 (US3): Mutation guard mirror for read-only-on-disconnect.
import '../../core/mutation_guard.dart';
export '../../core/mutation_guard.dart';
// Feature 009 (Auto-Deplete BOM): exceptions + stock-shortage policy enum
// used by _consumeBomComponentsAtomic in manufacturing_dao.dart and by
// applyAutoDepleteForSale (T015).
import 'daos/manufacturing_exceptions.dart';
export 'daos/manufacturing_exceptions.dart';
import '../../services/stock_shortage_policy_service.dart';
export '../../services/stock_shortage_policy_service.dart' show StockShortagePolicy;
// Feature 009 (T012h): shift-open populates Shifts.posTerminalId from this
// service so the per-terminal stock-shortage policy tier (FR-017) can
// resolve at sale time. Null-tolerant — see treasury_dao.dart openShift.
import '../../services/pos_terminal_registration_service.dart';
// 062 (D1-004) — PermissionEnforcer for critical financial ops.
import '../../services/permission_enforcer.dart';
import '../../core/config/brand.dart';
// قاعدةُ إشارة حركة الخزنة — مصدرٌ واحدٌ يشترك فيه الاستعلامُ والشاشة، فلا
// تُنسخ داخل `CASE` في SQL ثم تنحرف عن نسختها بأوّل نوعٍ جديد.
import '../../domain/models/safe_running_balance.dart';
// تقريرُ الطاولات: النوعُ الذي يعبر إلى التقرير خالصٌ، فالتجميعُ يُختبَر بلا
// قاعدة. و`TableOrderTotals` هو محرّكُ الخصم الوحيد — لا تُنسَخ قاعدتُه هنا.
import '../../domain/models/table_order_totals.dart';
import '../../domain/models/tables_report_row.dart';
import '../../domain/models/booking_overlap.dart';
import '../../domain/models/picpos_booking_view.dart';
import '../../domain/models/shift_drawer_resolver.dart';
export '../../services/permission_enforcer.dart' show PermissionDeniedException;

part 'database.g.dart';

// DAO EXTENSIONS
part 'daos/product_crud_dao.dart';
part 'daos/product_barcode_units_dao.dart';
part 'daos/sales_dao.dart';
part 'daos/sales_mutations_dao.dart';
part 'daos/invoice_integrity_dao.dart';
part 'daos/payment_allocations_dao.dart';
part 'daos/sales_actions_dao.dart';
part 'daos/sales_held_orders_dao.dart';
part 'daos/sales_analytics_dao.dart';
part 'daos/purchase_dao.dart';
part 'daos/purchase_models.dart';
part 'daos/purchase_queries_dao.dart';
part 'daos/purchase_return_reads_dao.dart';
part 'daos/purchase_insert_support_dao.dart';
part 'daos/purchase_update_dao.dart';
part 'daos/purchase_payments_dao.dart';
part 'daos/purchase_void_dao.dart';
part 'daos/purchase_summary_dao.dart';
part 'daos/purchase_reports_dao.dart';
part 'daos/treasury_dao.dart';
part 'daos/treasury_shift_models.dart';
part 'daos/treasury_shift_dao.dart';
part 'daos/treasury_shift_settlement_dao.dart';
part 'daos/treasury_shift_close_safes_dao.dart';
part 'daos/treasury_shift_aggregates_dao.dart';
part 'daos/treasury_safe_queries_dao.dart';
part 'daos/treasury_safe_resolution_dao.dart';
part 'daos/treasury_transactions_dao.dart';
part 'daos/treasury_safe_linking_dao.dart';
part 'daos/treasury_voucher_dao.dart';
part 'daos/treasury_reports_dao.dart';
part 'daos/user_dao.dart';
part 'daos/party_dao.dart';
part 'daos/party_reads_dao.dart';
part 'daos/party_profile_dao.dart';
part 'daos/party_coa_repair_dao.dart';
part 'daos/party_balances_dao.dart';
part 'daos/party_transactions_dao.dart';
part 'daos/party_reconciliation_dao.dart';
part 'daos/party_models.dart';
part 'daos/party_group_dao.dart';
part 'daos/party_dedup_dao.dart';
part 'daos/party_dedup_models.dart';
part 'daos/tables_dao.dart';
part 'daos/bookings_dao.dart';
part 'daos/inventory_dao.dart';
part 'daos/inventory_batch_dao.dart';
part 'daos/inventory_transfers_dao.dart';
part 'daos/offers_dao.dart';
part 'daos/settings_dao.dart';
part 'daos/printer_dao.dart';
part 'daos/permissions_dao.dart';
part 'daos/delivery_dao.dart';
part 'daos/kitchen_dao.dart';
part 'daos/branches_dao.dart';
part 'daos/regions_dao.dart';
part 'daos/accounting_dao.dart';
part 'daos/accounting_dao_reads.dart';
part 'daos/accounting_dao_writes.dart';
part 'daos/accounting_autopost_dao.dart';
part 'daos/accounting_autopost_cash_sale_dao.dart';
part 'daos/accounting_autopost_documents_dao.dart';
part 'daos/accounting_autopost_sales_return_dao.dart';
part 'daos/accounting_autopost_purchase_return_dao.dart';
part 'daos/accounting_autopost_delivery_repair_dao.dart';
part 'daos/autopost_repair_dao.dart';
part 'daos/accounting_reports_dao.dart';
part 'daos/accounting_fiscal_dao.dart';
part 'daos/accounting_audit_dao.dart';
part 'daos/commercial_papers_dao.dart';
part 'daos/cheque_books_dao.dart';
part 'daos/asset_disposals_dao.dart';
part 'daos/floor_plan_dao.dart';
part 'daos/attachments_dao.dart';
part 'daos/import_purchases_dao.dart';
part 'daos/multi_currency_pricelist_dao.dart';
part 'daos/manufacturing_dao.dart';
part 'daos/manufacturing_v180_dao.dart';
part 'lan_pairing_schema.dart';
part 'product_tax_exempt_schema.dart';
part 'sales_invoice_revenue_account_schema.dart';
part 'voucher_books_schema.dart';
part 'distribution_model_schema.dart';
part 'cheque_drawer_schema.dart';
part 'cloud_sync_schema.dart';
part 'purchase_invoice_purchase_account_schema.dart';
part 'return_drafts_schema.dart';
part 'system_parties_schema.dart';
part 'hr_core_schema.dart';
part 'daos/hr_employee_file_dao.dart';
part 'daos/hr_role_link_dao.dart';
part 'hr_attendance_schema.dart';
part 'daos/hr_attendance_dao.dart';
part 'daos/hr_leave_dao.dart';
part 'hr_payroll_schema.dart';
part 'daos/hr_payroll_dao.dart';
part 'daos/hr_payroll_posting_dao.dart';
part 'daos/hr_advances_dao.dart';
part 'daos/hr_commission_dao.dart';
part 'field_expense_schema.dart';
part 'warehouse_locations_schema.dart';
part 'daos/bin_stock_ledger.dart';
part 'daos/fefo_allocator.dart';
part 'daos/bin_transfer_lots.dart';
part 'daos/warehouse_locations_ops.dart';
part 'daos/distribution_rep_ops_dao.dart';
part 'daos/voucher_account_transfer_dao.dart';
part 'daos/fixed_assets_dao_ext.dart';
part 'daos/e_invoicing_dao.dart';
part 'daos/activity_logs_dao.dart';
part 'daos/invoice_template_dao.dart';
part 'daos/template_binding_dao.dart';
part 'daos/invoice_template_seeder_dao.dart';
part 'daos/sync_dao.dart';
part 'daos/quotations_dao.dart';
part 'daos/scale_dao.dart';
part 'daos/purchase_orders_dao.dart';
part 'daos/modifiers_dao.dart';
// fixed_assets_dao.dart merged into fixed_assets_dao_ext.dart (Phase 3.2 God DAO split)
part 'daos/sales_orders_dao.dart';
part 'daos/bank_reconciliation_dao.dart';
part 'daos/data_maintenance_dao.dart';
part 'daos/multi_currency_dao.dart';
part 'daos/fx_revaluation_dao.dart';
part 'daos/budgeting_dao.dart';
part 'daos/deferred_schedule_dao.dart';
part 'daos/approval_workflow_dao.dart';
part 'daos/sod_matrix_dao.dart';
part 'daos/consolidated_statements_dao.dart';
part 'daos/intercompany_dao.dart';
part 'daos/restatement_dao.dart';
part 'daos/compliance_dashboard_dao.dart';
part 'daos/journal_template_dao.dart';
part 'daos/field_audit_dao.dart';
part 'daos/cycle_count_dao.dart';
part 'daos/landed_cost_dao.dart';
part 'daos/api_key_dao.dart';
part 'daos/report_builder_dao.dart';
part 'daos/notification_dao.dart';
part 'daos/operational_expenses_dao.dart';
part 'daos/fk_resolver_dao.dart';
part 'daos/work_holidays_dao.dart';
part 'daos/party_engagement_dao.dart';
// Seeding & Projections
part 'database_seeder.dart';
part 'database_seeder_permissions.dart';
part 'database_seeder_accounts.dart';
part 'database_seeder_postgres.dart';
part 'database_migrations.dart';
part 'database_startup.dart';
part 'database_types.dart';
part 'database_sql_constants.dart';
part 'database_pg_create.dart';
part 'database_pg_sync_infra.dart';
part 'database_pg_parity.dart';
part 'database_numbering.dart';
part 'database_misc_dao_methods.dart';
part 'database_schema_history.dart';
part 'database_design_notes.dart';
part 'migrations/epoch_1.dart';
part 'migrations/epoch_2.dart';
part 'migrations/epoch_3.dart';
part 'migrations/epoch_3_v081_v093.dart';
part 'migrations/epoch_3_v094_v118.dart';
part 'migrations/epoch_3_v119_v133.dart';
part 'migrations/epoch_3_v134_v147.dart';
part 'migrations/epoch_3_v148_v156.dart';
part 'migrations/epoch_3_v157_v166.dart';
part 'migrations/epoch_3_v167_v173.dart';
part 'migrations/epoch_3_v174_v195.dart';
part 'models/projections.dart';

// Table Definitions
part 'tables/auth_tables.dart';
part 'tables/inventory_tables.dart';
part 'tables/product_tables.dart';
part 'tables/sales_purchase_tables.dart';
part 'tables/restaurant_tables.dart';
part 'tables/accounting_tables.dart';
part 'tables/treasury_settings_tables.dart';
part 'tables/delivery_tables.dart';
part 'tables/kitchen_tables.dart';
part 'tables/hr_tables.dart';
part 'tables/scale_tables.dart';
part 'tables/audit_tables.dart';
part 'tables/sync_tables.dart';
part 'tables/invoice_template_tables.dart';
part 'tables/commercial_finance_tables.dart';
part 'tables/manufacturing_assets_tables.dart';
part 'tables/e_invoicing_tables.dart';
part 'tables/loyalty_tables.dart';
part 'tables/distribution_tables.dart';
part 'tables/party_engagement_tables.dart';
part 'tables/document_sequences.dart';
part 'tables/quotation_tables.dart';
part 'tables/operational_expenses_tables.dart';
part 'tables/bank_reconciliation_tables.dart';
part 'tables/enterprise_tables.dart';
part 'tables/phase9_enterprise_tables.dart';
part 'tables/journal_template_tables.dart';
part 'tables/field_audit_tables.dart';
part 'tables/cycle_count_tables.dart';
part 'tables/landed_cost_tables.dart';
part 'tables/api_key_tables.dart';
part 'tables/report_builder_tables.dart';
part 'tables/booking_tables.dart';
part 'tables/attachment_tables.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DATABASE CLASS
// ═══════════════════════════════════════════════════════════════════════════

@DriftDatabase(
  tables: [
    Roles, // User roles
    Permissions, // Permission definitions
    RolePermissions, // Role-Permission mapping
    Users,
    UserBranchAccess, // N3: User-branch access control
    UserWarehouseAccess, // N3: User-warehouse access control
    UserRegionAccess, // Region-level access control
    Regions,
    Branches,
    Warehouses,
    Units,
    Categories,
    CategoryBranches, // PIR R-10: Category-Branch visibility join table
    Products,
    ProductBarcodes,
    ProductUnits,
    ProductBatches, // Batch tracking for expiry
    PartyGroups,
    Parties,
    PurchaseInvoices,
    PurchaseInvoiceItems,
    // v174 - تفاصيلُ فاتورة الاستيراد (١:١ مع الفاتورة)
    ImportPurchaseDetails,
    // §٦‑٢ — مستندُ مرتجع المشتريات. جدولٌ **مستقلٌّ** عمداً: صفٌّ في
    // `purchase_invoices` كان سيدخل خمسةً وثلاثين استعلامَ مشترياتٍ قائماً.
    PurchaseReturns,
    SalesInvoices,
    SalesInvoiceItems,
    Offers,
    OfferItems,
    TableSections, // NEW: Restaurant sections
    RestaurantTables, // NEW: Restaurant tables
    TableOrders, // NEW: Table orders
    TableOrderItems, // NEW: Items in table orders
    // v174 - معالمُ القاعة غيرُ الطاولات
    FloorPlanItems,
    TableReservations, // NEW: Table reservations
    TableOrderPayments, // v154: دفعةٌ لكلّ دافعٍ على طلب الطاولة
    BookingResources, // v159: «الموظفون / الموارد» — مَن يُحجَز وقتُه
    BookingServices, // v159: الخدماتُ المعروضة للحجز
    Bookings, // v159: مواعيدُ الخدمة — مستقلّةٌ عن TableReservations
    BookingReminders, // v161: تذكيرُ الموعد — «فُتحت» لا «أُرسلت»
    StockMovements,
    InventoryBalances,
    Accounts,
    JournalEntries,
    JournalEntryLines,
    Safes,
    SafeTransactions,
    Printers, // Work order printers
    PosTerminals, // v146 / Feature 009: POS terminal registry (FR-034)
    HeldOrders, // Held/suspended orders
    HeldOrderItems, // Items in held orders
    DeliveryCompanies,
    Couriers,
    Settings,
    // KDS Tables
    WorkOrders,
    WorkOrderItems,
    KitchenStations,
    // Spec 130 root-cause: the table class existed in kitchen_tables.dart
    // but was never registered here, so Drift never emitted a CREATE TABLE.
    // On PG installs this manifested as
    //   42P01 relation "category_station_mappings" does not exist
    // on every POS sale that hit KitchenDao.getStationForCategory.
    CategoryStationMappings,
    // HR Tables
    Employees,
    EmployeeAttendance,
    SalaryPayments,
    EmployeeTransactions, // NEW: Advances and deductions
    EmployeeLeaves, // Phase 5: Leave management
    LeaveBalances, // Phase 5: Leave balance tracking
    OvertimeRecords, // Phase 5: Overtime tracking
    FingerprintDevices, // Phase 5: Biometric device registry
    PerformanceReviews, // Phase 9: HR Performance evaluation
    PerformanceGoals, // Phase 9: Employee goal tracking
    EmployeeContracts, // Phase 9: Employment contracts
    WorkHolidays, // v153: Hourly wage/overtime — holiday calendar
    // Stock Audit Tables
    StockAudits,
    StockAuditItems,
    ReceiptSettings, // Receipt/Invoice customization
    ActivityLogs, // Audit trail for all user actions (#14)
    // Invoice Template Designer Tables
    InvoiceTemplates,
    InvoiceTemplateElements,
    InvoiceTableSettings,
    TemplateBindings,
    // Phase 2: Inventory Bonds
    InventoryBonds,
    InventoryBondItems,
    StockRequisitions, // Phase 2: Cross-Branch Stock Requisition
    StockRequisitionItems, // Phase 2: Cross-Branch Stock Requisition
    Shifts, // #Phase4: Operational Auditing
    LabelScales, // #Phase5: Multi-scale PLU export registry
    // Phase 1: Advanced Accounting
    CostCenters,
    FiscalYears,
    AccountingPeriods, // PIR Phase 1.5: Monthly period locking
    ActivityProfiles,
    // Phase 2: Commercial Papers & Finance
    // v174 - دفترُ الشيكات الصادرة، وهو قبلَ CommercialPapers
    // لأنَّ الأخيرَ صار يشير إليه بـchequeBookId.
    ChequeBooks,
    CommercialPapers,
    PaperStatusHistory,
    Currencies,
    ExchangeRateHistory,
    PriceLists,
    PriceListItems,
    // Phase 3: Manufacturing & Assets
    BillOfMaterials,
    BomComponents,
    ManufacturingOrders,
    AssetCategories,
    FixedAssets,
    // v174 - طلبُ استبعاد أصلٍ: مستندٌ بدورةِ حياة
    AssetDisposals,
    AssetDepreciations,
    // Phase 4: E-Invoicing
    EInvoiceConfigs,
    EInvoiceSubmissions,
    // v173 — كان صنفاً بلا إعلانٍ (٦‑١) يُبنى بـSQL خامٍّ في ثلاثة مواضع.
    // صار كياناً كأخواته: `onCreate` و`_createAllForPostgres` يبنيانه
    // بأعمدة المزامنة، والـSQL الخامُّ أدناه بقي شفاءً ذاتيّاً لا مصدراً.
    EInvoiceStatusLog,
    TaxTypes,
    TaxSubtypes,
    // Phase 5.2: Loyalty Points
    LoyaltyPrograms,
    CustomerLoyaltyPoints,
    LoyaltyTransactions,
    // Phase 5.3: Distribution & Sales Reps
    SalesRoutes,
    RouteVisits,
    SalesRepTargets,
    SalesRepCollections,
    // Phase 7: Sync Engine
    SyncOutbox,
    SyncConflictLog,
    AccountMappings,
    DocumentSequences,
    Quotations,
    QuotationItems,
    // Phase 8: Operational Expenses
    OpExpenseCategories,
    OpExpenses,
    MfgOrderCosts,
    // v146 / Feature 009: Auto-Deplete BOM consumption log
    SaleBomConsumptions,
    // Phase 8.1: Purchase Orders
    PurchaseOrders,
    PurchaseOrderItems,
    WarehousePrices, // v69: Per-warehouse product pricing
    // Phase 9: Sales Orders
    SalesOrders,
    SalesOrderItems,
    // Phase 10: Independent Payments
    Payments,
    PaymentAllocations,
    // Phase 11: Bank Reconciliation
    BankStatementLines,
    BankReconciliations,
    // Phase 12: Enterprise — Budgeting, Deferred, Approvals, SOD
    Budgets,
    BudgetLines,
    DeferredSchedules,
    DeferredEntries,
    ApprovalWorkflows,
    ApprovalSteps,
    ApprovalRequests,
    ApprovalDecisions,
    SodConflicts,
    SodViolations,
    // Phase 13: Enterprise Advanced — Consolidation, Intercompany, Restatement, Compliance
    Entities,
    EntityMappings,
    IntercompanyTransactions,
    Restatements,
    RestatementLines,
    ComplianceChecks,
    // Phase 14: Journal Entry Templates
    JournalEntryTemplates,
    JournalEntryTemplateLines,
    // Phase 15: Notifications
    Notifications,
    // Phase C7: Field-Level Audit Logging
    FieldAuditLogs,
    // Phase C4: Cycle Counting
    CycleCountPlans,
    CycleCountTasks,
    CycleCountItems,
    // Phase C2: Landed Cost
    LandedCostSheets,
    LandedCostItems,
    LandedCostAllocations,
    // Phase C1: API Keys
    ApiKeys,
    // Phase C5: Report Builder
    CustomReports,
    SavedReportRuns,
    // API Idempotency
    ProcessedMessages,
    // P2.2: FK remap table (replaces JSON blob in settings)
    RemoteIdMappings,
    // PIR P0-04: Failed Autopost monitoring
    FailedAutoposts,
    // v165 — سجلّا تواصلٍ لا قيدَين: متابعةُ التحصيل ومطالبةُ المورد.
    PartyFollowUps,
    SupplierClaims,
    // v176 / §٨ — المرفقات. الوصفُ يُزامَن، والبايتاتُ **خارجَ كلّ
    // قائمةِ سحبٍ عمداً** — انظر `tables/attachment_tables.dart`.
    Attachments,
    AttachmentBlobs,
  ],
)
/// MonixaERP ERP Core Database.
///
/// Drift-powered SQLite database with 41 schema versions, full-text search,
/// and 16 DAO extensions covering products, sales, purchases, treasury,
/// inventory, users, permissions, HR, delivery, kitchen, and audit logging.
///
/// Uses the SINGLETON PATTERN: `AppDatabase()` always returns the same instance.
/// This prevents multiple SQLCipher connections that would each run their own
/// `beforeOpen` seeder, leading to inconsistent data (e.g., password hash corruption).
///
/// `AppDatabase.forTesting()` opens an in-memory connection for tests (not singleton).
class AppDatabase extends _$AppDatabase {
  /// Whether this database is backed by PostgreSQL (affects migration behavior)
  final bool _isPostgres;

  /// صحيحٌ فقط لـ[AppDatabase.forWebRemote]: لا ترحيلات ولا عمل عند الفتح.
  bool _skipMigrations = false;

  /// Singleton instance for the default SQLite connection
  static AppDatabase? _instance;

  /// Factory constructor — returns the singleton SQLite instance.
  /// Every call to `AppDatabase()` returns the SAME database connection.
  factory AppDatabase() {
    _instance ??= AppDatabase._internal();
    return _instance!;
  }

  /// Private internal constructor — called only once
  AppDatabase._internal() : _isPostgres = false, super(openConnection());

  // Backwards compatibility for refactored DAOs
  AppDatabase get accountingDao => this;
  AppDatabase get quotationsDao => this;
  AppDatabase get journalTemplateDao => this;

  /// Opens the database using a custom [QueryExecutor] (e.g., PostgreSQL).
  /// NOT a singleton — each PostgreSQL config gets its own instance.
  AppDatabase.withExecutor(super.executor, {bool isPostgres = false})
      : _isPostgres = isPostgres;

  /// Web client (m3-6): a database over a drift-remote connection to the desktop host
  /// (read-only). Skips migrations and everything that runs on open; not a singleton.
  /// Full rationale: `database_design_notes.dart`.
  AppDatabase.forWebRemote(super.connection, {required bool isPostgres})
      : _isPostgres = isPostgres,
        _skipMigrations = true;

  /// Opens an in-memory database for widget / integration tests.
  /// NOT a singleton — each test gets its own isolated database.
  AppDatabase.forTesting() : _isPostgres = false, super(openTestConnection()) {
    // Clear top-level caches to prevent cross-test contamination
    resetProductCaches();
  }

  /// Whether this database is backed by PostgreSQL (public read-only accessor
  /// used by DAOs that need to generate database-agnostic raw SQL).
  bool get isPostgres => _isPostgres;

  /// Open-transaction depth. Nested transactions (savepoints) push it further,
  /// so it only returns to zero once the OUTERMOST one has settled.
  int _txDepth = 0;

  /// True while any transaction is open on this database.
  /// Why this is deliberately over-conservative: see `database_design_notes.dart`.
  bool get isInTransaction => _txDepth > 0;

  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) {
    return super.transaction(() async {
      _txDepth++;
      try {
        return await action();
      } finally {
        _txDepth--;
      }
    }, requireNew: requireNew);
  }

  // Why the PostgreSQL translation is applied here too: see the notes at the top of
  // `database_pg_create.dart`.

  @override
  Future<void> customStatement(String statement, [List<dynamic>? args]) {
    if (!_isPostgres) return super.customStatement(statement, args);
    return super.customStatement(
      PgCompatSql.fixSql(statement),
      args == null ? null : PgCompatSql.fixArgs(args),
    );
  }

  @override
  Selectable<QueryRow> customSelect(
    String query, {
    List<Variable> variables = const [],
    Set<ResultSetImplementation> readsFrom = const {},
  }) {
    // المتغيّراتُ تبقى كما هي — الترتيبُ الموضعيُّ نفسُه، و`fixSql` ترقّم
    // العلاماتِ من اليسار لليمين فتبقى المطابقةُ صحيحة.
    return super.customSelect(
      _isPostgres ? PgCompatSql.fixSql(query) : query,
      variables: variables,
      readsFrom: readsFrom,
    );
  }

  /// Lazy accessor for the Audit Dashboard DAO
  late final AuditDashboardDao auditDashboardDao = AuditDashboardDao(this);

  /// 062 (D1-004) — shared PermissionEnforcer for critical financial ops.
  /// Used by DAO part-files (sales_actions_dao, purchase_dao, …) to gate
  /// the admin bypass on voidPaidInvoice / modifyLockedInvoice /
  /// overrideCreditLimit. See specs/062-wire-critical-financial-ops.
  late final PermissionEnforcer permissionEnforcer =
      PermissionEnforcer(userHasPermission);

  /// Returns the SQL literal for a boolean value that is compatible with the
  /// current database backend. PostgreSQL uses TRUE/FALSE, SQLite uses 1/0.
  String sqlBool(bool value) => _isPostgres
      ? (value ? 'TRUE' : 'FALSE')
      : (value ? '1' : '0');

  /// Returns a [Variable] for DateTime that works in raw SQL (customSelect).
  ///
  /// Drift stores DateTime columns as epoch seconds (BIGINT) in both SQLite
  /// and our PostgreSQL schema. On SQLite, `Variable(DateTime)` auto-converts
  /// to integer. On PostgreSQL, `drift_postgres` sends DateTime as a native
  /// timestamp type which causes type mismatch with BIGINT columns.
  ///
  /// This helper always returns `Variable<int>` with epoch seconds, ensuring
  /// `BETWEEN ? AND ?` and other comparisons work on both backends.
  Variable<int> dateVar(DateTime dt) =>
      Variable<int>(dt.millisecondsSinceEpoch ~/ 1000);

  /// Current schema version. The per-version history (what each bump changed)
  /// lives in `database_schema_history.dart`; the migrations are in `migrations/`.
  @override
  int get schemaVersion => 195;


  /// Canonical list of sync-hardening tables (mirrors the list in
  /// `migrations/epoch_3.dart` v129). Used by the Postgres infrastructure
  /// ensurer to backfill columns and attach auto-bump triggers.
  /// Rationale and history of this list: see `database_pg_sync_infra.dart`.
  static const _syncHardenedTables = <String>[
    'party_groups', 'parties', 'purchase_invoices', 'purchase_invoice_items',
    'sales_invoices', 'sales_invoice_items', 'held_orders', 'held_order_items',
    'purchase_orders', 'purchase_order_items', 'sales_orders', 'sales_order_items',
    'payments', 'payment_allocations',
    'accounts', 'journal_entries', 'cost_centers', 'fiscal_years', 'accounting_periods',
    'roles', 'users',
    'commercial_papers', 'cheque_books',
    'currencies', 'price_lists', 'price_list_items',
    'regions', 'branches', 'warehouses', 'stock_movements',
    'units', 'categories', 'products', 'product_barcodes', 'product_units',
    // v176 — الإضافاتُ والخيارات. وبلا هذا يُولَد صفُّها على PostgreSQL
    // بختمٍ فارغٍ (‏`fn_bump_row_version` هو الوحيدُ الذي يختم عند
    // الإدراج) فلا يصل عميلاً بعد أوّل سحب.
    'modifier_groups', 'modifier_items', 'product_modifier_groups',
    'quotations', 'quotation_items',
    'safes', 'safe_transactions', 'printers',
    'shifts',

    // v166 / المرحلة ٢ — مستنداتُ الأثر المحاسبيّ (كانت غائبةً هنا).
    'asset_categories', 'op_expense_categories', 'bill_of_materials',
    'fixed_assets', 'manufacturing_orders', 'bom_components',
     'butchery_templates', 'butchery_template_lines', 'butchery_orders', 'butchery_order_lines',
    'op_expenses', 'asset_depreciations', 'mfg_order_costs',
    'landed_cost_sheets', 'landed_cost_items', 'landed_cost_allocations',
    // v175 / المرحلة ٧ — طلبُ استبعاد أصل.
    'asset_disposals',
    // v174 / المرحلة ٨ — وسمُ الاستيراد.
    'import_purchase_details',
    // §٦‑٢ (v172)
    'purchase_returns',
    // v167 / المرحلة ٣ — الفئةُ التشغيليّة (كانت غائبةً هنا).
    'employees',
    'table_sections', 'restaurant_tables', 'floor_plan_items',
    'table_orders',
    'table_order_items', 'table_reservations', 'table_order_payments',
    'kitchen_stations', 'category_station_mappings',
    'work_orders', 'work_order_items',
    'booking_resources', 'booking_services', 'bookings', 'booking_reminders',
    'sales_routes', 'route_visits', 'sales_rep_targets',
    'sales_rep_collections',

    // v173 / المرحلة ٤ — السجلُّ الرقابيُّ والتشغيلُ العابرُ للأجهزة.
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

    // v176 / §٨ — المرفقات. والعقدُ: كلُّ جدولٍ في `pullTables` هنا.
    'attachments',

    // v184 — دفاترُ السندات (المرحلة هـ / E3).
    'voucher_books', 'voucher_book_leaves_cancelled',

    // v185 — نموذجُ التوزيع (المرحلة و).
    'distribution_areas', 'route_customers', 'route_rep_history',
    'rep_resources',
    'warehouse_locations', 'location_stock',

    // v189 — مسوّداتُ المرتجعات (J2).
    'return_drafts',

    // v191 — ملفُّ الموظف (J4).
    'hr_departments', 'hr_job_titles', 'employee_allowances',
    'employee_documents', 'employee_history',

    // v192 — الورديّاتُ والحضورُ والإجازات (J4 الجزء ٢).
    'hr_shifts', 'hr_shift_assignments', 'hr_public_holidays',
    'hr_leave_types', 'hr_leave_requests', 'hr_leave_entitlements',
    'hr_attendance_days',

    // v193 — الرواتبُ والسلفُ والعمولات (J4 الجزء ٣).
    'hr_payroll_settings', 'hr_salary_components', 'hr_commission_plans',
    'hr_employee_advances', 'hr_advance_repayments', 'hr_payroll_adjustments',
    'hr_payroll_runs', 'hr_payroll_lines', 'hr_payroll_items',
  ];

  /// مكشوفةٌ لحارسٍ يثبّت أنّ كلَّ جدولٍ يُسحَب يحمل مُشغِّلَ الختم على
  /// PostgreSQL — انظر تعليقَ [_syncHardenedTables].
  @visibleForTesting
  static List<String> get syncHardenedTablesForTest => _syncHardenedTables;


  /// Information schema snapshot for one PG table column.
  /// Private helper structure for the parity pass.
  static const Map<DriftSqlType, List<String>> _driftTypeToPgAcceptable = {
    DriftSqlType.int: ['integer', 'bigint', 'smallint'],
    DriftSqlType.bigInt: ['bigint', 'integer'],
    DriftSqlType.string: ['text', 'character varying', 'character'],
    DriftSqlType.bool: ['boolean'],
    DriftSqlType.double: ['double precision', 'real', 'numeric'],
    DriftSqlType.dateTime: ['bigint'], // Drift stores epoch
    DriftSqlType.blob: ['bytea'],
    // `any` is Drift's wildcard for custom types — accept any actual PG
    // type to avoid false-positive drift warnings on columns the schema
    // intentionally leaves loose.
    DriftSqlType.any: [],
  };


  /// ISS-08: Migration logic delegated to database_migrations.dart
  @override
  MigrationStrategy get migration {
    if (_skipMigrations) {
      return MigrationStrategy(
        onCreate: (_) async {},
        onUpgrade: (_, _, _) async {},
        beforeOpen: (_) async {},
      );
    }
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        // PostgreSQL: create strftime() compatibility function BEFORE createAll
        if (_isPostgres) {
          await _createPostgresCompatLayer();
          // Use PostgreSQL-safe table creation with per-table fallback
          await _createAllForPostgres(m);
        } else {
          await m.createAll();
          // Spec 151: idx_je_autopost_dedup is raw SQL (not a Drift table
          // entity), so createAll() never emits it. Create it here so FRESH
          // SQLite installs get the same return-exempt dedup backstop that
          // upgraded DBs get via the v150 migration. Uses the shared SoT SQL so
          // fresh installs and upgrades agree on the exemption shape.
          await customStatement(kCreateJeAutopostDedupIndexSql);
          // نفس المنطق: فهارس خام مش كيانات Drift، فـcreateAll() ما بيصدّرهاش.
          // التنصيبات الجديدة لازم تاخد نفس حراسة B1/B2 اللي بتاخدها المُرقّاة.
          await customStatement(kCreateSalaryPaymentDedupIndexSql);
          await customStatement(kCreateAttendanceDayDedupIndexSql);
          // v159: فهرسُ المسار الساخن لمحرِّك الحجز — نفسُ المنطق، فهرسٌ
          // خامٌّ لا كيانُ drift فـ`createAll()` ما بيصدّرهوش.
          await customStatement(kCreateBookingResourceSlotIndexSql);
          // ٦‑١: نفسُ المنطق لكن على **جدول** لا فهرس. `EInvoiceStatusLog`
          // صنفُ جدولٍ غيرُ مُعلَنٍ في `@DriftDatabase`، فتنصيبةٌ جديدةٌ
          // تفتقده تماماً بينما المُرقّاةُ تأخذه من هجرة v81 — و
          // `e_invoicing_dao` يقرؤه ويكتبه بـSQL خامّ.
          await customStatement(kCreateEInvoiceStatusLogSql);
          await customStatement(kCreateEInvoiceStatusLogIndexSql);
        }
        await ensureManufacturingV180Schema();
        await ensureLanPairingSchema();
        await ensureProductTaxExemptSchema();
        await ensureSalesInvoiceRevenueAccountSchema();
        await ensureVoucherBooksSchema();
        await ensureDistributionModelSchema();
        await ensureChequeDrawerSchema();
        await ensureCloudSyncSchema();
        await ensurePurchaseInvoicePurchaseAccountSchema();
        await ensureReturnDraftsSchema();
        await ensureSystemPartiesSchema();
        await ensureHrCoreSchema();
        await ensureHrAttendanceSchema();
        await ensureHrPayrollSchema();
        await ensureFieldExpenseSchema();
        await ensureWarehouseLocationsSchema(backfill: false);
        // seedInitialData + syncDefaultAccounts moved to beforeOpen
        // (after defensive v110 column additions)
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // PostgreSQL: skip SQLite-specific migrations entirely.
        // PG schema is created fresh via _createAllForPostgres() in onCreate.
        // Incremental migrations use SQLite-only syntax (AUTOINCREMENT, PRAGMA,
        // INSERT OR IGNORE, typeof(), etc.) that fails on PostgreSQL.
        if (_isPostgres) {
          debugPrint('[PG] onUpgrade skipped (from=$from to=$to) — PG uses fresh schema');
          return;
        }
        await runOnUpgrade(m, from, to);
      },
      beforeOpen: (details) async {
        await runBeforeOpen(details);
      },
    );
  }
  // Seeding methods have been moved to DatabaseSeeder extension in database_seeder.dart
  // to keep the main database.dart file clean and manageable.

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITY METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// ═══════════════════════════════════════════════════════════════════════
  /// INVOICE / VOUCHER NUMBER PREFIXES — single source of truth
  /// ═══════════════════════════════════════════════════════════════════════
  ///
  /// Canonical defaults for each of the eight document types. Each prefix
  /// was chosen to be visually distinct even at a glance — `POS` / `SINV`
  /// / `SRET` / `PINV` / `PRET` / `RCPT` / `PMT` / `QUOT`. User-configured
  /// overrides live in the `settings` table under the matching key from
  /// [_prefixSettingKeys].
  static const defaultSalesPosPrefix = 'POS';
  static const defaultSalesManualPrefix = 'SINV';
  static const defaultSalesReturnPrefix = 'SRET';
  static const defaultPurchasePrefix = 'PINV';
  static const defaultPurchaseReturnPrefix = 'PRET';
  static const defaultReceiptVoucherPrefix = 'RCPT';
  static const defaultPaymentVoucherPrefix = 'PMT';
  static const defaultQuotationPrefix = 'QUOT';

  /// Map of canonical prefixes → setting key. Callers pass the canonical
  /// prefix (or one of the legacy aliases in [_prefixAliases]); the
  /// `generateInvoiceNumber` entry point normalises to the canonical form
  /// before looking up either a user override or the default.
  static const _prefixSettingKeys = <String, String>{
    defaultSalesPosPrefix: 'prefix_sales_pos',
    defaultSalesManualPrefix: 'prefix_sales_manual',
    defaultSalesReturnPrefix: 'prefix_sales_return',
    defaultPurchasePrefix: 'prefix_purchase',
    defaultPurchaseReturnPrefix: 'prefix_purchase_return',
    defaultReceiptVoucherPrefix: 'prefix_receipt_voucher',
    defaultPaymentVoucherPrefix: 'prefix_payment_voucher',
    defaultQuotationPrefix: 'prefix_quotation',
  };

  /// Legacy → canonical alias map. Historical call sites hard-coded older
  /// prefix strings (`R-`, `INV`, `RET-`, `PUR`, `RV`, `PV`, `QUO`, ...).
  /// We normalise them on entry so every new document flows through the
  /// same canonical prefix pipeline AND honours the shared settings keys.
  static const _prefixAliases = <String, String>{
    // Sales
    'R': defaultSalesPosPrefix,
    'R-': defaultSalesPosPrefix,
    'Receipt': defaultSalesPosPrefix,
    'Recept': defaultSalesPosPrefix,
    'INV': defaultSalesManualPrefix,
    'RET-': defaultSalesReturnPrefix,
    'SRET-': defaultSalesReturnPrefix,
    // Purchases
    'PUR': defaultPurchasePrefix,
    'PRET-': defaultPurchaseReturnPrefix,
    // Vouchers
    'RV': defaultReceiptVoucherPrefix,
    'PV': defaultPaymentVoucherPrefix,
    // Quotations
    'QUO': defaultQuotationPrefix,
  };

  /// All canonical prefixes — used by the settings screen to validate that
  /// no two document types accidentally share the same user-configured
  /// prefix.
  static List<String> get canonicalInvoicePrefixes => const [
        defaultSalesPosPrefix,
        defaultSalesManualPrefix,
        defaultSalesReturnPrefix,
        defaultPurchasePrefix,
        defaultPurchaseReturnPrefix,
        defaultReceiptVoucherPrefix,
        defaultPaymentVoucherPrefix,
        defaultQuotationPrefix,
      ];

}
