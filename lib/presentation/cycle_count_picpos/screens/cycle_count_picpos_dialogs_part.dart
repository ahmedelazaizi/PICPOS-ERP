// جزء من شاشة الجرد (cycle_count_picpos_screen.dart) — الحوارات، بلا تغيير سلوكي.
part of 'cycle_count_picpos_screen.dart';

extension _CycleCountDialogs on _CycleCountPicposScreenState {
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
    try {
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
    } on db.CycleCountGenerationException catch (e) {
      if (mounted) AppToast.show(context, e.message);
    }
  }
}
