import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../domain/repositories/audit_repository_interface.dart';
import '../repositories/audit_repository_impl.dart';
import '../../domain/repositories/hr_repository_interface.dart';
import '../repositories/hr_repository_impl.dart';
import '../repositories/auth_repository_impl.dart';
import '../../domain/repositories/i_products_repository.dart';
import '../../domain/repositories/i_quotations_repository.dart';
import '../../domain/repositories/purchases_repository.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../../domain/repositories/activity_log_repository.dart';
import '../../domain/repositories/parties_repository.dart';
import '../repositories/drift_product_repository.dart';
import '../repositories/drift_quotations_repository.dart';
import '../repositories/region_repository_impl.dart';
import '../repositories/web_product_repository.dart';
import '../repositories/web_quotations_repository.dart';
import '../repositories/purchases_repository_impl.dart';
import '../repositories/inventory_repository_impl.dart';
import '../repositories/activity_log_repository_impl.dart';
import '../repositories/parties_repository_impl.dart';
import '../repositories/treasury_repository_impl.dart';
import '../repositories/reporting_repository_impl.dart';
import '../repositories/restaurant_repository_impl.dart';
import '../repositories/branch_repository_impl.dart';
import '../repositories/settings_repository_impl.dart';
import '../../domain/repositories/reporting_repository.dart';
import '../../domain/repositories/restaurant_repository.dart';
import '../../domain/repositories/branch_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/offers_repository.dart';
import '../../domain/repositories/printers_repository.dart';
import '../repositories/offers_repository_impl.dart';
import '../repositories/printers_repository_impl.dart';
import '../../domain/repositories/sales_repository.dart' as domain;
import '../../domain/repositories/returns_repository.dart';
import '../repositories/sales_repository_impl.dart';
import '../repositories/returns_repository_impl.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../repositories/drift_accounting_repository.dart';
import '../../domain/repositories/scale_repository.dart';
import '../repositories/drift_scale_repository.dart';
import '../../domain/repositories/purchase_orders_repository.dart';
import '../repositories/purchase_orders_repository_impl.dart';
import '../../domain/repositories/kitchen_repository.dart';
import '../repositories/kitchen_repository_impl.dart';
import '../../domain/repositories/manufacturing_repository.dart';
import '../repositories/manufacturing_repository_impl.dart';
import '../../domain/repositories/budget_repository.dart';
import '../repositories/drift_budget_repository.dart';
import '../../services/secure_storage_service.dart';
import '../repositories/drift_e_invoice_repository.dart';
import '../../domain/repositories/e_invoice_repository.dart';
export '../../domain/repositories/distribution_repository.dart';
import '../repositories/drift_distribution_repository.dart';
export '../../domain/repositories/notification_repository.dart';
import '../repositories/drift_notification_repository.dart';
export '../../domain/repositories/delivery_repository.dart';
import '../repositories/drift_delivery_repository.dart';
import '../../domain/repositories/i_sales_orders_repository.dart';
import '../repositories/drift_sales_orders_repository.dart';
import '../../domain/repositories/commercial_papers_repository.dart';
import '../repositories/commercial_papers_repository_impl.dart';
import '../../domain/repositories/cycle_count_repository.dart';
import '../repositories/cycle_count_repository_impl.dart';
import '../../domain/repositories/landed_cost_repository.dart';
import '../repositories/landed_cost_repository_impl.dart';
import '../../domain/repositories/fixed_assets_repository.dart';
import '../repositories/fixed_assets_repository_impl.dart';
import '../../domain/repositories/loyalty_repository.dart';
import '../repositories/loyalty_repository_impl.dart';
import '../../domain/repositories/invoice_templates_repository.dart';
import '../repositories/invoice_templates_repository_impl.dart';
import '../../domain/repositories/sync_repository.dart';
import '../repositories/sync_repository_impl.dart';
import '../../domain/repositories/modifier_repository.dart';
import '../repositories/modifier_repository_impl.dart';
import '../../domain/repositories/fingerprint_repository.dart';
import '../repositories/fingerprint_repository_impl.dart';
import 'providers.dart';

/// Provides the correct IProductRepository implementation based on the platform.
/// This allows the rest of the application to ignore whether it's running on Web or Desktop.
final productRepositoryProvider = Provider<IProductRepository>((ref) {
  final db = ref.watch(databaseProvider);
  if (kIsWeb) {
    return WebProductRepository(db);
  } else {
    return DriftProductRepository(db);
  }
});

/// HR Repository provider
final hrRepositoryProvider = Provider<IHRRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return HRRepositoryImpl(db);
});

/// Audit Repository provider
final auditRepositoryProvider = Provider<IAuditRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return AuditRepositoryImpl(db);
});

/// Quotations Repository provider
final quotationsRepositoryProvider = Provider<IQuotationsRepository>((ref) {
  final db = ref.watch(databaseProvider);
  if (kIsWeb) {
    return WebQuotationsRepository();
  } else {
    return DriftQuotationsRepository(db);
  }
});

/// Purchases Repository provider
final purchasesRepositoryProvider = Provider<PurchasesRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final accountingService = ref.watch(accountingServiceProvider);
  return PurchasesRepositoryImpl(db, accountingService);
});

/// Inventory Repository provider
final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return InventoryRepositoryImpl(db);
});

/// Activity Log Repository provider
final activityLogRepositoryProvider = Provider<IActivityLogRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return ActivityLogRepositoryImpl(db);
});

/// Parties Repository provider
final partiesRepositoryProvider = Provider<IPartiesRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return PartiesRepositoryImpl(db);
});

/// Treasury Repository provider
final treasuryRepositoryProvider = Provider<ITreasuryRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return TreasuryRepositoryImpl(db, ref);
});

/// Reporting Repository provider
final reportingRepositoryProvider = Provider<IReportingRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return ReportingRepositoryImpl(db);
});

/// Restaurant Repository provider
final restaurantRepositoryProvider = Provider<IRestaurantRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return RestaurantRepositoryImpl(db);
});

/// Branch Repository provider
final branchRepositoryProvider = Provider<IBranchRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return BranchRepositoryImpl(db);
});

/// Settings Repository provider
final settingsRepositoryProvider = Provider<ISettingsRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return SettingsRepositoryImpl(db);
});

/// Auth Repository provider
final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return AuthRepositoryImpl(db);
});

/// Offers Repository provider
final offersRepositoryProvider = Provider<IOffersRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return OffersRepositoryImpl(db);
});

/// Printers Repository provider
final printersRepositoryProvider = Provider<IPrintersRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return PrintersRepositoryImpl(db);
});



/// Sales Repository provider
final salesRepositoryProvider = Provider<domain.SalesRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final accountingService = ref.watch(accountingServiceProvider);
  return SalesRepositoryImpl(db, accountingService);
});

/// Returns Repository provider
final returnsRepositoryProvider = Provider<IReturnsRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final accountingService = ref.watch(accountingServiceProvider);
  return ReturnsRepositoryImpl(db, accountingService);
});

/// Accounting Repository provider
final accountingRepositoryProvider = Provider<IAccountingRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return DriftAccountingRepository(db);
});

final scaleRepositoryProvider = Provider<IScaleRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return DriftScaleRepository(db);
});

/// Purchase Orders Repository provider
final purchaseOrdersRepositoryProvider = Provider<PurchaseOrdersRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return PurchaseOrdersRepositoryImpl(db);
});

/// Kitchen Repository provider
final kitchenRepositoryProvider = Provider<KitchenRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return KitchenRepositoryImpl(db);
});

final manufacturingRepositoryProvider = Provider<ManufacturingRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return ManufacturingRepositoryImpl(db);
});

/// Budget Repository provider
final budgetRepositoryProvider = Provider<IBudgetRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return DriftBudgetRepository(db);
});

final eInvoiceRepositoryProvider = Provider<IEInvoiceRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final secureStorage = ref.watch(secureStorageServiceProvider);
  return DriftEInvoiceRepository(db, secureStorage);
});

/// Distribution Repository provider
final distributionRepositoryProvider = Provider<IDistributionRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return DriftDistributionRepository(db);
});

/// Notification Repository provider
final notificationRepositoryProvider = Provider<INotificationRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return DriftNotificationRepository(db);
});

/// Delivery Repository provider
final deliveryRepositoryProvider = Provider<IDeliveryRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return DriftDeliveryRepository(db);
});

/// Sales Orders Repository provider
final salesOrdersRepositoryProvider = Provider<ISalesOrdersRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return DriftSalesOrdersRepository(db);
});

/// Commercial Papers Repository provider
final commercialPapersRepositoryProvider = Provider<ICommercialPapersRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return CommercialPapersRepositoryImpl(db);
});

final cycleCountRepositoryProvider = Provider<ICycleCountRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return CycleCountRepositoryImpl(db);
});

final landedCostRepositoryProvider = Provider<ILandedCostRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return LandedCostRepositoryImpl(db);
});

final fixedAssetsRepositoryProvider = Provider<IFixedAssetsRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return FixedAssetsRepositoryImpl(db);
});

final loyaltyRepositoryProvider = Provider<ILoyaltyRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return LoyaltyRepositoryImpl(db);
});

final invoiceTemplatesRepositoryProvider = Provider<IInvoiceTemplatesRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return InvoiceTemplatesRepositoryImpl(db);
});

final syncRepositoryProvider = Provider<ISyncRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return SyncRepositoryImpl(db);
});

final modifierRepositoryProvider = Provider<IModifierRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return ModifierRepositoryImpl(db);
});

final fingerprintRepositoryProvider = Provider<IFingerprintRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final service = ref.watch(fingerprintServiceProvider);
  return FingerprintRepositoryImpl(db, service);
});

/// Region Repository provider
final regionRepositoryProvider = Provider<RegionRepository>((ref) {
  return RegionRepositoryImpl(ref.watch(databaseProvider));
});
