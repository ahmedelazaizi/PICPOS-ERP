import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:ural_erp/core/theme/app_colors.dart';
import 'package:ural_erp/core/design_system/typography.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/repositories/kitchen_repository.dart';
import 'kds_stats_screen.dart';

/// Kitchen Display Screen - Shows pending orders for the kitchen
class KitchenDisplayScreen extends ConsumerStatefulWidget {
  const KitchenDisplayScreen({super.key});

  @override
  ConsumerState<KitchenDisplayScreen> createState() =>
      _KitchenDisplayScreenState();
}

class _KitchenDisplayScreenState extends ConsumerState<KitchenDisplayScreen> {
  String _selectedStation = 'all';
  Timer? _timer;
  DateTime _currentTime = DateTime.now();
  int _lastOrderCount = 0;
  bool _soundEnabled = true;

  @override
  void initState() {
    super.initState();
    // Update time every second for elapsed time display
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _currentTime = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Play alert sound when new orders arrive
  void _playNewOrderAlert() {
    if (_soundEnabled) {
      SystemSound.play(SystemSoundType.alert);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kitchenRepo = ref.watch(kitchenRepositoryProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.primaryDark,
        appBar: _buildAppBar(),
        body: StreamBuilder<List<WorkOrder>>(
          stream: _selectedStation == 'all'
              ? kitchenRepo.watchPendingOrders()
              : kitchenRepo.watchOrdersByStation(_selectedStation),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primaryLight),
              );
            }

            final orders = snapshot.data ?? [];

            // Sound alert when new orders arrive
            if (orders.length > _lastOrderCount && _lastOrderCount > 0) {
              _playNewOrderAlert();
            }
            _lastOrderCount = orders.length;

            if (orders.isEmpty) {
              return _buildEmptyState();
            }

            return Column(
              children: [
                // Stats bar
                _buildStatsBar(orders),
                // Orders grid
                Expanded(child: _buildOrdersGrid(orders, kitchenRepo)),
              ],
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.secondaryDark,
      title: Row(
        children: [
          const Icon(PhosphorIconsBold.chefHat, color: AppColors.warning),
          const SizedBox(width: 12),
          Text(
            'شاشة المطبخ',
            style: AppTypography.h3.copyWith(color: Colors.white),
          ),
          const Spacer(),
          // Sound toggle
          IconButton(
            onPressed: () => setState(() => _soundEnabled = !_soundEnabled),
            icon: Icon(
              _soundEnabled
                  ? PhosphorIconsBold.speakerHigh
                  : PhosphorIconsBold.speakerSlash,
              color: _soundEnabled ? AppColors.warning : Colors.white38,
            ),
            tooltip: _soundEnabled ? 'كتم الصوت' : 'تفعيل الصوت',
          ),
          const SizedBox(width: 8),
        // Stats button
        IconButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const KdsStatsScreen()),
          ),
          icon: const Icon(PhosphorIconsBold.chartBar, color: AppColors.primaryLight),
          tooltip: 'إحصائيات المطبخ',
        ),
        const SizedBox(width: 8),
        _buildStationFilter(),
        ],
      ),
      elevation: 0,
    );
  }

  Widget _buildStatsBar(List<WorkOrder> orders) {
    final pending = orders.where((o) => o.status == 'pending').length;
    final preparing = orders.where((o) => o.status == 'preparing').length;
    final ready = orders.where((o) => o.status == 'ready').length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.secondaryDark.withValues(alpha: 0.5),
      child: Row(
        children: [
          _buildStatChip('معلق', pending, AppColors.error),
          const SizedBox(width: 12),
          _buildStatChip('تحضير', preparing, AppColors.warning),
          const SizedBox(width: 12),
          _buildStatChip('جاهز', ready, AppColors.success),
          const SizedBox(width: 12),
          _buildStatChip('في الانتظار', pending + preparing, AppColors.info),
          const Spacer(),
          Text(
            '${_currentTime.hour.toString().padLeft(2, '0')}:${_currentTime.minute.toString().padLeft(2, '0')}:${_currentTime.second.toString().padLeft(2, '0')}',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 16,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildStationFilter() {
    final kitchenRepo = ref.watch(kitchenRepositoryProvider);
    return FutureBuilder<List<KitchenStation>>(
      future: kitchenRepo.getActiveStations(),
      builder: (context, snapshot) {
        final stations = snapshot.data ?? [];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<String>(
            value: _selectedStation,
            dropdownColor: AppColors.secondary,
            style: const TextStyle(color: Colors.white),
            underline: const SizedBox(),
            items: [
              const DropdownMenuItem(value: 'all', child: Text('جميع المحطات')),
              ...stations.map(
                (s) => DropdownMenuItem(value: s.code, child: Text(s.name)),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _selectedStation = value);
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            PhosphorIconsBold.checkCircle,
            size: 80,
            color: AppColors.success.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'لا توجد طلبات معلقة',
            style: AppTypography.h2.copyWith(color: Colors.white54),
          ),
          const SizedBox(height: 8),
          Text(
            'في انتظار طلبات جديدة...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersGrid(List<WorkOrder> orders, KitchenRepository kitchenRepo) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        return _buildOrderCard(orders[index], kitchenRepo);
      },
    );
  }

  Widget _buildOrderCard(WorkOrder order, KitchenRepository kitchenRepo) {
    final elapsedMinutes = _currentTime.difference(order.createdAt).inMinutes;
    final isUrgent = order.priority == 'urgent' || elapsedMinutes > 15;
    final isHigh = order.priority == 'high' || elapsedMinutes > 10;

    final borderColor = isUrgent
        ? AppColors.error
        : isHigh
            ? AppColors.warning
            : AppColors.success;

    final headerColor = isUrgent
        ? AppColors.errorDark
        : isHigh
            ? AppColors.warningDark
            : AppColors.successDark;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.secondaryDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 3),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          // Header — order number + table name + elapsed time
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(9),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        order.orderNumber,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$elapsedMinutes دقيقة',
                        style: TextStyle(
                          color: elapsedMinutes > 10
                              ? AppColors.error
                              : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    // Estimated wait time badge (pending/preparing only)
                    if (order.status == 'pending' || order.status == 'preparing')
                      FutureBuilder<int>(
                        future: kitchenRepo.estimateWaitTime(order.id),
                        builder: (context, snap) {
                          if (!snap.hasData || snap.data == 0) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.info.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(PhosphorIconsBold.timer, size: 10, color: AppColors.info),
                                  const SizedBox(width: 3),
                                  Text(
                                    '~${snap.data} د',
                                    style: const TextStyle(color: AppColors.info, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
                // Table name & station badge
                if (order.customerName != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(PhosphorIconsBold.mapPin,
                          color: Colors.white70, size: 14),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          order.customerName!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          order.station,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Items
          Expanded(
            child: StreamBuilder<List<WorkOrderItem>>(
              stream: kitchenRepo.watchOrderItems(order.id),
              builder: (context, snapshot) {
                final items = snapshot.data ?? [];
                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _buildOrderItem(item, kitchenRepo);
                  },
                );
              },
            ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                if (order.status == 'pending')
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _startPreparing(order.id, kitchenRepo),
                      icon:
                          const Icon(PhosphorIconsBold.cookingPot, size: 18),
                      label: const Text('تحضير'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.warning,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                if (order.status == 'preparing') ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _markReady(order.id, kitchenRepo),
                      icon: const Icon(PhosphorIconsBold.checkCircle,
                          size: 18),
                      label: const Text('جاهز'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
                if (order.status == 'ready') ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _recallOrder(order.id, kitchenRepo),
                      icon: const Icon(
                          PhosphorIconsBold.arrowCounterClockwise,
                          size: 18),
                      label: const Text('استرجاع'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        side: const BorderSide(color: AppColors.warning),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(WorkOrderItem item, KitchenRepository kitchenRepo) {
    final isReady = item.status == 'ready';
    return InkWell(
      onTap: () => kitchenRepo.markItemReady(item.id),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isReady
              ? AppColors.success.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Text(
              '${item.quantity.toStringAsFixed(0)}x',
              style: TextStyle(
                color: isReady ? AppColors.success : AppColors.warning,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: TextStyle(
                      color: isReady ? AppColors.success : Colors.white,
                      decoration:
                          isReady ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (item.notes != null && item.notes!.isNotEmpty)
                    Text(
                      item.notes!,
                      style: TextStyle(
                        color: AppColors.warning.withValues(alpha: 0.8),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
            if (isReady)
              const Icon(
                PhosphorIconsBold.check,
                color: AppColors.success,
                size: 16,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _startPreparing(int orderId, KitchenRepository kitchenRepo) async {
    await kitchenRepo.updateWorkOrderStatus(orderId, 'preparing');
  }

  Future<void> _markReady(int orderId, KitchenRepository kitchenRepo) async {
    await kitchenRepo.updateWorkOrderStatus(orderId, 'ready');
    if (mounted) {
      AppToast.show(context, 'تم تجهيز الطلب!', type: ToastType.success);
    }
  }

  Future<void> _recallOrder(int orderId, KitchenRepository kitchenRepo) async {
    await kitchenRepo.updateWorkOrderStatus(orderId, 'preparing');
    if (mounted) {
      AppToast.show(context, 'تم استرجاع الطلب للتحضير', type: ToastType.info);
    }
  }
}
