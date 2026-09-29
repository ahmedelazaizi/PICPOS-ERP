part of '../distribution_screen.dart';

// زرار «إضافة مسار» — `distribution_manage`. مستخرج كدالة top-level مستقلة
// عن `AppDatabase`/`DistributionController` عشان يتبنى في اختبار widget
// خفيف (Task 6a) — تركيب الشاشة كلها بقاعدة بيانات حقيقية علّق الاختبارات.
@visibleForTesting
Widget buildDistributionManageAddButton({required VoidCallback onPressed}) {
  return PermissionGuard(
    permission: PermissionCodes.distributionManage,
    allowManagerOverride: true,
    actionName: tr('إضافة مسار توزيع'),
    onGranted: onPressed,
    child: ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(PhosphorIconsBold.plus, size: 18),
      label:  Text(tr('إضافة مسار')),
      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// ROUTES TAB
// ═══════════════════════════════════════════════════════════════════════════

class _RoutesTab extends StatelessWidget {
  final WidgetRef ref;
  final String searchQuery;
  const _RoutesTab({required this.ref, this.searchQuery = ''});

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.watch(distributionControllerProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(PhosphorIconsBold.mapPin, color: AppColors.primary),
              const SizedBox(width: 8),
               Text(
                tr('مسارات التوزيع'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              buildDistributionManageAddButton(
                onPressed: () => _showRouteDialog(context, ctrl),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<SalesRoute>>(
            stream: ctrl.watchSalesRoutes(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final routes = snapshot.data!;
              final filteredRoutes = searchQuery.isEmpty
                  ? routes
                  : routes.where((r) =>
                      r.name.toLowerCase().contains(searchQuery) ||
                      (r.area ?? '').toLowerCase().contains(searchQuery) ||
                      (r.description ?? '').toLowerCase().contains(searchQuery)
                    ).toList();
              if (filteredRoutes.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        PhosphorIconsBold.mapPinLine,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        tr('لا توجد مسارات'),
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr('أنشئ مسارات توزيع لتنظيم زيارات المندوبين'),
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
                itemCount: filteredRoutes.length,
                itemBuilder: (context, i) {
                  final r = filteredRoutes[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.1,
                        ),
                        child: const Icon(
                          PhosphorIconsBold.mapPin,
                          color: AppColors.primary,
                        ),
                      ),
                      title: Text(
                        r.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(r.area ?? r.description ?? tr('بدون وصف')),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (r.salesRepId != null)
                            FutureBuilder<Employee?>(
                              future: ctrl.getEmployeeById(r.salesRepId!),
                              builder: (ctx, snap) =>
                                  Chip(label: Text(snap.data?.name ?? '...')),
                            ),
                          PermissionGuard(
                            permission: PermissionCodes.distributionManage,
                            allowManagerOverride: true,
                            actionName: tr('تعديل مسار توزيع'),
                            onGranted: () =>
                                _showRouteDialog(context, ctrl, existing: r),
                            child: IconButton(
                              icon: const Icon(PhosphorIconsBold.pencilSimple),
                              tooltip: tr('تعديل'),
                              onPressed: () =>
                                  _showRouteDialog(context, ctrl, existing: r),
                            ),
                          ),
                          PermissionGuard(
                            permission: PermissionCodes.distributionManage,
                            allowManagerOverride: true,
                            actionName: tr('حذف مسار توزيع'),
                            onGranted: () => _confirmDelete(context, ctrl, r),
                            child: IconButton(
                              icon: const Icon(PhosphorIconsBold.trash,
                                color: AppColors.error,
                              ),
                              tooltip: tr('حذف'),
                              onPressed: () => _confirmDelete(context, ctrl, r),
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

  void _confirmDelete(
    BuildContext context,
    DistributionController ctrl,
    SalesRoute route,
  ) {
    bool saving = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title:  Text(tr('حذف المسار')),
          content: Text(tr('هل أنت متأكد من حذف مسار "{p0}"؟', {'p0': route.name})),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      try {
                        await ctrl.deactivateSalesRoute(route.id);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          AppToast.show(context, tr('تم حذف المسار'));
                        }
                      } finally {
                        if (ctx.mounted) setDialogState(() => saving = false);
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child:  Text(tr('حذف')),
            ),
          ],
        ),
      ),
    );
  }

  void _showRouteDialog(
    BuildContext context,
    DistributionController ctrl, {
    SalesRoute? existing,
  }) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final areaCtrl = TextEditingController(text: existing?.area ?? '');
    int? selectedRepId = existing?.salesRepId;
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing != null ? tr('تعديل مسار') : tr('إضافة مسار توزيع')),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration:  InputDecoration(
                    labelText: tr('اسم المسار'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: areaCtrl,
                  decoration:  InputDecoration(
                    labelText: tr('المنطقة'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration:  InputDecoration(
                    labelText: tr('وصف'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                // Sales Rep selector
                FutureBuilder<List<Employee>>(
                  future: ctrl.getAllEmployees(),
                  builder: (ctx, snap) {
                    final employees = snap.data ?? [];
                    return DropdownButtonFormField<int?>(
                      initialValue: selectedRepId,
                      decoration:  InputDecoration(
                        labelText: tr('المندوب المسؤول'),
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                         DropdownMenuItem(
                          value: null,
                          child: Text(tr('بدون مندوب')),
                        ),
                        ...employees.map(
                          (e) => DropdownMenuItem(
                            value: e.id,
                            child: Text(e.name),
                          ),
                        ),
                      ],
                      onChanged: (v) => setDialogState(() => selectedRepId = v),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      setDialogState(() => saving = true);
                      try {
                        final data = SalesRoutesCompanion(
                          name: Value(nameCtrl.text.trim()),
                          description: Value(
                            descCtrl.text.isNotEmpty ? descCtrl.text : null,
                          ),
                          area: Value(
                            areaCtrl.text.isNotEmpty ? areaCtrl.text : null,
                          ),
                          salesRepId: Value(selectedRepId),
                        );
                        if (existing != null) {
                          await ctrl.updateSalesRoute(existing.id, data);
                        } else {
                          await ctrl.createSalesRoute(data);
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          AppToast.show(
                            context,
                            existing != null
                                ? tr('تم تحديث المسار')
                                : tr('تم إضافة المسار'),
                          );
                        }
                      } finally {
                        if (ctx.mounted) setDialogState(() => saving = false);
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text(existing != null ? tr('تحديث') : tr('إضافة')),
            ),
          ],
        ),
      ),
    );
  }
}
