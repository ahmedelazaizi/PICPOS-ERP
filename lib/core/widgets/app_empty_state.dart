import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../theme/app_colors.dart';

/// A professional empty state widget with icon, title, description and optional action button.
/// Use this across all screens when data lists are empty.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double iconSize;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.iconSize = 64,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated icon container
            Container(
              width: iconSize + 40,
              height: iconSize + 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.08),
                    AppColors.primary.withValues(alpha: 0.03),
                  ],
                ),
              ),
              child: Icon(
                icon,
                size: iconSize,
                color: AppColors.primary.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                description!,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(PhosphorIconsBold.plus, size: 18),
                label: Text(actionLabel!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Factory constructors for common scenarios ─────────────────────

  /// Empty products list
  factory AppEmptyState.products({VoidCallback? onAdd}) => AppEmptyState(
    icon: PhosphorIconsBold.package,
    title: 'لا توجد منتجات',
    description: 'أضف أول منتج للبدء في البيع',
    actionLabel: onAdd != null ? 'إضافة منتج' : null,
    onAction: onAdd,
  );

  /// Empty customers/parties list
  factory AppEmptyState.customers({VoidCallback? onAdd}) => AppEmptyState(
    icon: PhosphorIconsBold.users,
    title: 'لا يوجد عملاء',
    description: 'أضف أول عميل للبدء',
    actionLabel: onAdd != null ? 'إضافة عميل' : null,
    onAction: onAdd,
  );

  /// Empty suppliers list
  factory AppEmptyState.suppliers({VoidCallback? onAdd}) => AppEmptyState(
    icon: PhosphorIconsBold.truck,
    title: 'لا يوجد موردين',
    description: 'أضف أول مورد لتتبع المشتريات',
    actionLabel: onAdd != null ? 'إضافة مورد' : null,
    onAction: onAdd,
  );

  /// Empty invoices/orders
  factory AppEmptyState.invoices() => const AppEmptyState(
    icon: PhosphorIconsBold.receipt,
    title: 'لا توجد فواتير',
    description: 'ستظهر الفواتير هنا بعد إتمام أول عملية بيع',
  );

  /// No data for selected period
  factory AppEmptyState.noData() => const AppEmptyState(
    icon: PhosphorIconsBold.chartBar,
    title: 'لا توجد بيانات لهذه الفترة',
    description: 'جرب تغيير نطاق التاريخ',
  );

  /// Empty held orders
  factory AppEmptyState.heldOrders() => const AppEmptyState(
    icon: PhosphorIconsBold.clockCounterClockwise,
    title: 'لا توجد طلبات معلقة',
    iconSize: 48,
  );
}
