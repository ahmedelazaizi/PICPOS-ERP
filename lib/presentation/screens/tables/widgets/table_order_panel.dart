import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:ural_erp/core/utils/number_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../data/database/database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/permissions/permission_codes.dart';
import '../../../../domain/entities/product_entity.dart';
import '../../../../domain/repositories/restaurant_repository.dart';
import '../../../../data/providers/repository_providers.dart';
import '../../../widgets/permission_guard.dart';
import '../providers/tables_state_provider.dart';

class TableOrderPanel extends ConsumerWidget {
  final RestaurantTable table;
  final VoidCallback onOpenOrder;
  final VoidCallback onShowOrder;
  final VoidCallback onTransfer;
  final VoidCallback onSplit;

  const TableOrderPanel({
    super.key,
    required this.table,
    required this.onOpenOrder,
    required this.onShowOrder,
    required this.onTransfer,
    required this.onSplit,
  });

  static Map<String, _StatusInfo> get _statusMap => {
    'available': _StatusInfo(tr('متاحة'), const Color(0xFF10B981), PhosphorIconsBold.checkCircle),
    'reserved': _StatusInfo(tr('محجوزة'), const Color(0xFFF59E0B), PhosphorIconsBold.calendarCheck),
    'occupied': _StatusInfo(tr('مشغولة'), const Color(0xFF3B82F6), PhosphorIconsBold.users),
    'seated': _StatusInfo(tr('مشغولة'), const Color(0xFF3B82F6), PhosphorIconsBold.users),
    'ordered': _StatusInfo(tr('مشغولة'), const Color(0xFF3B82F6), PhosphorIconsBold.users),
    'eating': _StatusInfo(tr('مشغولة'), const Color(0xFF3B82F6), PhosphorIconsBold.users),
    'billing': _StatusInfo(tr('مشغولة'), const Color(0xFF3B82F6), PhosphorIconsBold.users),
    'cleaning': _StatusInfo(tr('تنظيف'), const Color(0xFF6366F1), PhosphorIconsBold.broom),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurantRepo = ref.watch(restaurantRepositoryProvider);
    final uiNotifier = ref.read(tablesUIProvider.notifier);
    
    final statusInfo = _statusMap[table.status] ?? _statusMap['available']!;
    final isActive = [
      'occupied',
      'seated',
      'ordered',
      'eating',
      'billing'
    ].contains(table.status);

    final elapsed = DateTime.now().difference(table.lastStatusAt);
    final elapsedStr = elapsed.inMinutes > 0
        ? '${elapsed.inHours > 0 ? '${elapsed.inHours}:' : ''}${(elapsed.inMinutes % 60).toString().padLeft(2, '0')}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}'
        : '00:${elapsed.inSeconds.toString().padLeft(2, '0')}';

    return Column(
      children: [
        // ── Header ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                statusInfo.color.withValues(alpha: 0.12),
                statusInfo.color.withValues(alpha: 0.03),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            border: Border(
              bottom: BorderSide(
                  color: statusInfo.color.withValues(alpha: 0.1)),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          statusInfo.color.withValues(alpha: 0.2),
                          statusInfo.color.withValues(alpha: 0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: statusInfo.color.withValues(alpha: 0.3)),
                    ),
                    child: Icon(statusInfo.icon,
                        color: statusInfo.color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(table.name,
                            style: GoogleFonts.cairo(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(statusInfo.label,
                                style: GoogleFonts.cairo(
                                    fontSize: 10,
                                    color: statusInfo.color,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(width: 8),
                            if (isActive) ...[
                              Icon(PhosphorIconsBold.timer,
                                  size: 10, color: statusInfo.color),
                              const SizedBox(width: 3),
                              Text(elapsedStr,
                                  style: GoogleFonts.cairo(
                                      fontSize: 10,
                                      color: statusInfo.color,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(PhosphorIconsBold.x, size: 16),
                    onPressed: () => uiNotifier.selectTable(null),
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (table.status == 'available')
                    _panelAction(tr('فتح طلب'), PhosphorIconsBold.notepad,
                        const Color(0xFF10B981), onOpenOrder),
                  if (isActive) ...[
                    PermissionGuard(
                      permission: PermissionCodes.tablesPosAccess,
                      child: _panelAction(tr('الطلب'), PhosphorIconsBold.shoppingCart,
                          const Color(0xFF3B82F6), onShowOrder),
                    ),
                    const SizedBox(width: 6),
                    PermissionGuard(
                      permission: PermissionCodes.tablesTransfer,
                      child: _panelAction(
                          tr('تحويل'),
                          PhosphorIconsBold.arrowsLeftRight,
                          const Color(0xFF8B5CF6), onTransfer),
                    ),
                    const SizedBox(width: 6),
                    PermissionGuard(
                      permission: PermissionCodes.tablesTransfer,
                      child: _panelAction(
                          tr('تقسيم'),
                          PhosphorIconsBold.splitHorizontal,
                          const Color(0xFFF59E0B), onSplit),
                    ),
                  ],
                  if (table.status == 'cleaning')
                    _panelAction(tr('جاهزة'), PhosphorIconsBold.checkCircle,
                        const Color(0xFF10B981), () async {
                      await restaurantRepo.updateTableStatus(
                          table.id, 'available');
                      uiNotifier.selectTable(null);
                    }),
                ],
              ),
            ],
          ),
        ),

        // ── Order items ──
        Expanded(
          child: !isActive
              ? _buildInactiveState(table)
              : _buildOrderItemList(restaurantRepo, table),
        ),

        // ── Footer ──
        if (isActive) _buildFooter(restaurantRepo, table),
      ],
    );
  }

  Widget _buildInactiveState(RestaurantTable table) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(PhosphorIconsBold.selection,
              size: 40, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 12),
          Text(table.status == 'reserved' ? tr('طاولة محجوزة') : tr('الطاولة متاحة'),
              style: GoogleFonts.cairo(
                  color: Colors.white.withValues(alpha: 0.2))),
        ],
      ),
    );
  }

  Widget _buildOrderItemList(IRestaurantRepository repo, RestaurantTable table) {
    return FutureBuilder<TableOrder?>(
      future: repo.getActiveOrderForTable(table.id),
      builder: (context, snap) {
        if (!snap.hasData || snap.data == null) return const SizedBox.shrink();
        final order = snap.data!;
        return FutureBuilder<List<TableOrderItem>>(
          future: repo.getTableOrderItems(order.id),
          builder: (context, itemsSnap) {
            final items = itemsSnap.data ?? [];
            if (items.isEmpty) return Center(child: Text(tr('الطلب فارغ'), style: GoogleFonts.cairo(color: Colors.white.withValues(alpha: 0.2))));
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return _OrderItemTile(item: item);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildFooter(IRestaurantRepository repo, RestaurantTable table) {
    return FutureBuilder<TableOrder?>(
      future: repo.getActiveOrderForTable(table.id),
      builder: (context, snap) {
        final total = snap.data?.total ?? 0.0;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.05),
            border: Border(top: BorderSide(color: AppColors.primary.withValues(alpha: 0.1))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(tr('الإجمالي'), style: GoogleFonts.cairo(color: Colors.white.withValues(alpha: 0.5))),
              Text(total.toStringAsFixed(AppConstants.decimalPlaces), style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
            ],
          ),
        );
      },
    );
  }

  Widget _panelAction(String label, IconData icon, Color color, VoidCallback onTap) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(height: 2),
                Text(label, style: GoogleFonts.cairo(fontSize: 9, color: color, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderItemTile extends ConsumerWidget {
  final TableOrderItem item;
  const _OrderItemTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<ProductEntity?>(
      future: ref.read(productRepositoryProvider).getProductById(item.productId),
      builder: (context, snap) {
        final name = snap.data?.name ?? '#${item.productId}';
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              // BUG-M06: format fractional quantities (weight / partial portions)
              Text('${NumberUtils.formatQuantity(item.quantity)}x', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: AppColors.primary)),
              const SizedBox(width: 10),
              Expanded(child: Text(name, style: GoogleFonts.cairo(fontSize: 12))),
              Text(item.total.toStringAsFixed(AppConstants.decimalPlaces), style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
            ],
          ),
        );
      },
    );
  }
}

class _StatusInfo {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusInfo(this.label, this.color, this.icon);
}
