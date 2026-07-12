// ═══════════════════════════════════════════════════════════════════════════
// I-05: Reorder Point & Auto-Requisition Service
// Monitors stock levels and generates purchase requisitions when min stock hit
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Represents a product that needs reordering
class ReorderAlert {
  final int productId;
  final String productName;
  final double currentStock;
  final double minStock;
  final double reorderQty;
  final String? supplierName;
  final int? supplierId;
  final DateTime detectedAt;

  const ReorderAlert({
    required this.productId,
    required this.productName,
    required this.currentStock,
    required this.minStock,
    required this.reorderQty,
    this.supplierName,
    this.supplierId,
    required this.detectedAt,
  });

  double get deficit => minStock - currentStock;
  bool get isCritical => currentStock <= 0;
  bool get isWarning => currentStock > 0 && currentStock <= minStock;
}

/// Service to check reorder points and generate alerts
class ReorderPointService {
  /// Check all products and return those below minimum stock
  /// [products] should be a list of maps with keys: id, name, currentStock, minStock, reorderQty, supplierName, supplierId
  static List<ReorderAlert> checkReorderPoints(List<Map<String, dynamic>> products) {
    final alerts = <ReorderAlert>[];

    for (final p in products) {
      final current = (p['currentStock'] as num?)?.toDouble() ?? 0;
      final min = (p['minStock'] as num?)?.toDouble() ?? 0;
      
      if (min > 0 && current <= min) {
        alerts.add(ReorderAlert(
          productId: p['id'] as int,
          productName: p['name'] as String,
          currentStock: current,
          minStock: min,
          reorderQty: (p['reorderQty'] as num?)?.toDouble() ?? (min * 2),
          supplierName: p['supplierName'] as String?,
          supplierId: p['supplierId'] as int?,
          detectedAt: DateTime.now(),
        ));
      }
    }

    // Sort: critical (zero stock) first, then by deficit ratio
    alerts.sort((a, b) {
      if (a.isCritical && !b.isCritical) return -1;
      if (!a.isCritical && b.isCritical) return 1;
      return (a.currentStock / a.minStock).compareTo(b.currentStock / b.minStock);
    });

    return alerts;
  }
}

/// Widget to display reorder alerts
class ReorderAlertsBanner extends StatelessWidget {
  final List<ReorderAlert> alerts;
  final VoidCallback? onViewAll;

  const ReorderAlertsBanner({super.key, required this.alerts, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();

    final criticalCount = alerts.where((a) => a.isCritical).length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: criticalCount > 0 ? Colors.red.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: criticalCount > 0 ? Colors.red.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            PhosphorIconsBold.warningDiamond,
            color: criticalCount > 0 ? Colors.red : Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${alerts.length} صنف وصل الحد الأدنى',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: criticalCount > 0 ? Colors.red.shade700 : Colors.orange.shade800,
                  ),
                ),
                if (criticalCount > 0)
                  Text(
                    '$criticalCount صنف نفد من المخزون',
                    style: GoogleFonts.cairo(fontSize: 10, color: Colors.red),
                  ),
              ],
            ),
          ),
          if (onViewAll != null)
            TextButton(
              onPressed: onViewAll,
              child: Text('عرض الكل', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}
