// جزء من شاشة الجرد (cycle_count_picpos_screen.dart) — تبويب الخطط، بلا تغيير سلوكي.
part of 'cycle_count_picpos_screen.dart';

extension _CycleCountPlansTab on _CycleCountPicposScreenState {
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
                  try {
                    final taskId = await repo.generateCycleCountTask(
                      planId: plan.id, warehouseId: plan.warehouseId,
                      productsPerTask: plan.productsPerTask, abcClassification: plan.abcClassification,
                    );
                    if (!mounted) return;
                    if (taskId > 0) {
                      AppToast.show(context, tr('تم إنشاء مهمة جرد جديدة'));
                      notifier.refresh();
                      _tabController.animateTo(1);
                    } else {
                      AppToast.show(context, tr('لا توجد أصناف موجبة المخزون متاحة للجرد'));
                    }
                  } on db.CycleCountGenerationException catch (e) {
                    if (mounted) AppToast.show(context, e.message);
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

  String _freqLabel(String f) =>
      {'daily': tr('يومي'), 'weekly': tr('أسبوعي'), 'monthly': tr('شهري'), 'quarterly': tr('ربع سنوي')}[f] ?? f;
}
