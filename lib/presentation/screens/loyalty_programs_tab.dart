part of 'loyalty_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PROGRAMS TAB
// ═══════════════════════════════════════════════════════════════════════════

// ── دالة بناء مستخرجة (Task 6b) ─────────────────────────────────────────
// الحارس هنا (`PermissionGuard`) declarative بحت — زرار «إضافة برنامج» كان
// محمي بكود عرض خشن بس (`loyalty_view`)، مفيش فحص على الإنشاء نفسه. مستخرج
// كدالة top-level عشان يتبنى في اختبار widget خفيف من غير شاشة/قاعدة بيانات.
@visibleForTesting
Widget buildLoyaltyManageAddButton({required VoidCallback onPressed}) {
  return PermissionGuard(
    permission: PermissionCodes.loyaltyManage,
    allowManagerOverride: true,
    actionName: tr('إضافة برنامج ولاء'),
    onGranted: onPressed,
    child: ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(PhosphorIconsBold.plus, size: 18),
      label:  Text(tr('إضافة برنامج')),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
      ),
    ),
  );
}

class _ProgramsTab extends StatelessWidget {
  final WidgetRef ref;
  final String searchQuery;
  const _ProgramsTab({required this.ref, this.searchQuery = ''});

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(loyaltyRepositoryProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(PhosphorIconsBold.trophy, color: AppColors.primary),
              const SizedBox(width: 8),
               Text(
                tr('برامج الولاء'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              buildLoyaltyManageAddButton(
                onPressed: () => _showProgramDialog(context, repo),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<LoyaltyProgram>>(
            stream: repo.watchLoyaltyPrograms(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final programs = snapshot.data!;
              final filteredPrograms = searchQuery.isEmpty
                  ? programs
                  : programs.where((p) =>
                      p.name.toLowerCase().contains(searchQuery)
                    ).toList();
              if (filteredPrograms.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        PhosphorIconsBold.star,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        tr('لا توجد برامج ولاء'),
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr('أنشئ برنامج ولاء لمكافأة عملائك بالنقاط'),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: filteredPrograms.length,
                itemBuilder: (context, i) {
                  final p = filteredPrograms[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: p.isActive
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : Colors.grey.withValues(alpha: 0.1),
                        child: Icon(
                          PhosphorIconsBold.trophy,
                          color: p.isActive ? AppColors.primary : Colors.grey,
                        ),
                      ),
                      title: Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        tr('{p0} نقطة/وحدة • استبدال: {p1} • أقل: {p2}', {'p0': p.pointsPerUnit, 'p1': p.redemptionRate, 'p2': p.minRedeemPoints}),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Chip(
                            label: Text(p.isActive ? tr('نشط') : tr('معطل')),
                            backgroundColor: p.isActive
                                ? Colors.green.shade50
                                : Colors.grey.shade200,
                          ),
                          PermissionGuard(
                            permission: PermissionCodes.loyaltyManage,
                            allowManagerOverride: true,
                            actionName: tr('تعديل برنامج ولاء'),
                            onGranted: () =>
                                _showProgramDialog(context, repo, existing: p),
                            child: IconButton(
                              icon: const Icon(PhosphorIconsBold.pencilSimple),
                              tooltip: tr('تعديل'),
                              onPressed: () => _showProgramDialog(
                                  context, repo,
                                  existing: p),
                            ),
                          ),
                          PermissionGuard(
                            permission: PermissionCodes.loyaltyManage,
                            allowManagerOverride: true,
                            actionName: tr('حذف برنامج ولاء'),
                            onGranted: () =>
                                _confirmDeleteProgram(context, repo, p),
                            child: IconButton(
                              icon: const Icon(PhosphorIconsBold.trash,
                                color: AppColors.error,
                              ),
                              tooltip: tr('حذف'),
                              onPressed: () =>
                                  _confirmDeleteProgram(context, repo, p),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _confirmDeleteProgram(
    BuildContext context,
    ILoyaltyRepository repo,
    LoyaltyProgram program,
  ) {
    bool saving = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title:  Text(tr('حذف البرنامج')),
          content: Text(
            'هل أنت متأكد من حذف برنامج "${program.name}"؟\n'
            'سيتم حذف جميع النقاط والحركات المرتبطة.',
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      try {
                        await repo.deleteLoyaltyProgram(program.id);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          AppToast.show(context, tr('تم حذف البرنامج'));
                        }
                      } finally {
                        if (ctx.mounted) setDialogState(() => saving = false);
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  :  Text(tr('حذف')),
            ),
          ],
        ),
      ),
    );
  }

  void _showProgramDialog(
    BuildContext context,
    ILoyaltyRepository repo, {
    LoyaltyProgram? existing,
  }) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final ppuCtrl = TextEditingController(
      text: existing?.pointsPerUnit.toString() ?? '1',
    );
    final rrCtrl = TextEditingController(
      text: existing?.redemptionRate.toString() ?? '0.1',
    );
    final minCtrl = TextEditingController(
      text: existing?.minRedeemPoints.toString() ?? '100',
    );
    bool isActive = existing?.isActive ?? true;
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(
            existing != null ? tr('تعديل البرنامج') : tr('إضافة برنامج ولاء'),
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration:  InputDecoration(
                    labelText: tr('اسم البرنامج'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ppuCtrl,
                  keyboardType: TextInputType.number,
                  decoration:  InputDecoration(
                    labelText: tr('نقاط لكل وحدة عملة'),
                    helperText: tr('مثال: 1 = نقطة واحدة لكل 1 عملة'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: rrCtrl,
                  keyboardType: TextInputType.number,
                  decoration:  InputDecoration(
                    labelText: tr('قيمة استبدال النقطة'),
                    helperText: tr('مثال: 0.1 = كل نقطة تساوي 0.1 عملة'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: minCtrl,
                  keyboardType: TextInputType.number,
                  decoration:  InputDecoration(
                    labelText: tr('أقل عدد نقاط للاستبدال'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  title:  Text(tr('نشط')),
                  subtitle:  Text(tr('البرنامج يكسب نقاط عند البيع')),
                  value: isActive,
                  onChanged: (v) => setState(() => isActive = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      setState(() => saving = true);
                      try {
                        final data = LoyaltyProgramsCompanion(
                          name: Value(nameCtrl.text.trim()),
                          pointsPerUnit: Value(double.tryParse(ppuCtrl.text) ?? 1),
                          redemptionRate: Value(double.tryParse(rrCtrl.text) ?? 0.1),
                          minRedeemPoints: Value(int.tryParse(minCtrl.text) ?? 100),
                          isActive: Value(isActive),
                        );
                        if (existing != null) {
                          await repo.updateLoyaltyProgram(existing.id, data);
                        } else {
                          await repo.createLoyaltyProgram(data);
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          AppToast.show(
                            context,
                            existing != null
                                ? tr('تم تحديث البرنامج')
                                : tr('تم إضافة البرنامج'),
                          );
                        }
                      } finally {
                        if (ctx.mounted) setState(() => saving = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(existing != null ? tr('تحديث') : tr('إضافة')),
            ),
          ],
        ),
      ),
    );
  }
}
