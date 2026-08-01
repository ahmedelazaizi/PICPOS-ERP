part of '../distribution_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// VISITS TAB
// ═══════════════════════════════════════════════════════════════════════════

class _VisitsTab extends StatefulWidget {
  final WidgetRef ref;
  final String searchQuery;
  const _VisitsTab({required this.ref, this.searchQuery = ''});
  @override
  State<_VisitsTab> createState() => _VisitsTabState();
}

class _VisitsTabState extends State<_VisitsTab> {
  DateTime _selectedDate = DateTime.now();
  final _fmt = DateFormat('yyyy/MM/dd', 'ar');

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ref.watch(distributionControllerProvider);
    final from = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final to = from.add(const Duration(days: 1));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(PhosphorIconsBold.path, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'زيارات ${_fmt.format(_selectedDate)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => _selectedDate = picked);
                },
                icon: const Icon(PhosphorIconsBold.calendar, size: 18),
                label: const Text('تغيير التاريخ'),
              ),
              const SizedBox(width: 8),
              // نفس صلاحية إدارة التوزيع (المسارات) — التريّاج وقّف عند
              // تبويب المسارات بس، لكن الزيارات جزء من نفس الشاشة ونفس
              // الكود المتاح للوحدة، ومفيش كود تاني أدق ليها.
              PermissionGuard(
                permission: PermissionCodes.distributionManage,
                allowManagerOverride: true,
                actionName: 'إضافة زيارة',
                onGranted: () => _showAddVisitDialog(context, ctrl),
                child: ElevatedButton.icon(
                  onPressed: () => _showAddVisitDialog(context, ctrl),
                  icon: const Icon(PhosphorIconsBold.plus, size: 18),
                  label: const Text('إضافة زيارة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<SalesRoute>>(
            stream: ctrl.watchSalesRoutes(),
            builder: (context, routeSnap) {
              if (!routeSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final routes = routeSnap.data!;
              if (routes.isEmpty) {
                return Center(
                  child: Text(
                    'أضف مسارات أولاً',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: routes.length,
                itemBuilder: (context, i) {
                  final route = routes[i];
                  return StreamBuilder<List<RouteVisit>>(
                    stream: ctrl.watchRouteVisits(route.id, from, to),
                    builder: (context, visitSnap) {
                      final visits = visitSnap.data ?? [];
                      return ExpansionTile(
                        leading: const Icon(
                          PhosphorIconsBold.mapPin,
                          color: AppColors.primary,
                        ),
                        title: Text(
                          route.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('${visits.length} زيارة'),
                        children: visits.isEmpty
                            ? [
                                const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text(
                                    'لا توجد زيارات لهذا المسار اليوم',
                                  ),
                                ),
                              ]
                            : visits
                                  .map(
                                    (v) => ListTile(
                                      leading: Icon(
                                        _statusIcon(v.status),
                                        color: _statusColor(v.status),
                                      ),
                                      title: FutureBuilder<Party?>(
                                        future: ctrl.getPartyById(v.customerId),
                                        builder: (ctx, snap) => Text(
                                          snap.data?.name ??
                                              'عميل #${v.customerId}',
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${_statusLabel(v.status)}'
                                        '${v.orderAmount > 0 ? " • ${v.orderAmount.toStringAsFixed(0)} ${AppConstants.currencySymbol}" : ""}',
                                      ),
                                      trailing: PopupMenuButton<String>(
                                        tooltip: 'تغيير الحالة',
                                        icon: const Icon(
                                          PhosphorIconsBold.dotsThreeVertical,
                                        ),
                                        onSelected: (status) async {
                                          await ctrl
                                              .updateRouteVisitStatus(
                                            v.id,
                                            status,
                                          );
                                        },
                                        itemBuilder: (_) => [
                                          const PopupMenuItem(
                                            value: 'completed',
                                            child: Text('✅ مكتملة'),
                                          ),
                                          const PopupMenuItem(
                                            value: 'cancelled',
                                            child: Text('❌ ملغية'),
                                          ),
                                          const PopupMenuItem(
                                            value: 'skipped',
                                            child: Text('⏭ تخطي'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAddVisitDialog(BuildContext context, DistributionController ctrl) {
    int? selectedRouteId;
    int? selectedCustomerId;
    int? selectedRepId;
    final notesCtrl = TextEditingController();
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('إضافة زيارة'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Route
                StreamBuilder<List<SalesRoute>>(
                  stream: ctrl.watchSalesRoutes(),
                  builder: (ctx, snap) {
                    final routes = snap.data ?? [];
                    return DropdownButtonFormField<int>(
                      initialValue: selectedRouteId,
                      decoration: const InputDecoration(
                        labelText: 'المسار',
                        border: OutlineInputBorder(),
                      ),
                      items: routes
                          .map((r) => DropdownMenuItem(
                                value: r.id,
                                child: Text(r.name),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => selectedRouteId = v),
                    );
                  },
                ),
                const SizedBox(height: 12),
                // Employee
                FutureBuilder<List<Employee>>(
                  future: ctrl.getAllEmployees(),
                  builder: (ctx, snap) {
                    final employees = snap.data ?? [];
                    return DropdownButtonFormField<int>(
                      initialValue: selectedRepId,
                      decoration: const InputDecoration(
                        labelText: 'المندوب',
                        border: OutlineInputBorder(),
                      ),
                      items: employees
                          .map((e) => DropdownMenuItem(
                                value: e.id,
                                child: Text(e.name),
                              ))
                          .toList(),
                      onChanged: (v) => setDialogState(() => selectedRepId = v),
                    );
                  },
                ),
                const SizedBox(height: 12),
                // Customer
                FutureBuilder<List<Party>>(
                  future: ctrl.getAllCustomers(),
                  builder: (ctx, snap) {
                    final customers = snap.data ?? [];
                    return DropdownButtonFormField<int>(
                      initialValue: selectedCustomerId,
                      decoration: const InputDecoration(
                        labelText: 'العميل',
                        border: OutlineInputBorder(),
                      ),
                      items: customers
                          .map((c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.name),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => selectedCustomerId = v),
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (selectedRouteId == null ||
                          selectedCustomerId == null ||
                          selectedRepId == null) {
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await ctrl.createRouteVisit(
                          RouteVisitsCompanion(
                            routeId: Value(selectedRouteId!),
                            customerId: Value(selectedCustomerId!),
                            salesRepId: Value(selectedRepId!),
                            visitDate: Value(_selectedDate),
                            status: const Value('planned'),
                            notes: Value(
                              notesCtrl.text.isNotEmpty
                                  ? notesCtrl.text
                                  : null,
                            ),
                          ),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          AppToast.show(context, 'تمت إضافة الزيارة');
                        }
                      } finally {
                        if (ctx.mounted) setDialogState(() => saving = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary),
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(String s) => switch (s) {
    'completed' => PhosphorIconsBold.checkCircle,
    'cancelled' => PhosphorIconsBold.xCircle,
    'skipped' => PhosphorIconsBold.skipForward,
    _ => PhosphorIconsBold.clock,
  };
  Color _statusColor(String s) => switch (s) {
    'completed' => Colors.green,
    'cancelled' => Colors.red,
    'skipped' => Colors.orange,
    _ => Colors.blue,
  };
  String _statusLabel(String s) => switch (s) {
    'completed' => 'مكتملة',
    'cancelled' => 'ملغية',
    'skipped' => 'تم تخطيها',
    _ => 'مخططة',
  };
}
