// جزء من شاشة الجرد (cycle_count_picpos_screen.dart) — تبويب المهام وبنود العدّ، بلا تغيير سلوكي.
part of 'cycle_count_picpos_screen.dart';

extension _CycleCountTasksTab on _CycleCountPicposScreenState {
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

  Icon _taskStatusIcon(String s) => switch (s) {
    'completed' => const Icon(Icons.check_circle, color: Colors.green, size: 20),
    'in_progress' => const Icon(Icons.hourglass_top, color: Colors.blue, size: 20),
    'cancelled' => const Icon(Icons.cancel, color: AppColors.error, size: 20),
    _ => const Icon(Icons.schedule, color: Colors.amber, size: 20),
  };
}
