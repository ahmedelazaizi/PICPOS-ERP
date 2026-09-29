import 'package:ural_erp/core/i18n/tr.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:ural_erp/core/theme/app_colors.dart';
import 'package:ural_erp/core/design_system/typography.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/repositories/kitchen_repository.dart';
import '../../widgets/permission_guard.dart';
import 'kds_stats_screen.dart';

// ── دالة بناء مستخرجة (Task 6b) ─────────────────────────────────────────
// الحارس هنا (`PermissionGuard`) declarative بحت — الثلاث أزرار (تحضير/جاهز/
// استرجاع) بتغيّر حالة أمر المطبخ وكانت شاشتها محمية بكود عرض خشن بس
// (`kitchen_view`)، من غير أي فحص على الفعل نفسه. الثلاثة بيستخدموا نفس
// الدالة عشان يتبنوا في اختبار widget خفيف واحد (بدون قاعدة بيانات حقيقية).
@visibleForTesting
Widget buildKitchenManageActionButton({
  required VoidCallback onPressed,
  required IconData icon,
  required String label,
  required Color color,
  bool outlined = false,
}) {
  final child = outlined
      ? OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color),
          ),
        )
      : ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
          ),
        );
  return PermissionGuard(
    permission: PermissionCodes.kitchenManage,
    allowManagerOverride: true,
    actionName: tr('تغيير حالة طلب المطبخ'),
    onGranted: onPressed,
    child: child,
  );
}

// ── فيكس المراجعة (Task 6b) ──────────────────────────────────────────────
// «تعليم صنف كجاهز» (`kitchenRepo.markItemReady`، ضغطة على صف الصنف جوه
// الطلب) اتستبعد أول مرة بسبب "فعل أدق من غير كود مخصص" — نفس المنطق اللي
// استُبعد بيه offers_toggle، لكن هناك اتحطّت تحت كود أوسع (offers_edit) بدل
// ما تتسحب. المراجعة رصدت التناقض: «تعليم جاهز» هو بالظبط نفس فئة الفعل اللي
// kitchen_manage («إدارة طلبات المطبخ») موجود عشان يحميها — تغيير حالة عنصر
// جوه أمر مطبخ، زي تحضير/جاهز/استرجاع بالظبط بس على مستوى الصنف مش الطلب
// كله. فبيتحمي بنفس الكود.
@visibleForTesting
Widget buildKitchenManageItemReadyTile({
  required VoidCallback onTap,
  required Widget child,
}) {
  return PermissionGuard(
    permission: PermissionCodes.kitchenManage,
    allowManagerOverride: true,
    actionName: tr('تعليم صنف كجاهز'),
    onGranted: onTap,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: child,
    ),
  );
}

/// Kitchen Display Screen - Shows pending orders for the kitchen
class KitchenDisplayScreen extends ConsumerStatefulWidget {
  const KitchenDisplayScreen({super.key});

  @override
  ConsumerState<KitchenDisplayScreen> createState() =>
      _KitchenDisplayScreenState();
}

class _KitchenDisplayScreenState extends ConsumerState<KitchenDisplayScreen> {
  String _selectedStation = 'all';
  int _lastOrderCount = 0;
  bool _soundEnabled = true;

  // ── مصادرُ البيانات تُحفَظ ولا تُنشَأ في `build` ────────────────────────
  //
  // كانت `stream:` تُستدعى داخل `build` مباشرةً، ومعها مؤقّتٌ يضرب
  // `setState` كلَّ ثانيةٍ لعرض الساعة. فكانت كلُّ ثانيةٍ تخلق كائناتِ
  // Stream جديدةً ⇒ يفسخ `StreamBuilder` اشتراكَه ويشترك من جديد ⇒
  // استعلامُ قاعدةٍ جديد، ويمرّ بـ`ConnectionState.waiting` فيومض
  // مؤشّرُ التحميل. ومع N بطاقةً معروضةً كان ذلك **١ + N استعلاماً كلَّ
  // ثانية**.
  //
  // الآن: الساعةُ والزمنُ المنقضي يدقّان في ودجتٍ يملك مؤقّتَه (`_Ticker`)
  // فلا يُعاد بناءُ الشاشة أصلاً؛ وهذه الحقولُ تُثبّت هُويّةَ الـStream
  // فحتى إعادةُ البناءِ المشروعة (تبديلُ المحطة أو كتمُ الصوت) لا تُعيد
  // الاشتراك.
  Stream<List<WorkOrder>>? _ordersStream;
  String? _ordersStreamStation;
  final Map<int, Stream<List<WorkOrderItem>>> _itemStreams = {};

  Stream<List<WorkOrder>> _ordersFor(KitchenRepository repo) {
    if (_ordersStream == null || _ordersStreamStation != _selectedStation) {
      _ordersStreamStation = _selectedStation;
      _ordersStream = _selectedStation == 'all'
          ? repo.watchPendingOrders()
          : repo.watchOrdersByStation(_selectedStation);
    }
    return _ordersStream!;
  }

  Stream<List<WorkOrderItem>> _itemsFor(KitchenRepository repo, int orderId) =>
      _itemStreams.putIfAbsent(orderId, () => repo.watchOrderItems(orderId));

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
          stream: _ordersFor(kitchenRepo),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primaryLight),
              );
            }

            final orders = snapshot.data ?? [];

            // الطلبُ الذي غادر الشاشةَ يُسقَط مجرى بنوده معه، وإلّا نما
            // الكاشُ بلا حدٍّ على مدى الوردية.
            final liveIds = orders.map((o) => o.id).toSet();
            _itemStreams.removeWhere((id, _) => !liveIds.contains(id));

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
            tr('شاشة المطبخ'),
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
            tooltip: _soundEnabled ? tr('كتم الصوت') : tr('تفعيل الصوت'),
          ),
          const SizedBox(width: 8),
        // Stats button
        IconButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const KdsStatsScreen()),
          ),
          icon: const Icon(PhosphorIconsBold.chartBar, color: AppColors.primaryLight),
          tooltip: tr('إحصائيات المطبخ'),
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
          _buildStatChip(tr('معلق'), pending, AppColors.error),
          const SizedBox(width: 12),
          _buildStatChip(tr('تحضير'), preparing, AppColors.warning),
          const SizedBox(width: 12),
          _buildStatChip(tr('جاهز'), ready, AppColors.success),
          const SizedBox(width: 12),
          _buildStatChip(tr('في الانتظار'), pending + preparing, AppColors.info),
          const Spacer(),
          // الساعةُ وحدَها تدقّ — لا الشاشةُ من ورائها.
          _Ticker(
            interval: const Duration(seconds: 1),
            builder: (_, now) => Text(
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 16,
                fontFamily: AppTypography.mono,
              ),
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
               DropdownMenuItem(value: 'all', child: Text(tr('جميع المحطات'))),
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
            tr('لا توجد طلبات معلقة'),
            style: AppTypography.h2.copyWith(color: Colors.white54),
          ),
          const SizedBox(height: 8),
          Text(
            tr('في انتظار طلبات جديدة...'),
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

  /// لونُ البطاقة وإلحاحُها يتبعان الزمنَ المنقضي، فالبطاقةُ تدقّ بنفسها —
  /// **بدقّةِ الدقيقة** لا الثانية، لأن `inMinutes` لا يتغيّر إلّا عندها.
  Widget _buildOrderCard(WorkOrder order, KitchenRepository kitchenRepo) => _Ticker(
        interval: const Duration(minutes: 1),
        builder: (_, now) => _orderCardAt(order, kitchenRepo, now),
      );

  Widget _orderCardAt(
      WorkOrder order, KitchenRepository kitchenRepo, DateTime now) {
    final elapsedMinutes = now.difference(order.createdAt).inMinutes;
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
                        tr('{elapsedMinutes} دقيقة', {'elapsedMinutes': elapsedMinutes}),
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
                            padding: const EdgeInsetsDirectional.only(start: 6),
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
                                    tr('~{p0} د', {'p0': snap.data}),
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
              stream: _itemsFor(kitchenRepo, order.id),
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
                    child: buildKitchenManageActionButton(
                      onPressed: () => _startPreparing(order.id, kitchenRepo),
                      icon: PhosphorIconsBold.cookingPot,
                      label: tr('تحضير'),
                      color: AppColors.warning,
                    ),
                  ),
                if (order.status == 'preparing') ...[
                  Expanded(
                    child: buildKitchenManageActionButton(
                      onPressed: () => _markReady(order.id, kitchenRepo),
                      icon: PhosphorIconsBold.checkCircle,
                      label: tr('جاهز'),
                      color: AppColors.success,
                    ),
                  ),
                ],
                if (order.status == 'ready') ...[
                  Expanded(
                    child: buildKitchenManageActionButton(
                      onPressed: () => _recallOrder(order.id, kitchenRepo),
                      icon: PhosphorIconsBold.arrowCounterClockwise,
                      label: tr('استرجاع'),
                      color: AppColors.warning,
                      outlined: true,
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
    return buildKitchenManageItemReadyTile(
      onTap: () => kitchenRepo.markItemReady(item.id),
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
      AppToast.show(context, tr('تم تجهيز الطلب!'), type: ToastType.success);
    }
  }

  Future<void> _recallOrder(int orderId, KitchenRepository kitchenRepo) async {
    await kitchenRepo.updateWorkOrderStatus(orderId, 'preparing');
    if (mounted) {
      AppToast.show(context, tr('تم استرجاع الطلب للتحضير'), type: ToastType.info);
    }
  }
}

/// ودجتٌ يملك مؤقّتَه فيُعيد بناءَ **نفسِه وحدَه**.
///
/// وُجد لأن عرضَ الوقت كان يُكلّف شاشةَ المطبخ إعادةَ بناءٍ كاملةً كلَّ ثانية:
/// `setState` على حالة الشاشة يُعيد تنفيذ `build`، وفيها كانت تُنشَأ مصادرُ
/// البيانات، فيُفسَخ الاشتراكُ ويُعاد — استعلامٌ لكلِّ بطاقةٍ كلَّ ثانيةٍ
/// ووميضُ مؤشّرِ تحميل. وحصرُ الدقّ في الورقة يُبقي الوقتَ حيّاً بلا أن يمسّ
/// شيئاً فوقه.
class _Ticker extends StatefulWidget {
  const _Ticker({required this.interval, required this.builder});

  final Duration interval;
  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}
