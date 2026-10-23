import 'package:picpos_erp/core/i18n/tr.dart';
// ═══════════════════════════════════════════════════════════════════════════
// I-03: Inventory Aging Report
// Shows inventory items grouped by purchase age
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';

final _currFmt = NumberFormat('#,##0.00');

/// Aging bucket for inventory
class InventoryAgingItem {
  final int productId;
  final String productName;
  final String? category;
  final double quantity;
  final double costPrice;
  final double totalValue;
  final DateTime? lastPurchaseDate;
  final int ageInDays;

  const InventoryAgingItem({
    required this.productId,
    required this.productName,
    this.category,
    required this.quantity,
    required this.costPrice,
    required this.totalValue,
    this.lastPurchaseDate,
    required this.ageInDays,
  });

  String get ageBucket {
    if (ageInDays <= 30) return tr('0-30 يوم');
    if (ageInDays <= 60) return tr('31-60 يوم');
    if (ageInDays <= 90) return tr('61-90 يوم');
    if (ageInDays <= 180) return tr('91-180 يوم');
    if (ageInDays <= 365) return tr('181-365 يوم');
    return tr('+365 يوم');
  }

  Color get ageColor {
    if (ageInDays <= 30) return AppColors.success;
    if (ageInDays <= 60) return Colors.lightGreen;
    if (ageInDays <= 90) return Colors.amber;
    if (ageInDays <= 180) return Colors.orange;
    if (ageInDays <= 365) return Colors.deepOrange;
    return AppColors.error;
  }
}

/// Inventory Aging Summary
class InventoryAgingSummary {
  final Map<String, List<InventoryAgingItem>> buckets;
  final double totalValue;
  final int totalItems;

  InventoryAgingSummary({required List<InventoryAgingItem> items})
      : buckets = _groupByAge(items),
        totalValue = items.fold(0, (sum, i) => sum + i.totalValue),
        totalItems = items.length;

  static Map<String, List<InventoryAgingItem>> _groupByAge(List<InventoryAgingItem> items) {
    final map = <String, List<InventoryAgingItem>>{};
    for (final item in items) {
      (map[item.ageBucket] ??= []).add(item);
    }
    return map;
  }

  double valueForBucket(String bucket) =>
      (buckets[bucket] ?? []).fold(0.0, (sum, i) => sum + i.totalValue);
}

/// Widget to display inventory aging report
class InventoryAgingReportWidget extends StatelessWidget {
  final InventoryAgingSummary summary;
  final String currencySymbol;

  const InventoryAgingReportWidget({
    super.key,
    required this.summary,
    this.currencySymbol = '',
  });

  static List<String> get _bucketOrder => [
    tr('0-30 يوم'),
    tr('31-60 يوم'),
    tr('61-90 يوم'),
    tr('91-180 يوم'),
    tr('181-365 يوم'),
    tr('+365 يوم'),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(PhosphorIconsBold.clockCounterClockwise, color: AppColors.warning, size: 20),
                const SizedBox(width: 8),
                Text(tr('تقرير أعمار المخزون'),
                    style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(tr('{p0} صنف', {'p0': summary.totalItems}),
                    style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
            const SizedBox(height: 16),
            ..._bucketOrder.map((bucket) {
              final items = summary.buckets[bucket] ?? [];
              final value = summary.valueForBucket(bucket);
              final pct = summary.totalValue > 0 ? (value / summary.totalValue * 100) : 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(bucket, style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: pct / 100,
                          backgroundColor: AppColors.border.withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation(
                            items.isNotEmpty ? items.first.ageColor : Colors.grey,
                          ),
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      child: Text(
                        '$currencySymbol ${_currFmt.format(value)}',
                        style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.end,
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${pct.toStringAsFixed(0)}%',
                        style: GoogleFonts.cairo(fontSize: 10, color: AppColors.textMuted),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(tr('القيمة الإجمالية'), style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600)),
                Text(
                  '$currencySymbol ${_currFmt.format(summary.totalValue)}',
                  style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
