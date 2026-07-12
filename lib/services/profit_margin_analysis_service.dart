// ═══════════════════════════════════════════════════════════════════════════
// F-08: Profit Margin Analysis per Invoice Line
// Calculates and displays profit margins at the line-item level
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../core/theme/app_colors.dart';

final _currFmt = NumberFormat('#,##0.00');
final _pctFmt = NumberFormat('#,##0.0');

/// Profit analysis for a single invoice line
class LineProfitAnalysis {
  final String productName;
  final double quantity;
  final double sellingPrice;
  final double costPrice;
  final double lineTotal;
  final double lineCost;

  const LineProfitAnalysis({
    required this.productName,
    required this.quantity,
    required this.sellingPrice,
    required this.costPrice,
    required this.lineTotal,
    required this.lineCost,
  });

  double get lineProfit => lineTotal - lineCost;
  double get marginPercent => lineTotal > 0 ? (lineProfit / lineTotal * 100) : 0;
  double get markupPercent => lineCost > 0 ? (lineProfit / lineCost * 100) : 0;

  bool get isLoss => lineProfit < 0;
  bool get isLowMargin => marginPercent >= 0 && marginPercent < 10;
}

/// Aggregate profit analysis for an entire invoice
class InvoiceProfitAnalysis {
  final List<LineProfitAnalysis> lines;

  const InvoiceProfitAnalysis({required this.lines});

  double get totalRevenue => lines.fold(0, (sum, l) => sum + l.lineTotal);
  double get totalCost => lines.fold(0, (sum, l) => sum + l.lineCost);
  double get totalProfit => totalRevenue - totalCost;
  double get overallMargin => totalRevenue > 0 ? (totalProfit / totalRevenue * 100) : 0;
  int get lossItems => lines.where((l) => l.isLoss).length;
  int get lowMarginItems => lines.where((l) => l.isLowMargin).length;
}

/// Widget to display profit margin analysis
class ProfitMarginAnalysisWidget extends StatelessWidget {
  final InvoiceProfitAnalysis analysis;
  final String currencySymbol;

  const ProfitMarginAnalysisWidget({
    super.key,
    required this.analysis,
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
            // Header with overall margin
            Row(
              children: [
                Text('تحليل هوامش الربح',
                    style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _marginColor(analysis.overallMargin).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_pctFmt.format(analysis.overallMargin)}%',
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _marginColor(analysis.overallMargin),
                    ),
                  ),
                ),
              ],
            ),
            if (analysis.lossItems > 0 || analysis.lowMarginItems > 0) ...[
              const SizedBox(height: 8),
              if (analysis.lossItems > 0)
                Text(
                  '⛔ ${analysis.lossItems} صنف بخسارة',
                  style: GoogleFonts.cairo(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600),
                ),
              if (analysis.lowMarginItems > 0)
                Text(
                  '⚠️ ${analysis.lowMarginItems} صنف بهامش منخفض (<10%)',
                  style: GoogleFonts.cairo(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600),
                ),
            ],
            const SizedBox(height: 12),
            // Summary row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _summaryCol('إيرادات', analysis.totalRevenue, AppColors.primary),
                _summaryCol('تكلفة', analysis.totalCost, AppColors.textMuted),
                _summaryCol('ربح', analysis.totalProfit,
                    analysis.totalProfit >= 0 ? AppColors.success : AppColors.error),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            // Per-line details
            ...analysis.lines.map((line) => _lineRow(line)),
          ],
        ),
      ),
    );
  }

  Widget _summaryCol(String label, double value, Color color) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.cairo(fontSize: 10, color: AppColors.textMuted)),
        Text('$currencySymbol ${_currFmt.format(value)}',
            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }

  Widget _lineRow(LineProfitAnalysis line) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(line.productName,
                style: GoogleFonts.cairo(fontSize: 11), overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: Text(
              '${_pctFmt.format(line.marginPercent)}%',
              style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _marginColor(line.marginPercent),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '$currencySymbol ${_currFmt.format(line.lineProfit)}',
              style: GoogleFonts.cairo(
                fontSize: 11,
                color: line.isLoss ? Colors.red : AppColors.success,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Color _marginColor(double margin) {
    if (margin < 0) return Colors.red;
    if (margin < 10) return Colors.orange;
    if (margin < 20) return Colors.amber;
    return AppColors.success;
  }
}
