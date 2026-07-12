import '../config/business_profile.dart';
import 'screen_id.dart';

/// Central place for profile → screen visibility mapping.
class ScreenRegistry {
  static const List<ScreenId> restaurant = [
    ScreenId.dashboard,
    ScreenId.pos,
    ScreenId.tables,
    ScreenId.products,
    ScreenId.categories,
    ScreenId.parties,
    ScreenId.inventory,
    ScreenId.purchases,
    ScreenId.treasury,
    ScreenId.reports,
    ScreenId.settings,
    ScreenId.kitchen,
    ScreenId.analytics,
    ScreenId.salesInvoices,
    ScreenId.activityLog,
    ScreenId.eInvoice,
    ScreenId.inventoryBonds,
    ScreenId.stockTransfer,
    ScreenId.fieldAudit,
    ScreenId.users,
    ScreenId.rolesAndPermissions,
    ScreenId.auditTrail,
    ScreenId.shiftClose,
    ScreenId.taxReports,
    ScreenId.salesReturns,
    ScreenId.purchaseReturns,
  ];

  static const List<ScreenId> cafe = restaurant;

  static const List<ScreenId> supermarket = [
    ScreenId.dashboard,
    ScreenId.pos,
    ScreenId.offers,
    ScreenId.products,
    ScreenId.categories,
    ScreenId.parties,
    ScreenId.inventory,
    ScreenId.purchases,
    ScreenId.treasury,
    ScreenId.reports,
    ScreenId.settings,
    ScreenId.analytics,
    ScreenId.salesInvoices,
    ScreenId.activityLog,
    // NOTE: eInvoice intentionally excluded from the base supermarket flavor.
    // Pro/Plus retain it. Do not re-add without product-owner approval.
    ScreenId.inventoryBonds,
    ScreenId.stockTransfer,
    ScreenId.scalePlu,
    ScreenId.fieldAudit,
    ScreenId.users,
    ScreenId.rolesAndPermissions,
    ScreenId.auditTrail,
    ScreenId.shiftClose,
    ScreenId.taxReports,
    ScreenId.fiscalYear,
    ScreenId.salesReturns,
    ScreenId.purchaseReturns,
  ];

  /// Supermarket + HR module (no tables/kitchen)
  static const List<ScreenId> supermarketPro = [
    ScreenId.dashboard,
    ScreenId.pos,
    ScreenId.offers,
    ScreenId.products,
    ScreenId.categories,
    ScreenId.parties,
    ScreenId.inventory,
    ScreenId.purchases,
    ScreenId.treasury,
    ScreenId.reports,
    ScreenId.settings,
    ScreenId.analytics,
    ScreenId.hr,
    ScreenId.salesInvoices,
    ScreenId.activityLog,
    ScreenId.eInvoice,
    ScreenId.inventoryBonds,
    ScreenId.loyalty,
    ScreenId.stockTransfer,
    ScreenId.scalePlu,
    ScreenId.fieldAudit,
    ScreenId.users,
    ScreenId.rolesAndPermissions,
    ScreenId.auditTrail,
    ScreenId.shiftClose,
    ScreenId.taxReports,
    ScreenId.fiscalYear,
    ScreenId.salesReturns,
    ScreenId.purchaseReturns,
  ];

  /// Supermarket + Restaurant features (tables, kitchen, delivery) + HR
  static const List<ScreenId> supermarketPlus = [
    ScreenId.dashboard,
    ScreenId.pos,
    ScreenId.offers,
    ScreenId.tables,
    ScreenId.products,
    ScreenId.categories,
    ScreenId.parties,
    ScreenId.inventory,
    ScreenId.purchases,
    ScreenId.treasury,
    ScreenId.reports,
    ScreenId.settings,
    ScreenId.kitchen,
    ScreenId.analytics,
    ScreenId.hr,
    ScreenId.salesInvoices,
    ScreenId.activityLog,
    ScreenId.eInvoice,
    ScreenId.inventoryBonds,
    ScreenId.loyalty,
    ScreenId.stockTransfer,
    ScreenId.scalePlu,
    ScreenId.fieldAudit,
    ScreenId.users,
    ScreenId.rolesAndPermissions,
    ScreenId.auditTrail,
    ScreenId.shiftClose,
    ScreenId.taxReports,
    ScreenId.fiscalYear,
    ScreenId.salesReturns,
    ScreenId.purchaseReturns,
  ];

  static const List<ScreenId> commercial = [
    ScreenId.dashboard,
    ScreenId.salesInvoices,
    ScreenId.products,
    ScreenId.categories,
    ScreenId.parties,
    ScreenId.inventory,
    ScreenId.purchases,
    ScreenId.treasury,
    ScreenId.reports,
    ScreenId.settings,
    ScreenId.branches,
    ScreenId.regions,
    ScreenId.analytics,
    ScreenId.hr,
    ScreenId.activityLog,
    ScreenId.eInvoice,
    ScreenId.inventoryBonds,
    ScreenId.stockTransfer,
    ScreenId.scalePlu,
    ScreenId.distribution,
    ScreenId.manufacturing,
    ScreenId.fieldAudit,
    ScreenId.users,
    ScreenId.rolesAndPermissions,
    ScreenId.auditTrail,
    ScreenId.pricingRules,
    ScreenId.shiftClose,
    ScreenId.taxReports,
    ScreenId.salesReturns,
    ScreenId.purchaseReturns,
  ];

  static const List<ScreenId> unified = [
    ScreenId.dashboard,
    ScreenId.pos,
    ScreenId.offers,
    ScreenId.tables,
    ScreenId.products,
    ScreenId.categories,
    ScreenId.parties,
    ScreenId.inventory,
    ScreenId.purchases,
    ScreenId.treasury,
    ScreenId.reports,
    ScreenId.settings,
    ScreenId.branches,
    ScreenId.regions,
    ScreenId.kitchen,
    ScreenId.analytics,
    ScreenId.hr,
    ScreenId.salesInvoices,
    ScreenId.activityLog,
    ScreenId.eInvoice,
    ScreenId.inventoryBonds,
    ScreenId.loyalty,
    ScreenId.stockTransfer,
    ScreenId.scalePlu,
    ScreenId.distribution,
    ScreenId.manufacturing,
    ScreenId.operationalExpenses,
    ScreenId.chartOfAccounts,
    ScreenId.fiscalYear,
    ScreenId.stockMovements,
    ScreenId.purchaseOrders,
    ScreenId.accountMapping,
    ScreenId.journalEntries,
    ScreenId.costCenters,
    ScreenId.commercialPapers,
    ScreenId.fixedAssets,
    ScreenId.generalLedger,
    ScreenId.salesOrders,
    ScreenId.stockRequisitions,
    ScreenId.branchPerformance,
    ScreenId.helpCenter,
    ScreenId.landedCost,
    ScreenId.cycleCounting,
    ScreenId.reportBuilder,
    ScreenId.salesReturns,
    ScreenId.purchaseReturns,
  ];

  static List<ScreenId> forProfile(BusinessProfile profile) {
    switch (profile) {
      case BusinessProfile.restaurant:
        return restaurant;
      case BusinessProfile.cafe:
        return cafe;
      case BusinessProfile.supermarket:
        return supermarket;
      case BusinessProfile.supermarketPro:
        return supermarketPro;
      case BusinessProfile.supermarketPlus:
        return supermarketPlus;
      case BusinessProfile.commercial:
        return commercial;
      case BusinessProfile.unified:
        return unified;
    }
  }
}
