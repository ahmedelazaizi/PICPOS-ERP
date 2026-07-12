// ═══════════════════════════════════════════════════════════════════════════
// Dashboard Aging & KPI Widgets (U-13, U-14, U-15, U-16)
// AR Aging, AP Aging, Cash Flow Forecast, Slow-Moving Items
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';

final _fmt = NumberFormat('#,##0.00');

/// Aging bucket data for AR/AP
class AgingBucket {
  final String label; // e.g. "0-30 يوم"
  final double amount;
  final int count;
  final Color color;

  const AgingBucket({
    required this.label,
    required this.amount,
    required this.count,
    required this.color,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// U-13: Accounts Receivable Aging Widget
// ═══════════════════════════════════════════════════════════════════════════

class ARAgingWidget extends StatelessWidget {
  final List<AgingBucket> buckets;
  final double totalOutstanding;
  final String currencySymbol;

  const ARAgingWidget({
    super.key,
    required this.buckets,
    required this.totalOutstanding,
    this.currencySymbol = '',
  });

  @override
  Widget build(BuildContext context) {
    return _AgingCard(
      title: 'أعمار الذمم المدينة',
      icon: PhosphorIconsBold.usersThree,
      iconColor: AppColors.warning,
      buckets: buckets,
      total: totalOutstanding,
      totalLabel: 'إجمالي المديونية',
      currencySymbol: currencySymbol,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// U-14: Accounts Payable Aging Widget
// ═══════════════════════════════════════════════════════════════════════════

class APAgingWidget extends StatelessWidget {
  final List<AgingBucket> buckets;
  final double totalPayable;
  final String currencySymbol;

  const APAgingWidget({
    super.key,
    required this.buckets,
    required this.totalPayable,
    this.currencySymbol = '',
  });

  @override
  Widget build(BuildContext context) {
    return _AgingCard(
      title: 'أعمار الذمم الدائنة',
      icon: PhosphorIconsBold.storefront,
      iconColor: AppColors.info,
      buckets: buckets,
      total: totalPayable,
      totalLabel: 'إجمالي المستحقات',
      currencySymbol: currencySymbol,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// U-15: Cash Flow Forecast Widget
// ═══════════════════════════════════════════════════════════════════════════

class CashFlowForecastWidget extends StatelessWidget {
  final double currentCash;
  final double projectedIncome30;
  final double projectedExpenses30;
  final String currencySymbol;

  const CashFlowForecastWidget({
    super.key,
    required this.currentCash,
    required this.projectedIncome30,
    required this.projectedExpenses30,
    this.currencySymbol = '',
  });

  @override
  Widget build(BuildContext context) {
    final forecast = currentCash + projectedIncome30 - projectedExpenses30;
    final isPositive = forecast >= 0;

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
                const Icon(PhosphorIconsBold.chartLine, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text('توقعات التدفق النقدي', style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('30 يوم', style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
            const SizedBox(height: 16),
            _flowRow('الرصيد الحالي', currentCash, AppColors.primary),
            _flowRow('+ إيرادات متوقعة', projectedIncome30, AppColors.success),
            _flowRow('- مصروفات متوقعة', projectedExpenses30, AppColors.error),
            const Divider(height: 16),
            _flowRow(
              'الرصيد المتوقع',
              forecast,
              isPositive ? AppColors.success : AppColors.error,
              isBold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _flowRow(String label, double amount, Color color, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted)),
          Text(
            '$currencySymbol ${_fmt.format(amount)}',
            style: GoogleFonts.cairo(
              fontSize: isBold ? 14 : 12,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// U-16: Top 10 Slow-Moving Items Widget
// ═══════════════════════════════════════════════════════════════════════════

class SlowMovingItem {
  final String name;
  final int daysSinceLastSale;
  final double currentStock;
  final double stockValue;

  const SlowMovingItem({
    required this.name,
    required this.daysSinceLastSale,
    required this.currentStock,
    required this.stockValue,
  });
}

class SlowMovingItemsWidget extends StatelessWidget {
  final List<SlowMovingItem> items;
  final String currencySymbol;

  const SlowMovingItemsWidget({
    super.key,
    required this.items,
    this.currencySymbol = '',
  });

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
                const Icon(PhosphorIconsBold.hourglass, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'أصناف بطيئة الحركة',
                    style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  'أعلى ${items.length}',
                  style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Center(
                child: Text(
                  'لا توجد أصناف بطيئة الحركة',
                  style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted),
                ),
              )
            else
              ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        item.name,
                        style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${item.daysSinceLastSale}d',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: item.daysSinceLastSale > 90 ? Colors.red : Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item.currentStock.toStringAsFixed(0),
                        style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '$currencySymbol ${_fmt.format(item.stockValue)}',
                        style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              )),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Shared Aging Card Widget
// ═══════════════════════════════════════════════════════════════════════════

class _AgingCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<AgingBucket> buckets;
  final double total;
  final String totalLabel;
  final String currencySymbol;

  const _AgingCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.buckets,
    required this.total,
    required this.totalLabel,
    required this.currencySymbol,
  });

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
            // Header
            Row(
              children: [
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 8),
                Text(title, style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            // Aging bars
            ...buckets.map((b) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(b.label, style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
                      Text(
                        '$currencySymbol ${_fmt.format(b.amount)} (${b.count})',
                        style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: total > 0 ? b.amount / total : 0,
                      backgroundColor: AppColors.border.withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation(b.color),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            )),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(totalLabel, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600)),
                Text(
                  '$currencySymbol ${_fmt.format(total)}',
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
