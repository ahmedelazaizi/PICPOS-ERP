import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Payment status types for invoices
enum PaymentStatus { paid, partial, pending }

/// Stock status types for inventory
enum StockStatus { available, low, outOfStock }

/// Reusable status badge widget
/// Used for invoice payment status and inventory stock status
class StatusBadge extends StatelessWidget {
  final String text;
  final Color color;

  const StatusBadge({super.key, required this.text, required this.color});

  /// Create badge from payment status
  factory StatusBadge.fromPaymentStatus(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.paid:
        return const StatusBadge(text: 'مدفوع', color: AppColors.success);
      case PaymentStatus.partial:
        return const StatusBadge(text: 'جزئي', color: AppColors.warning);
      case PaymentStatus.pending:
        return const StatusBadge(text: 'معلق', color: AppColors.error);
    }
  }

  /// Create badge from payment status string
  factory StatusBadge.fromPaymentStatusString(String status) {
    switch (status) {
      case 'paid':
        return const StatusBadge(text: 'مدفوع', color: AppColors.success);
      case 'partial':
        return const StatusBadge(text: 'جزئي', color: AppColors.warning);
      default:
        return const StatusBadge(text: 'معلق', color: AppColors.error);
    }
  }

  /// Create badge from stock status
  factory StatusBadge.fromStockStatus(StockStatus status) {
    switch (status) {
      case StockStatus.available:
        return const StatusBadge(text: 'متوفر', color: AppColors.success);
      case StockStatus.low:
        return const StatusBadge(text: 'منخفض', color: AppColors.warning);
      case StockStatus.outOfStock:
        return const StatusBadge(text: 'نفذ', color: AppColors.error);
    }
  }

  /// Create badge for stock based on current and minimum values
  factory StatusBadge.forStock({
    required double currentStock,
    required double minStock,
  }) {
    if (currentStock <= 0) {
      return StatusBadge.fromStockStatus(StockStatus.outOfStock);
    } else if (currentStock <= minStock) {
      return StatusBadge.fromStockStatus(StockStatus.low);
    } else {
      return StatusBadge.fromStockStatus(StockStatus.available);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
