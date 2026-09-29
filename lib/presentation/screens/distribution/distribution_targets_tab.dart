part of '../distribution_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TARGETS TAB
// ═══════════════════════════════════════════════════════════════════════════

class _TargetsTab extends StatefulWidget {
  final WidgetRef ref;
  final String searchQuery;
  const _TargetsTab({required this.ref, this.searchQuery = ''});
  @override
  State<_TargetsTab> createState() => _TargetsTabState();
}

class _TargetsTabState extends State<_TargetsTab> {
  DateTime _selectedMonth = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ref.watch(distributionControllerProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(PhosphorIconsBold.target, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                tr('أهداف {p0}', {'p0': DateFormat('MMMM yyyy', 'ar').format(_selectedMonth)}),
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
                    initialDate: _selectedMonth,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => _selectedMonth = picked);
                },
                icon: const Icon(PhosphorIconsBold.calendar, size: 18),
                label:  Text(tr('تغيير الشهر')),
              ),
              const SizedBox(width: 8),
              // نفس صلاحية إدارة التوزيع — راجع نفس التعليق في
              // distribution_visits_tab.dart.
              PermissionGuard(
                permission: PermissionCodes.distributionManage,
                allowManagerOverride: true,
                actionName: tr('إضافة هدف شهري'),
                onGranted: () => _showAddTargetDialog(context, ctrl),
                child: ElevatedButton.icon(
                  onPressed: () => _showAddTargetDialog(context, ctrl),
                  icon: const Icon(PhosphorIconsBold.plus, size: 18),
                  label:  Text(tr('إضافة هدف')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<SalesRepTarget>>(
            stream: ctrl.watchMonthlyTargets(
              _selectedMonth.year,
              _selectedMonth.month,
            ),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final targets = snapshot.data!;
              if (targets.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        PhosphorIconsBold.target,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tr('لا توجد أهداف لهذا الشهر'),
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: targets.length,
                itemBuilder: (context, i) {
                  final t = targets[i];
                  final pct = t.targetAmount > 0
                      ? (t.achievedAmount / t.targetAmount * 100).clamp(0, 100)
                      : 0.0;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FutureBuilder<Employee?>(
                            future: ctrl.getEmployeeById(t.salesRepId),
                            builder: (ctx, snap) => Text(
                              snap.data?.name ?? tr('مندوب #{p0}', {'p0': t.salesRepId}),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tr('الهدف: {p0} {p1}', {'p0': t.targetAmount.toStringAsFixed(0), 'p1': AppConstants.currencySymbol}),
                                    ),
                                    Text(
                                      tr('المحقق: {p0} {p1}', {'p0': t.achievedAmount.toStringAsFixed(0), 'p1': AppConstants.currencySymbol}),
                                      style: TextStyle(
                                        color: pct >= 100
                                            ? Colors.green
                                            : Colors.orange,
                                      ),
                                    ),
                                    if (t.targetVisits > 0)
                                      Text(
                                        tr('الزيارات: {p0}/{p1}', {'p0': t.achievedVisits, 'p1': t.targetVisits}),
                                      ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                height: 80,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      value: pct / 100,
                                      strokeWidth: 8,
                                      backgroundColor: Colors.grey.shade200,
                                      color: pct >= 100
                                          ? Colors.green
                                          : AppColors.primary,
                                    ),
                                    Text(
                                      '${pct.toStringAsFixed(0)}%',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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

  void _showAddTargetDialog(BuildContext context, DistributionController ctrl) {
    int? selectedRepId;
    final amountCtrl = TextEditingController();
    final visitsCtrl = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title:  Text(tr('إضافة هدف شهري')),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FutureBuilder<List<Employee>>(
                  future: ctrl.getAllEmployees(),
                  builder: (ctx, snap) {
                    final employees = snap.data ?? [];
                    return DropdownButtonFormField<int>(
                      initialValue: selectedRepId,
                      decoration:  InputDecoration(
                        labelText: tr('المندوب'),
                        border: const OutlineInputBorder(),
                      ),
                      items: employees
                          .map((e) => DropdownMenuItem(
                                value: e.id,
                                child: Text(e.name),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => selectedRepId = v),
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr('المبلغ المستهدف ({p0})', {'p0': AppConstants.currencySymbol}),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: visitsCtrl,
                  keyboardType: TextInputType.number,
                  decoration:  InputDecoration(
                    labelText: tr('الزيارات المستهدفة (اختياري)'),
                    border: const OutlineInputBorder(),
                  ),
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
              onPressed: () async {
                if (selectedRepId == null) return;
                final amount = double.tryParse(amountCtrl.text) ?? 0;
                if (amount <= 0) return;
                await ctrl.setSalesRepTarget(
                  salesRepId: selectedRepId!,
                  year: _selectedMonth.year,
                  month: _selectedMonth.month,
                  targetAmount: amount,
                  targetVisits: int.tryParse(visitsCtrl.text) ?? 0,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  AppToast.show(context, tr('تمت إضافة الهدف'));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child:  Text(tr('إضافة')),
            ),
          ],
        ),
      ),
    );
  }
}
