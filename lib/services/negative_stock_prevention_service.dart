// ═══════════════════════════════════════════════════════════════════════════
// I-01: Global Negative Stock Prevention Service
// System-wide toggle to prevent all products from going negative
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/providers/providers.dart';

/// System-wide constant key for negative stock prevention
const kGlobalNegativeStockPreventionKey = 'global_prevent_negative_stock';

/// Service to check and enforce the global negative stock toggle
class NegativeStockPreventionService {

  /// Check if stock should be blocked for a given product+quantity combination
  /// Returns null if OK, or an error message if blocked.
  static Future<String?> checkStock({
    required double currentStock,
    required double requestedQty,
    required bool productAllowsNegative,
    required bool globalPreventionEnabled,
    required String productName,
  }) async {
    // Global override takes precedence over per-product setting
    if (globalPreventionEnabled && !productAllowsNegative) {
      if (currentStock < requestedQty) {
        return 'الكمية المطلوبة ($requestedQty) من "$productName" '
            'تتجاوز الرصيد المتاح ($currentStock). '
            'منع البيع بالسالب مفعل على مستوى النظام.';
      }
    }
    return null;
  }
}

/// Provider that reads the global toggle from settings
final globalNegativeStockPreventionProvider = FutureProvider<bool>((ref) async {
  final settings = ref.watch(settingsRepositoryProvider);
  final value = await settings.getSetting(kGlobalNegativeStockPreventionKey);
  return value == 'true';
});
