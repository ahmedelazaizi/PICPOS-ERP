import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../data/database/database.dart' as db;
import '../../data/providers/providers.dart';
import '../../domain/repositories/cycle_count_repository.dart';
import '../../core/widgets/app_toast.dart';
import 'cycle_count/cycle_count_controller.dart';

final _fmt = NumberFormat('#,##0.00', 'ar');

/// Cycle Counting Screen — الجرد الدوري المستمر
class CycleCountScreen extends ConsumerStatefulWidget {
  const CycleCountScreen({super.key});

  @override
  ConsumerState<CycleCountScreen> createState() => _CycleCountScreenState();
}

class _CycleCountScreenState extends ConsumerState<CycleCountScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Spec 147 (S-COUNT): R2 double-submission guard for the atomic finalize.
  // State field (survives rebuilds) — a double-tap on «إكمال» must not
  // apply/post the count twice.
  bool _finalizing = false;

  // BUG-C: hold the per-item count controllers in State (keyed by item id) so a
  // typed-but-not-Enter value survives rebuilds and can be flushed to the DB
  // before finalize. Recreating them each build (the old code) meant clicking
  // «إكمال» without pressing Enter first silently dropped the count → finalize
  // adjusted nothing while still toasting success.
  final Map<int, TextEditingController> _countCtrls = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _countCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = ref.watch(cycleCountRepositoryProvider);
    final state = ref.watch(cycleCountControllerProvider);
    final notifier = ref.read(cycleCountControllerProvider.notifier);

    return Scaffold(
      body: Column(
        children: [
          Container(
            color: theme.colorScheme.surfaceContainerLow,
            child: TabBar(
              controller: _tabController,
              tabs:  [
                Tab(icon: const Icon(PhosphorIconsBold.listChecks), text: tr('الخطط')),
                Tab(icon: const Icon(PhosphorIconsBold.clipboardText), text: tr('المهام')),
                Tab(icon: const Icon(PhosphorIconsBold.chartBar), text: tr('التحليلات')),
              ],
            ),
          ),
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPlansTab(theme, repo, state, notifier),
                      _buildTasksTab(theme, repo, state, notifier),
                      _buildAnalyticsTab(theme, repo, state),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tabController.index == 0) {
            _showCreatePlanDialog(repo, notifier);
          } else if (_tabController.index == 1) {
            _showGenerateTaskDialog(repo, state, notifier);
          }
        },
        icon: const Icon(Icons.add),
        label: Text(_tabController.index == 0 ? tr('خطة جديدة') : tr('مهمة جديدة')),
      ),
    );
  }

  // ─── Plans Tab ──

  Widget _buildPlansTab(ThemeData theme, ICycleCountRepository repo, CycleCountState state, CycleCountController notifier) {
    if (state.plans.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(PhosphorIconsBold.listChecks,
              size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(tr('لا توجد خطط جرد'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(tr('أنشئ خطة جرد دوري لمتابعة دقة المخزون'),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: state.plans.length,
      itemBuilder: (ctx, i) => _buildPlanCard(theme, repo, state.plans[i], notifier),
    );
  }

  Widget _buildPlanCard(ThemeData theme, ICycleCountRepository repo, db.CycleCountPlanData plan, CycleCountController notifier) {
    final statusColor = plan.status == 'active'
        ? Colors.green : plan.status == 'paused' ? Colors.amber : Colors.grey;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(PhosphorIconsBold.listChecks,
                  color: theme.colorScheme.onPrimaryContainer, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(plan.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 2),
                Text(
                  tr('التكرار: {p0} | عدد الأصناف: {p1}', {'p0': _freqLabel(plan.frequency), 'p1': plan.productsPerTask}),
                  style: theme.textTheme.bodySmall,
                ),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                plan.status == 'active' ? tr('نشط') : plan.status == 'paused' ? tr('متوقف') : tr('مكتمل'),
                style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _infoChip(theme, tr('التصنيف'), plan.abcClassification == 'all' ? tr('الكل') : plan.abcClassification),
            const SizedBox(width: 8),
            if (plan.nextDueDate != null)
              _infoChip(theme, tr('الموعد القادم'), DateFormat('yyyy/MM/dd').format(plan.nextDueDate!)),
            const Spacer(),
            if (plan.status == 'active')
              OutlinedButton.icon(
                onPressed: () async {
                  final taskId = await repo.generateCycleCountTask(
                    planId: plan.id, warehouseId: plan.warehouseId,
                    productsPerTask: plan.productsPerTask, abcClassification: plan.abcClassification,
                  );
                  if (taskId > 0 && mounted) {
                    AppToast.show(context, tr('تم إنشاء مهمة جرد جديدة'));
                    notifier.refresh();
                    _tabController.animateTo(1);
                  }
                },
                icon: const Icon(Icons.play_arrow, size: 18),
                label:  Text(tr('بدء جرد')),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _infoChip(ThemeData theme, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label: ',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(value, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ─── Tasks Tab ──

  Widget _buildTasksTab(ThemeData theme, ICycleCountRepository repo, CycleCountState state, CycleCountController notifier) {
    return Row(children: [
      SizedBox(
        width: 350,
        child: state.tasks.isEmpty
            ? Center(child: Text(tr('لا توجد مهام جرد'), style: theme.textTheme.bodyMedium))
            : ListView.builder(
                itemCount: state.tasks.length,
                itemBuilder: (ctx, i) {
                  final t = state.tasks[i];
                  return _buildTaskTile(theme, repo, t, state, notifier, state.selectedTask?.id == t.id);
                },
              ),
      ),
      VerticalDivider(width: 1, color: theme.dividerColor),
      Expanded(
        child: state.selectedTask == null
            ? Center(child: Text(tr('اختر مهمة من القائمة'), style: theme.textTheme.bodyLarge))
            : _buildCountingPanel(theme, repo, state, notifier),
      ),
    ]);
  }

  Widget _buildTaskTile(ThemeData theme, ICycleCountRepository repo, db.CycleCountTaskData task, CycleCountState state, CycleCountController notifier, bool sel) {
    final progress = task.productCount > 0 ? task.countedCount / task.productCount : 0.0;
    return ListTile(
      selected: sel,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      onTap: () => notifier.selectTask(task),
      title: Text(DateFormat('yyyy/MM/dd').format(task.taskDate),
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 4),
        LinearProgressIndicator(
            value: progress, backgroundColor: theme.colorScheme.surfaceContainerHigh),
        const SizedBox(height: 4),
        Text(tr('{p0}/{p1} أصناف | {p2} فروقات', {'p0': task.countedCount, 'p1': task.productCount, 'p2': task.varianceCount}),
            style: theme.textTheme.bodySmall),
      ]),
      trailing: _taskStatusIcon(task.status),
    );
  }

  Widget _buildCountingPanel(ThemeData theme, ICycleCountRepository repo, CycleCountState state, CycleCountController notifier) {
    final task = state.selectedTask!;
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(16),
        color: theme.colorScheme.surfaceContainerLow,
        child: Row(children: [
          Text(tr('مهمة {p0}', {'p0': DateFormat('yyyy/MM/dd').format(task.taskDate)}),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const Spacer(),
          if (task.status == 'pending')
            FilledButton.icon(
              onPressed: () async { await repo.startCycleCountTask(task.id); notifier.refresh(); },
              icon: const Icon(Icons.play_arrow, size: 18),
              label:  Text(tr('بدء')),
            ),
          if (task.status == 'in_progress')
            FilledButton.icon(
              // Spec 147 (S-COUNT): ONE atomic finalize (complete + apply @
              // costPrice + one settlement JE) in the DAO — replaces the old
              // three non-atomic calls + the UI-level JE hop. R2 guard blocks a
              // double-tap double-post.
              onPressed: _finalizing
                  ? null
                  : () async {
                      // Option B: block finalize on client/mirror (not sync-aware
                      // yet — would apply adjustments + JE local-only, reverted on pull).
                      if (ref.read(isClientModeProvider)) {
                        AppToast.show(context,
                            tr('لا يمكن اعتماد الجرد من جهاز عميل أو مرآة — نفّذه على الخادم الرئيسي'));
                        return;
                      }
                      setState(() => _finalizing = true);
                      try {
                        // BUG-C: flush any typed-but-not-submitted counts first,
                        // so finalize sees them (otherwise countedQty stays null
                        // → applyCycleCountAdjustments skips the item → no stock
                        // change but a success toast).
                        await _flushPendingCounts(repo, state);
                        await repo.finalizeCycleCountTask(task.id, approverUserId: ref.read(authProvider).user?.id);
                        if (mounted) {
                          AppToast.show(context, tr('تم إكمال المهمة وتعديل المخزون'));
                          notifier.refresh();
                        }
                      } catch (e) {
                        if (mounted) {
                          AppToast.show(context, tr('تعذّر إكمال المهمة: {e}', {'e': e}));
                        }
                      } finally {
                        if (mounted) setState(() => _finalizing = false);
                      }
                    },
              icon: _finalizing
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, size: 18),
              label:  Text(tr('إكمال')),
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
            ),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: state.taskItems.length,
          itemBuilder: (ctx, i) => _buildCountItem(theme, repo, state.taskItems[i], state, notifier),
        ),
      ),
    ]);
  }

  Widget _buildCountItem(ThemeData theme, ICycleCountRepository repo, db.CycleCountItemView item, CycleCountState state, CycleCountController notifier) {
    final isCounted = item.countedQty != null;
    final hasVariance = item.variance != null && item.variance!.abs() > 0.001;
    // BUG-C: persistent controller (survives rebuilds), seeded once from the DB.
    final countCtrl = _countCtrls.putIfAbsent(
      item.id,
      () => TextEditingController(
          text: isCounted ? item.countedQty!.toStringAsFixed(2) : ''),
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      color: hasVariance
          ? Colors.orange.withValues(alpha: 0.06)
          : isCounted ? Colors.green.withValues(alpha: 0.04) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          // BUG-B: real product name + category (was "صنف #<id>").
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.productName,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (item.categoryName != null && item.categoryName!.isNotEmpty)
                  Text(item.categoryName!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          SizedBox(
            width: 80,
            child: Column(children: [
              Text(tr('المتوقع'), style: theme.textTheme.bodySmall),
              Text(_fmt.format(item.expectedQty),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
          ),
          SizedBox(
            width: 120,
            child: TextField(
              controller: countCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr('العدد الفعلي'),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              onSubmitted: (val) async {
                final qty = double.tryParse(val);
                if (qty != null) {
                  await repo.submitCount(itemId: item.id, countedQty: qty);
                  notifier.selectTask(state.selectedTask!);
                  // we don't need full refresh because it's localized, although cycle count logic triggers selectTask
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: hasVariance
                ? Column(children: [
                    Text(
                      '${item.variance! > 0 ? '+' : ''}${item.variance!.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: item.variance! > 0 ? Colors.green : AppColors.error),
                    ),
                    Text('${item.variancePercent!.toStringAsFixed(1)}%',
                        style: theme.textTheme.bodySmall),
                  ])
                : isCounted
                    ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                    : const SizedBox(),
          ),
        ]),
      ),
    );
  }

  /// BUG-C: persist any typed-but-not-Enter counts before finalize. Without this
  /// a value typed then followed by a click on «إكمال» (no Enter in the field)
  /// never reached the DB, so finalize adjusted nothing yet still toasted success.
  Future<void> _flushPendingCounts(ICycleCountRepository repo, CycleCountState state) async {
    for (final v in state.taskItems) {
      final ctrl = _countCtrls[v.id];
      if (ctrl == null) continue;
      final txt = ctrl.text.trim();
      if (txt.isEmpty) continue;
      final qty = double.tryParse(txt);
      if (qty == null) continue;
      // Only write when it differs from what's already persisted.
      if (v.countedQty == null || (v.countedQty! - qty).abs() > 0.0001) {
        await repo.submitCount(itemId: v.id, countedQty: qty);
      }
    }
  }

  // ─── Analytics ──

  Widget _buildAnalyticsTab(ThemeData theme, ICycleCountRepository repo, CycleCountState state) {
    return FutureBuilder<double>(
      future: repo.getCountAccuracy(),
      builder: (ctx, snap) {
        final accuracy = snap.data ?? 100.0;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Text(tr('دقة الجرد'),
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CircularProgressIndicator(
                      value: accuracy / 100,
                      strokeWidth: 12,
                      backgroundColor: theme.colorScheme.surfaceContainerHigh,
                      color: accuracy >= 95 ? Colors.green : accuracy >= 80 ? Colors.amber : AppColors.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('${accuracy.toStringAsFixed(1)}%',
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              _statCard(theme, tr('إجمالي الخطط'), state.plans.length.toString(),
                  PhosphorIconsBold.listChecks, Colors.blue),
              const SizedBox(width: 12),
              _statCard(theme, tr('المهام المكتملة'),
                  state.tasks.where((t) => t.status == 'completed').length.toString(),
                  PhosphorIconsBold.checkCircle, Colors.green),
              const SizedBox(width: 12),
              _statCard(theme, tr('المهام المعلقة'),
                  state.tasks.where((t) => t.status == 'pending').length.toString(),
                  PhosphorIconsBold.clock, Colors.amber),
            ]),
          ]),
        );
      },
    );
  }

  Widget _statCard(ThemeData theme, String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: theme.textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }

  // ─── Dialogs ──

  Future<void> _showCreatePlanDialog(ICycleCountRepository repo, CycleCountController notifier) async {
    final nameCtrl = TextEditingController();
    String frequency = 'weekly';
    int productsPerTask = 20;
    int? warehouseId;
    final inventoryRepo = ref.read(inventoryRepositoryProvider);
    final warehouses = await inventoryRepo.watchWarehouses().first;
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title:  Row(children: [
          const Icon(PhosphorIconsBold.listChecks, color: Colors.indigo),
          const SizedBox(width: 8),
          Text(tr('خطة جرد جديدة')),
        ]),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameCtrl,
              decoration:  InputDecoration(labelText: tr('اسم الخطة'), border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              decoration:  InputDecoration(labelText: tr('المستودع'), border: const OutlineInputBorder()),
              items: warehouses.map((w) {
                return DropdownMenuItem(
                    value: w.id,
                    child: Text(trData(w.name)));
              }).toList(),
              onChanged: (v) => warehouseId = v,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: frequency,
              decoration:  InputDecoration(labelText: tr('التكرار'), border: const OutlineInputBorder()),
              items:  [
                DropdownMenuItem(value: 'daily', child: Text(tr('يومي'))),
                DropdownMenuItem(value: 'weekly', child: Text(tr('أسبوعي'))),
                DropdownMenuItem(value: 'monthly', child: Text(tr('شهري'))),
                DropdownMenuItem(value: 'quarterly', child: Text(tr('ربع سنوي'))),
              ],
              onChanged: (v) { if (v != null) frequency = v; },
            ),
            const SizedBox(height: 12),
            TextField(
              decoration:  InputDecoration(
                  labelText: tr('عدد الأصناف لكل مهمة'), border: const OutlineInputBorder()),
              keyboardType: TextInputType.number,
              controller: TextEditingController(text: '20'),
              onChanged: (v) => productsPerTask = int.tryParse(v) ?? 20,
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child:  Text(tr('إلغاء'))),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty || warehouseId == null) {
                AppToast.show(ctx, tr('يرجى ملء جميع الحقول'), type: ToastType.error);
                return;
              }
              await repo.createCycleCountPlan(
                name: nameCtrl.text, warehouseId: warehouseId!,
                frequency: frequency, productsPerTask: productsPerTask,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              notifier.refresh();
            },
            child:  Text(tr('إنشاء')),
          ),
        ],
      ),
    );
  }

  Future<void> _showGenerateTaskDialog(ICycleCountRepository repo, CycleCountState state, CycleCountController notifier) async {
    if (state.plans.isEmpty) {
      AppToast.show(context, tr('أنشئ خطة جرد أولاً'), type: ToastType.error);
      return;
    }
    // Second guard: state may have become empty due to a Riverpod rebuild race
    // between the isEmpty check above and the firstWhere below.
    if (state.plans.isEmpty) return;
    final plan = state.plans.firstWhere((p) => p.status == 'active', orElse: () => state.plans.first);
    final taskId = await repo.generateCycleCountTask(
      planId: plan.id, warehouseId: plan.warehouseId,
      productsPerTask: plan.productsPerTask,
    );
    if (taskId > 0 && mounted) {
      AppToast.show(context, tr('تم إنشاء مهمة جرد جديدة'));
      notifier.refresh();
    } else if (mounted) {
      AppToast.show(context, tr('لا توجد أصناف بمخزون لجردها'), type: ToastType.error);
    }
  }

  // ─── Helpers ──

  String _freqLabel(String f) =>
      {'daily': tr('يومي'), 'weekly': tr('أسبوعي'), 'monthly': tr('شهري'), 'quarterly': tr('ربع سنوي')}[f] ?? f;

  Icon _taskStatusIcon(String s) => switch (s) {
    'completed' => const Icon(Icons.check_circle, color: Colors.green, size: 20),
    'in_progress' => const Icon(Icons.hourglass_top, color: Colors.blue, size: 20),
    'cancelled' => const Icon(Icons.cancel, color: AppColors.error, size: 20),
    _ => const Icon(Icons.schedule, color: Colors.amber, size: 20),
  };
}
