part of 'app_main_screen.dart';

extension _MainScreenCatalog on _MainScreenState {
  List<ScreenConfig> buildAllScreens() {
    return [
      ScreenConfig(
        appScreen: AppScreen.dashboard,
        builder: (_) => Brand.isPicPos
            ? DashboardPicposScreen(
                onNavigate: (index) => _navigateToScreen(index),
              )
            : DashboardScreen(onNavigate: (index) => _navigateToScreen(index)),
        label: 'Dashboard',
        icon: PhosphorIconsBold.house,
      ),
      ScreenConfig(
        appScreen: AppScreen.pos,
        builder: (_) =>
            Brand.isPicPos ? const PicPosPosScreen() : const PosScreenV2(),
        label: tr('البيع السريع'),
        icon: PhosphorIconsBold.shoppingCart,
      ),
      ScreenConfig(
        appScreen: AppScreen.offers,
        builder: (_) =>
            Brand.isPicPos ? const OffersPicPosScreen() : const OffersScreen(),
        label: tr('العروض'),
        icon: PhosphorIconsBold.tag,
      ),
      ScreenConfig(
        appScreen: AppScreen.tables,
        builder: (_) =>
            Brand.isPicPos ? const TablesPicposScreen() : const TablesScreen(),
        label: tr('الطاولات'),
        icon: PhosphorIconsBold.circlesThree,
      ),
      ScreenConfig(
        appScreen: AppScreen.products,
        builder: (_) => Brand.isPicPos
            ? const ProductsPicposScreen()
            : const ProductsScreen(),
        label: tr('الأصناف'),
        icon: PhosphorIconsBold.package,
      ),
      ScreenConfig(
        appScreen: AppScreen.categories,
        builder: (_) => Brand.isPicPos
            ? const CategoriesPicposScreen()
            : const CategoriesScreen(),
        label: tr('التصنيفات'),
        icon: PhosphorIconsBold.squaresFour,
      ),
      ScreenConfig(
        appScreen: AppScreen.parties,
        builder: (_) => Brand.isPicPos
            ? const PartiesPicposScreen()
            : const UnifiedPartiesScreen(),
        label: tr('العملاء والموردين'),
        icon: PhosphorIconsBold.usersThree,
      ),
      ScreenConfig(
        appScreen: AppScreen.customers,
        builder: (_) => const PartiesPicposScreen.customers(),
        label: tr('العملاء'),
        icon: PhosphorIconsBold.user,
      ),
      ScreenConfig(
        appScreen: AppScreen.suppliers,
        builder: (_) => const PartiesPicposScreen.suppliers(),
        label: tr('الموردون'),
        icon: PhosphorIconsBold.truck,
      ),
      ScreenConfig(
        appScreen: AppScreen.repDistribution,
        builder: (_) => const RepDistributionPicPosScreen(),
        label: tr('إدارة المناديب والتوزيع'),
        icon: PhosphorIconsBold.truck,
      ),
      ScreenConfig(
        appScreen: AppScreen.inventory,
        builder: (_) => SecurityScreenGate(
          settingKey: 'inventory_access_password',
          title: tr('المخازن'),
          child: Brand.isPicPos
              ? const InventoryPicposScreen()
              : const InventoryScreen(),
        ),
        label: tr('المخزون'),
        icon: PhosphorIconsBold.warehouse,
      ),
      ScreenConfig(
        appScreen: AppScreen.purchases,
        builder: (_) => SecurityScreenGate(
          settingKey: 'purchases_access_password',
          title: tr('المشتريات'),
          child: Brand.isPicPos
              ? const PurchasesPicposScreen()
              : const PurchaseInvoicesScreen(),
        ),
        label: tr('المشتريات'),
        icon: PhosphorIconsBold.receipt,
      ),
      ScreenConfig(
        appScreen: AppScreen.treasury,
        builder: (_) => SecurityScreenGate(
          settingKey: 'accounting_access_password',
          title: tr('الحسابات والمالية'),
          child: Brand.isPicPos
              ? const TreasuryPicposScreen()
              : const TreasuryScreen(),
        ),
        label: tr('الخزينة'),
        icon: PhosphorIconsBold.wallet,
      ),
      ScreenConfig(
        appScreen: AppScreen.reports,
        builder: (_) => SecurityScreenGate(
          settingKey: 'reports_access_password',
          title: tr('التقارير'),
          child: Brand.isPicPos
              ? const ReportsPicposScreen()
              : const ReportsScreen(),
        ),
        label: tr('التقارير'),
        icon: PhosphorIconsBold.chartBar,
      ),
      ScreenConfig(
        appScreen: AppScreen.settings,
        builder: (_) => Brand.isPicPos
            ? const SettingsPicposScreen()
            : const SettingsScreen(),
        label: tr('الإعدادات'),
        icon: PhosphorIconsBold.gear,
      ),
      ScreenConfig(
        appScreen: AppScreen.branches,
        builder: (_) => Brand.isPicPos
            ? const BranchesPicposScreen()
            : const BranchManagementScreen(),
        label: tr('الفروع والمخازن'),
        icon: PhosphorIconsBold.buildings,
      ),
      ScreenConfig(
        appScreen: AppScreen.regions,
        builder: (_) => const RegionManagementScreen(),
        label: tr('المناطق'),
        icon: PhosphorIconsBold.mapPin,
      ),
      ScreenConfig(
        appScreen: AppScreen.kitchen,
        builder: (_) => const KitchenDisplayScreen(),
        label: tr('المطبخ'),
        icon: PhosphorIconsBold.cookingPot,
      ),
      ScreenConfig(
        appScreen: AppScreen.analytics,
        builder: (_) => Brand.isPicPos
            ? const AnalyticsPicposScreen()
            : const AnalyticsDashboardScreen(),
        label: tr('التحليلات'),
        icon: PhosphorIconsBold.chartPie,
      ),
      ScreenConfig(
        appScreen: AppScreen.hr,
        builder: (_) => SecurityScreenGate(
          settingKey: 'hr_access_password',
          title: tr('شؤون الموظفين'),
          child: const HRScreen(),
        ),
        label: Brand.isPicPos ? tr('الحضور والرواتب') : tr('الموظفين'),
        icon: PhosphorIconsBold.users,
      ),
      ScreenConfig(
        appScreen: AppScreen.hrEmployees,
        builder: (_) => SecurityScreenGate(
          settingKey: 'hr_access_password',
          title: tr('شؤون الموظفين'),
          child: const HrEmployeesPicPosScreen(),
        ),
        label: tr('سجل الموظفين'),
        icon: PhosphorIconsBold.identificationCard,
      ),
      ScreenConfig(
        appScreen: AppScreen.hrOrganization,
        builder: (_) => SecurityScreenGate(
          settingKey: 'hr_access_password',
          title: tr('شؤون الموظفين'),
          child: const HrOrganizationPicPosScreen(),
        ),
        label: tr('الأقسام والمسميات الوظيفية'),
        icon: PhosphorIconsBold.treeStructure,
      ),
      ScreenConfig(
        appScreen: AppScreen.hrAttendance,
        builder: (_) => SecurityScreenGate(
          settingKey: 'hr_access_password',
          title: tr('شؤون الموظفين'),
          child: const HrAttendancePicPosScreen(),
        ),
        label: tr('الحضور والانصراف'),
        icon: PhosphorIconsBold.fingerprint,
      ),
      ScreenConfig(
        appScreen: AppScreen.hrLeave,
        builder: (_) => SecurityScreenGate(
          settingKey: 'hr_access_password',
          title: tr('شؤون الموظفين'),
          child: const HrLeavePicPosScreen(),
        ),
        label: tr('الإجازات'),
        icon: PhosphorIconsBold.airplaneTilt,
      ),
      ScreenConfig(
        appScreen: AppScreen.hrShifts,
        builder: (_) => SecurityScreenGate(
          settingKey: 'hr_access_password',
          title: tr('شؤون الموظفين'),
          child: const HrShiftsPicPosScreen(),
        ),
        label: tr('الورديات'),
        icon: PhosphorIconsBold.clockClockwise,
      ),
      ScreenConfig(
        appScreen: AppScreen.hrPayroll,
        builder: (_) => SecurityScreenGate(
          settingKey: 'hr_access_password',
          title: tr('شؤون الموظفين'),
          child: const HrPayrollPicPosScreen(),
        ),
        label: tr('الرواتب'),
        icon: PhosphorIconsBold.money,
      ),
      ScreenConfig(
        appScreen: AppScreen.hrAdvances,
        builder: (_) => SecurityScreenGate(
          settingKey: 'hr_access_password',
          title: tr('شؤون الموظفين'),
          child: const HrAdvancesPicPosScreen(),
        ),
        label: tr('السلف والجزاءات'),
        icon: PhosphorIconsBold.handCoins,
      ),
      ScreenConfig(
        appScreen: AppScreen.hrCommissions,
        builder: (_) => SecurityScreenGate(
          settingKey: 'hr_access_password',
          title: tr('شؤون الموظفين'),
          child: const HrCommissionsPicPosScreen(),
        ),
        label: tr('عمولات المندوبين'),
        icon: PhosphorIconsBold.percent,
      ),
      ScreenConfig(
        appScreen: AppScreen.salesInvoices,
        builder: (_) => Brand.isPicPos
            ? const SalesInvoicesPicposScreen()
            : const SalesInvoicesScreen(),
        label: tr('فواتير المبيعات'),
        icon: PhosphorIconsBold.fileText,
      ),
      ScreenConfig(
        appScreen: AppScreen.quotations,
        builder: (_) => const QuotationsPicposScreen(),
        label: tr('عروض الأسعار'),
        icon: PhosphorIconsBold.fileText,
      ),
      ScreenConfig(
        appScreen: AppScreen.activityLog,
        builder: (_) => Brand.isPicPos
            ? const ActivityLogPicposScreen()
            : const ActivityLogScreen(),
        label: tr('سجل العمليات'),
        icon: PhosphorIconsBold.clipboardText,
      ),
      ScreenConfig(
        appScreen: AppScreen.inventoryBonds,
        builder: (_) => Brand.isPicPos
            ? const InventoryBondsPicposScreen()
            : const InventoryBondsScreen(),
        label: tr('أرصدة المخزون'),
        icon: PhosphorIconsBold.clipboardText,
      ),
      ScreenConfig(
        appScreen: AppScreen.stockTransfer,
        builder: (_) => Brand.isPicPos
            ? const StockTransferPicposScreen()
            : const StockTransferScreen(),
        label: tr('سند تحويل اصناف'),
        icon: PhosphorIconsBold.arrowsLeftRight,
      ),
      ScreenConfig(
        appScreen: AppScreen.stockRequisitions,
        builder: (_) => const StockRequisitionsScreen(),
        label: tr('طلبات الصرف'),
        icon: PhosphorIconsBold.truck,
      ),
      ScreenConfig(
        appScreen: AppScreen.scalePlu,
        builder: (_) => Brand.isPicPos
            ? const ScalePluPicposScreen()
            : const ScalePluExportScreen(),
        label: tr('ميزان التسعير'),
        icon: PhosphorIconsBold.scales,
      ),
      ScreenConfig(
        appScreen: AppScreen.eInvoice,
        builder: (_) => Brand.isPicPos
            ? const EInvoicingPicposScreen()
            : const EInvoiceDashboardScreen(),
        label: tr('الفوترة الإلكترونية'),
        icon: PhosphorIconsBold.invoice,
      ),
      ScreenConfig(
        appScreen: AppScreen.loyalty,
        builder: (_) => const LoyaltyScreen(),
        label: tr('نقاط العملاء'),
        icon: PhosphorIconsBold.trophy,
      ),
      ScreenConfig(
        appScreen: AppScreen.distribution,
        builder: (_) => Brand.isPicPos
            ? const DistributionPicposScreen()
            : const DistributionScreen(),
        label: tr('التوزيع'),
        icon: PhosphorIconsBold.truck,
      ),
      ScreenConfig(
        appScreen: AppScreen.manufacturing,
        builder: (_) => Brand.isPicPos
            ? const ManufacturingPicposScreen()
            : const ManufacturingScreen(),
        label: tr('التصنيع'),
        icon: PhosphorIconsBold.factory,
      ),
      ScreenConfig(
        appScreen: AppScreen.operationalExpenses,
        builder: (_) => Brand.isPicPos
            ? const OpexPicposScreen()
            : const OperationalExpensesScreen(),
        label: tr('المصروفات التشغيلية'),
        icon: PhosphorIconsBold.coins,
      ),
      ScreenConfig(
        appScreen: AppScreen.chartOfAccounts,
        builder: (_) => SecurityScreenGate(
          settingKey: 'accounting_access_password',
          title: tr('دليل الحسابات'),
          child: Brand.isPicPos
              ? const ChartOfAccountsPicPosScreen()
              : const ChartOfAccountsScreen(),
        ),
        label: tr('دليل الحسابات'),
        icon: PhosphorIconsBold.treeStructure,
      ),
      ScreenConfig(
        appScreen: AppScreen.fiscalYear,
        builder: (_) => const FiscalYearScreen(),
        label: tr('السنوات المالية'),
        icon: PhosphorIconsBold.calendar,
      ),
      ScreenConfig(
        appScreen: AppScreen.stockMovements,
        builder: (_) => const StockMovementsScreen(),
        label: tr('حركة المخزون'),
        icon: PhosphorIconsBold.arrowsDownUp,
      ),
      ScreenConfig(
        appScreen: AppScreen.purchaseOrders,
        builder: (_) => const PurchaseOrdersScreen(),
        label: tr('أوامر الشراء'),
        icon: PhosphorIconsBold.clipboardText,
      ),
      ScreenConfig(
        appScreen: AppScreen.accountMapping,
        builder: (_) => Brand.isPicPos
            ? const AccountMappingPicPosScreen()
            : const AccountMappingSettingsScreen(),
        label: tr('ربط الحسابات'),
        icon: PhosphorIconsBold.link,
      ),
      ScreenConfig(
        appScreen: AppScreen.journalEntries,
        builder: (_) => SecurityScreenGate(
          settingKey: 'accounting_access_password',
          title: journalEntriesScreenLabel,
          child: Brand.isPicPos
              ? const JournalEntriesPicPosScreen()
              : const JournalEntriesScreen(),
        ),
        label: journalEntriesScreenLabel,
        icon: PhosphorIconsBold.notebook,
      ),
      ScreenConfig(
        appScreen: AppScreen.costCenters,
        builder: (_) => Brand.isPicPos
            ? const CostCentersPicPosScreen()
            : const CostCentersScreen(),
        label: tr('مراكز التكلفة'),
        icon: PhosphorIconsBold.treeStructure,
      ),
      ScreenConfig(
        appScreen: AppScreen.commercialPapers,
        builder: (_) => Brand.isPicPos
            ? const ChequesPicposScreen()
            : const CommercialPapersScreen(),
        label: chequesScreenLabel,
        icon: PhosphorIconsBold.receipt,
      ),
      ScreenConfig(
        appScreen: AppScreen.fixedAssets,
        builder: (_) => Brand.isPicPos
            ? const FixedAssetsPicposScreen()
            : const FixedAssetsScreen(),
        label: tr('الأصول الثابتة'),
        icon: PhosphorIconsBold.buildings,
      ),
      ScreenConfig(
        appScreen: AppScreen.generalLedger,
        builder: (_) => SecurityScreenGate(
          settingKey: 'accounting_access_password',
          title: tr('دفتر الأستاذ'),
          child: Brand.isPicPos
              ? const GeneralLedgerPicPosScreen()
              : const GeneralLedgerScreen(),
        ),
        label: tr('دفتر الأستاذ'),
        icon: PhosphorIconsBold.book,
      ),
      ScreenConfig(
        appScreen: AppScreen.salesOrders,
        builder: (_) => const SalesOrdersScreen(),
        label: tr('طلبات البيع'),
        icon: PhosphorIconsBold.fileText,
      ),
      ScreenConfig(
        appScreen: AppScreen.branchPerformance,
        builder: (_) => const BranchPerformanceScreen(),
        label: tr('أداء الفروع'),
        icon: PhosphorIconsBold.chartBar,
      ),
      ScreenConfig(
        appScreen: AppScreen.helpCenter,
        builder: (_) => const HelpCenterScreen(),
        label: tr('مركز المساعدة'),
        icon: PhosphorIconsBold.question,
      ),
      ScreenConfig(
        appScreen: AppScreen.landedCost,
        builder: (_) => Brand.isPicPos
            ? const LandedCostPicposScreen()
            : const LandedCostScreen(),
        label: tr('التكاليف المحملة'),
        icon: PhosphorIconsBold.money,
      ),
      ScreenConfig(
        appScreen: AppScreen.cycleCounting,
        builder: (_) => Brand.isPicPos
            ? const CycleCountPicposScreen()
            : const CycleCountScreen(),
        label: tr('الجرد الدوري'),
        icon: PhosphorIconsBold.listChecks,
      ),
      ScreenConfig(
        appScreen: AppScreen.reportBuilder,
        builder: (_) => Brand.isPicPos
            ? const ReportBuilderPicposScreen()
            : const ReportBuilderScreen(),
        label: tr('اعداد وتصميم التقارير'),
        icon: PhosphorIconsBold.chartBar,
      ),
      ScreenConfig(
        appScreen: AppScreen.salesReturns,
        builder: (_) => Brand.isPicPos
            ? const SalesReturnRecordsPicPosScreen()
            : const SalesReturnsScreen(),
        label: tr('مرتجع المبيعات'),
        icon: PhosphorIconsBold.arrowUUpLeft,
      ),
      ScreenConfig(
        appScreen: AppScreen.purchaseReturns,
        builder: (_) => Brand.isPicPos
            ? const PurchaseReturnRecordsPicPosScreen()
            : const PurchaseReturnsScreen(),
        label: tr('مرتجع المشتريات'),
        icon: PhosphorIconsBold.arrowUUpLeft,
      ),
      ScreenConfig(
        appScreen: AppScreen.shiftClose,
        builder: (_) => Brand.isPicPos
            ? const ShiftClosePicposScreen()
            : const ShiftCloseScreen(),
        label: tr('إغلاق الوردية'),
        icon: PhosphorIconsBold.lockKey,
      ),
      ScreenConfig(
        appScreen: AppScreen.bookings,
        builder: (_) => const BookingsPicPosScreen(),
        label: tr('الحجوزات'),
        icon: PhosphorIconsBold.calendarCheck,
      ),
      ScreenConfig(
        appScreen: AppScreen.financialStatements,
        builder: (_) => Brand.isPicPos
            ? const FinancialStatementsPicPosScreen()
            : const FinancialStatementsScreen(),
        label: tr('القوائم المالية'),
        icon: PhosphorIconsBold.scales,
      ),
      ScreenConfig(
        appScreen: AppScreen.bankReconciliation,
        builder: (_) => const BankReconciliationPicposScreen(),
        label: tr('المطابقة البنكية'),
        icon: PhosphorIconsBold.bank,
      ),
      ScreenConfig(
        appScreen: AppScreen.trialBalance,
        builder: (_) => const FinancialStatementsPicPosScreen(
          view: FinancialStatementsView.trialBalance,
        ),
        label: tr('ميزان المراجعة'),
        icon: PhosphorIconsBold.scales,
      ),
      ScreenConfig(
        appScreen: AppScreen.journalTemplates,
        builder: (_) => const JournalTemplatesPicPosScreen(),
        label: tr('قوالب القيود'),
        icon: PhosphorIconsBold.stack,
      ),
      ScreenConfig(
        appScreen: AppScreen.templateResolution,
        builder: (_) => const TemplateResolutionPicposScreen(),
        label: tr('حسم القوالب'),
        icon: PhosphorIconsBold.gitFork,
      ),
      ScreenConfig(
        appScreen: AppScreen.assetCategories,
        builder: (_) => const AssetCategoriesPicposScreen(),
        label: tr('فئات الأصول'),
        icon: PhosphorIconsBold.folders,
      ),
      ScreenConfig(
        appScreen: AppScreen.assetLocations,
        builder: (_) => const AssetLocationsPicposScreen(),
        label: tr('التوزيع والمواقع'),
        icon: PhosphorIconsBold.mapPin,
      ),
      ScreenConfig(
        appScreen: AppScreen.journalVoucher,
        builder: (_) => const JournalVoucherPicposScreen(),
        label: tr('سند قيد'),
        icon: PhosphorIconsBold.notePencil,
      ),
      ScreenConfig(
        appScreen: AppScreen.receiptVoucher,
        builder: (_) => const VoucherRecordsPicPosScreen(
          direction: VoucherDirection.receipt,
        ),
        label: tr('سند قبض'),
        icon: PhosphorIconsBold.arrowCircleDown,
      ),
      ScreenConfig(
        appScreen: AppScreen.paymentVoucher,
        builder: (_) => const VoucherRecordsPicPosScreen(
          direction: VoucherDirection.payment,
        ),
        label: tr('سند صرف'),
        icon: PhosphorIconsBold.arrowCircleUp,
      ),
      ScreenConfig(
        appScreen: AppScreen.chequeBooks,
        builder: (_) => const ChequeBooksPicposScreen(),
        label: tr('دفتر الشيكات'),
        icon: PhosphorIconsBold.checkSquareOffset,
      ),
      ScreenConfig(
        appScreen: AppScreen.importPurchases,
        builder: (_) => const ImportPurchasesPicposScreen(),
        label: tr('المشتريات الخارجية'),
        icon: PhosphorIconsBold.globeHemisphereEast,
      ),
      ScreenConfig(
        appScreen: AppScreen.floorPlanDesigner,
        builder: (_) => const FloorPlanDesignerPicposScreen(),
        label: tr('مصمم القاعة'),
        icon: PhosphorIconsBold.squaresFour,
      ),
      ScreenConfig(
        appScreen: AppScreen.syncConflicts,
        builder: (_) => const SyncConflictsScreen(),
        label: tr('تعارضات المزامنة'),
        icon: PhosphorIconsBold.arrowsClockwise,
      ),
      ScreenConfig(
        appScreen: AppScreen.auditDashboard,
        builder: (_) => const AuditDashboardScreen(),
        label: tr('لوحة التدقيق'),
        icon: PhosphorIconsBold.shieldCheck,
      ),
    ];
  }
}
