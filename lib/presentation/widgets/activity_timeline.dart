import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../data/database/database.dart';
import '../../../../../core/constants/app_constants.dart';

/// Timeline View Widget for Activity Logs
/// Displays activities in a vertical timeline format with connecting lines
class ActivityTimeline extends StatelessWidget {
  final List<ActivityLog> logs;
  final Function(ActivityLog) onTap;
  final Map<String, String> actionLabels;
  final Map<String, String> entityLabels;

  const ActivityTimeline({
    super.key,
    required this.logs,
    required this.onTap,
    required this.actionLabels,
    required this.entityLabels,
  });

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return  Center(
        child: Text(
          tr('لا توجد عمليات مسجلة'),
          style: const TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    // Group logs by date
    final groupedLogs = <String, List<ActivityLog>>{};
    for (final log in logs) {
      final dateKey =
          '${log.createdAt.day}/${log.createdAt.month}/${log.createdAt.year}';
      groupedLogs.putIfAbsent(dateKey, () => []).add(log);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groupedLogs.length,
      itemBuilder: (context, groupIndex) {
        final dateKey = groupedLogs.keys.elementAt(groupIndex);
        final dayLogs = groupedLogs[dateKey]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date Header
            _buildDateHeader(context, dateKey, dayLogs.first.createdAt),
            const SizedBox(height: 8),
            // Timeline Items for this day
            ...dayLogs.asMap().entries.map((entry) {
              final index = entry.key;
              final log = entry.value;
              final isLast = index == dayLogs.length - 1;
              return _TimelineItem(
                log: log,
                isLast: isLast,
                actionLabel: actionLabels[log.action] ?? log.action,
                entityLabel: entityLabels[log.entityType] ?? log.entityType,
                onTap: () => onTap(log),
              );
            }),
            if (groupIndex < groupedLogs.length - 1) const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _buildDateHeader(BuildContext context, String dateKey, DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final logDate = DateTime(date.year, date.month, date.day);

    String dateLabel;
    if (logDate == today) {
      dateLabel = tr('اليوم');
    } else if (logDate == today.subtract(const Duration(days: 1))) {
      dateLabel = tr('أمس');
    } else {
      dateLabel = dateKey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.1),
            AppColors.primary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            PhosphorIconsBold.calendar,
            size: 16,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Text(
            dateLabel,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual Timeline Item with connector line
class _TimelineItem extends StatefulWidget {
  final ActivityLog log;
  final bool isLast;
  final String actionLabel;
  final String entityLabel;
  final VoidCallback onTap;

  const _TimelineItem({
    required this.log,
    required this.isLast,
    required this.actionLabel,
    required this.entityLabel,
    required this.onTap,
  });

  @override
  State<_TimelineItem> createState() => _TimelineItemState();
}

class _TimelineItemState extends State<_TimelineItem> {
  bool _isHovered = false;

  IconData _getIconForAction(String action) {
    switch (action) {
      case 'sale':
        return PhosphorIconsBold.shoppingCart;
      case 'refund':
      case 'return':
      case 'cancel_return':
      case 'sales_return':
        return PhosphorIconsBold.arrowCounterClockwise;
      case 'void':
      case 'delete_invoice':
        return PhosphorIconsBold.fileX;
      case 'discount':
      case 'pos_discount':
        return PhosphorIconsBold.percent;
      case 'expense':
      case 'delete_expense':
        return PhosphorIconsBold.money;
      case 'receipt':
        return PhosphorIconsBold.receipt;
      case 'login':
      case 'logout':
      case 'admin_elevation':
        return PhosphorIconsBold.user;
      case 'delete_product':
      case 'product_delete':
      case 'delete_customer':
      case 'delete_supplier':
      case 'delete_purchase':
        return PhosphorIconsBold.trash;
      case 'price_override':
      case 'product_edit':
      case 'update_customer':
      case 'update_supplier':
      case 'update_payment':
        return PhosphorIconsBold.pencil;
      case 'add_product':
        return PhosphorIconsBold.package;
      case 'add_customer':
      case 'add_supplier':
      case 'add_purchase':
      case 'purchase':
        return PhosphorIconsBold.plus;
      case 'purchase_return':
        return PhosphorIconsBold.arrowCounterClockwise;
      case 'cart_add':
      case 'cart_remove':
      case 'cart_clear':
        return PhosphorIconsBold.shoppingCartSimple;
      case 'hold_order':
      case 'order_suspend':
      case 'retrieve_held_order':
      case 'delete_held_order':
        return PhosphorIconsBold.pause;
      case 'open_drawer':
      case 'cash_drawer_open':
        return PhosphorIconsBold.lockOpen;
      case 'settings_change':
        return PhosphorIconsBold.gear;
      case 'price_edit':
        return PhosphorIconsBold.currencyDollar;
      case 'pos_item_qty_change':
        return PhosphorIconsBold.scales;
      case 'shift_close':
      case 'daily_closing':
        return PhosphorIconsBold.clockCountdown;
      case 'safe_adjustment':
        return PhosphorIconsBold.vault;
      case 'offer_add':
      case 'offer_edit':
      case 'offer_delete':
      case 'offer_toggle':
        return PhosphorIconsBold.tag;
      case 'stock_adjust':
        return PhosphorIconsBold.warehouse;
      case 'category_add':
      case 'category_edit':
      case 'category_delete':
        return PhosphorIconsBold.folders;
      case 'user_create':
      case 'user_edit':
      case 'user_activate':
      case 'user_deactivate':
      case 'user_lock':
      case 'user_unlock':
      case 'user_reset_password':
      case 'perm_change':
        return PhosphorIconsBold.userGear;
      case 'add_section':
      case 'update_section':
      case 'delete_section':
      case 'add_table':
      case 'update_table':
      case 'delete_table':
        return PhosphorIconsBold.table;
      case 'add_reservation':
      case 'cancel_reservation':
        return PhosphorIconsBold.calendarCheck;
      case 'add_delivery_company':
      case 'update_delivery_company':
      case 'delete_delivery_company':
        return PhosphorIconsBold.buildings;
      case 'add_courier':
      case 'update_courier':
      case 'delete_courier':
        return PhosphorIconsBold.moped;
      case 'add_printer':
      case 'update_printer':
      case 'delete_printer':
        return PhosphorIconsBold.printer;
      case 'add_employee':
      case 'update_employee':
        return PhosphorIconsBold.userPlus;
      case 'employee_advance':
      case 'employee_deduction':
        return PhosphorIconsBold.currencyCircleDollar;
      case 'employee_checkin':
        return PhosphorIconsBold.signIn;
      case 'employee_checkout':
        return PhosphorIconsBold.signOut;
      case 'salary_payment':
        return PhosphorIconsBold.money;
      case 'update_role_permissions':
      case 'add_role':
      case 'delete_role':
        return PhosphorIconsBold.shieldCheck;
      case 'create_invoice_template':
      case 'update_invoice_template':
      case 'delete_invoice_template':
      case 'import_invoice_template':
        return PhosphorIconsBold.fileText;
      case 'screen_view':
        return PhosphorIconsBold.monitor;
      default:
        return PhosphorIconsBold.note;
    }
  }

  Color _getColorForAction(String action) {
    switch (action) {
      case 'sale':
      case 'receipt':
      case 'add_product':
      case 'add_customer':
      case 'add_supplier':
      case 'add_purchase':
      case 'purchase':
      case 'employee_checkin':
      case 'salary_payment':
      case 'add_courier':
      case 'update_courier':
      case 'delete_courier':
        return AppColors.success;
      case 'refund':
      case 'return':
      case 'cancel_return':
      case 'sales_return':
      case 'purchase_return':
      case 'discount':
      case 'pos_discount':
      case 'update_payment':
      case 'price_override':
      case 'product_edit':
      case 'update_customer':
      case 'update_supplier':
      case 'price_edit':
      case 'hold_order':
      case 'order_suspend':
      case 'retrieve_held_order':
      case 'open_drawer':
      case 'cash_drawer_open':
      case 'offer_add':
      case 'offer_edit':
      case 'offer_delete':
      case 'offer_toggle':
      case 'safe_adjustment':
      case 'update_role_permissions':
      case 'add_role':
      case 'delete_role':
      case 'add_reservation':
      case 'cancel_reservation':
        return AppColors.warning;
      case 'expense':
      case 'delete_expense':
      case 'delete_product':
      case 'product_delete':
      case 'delete_customer':
      case 'delete_supplier':
      case 'delete_purchase':
      case 'void':
      case 'delete_invoice':
      case 'delete_held_order':
      case 'employee_checkout':
      case 'employee_advance':
      case 'employee_deduction':
        return AppColors.error;
      case 'login':
      case 'logout':
      case 'admin_elevation':
      case 'settings_change':
      case 'cart_add':
      case 'cart_remove':
      case 'cart_clear':
      case 'pos_item_qty_change':
      case 'stock_adjust':
      case 'shift_close':
      case 'daily_closing':
      case 'screen_view':
      case 'user_create':
      case 'user_edit':
      case 'user_activate':
      case 'user_deactivate':
      case 'user_lock':
      case 'user_unlock':
      case 'user_reset_password':
      case 'perm_change':
      case 'add_printer':
      case 'update_printer':
      case 'delete_printer':
      case 'add_delivery_company':
      case 'update_delivery_company':
      case 'delete_delivery_company':
        return AppColors.info;
      case 'add_section':
      case 'update_section':
      case 'delete_section':
      case 'add_table':
      case 'update_table':
      case 'delete_table':
      case 'add_employee':
      case 'update_employee':
      case 'create_invoice_template':
      case 'update_invoice_template':
      case 'delete_invoice_template':
      case 'import_invoice_template':
      case 'category_add':
      case 'category_edit':
      case 'category_delete':
        return AppColors.primary;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final icon = _getIconForAction(log.action);
    final color = _getColorForAction(log.action);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Timeline connector
              SizedBox(
                width: 60,
                child: Column(
                  children: [
                    // Time
                    Text(
                      '${log.createdAt.hour.toString().padLeft(2, '0')}:${log.createdAt.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        fontSize: 11,
                        color: _isHovered ? color : AppColors.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Icon node
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: _isHovered ? 36 : 32,
                      height: _isHovered ? 36 : 32,
                      decoration: BoxDecoration(
                        color: _isHovered
                            ? color
                            : color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        boxShadow: _isHovered
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        icon,
                        size: 16,
                        color: _isHovered ? Colors.white : color,
                      ),
                    ),
                    // Connector line
                    if (!widget.isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                color.withValues(alpha: 0.5),
                                color.withValues(alpha: 0.1),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 16),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Content Card
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isHovered
                        ? color.withValues(alpha: 0.08)
                        : Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isHovered
                          ? color.withValues(alpha: 0.3)
                          : Colors.transparent,
                    ),
                    boxShadow: _isHovered
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 4,
                            ),
                          ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Action badge and description
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.actionLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.textMuted.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.entityLabel,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (log.amount != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (log.action == 'expense'
                                            ? AppColors.error
                                            : AppColors.success)
                                        .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${log.amount!.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: log.action == 'expense'
                                      ? AppColors.error
                                      : AppColors.success,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Description
                      Text(
                        log.description,
                        style: const TextStyle(fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      // User info
                      Row(
                        children: [
                          const Icon(
                            PhosphorIconsBold.user,
                            size: 12,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            log.userName,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (log.oldValue != null || log.newValue != null) ...[
                            const SizedBox(width: 12),
                            const Icon(
                              PhosphorIconsBold.arrowRight,
                              size: 12,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '${log.oldValue ?? ""} → ${log.newValue ?? ""}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
