// نطاق شاشات الويب (م3-8): أيُّ `ScreenId` يدخل نسخة الويب.
//
// القرار (docs/superpowers/specs/2026-09-01-saas-web-design.md):
//   * مشمولة: لوحة التحكم والمبيعات والمشتريات والمخزون والخزينة والأطراف
//     والمحاسبة والتقارير والإعدادات... وإضافةً: طلبات البيع/الشراء وعروض
//     الأسعار والعروض والفروع والمناطق والمشتريات الخارجية.
//   * مؤجّلة (خارج النطاق الآن): الموارد البشرية والتصنيع والتوزيع.
//   * مستبعدة: POS والطاولات والمطبخ والميزان/PLU وإغلاق الوردية ومصمّم القاعة
//     والحجوزات وطباعة القوالب.
//
// «مشمولة» لا تعني «مترجَمة»: ما لا يُترجَم للويب (يسحب POS بالاستيراد) يُعرض
// «قريبًا» — انظر `web_screen_registry.dart`.
//
// الأسماء مأخوذة من `lib/core/navigation/screen_id.dart` كما هي.
import '../core/navigation/screen_id.dart';

/// الشاشات المشمولة في نسخة الويب. يُقطع بها `AppConfig.allowedScreenIds`
/// عند `kIsWeb`.
const Set<ScreenId> kWebScreenIds = {
  ScreenId.dashboard,
  // المبيعات
  ScreenId.salesInvoices,
  ScreenId.salesReturns,
  ScreenId.salesOrders,
  ScreenId.quotations,
  ScreenId.offers,
  // المشتريات
  ScreenId.purchases,
  ScreenId.purchaseReturns,
  ScreenId.purchaseOrders,
  ScreenId.importPurchases,
  ScreenId.landedCost,
  // الأصناف والمخزون
  ScreenId.products,
  ScreenId.categories,
  ScreenId.inventory,
  ScreenId.inventoryBonds,
  ScreenId.stockTransfer,
  ScreenId.cycleCounting,
  // `fieldAudit` اسمٌ بديلٌ لنفس الفهرس (42): سجلّاتُ الملفّات تذكره في بعض
  // النطاقات (restaurant/supermarket/…) فبدونه يسقط الجردُ منها.
  ScreenId.fieldAudit,
  // العملاء والموردون
  ScreenId.parties,
  ScreenId.customers,
  ScreenId.suppliers,
  // الإدارة المالية
  ScreenId.treasury,
  ScreenId.receiptVoucher,
  ScreenId.paymentVoucher,
  ScreenId.chequeBooks,
  ScreenId.commercialPapers,
  ScreenId.operationalExpenses,
  ScreenId.fixedAssets,
  ScreenId.assetCategories,
  ScreenId.assetLocations,
  ScreenId.eInvoice,
  // إدارة الحسابات
  ScreenId.chartOfAccounts,
  ScreenId.journalEntries,
  ScreenId.journalVoucher,
  ScreenId.generalLedger,
  ScreenId.costCenters,
  ScreenId.accountMapping,
  ScreenId.fiscalYear,
  ScreenId.trialBalance,
  ScreenId.financialStatements,
  ScreenId.bankReconciliation,
  ScreenId.journalTemplates,
  // التقارير
  ScreenId.reports,
  ScreenId.reportBuilder,
  ScreenId.analytics,
  // النظام
  ScreenId.users,
  ScreenId.settings,
  ScreenId.activityLog,
  ScreenId.branches,
  ScreenId.regions,
};

/// مؤجَّلة: خارج نطاق الويب الآن (تُضاف لاحقاً).
const Set<ScreenId> kWebDeferredScreenIds = {
  ScreenId.hr,
  ScreenId.hrEmployees,
  ScreenId.hrOrganization,
  ScreenId.hrAttendance,
  ScreenId.hrLeave,
  ScreenId.hrShifts,
  ScreenId.hrPayroll,
  ScreenId.hrAdvances,
  ScreenId.hrCommissions,
  ScreenId.financialIndicators,
  ScreenId.payroll,
  ScreenId.attendance,
  ScreenId.manufacturing,
  ScreenId.distribution,
  ScreenId.repDistribution,
};

/// مستبعدة من الويب بقرار: لا تدخل الاستيراد ولا القائمة.
const Set<ScreenId> kWebExcludedScreenIds = {
  ScreenId.pos,
  ScreenId.tables,
  ScreenId.kitchen,
  ScreenId.scalePlu,
  ScreenId.pluManager,
  ScreenId.shiftClose,
  ScreenId.floorPlanDesigner,
  ScreenId.bookings,
  ScreenId.templateResolution,
};
