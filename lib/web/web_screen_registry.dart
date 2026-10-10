// سجلّ شاشات الويب (م3-8): `ScreenId` ← باني الشاشة، للشاشات التي **تُترجَم**
// للويب بإعادة استخدام واجهات PicPos الموجودة.
//
// القاعدة: لا يدخل هنا استيرادُ شاشةٍ تسحب POS/مطبخ/طاولات/ميزان/وردية/طباعة
// (يفرضه `test/structural/web_entry_scope_test.dart`). ما سقط لهذا السبب يبقى
// **مشمولاً** في [kWebScreenIds] ويُعرض «قريبًا» (لا باني له هنا):
//
//   * salesReturns / purchaseReturns — `shared_widgets/open_shift_prompt.dart`
//     ← `pos/widgets/pos_opening_balance_dialog.dart` (حوار وردية POS).
//   * settings — `widgets/settings/pos_settings_widget.dart` +
//     `pos_picpos/widgets/picpos_payment_methods.dart` + `pos_terminals_screen`.
//   * branches — `screens/pos_terminals_screen.dart`.
//   * users — لا شاشةَ مستقلّةً أصلاً (تبويبٌ داخل الإعدادات).
//
// الشاشات تُبنى بنسخة PicPos دائماً (لا فوركَ علامةٍ): كثيرٌ منها بلا نظيرٍ في
// UralCash (العملاء/الموردون/عروض الأسعار/السندات/المطابقة البنكية...).
import 'package:flutter/widgets.dart';

import '../core/navigation/screen_id.dart';
import '../domain/models/document_record.dart';
import '../presentation/accounting_picpos/account_mapping_picpos_screen.dart';
import '../presentation/accounting_picpos/bank_reconciliation_picpos_screen.dart';
import '../presentation/accounting_picpos/chart_of_accounts_picpos_screen.dart';
import '../presentation/accounting_picpos/cost_centers_picpos_screen.dart';
import '../presentation/accounting_picpos/financial_statements_picpos_screen.dart';
import '../presentation/accounting_picpos/general_ledger_picpos_screen.dart';
import '../presentation/accounting_picpos/journal_entries_picpos_screen.dart';
import '../presentation/accounting_picpos/journal_templates_picpos_screen.dart';
import '../presentation/accounting_picpos/journal_voucher_picpos_screen.dart';
import '../presentation/activity_log_picpos/screens/activity_log_picpos_screen.dart';
import '../presentation/analytics_picpos/screens/analytics_picpos_screen.dart';
import '../presentation/categories_picpos/screens/categories_picpos_screen.dart';
import '../presentation/cycle_count_picpos/screens/cycle_count_picpos_screen.dart';
import '../presentation/dashboard_picpos/screens/dashboard_picpos_screen.dart';
import '../presentation/e_invoicing_picpos/screens/e_invoicing_picpos_screen.dart';
import '../presentation/fixed_assets_picpos/screens/asset_categories_picpos_screen.dart';
import '../presentation/fixed_assets_picpos/screens/asset_locations_picpos_screen.dart';
import '../presentation/fixed_assets_picpos/screens/fixed_assets_picpos_screen.dart';
import '../presentation/import_purchases_picpos/screens/import_purchases_picpos_screen.dart';
import '../presentation/inventory_bonds_picpos/screens/inventory_bonds_picpos_screen.dart';
import '../presentation/inventory_picpos/screens/inventory_picpos_screen.dart';
import '../presentation/landed_cost_picpos/screens/landed_cost_picpos_screen.dart';
import '../presentation/offers_picpos/offers_picpos_screen.dart';
import '../presentation/opex_picpos/screens/opex_picpos_screen.dart';
import '../presentation/parties_picpos/screens/parties_picpos_screen.dart';
import '../presentation/products_picpos/screens/products_picpos_screen.dart';
import '../presentation/purchases_picpos/screens/purchases_picpos_screen.dart';
import '../presentation/report_builder_picpos/screens/report_builder_picpos_screen.dart';
import '../presentation/reports_picpos/screens/reports_picpos_screen.dart';
import '../presentation/sales_invoices_picpos/screens/sales_invoices_picpos_screen.dart';
import '../presentation/screens/fiscal_year_screen.dart';
import '../presentation/screens/purchase_orders_screen.dart';
import '../presentation/screens/region_management_screen.dart';
import '../presentation/screens/sales_orders_screen.dart';
import '../presentation/settings_picpos/screens/cheques_picpos_screen.dart';
import '../presentation/stock_transfer_picpos/screens/stock_transfer_picpos_screen.dart';
import '../presentation/treasury_picpos/screens/cheque_books_picpos_screen.dart';
import '../presentation/treasury_picpos/screens/treasury_picpos_screen.dart';
import '../presentation/treasury_picpos/screens/voucher_records_picpos_screen.dart';

/// باني شاشة ويب. [onNavigate] يفتح شاشةً أخرى بفهرس التنقّل (لوحة التحكم).
typedef WebScreenBuilder = Widget Function(void Function(int index) onNavigate);

Widget _quotations() => const QuotationsPicposScreen();

/// الشاشات المترجَمة للويب. ما ليس هنا ولا في [kWebScreenIds] غير موجود؛ وما
/// في [kWebScreenIds] دون باني هنا يُعرض «قريبًا».
final Map<ScreenId, WebScreenBuilder> kWebScreenBuilders = {
  ScreenId.dashboard: (go) => DashboardPicposScreen(onNavigate: go),
  // المبيعات
  ScreenId.salesInvoices: (_) => const SalesInvoicesPicposScreen(),
  ScreenId.quotations: (_) => _quotations(),
  ScreenId.salesOrders: (_) => const SalesOrdersScreen(),
  ScreenId.offers: (_) => const OffersPicPosScreen(),
  // المشتريات
  ScreenId.purchases: (_) => const PurchasesPicposScreen(),
  ScreenId.purchaseOrders: (_) => const PurchaseOrdersScreen(),
  ScreenId.importPurchases: (_) => const ImportPurchasesPicposScreen(),
  ScreenId.landedCost: (_) => const LandedCostPicposScreen(),
  // الأصناف والمخزون
  ScreenId.products: (_) => const ProductsPicposScreen(),
  ScreenId.categories: (_) => const CategoriesPicposScreen(),
  ScreenId.inventory: (_) => const InventoryPicposScreen(),
  ScreenId.inventoryBonds: (_) => const InventoryBondsPicposScreen(),
  ScreenId.stockTransfer: (_) => const StockTransferPicposScreen(),
  ScreenId.cycleCounting: (_) => const CycleCountPicposScreen(),
  ScreenId.fieldAudit: (_) => const CycleCountPicposScreen(),
  // العملاء والموردون
  ScreenId.parties: (_) => const PartiesPicposScreen(),
  ScreenId.customers: (_) => const PartiesPicposScreen.customers(),
  ScreenId.suppliers: (_) => const PartiesPicposScreen.suppliers(),
  // الإدارة المالية
  ScreenId.treasury: (_) => const TreasuryPicposScreen(),
  ScreenId.receiptVoucher: (_) =>
      const VoucherRecordsPicPosScreen(direction: VoucherDirection.receipt),
  ScreenId.paymentVoucher: (_) =>
      const VoucherRecordsPicPosScreen(direction: VoucherDirection.payment),
  ScreenId.chequeBooks: (_) => const ChequeBooksPicposScreen(),
  ScreenId.commercialPapers: (_) => const ChequesPicposScreen(),
  ScreenId.operationalExpenses: (_) => const OpexPicposScreen(),
  ScreenId.fixedAssets: (_) => const FixedAssetsPicposScreen(),
  ScreenId.assetCategories: (_) => const AssetCategoriesPicposScreen(),
  ScreenId.assetLocations: (_) => const AssetLocationsPicposScreen(),
  ScreenId.eInvoice: (_) => const EInvoicingPicposScreen(),
  // إدارة الحسابات
  ScreenId.chartOfAccounts: (_) => const ChartOfAccountsPicPosScreen(),
  ScreenId.journalEntries: (_) => const JournalEntriesPicPosScreen(),
  ScreenId.journalVoucher: (_) => const JournalVoucherPicposScreen(),
  ScreenId.generalLedger: (_) => const GeneralLedgerPicPosScreen(),
  ScreenId.costCenters: (_) => const CostCentersPicPosScreen(),
  ScreenId.accountMapping: (_) => const AccountMappingPicPosScreen(),
  ScreenId.fiscalYear: (_) => const FiscalYearScreen(),
  ScreenId.trialBalance: (_) => const FinancialStatementsPicPosScreen(
        view: FinancialStatementsView.trialBalance,
      ),
  ScreenId.financialStatements: (_) => const FinancialStatementsPicPosScreen(),
  ScreenId.bankReconciliation: (_) => const BankReconciliationPicposScreen(),
  ScreenId.journalTemplates: (_) => const JournalTemplatesPicPosScreen(),
  // التقارير
  ScreenId.reports: (_) => const ReportsPicposScreen(),
  ScreenId.reportBuilder: (_) => const ReportBuilderPicposScreen(),
  ScreenId.analytics: (_) => const AnalyticsPicposScreen(),
  // النظام
  ScreenId.activityLog: (_) => const ActivityLogPicposScreen(),
  ScreenId.regions: (_) => const RegionManagementScreen(),
};
