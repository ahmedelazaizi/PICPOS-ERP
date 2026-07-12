import '../core/utils/financial_utils.dart';
import '../domain/repositories/settings_repository.dart';

/// ───────────────────────────────────────────────────────────────────
/// Costing Method Service
/// ───────────────────────────────────────────────────────────────────
/// Controls how product cost price is calculated on purchase receipt:
/// - lastPurchase: Cost = latest purchase unit cost (default)
/// - weightedAverage: Cost = (old_qty × old_cost + new_qty × new_cost) / total_qty
///
/// Stored in the app settings table under 'costing_method' (P1-02: migrated
/// from SharedPreferences to the encrypted SQLite settings table so the value
/// travels with database backups and is consistent with all other settings).

enum CostingMethod {
  lastPurchase,      // آخر سعر شراء (default)
  weightedAverage,   // متوسط مرجح (WAC)
}

class CostingMethodService {
  static const _key = 'costing_method';

  static Future<CostingMethod> load(ISettingsRepository settings) async {
    final value = await settings.getSetting(_key) ?? 'lastPurchase';
    return value == 'weightedAverage'
        ? CostingMethod.weightedAverage
        : CostingMethod.lastPurchase;
  }

  static Future<void> save(ISettingsRepository settings, CostingMethod method) async {
    await settings.saveSetting(_key, method.name);
  }

  /// Calculate the new cost price based on the selected method.
  ///
  /// [currentStock] — existing quantity on hand
  /// [currentCost] — existing cost price per unit
  /// [purchaseQty] — new quantity being purchased
  /// [purchaseUnitCost] — unit cost of the new purchase
  static double calculateCost({
    required CostingMethod method,
    required double currentStock,
    required double currentCost,
    required double purchaseQty,
    required double purchaseUnitCost,
  }) {
    switch (method) {
      case CostingMethod.lastPurchase:
        return purchaseUnitCost;
      case CostingMethod.weightedAverage:
        final totalQty = currentStock + purchaseQty;
        if (totalQty <= 0) return purchaseUnitCost;
        // WAC = (existing_value + new_value) / total_qty
        // BUG-M04: round to financial precision (3dp) at write time so the
        // stored cost has no long float tail that drifts COGS/margin reports.
        final existingValue = currentStock * currentCost;
        final newValue = purchaseQty * purchaseUnitCost;
        return FinancialUtils.round((existingValue + newValue) / totalQty);
    }
  }

  /// Human-readable label
  static String label(CostingMethod method) {
    switch (method) {
      case CostingMethod.lastPurchase:
        return 'آخر سعر شراء';
      case CostingMethod.weightedAverage:
        return 'متوسط مرجح (WAC)';
    }
  }
}
