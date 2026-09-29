part of 'operational_expenses_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TAB 2: EXPENSE RECORDS — سجل المصروفات
// ═══════════════════════════════════════════════════════════════════════════

class _ExpensesTab extends ConsumerWidget {
  final DateTimeRange dateRange;
  final ValueChanged<DateTimeRange> onDateRangeChanged;

  const _ExpensesTab({
    required this.dateRange,
    required this.onDateRangeChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(manufacturingRepositoryProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showExpenseDialog(context, ref),
        icon: const Icon(Icons.add),
        label:  Text(tr('مصروف جديد')),
        backgroundColor: Colors.orange,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Date range picker
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(PhosphorIconsBold.calendarBlank,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    tr('من {p0} إلى {p1}', {'p0': _formatDate(dateRange.start), 'p1': _formatDate(dateRange.end)}),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        initialDateRange: dateRange,
                      );
                      if (picked != null) onDateRangeChanged(picked);
                    },
                    child:  Text(tr('تغيير')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Expense list
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: () async {
                  // Phase 5C.3 (Issue 4) — branch-scope guard. Same
                  // pattern as the sales / purchases controllers: the
                  // expenses report query has no native branch scope
                  // yet (would need a DAO change), so we filter the
                  // result list here. Admin (BranchScope.fullAccess)
                  // skips. Restricted users only see expenses whose
                  // branch_id is in their allowed set OR is null
                  // (legacy data without a branch link stays visible).
                  final all = await repo.getExpensesReport(
                      from: dateRange.start, to: dateRange.end);
                  final scope =
                      await ref.read(branchScopeProvider.future);
                  if (scope.hasFullAccess) return all;
                  return all.where((e) {
                    final bid = e['branch_id'] ?? e['branchId'];
                    final asInt = bid is int ? bid : int.tryParse(bid?.toString() ?? '');
                    return scope.isAllowed(asInt);
                  }).toList();
                }(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final expenses = snapshot.data ?? [];
                  if (expenses.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsBold.receipt,
                              size: 64,
                              color: AppColors.textMuted.withValues(alpha: 0.3)),
                          const SizedBox(height: 16),
                           Text(tr('لا توجد مصروفات في هذه الفترة'),
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 16)),
                        ],
                      ),
                    );
                  }

                  // Summary card
                  double total = 0;
                  for (final e in expenses) {
                    total +=
                        (e['amount'] as num?)?.toDouble() ?? 0;
                  }

                  return Column(
                    children: [
                      // Summary
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            Colors.orange.shade400,
                            Colors.deepOrange.shade400,
                          ]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(PhosphorIconsBold.chartBar,
                                color: Colors.white, size: 28),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                 Text(tr('إجمالي المصروفات'),
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12)),
                                Text(
                                  '${total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Text(tr('{p0} سجل', {'p0': expenses.length}),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // List
                      Expanded(
                        child: ListView.builder(
                          itemCount: expenses.length,
                          itemBuilder: (context, index) {
                            final exp = expenses[index];
                            final amount =
                                (exp['amount'] as num?)?.toDouble() ?? 0;
                            final catName =
                                exp['category_name'] as String? ?? '';
                            final catType =
                                exp['category_type'] as String? ?? '';
                            final notes = exp['notes'] as String? ?? '';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color:
                                        Colors.grey.withValues(alpha: 0.15)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                        PhosphorIconsBold.coins,
                                        size: 18,
                                        color: Colors.orange),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(catName,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13)),
                                        if (notes.isNotEmpty)
                                          Text(notes,
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      AppColors.textMuted)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${amount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Colors.orange),
                                      ),
                                      Text(catType,
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: AppColors.textMuted)),
                                    ],
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      final id = exp['id'] as int?;
                                      if (id != null) _confirmDelete(context, ref, id);
                                    },
                                    icon: const Icon(PhosphorIconsBold.trash,
                                        size: 16, color: AppColors.error),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showExpenseDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => const OpexRecordEditDialog(),
    ).then((_) => onDateRangeChanged(dateRange)); // Refresh list
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, int id) async {
    bool saving = false;

    final confirmed = await AppConfirmDialog.show(
      context,
      title: tr('تأكيد الحذف'),
      message: tr('هل أنت متأكد من حذف هذا المصروف؟'),
      confirmLabel: tr('حذف'),
      isDangerous: true,
    );

    if (confirmed == true) {
  // ignore: dead_code
      if (saving) return;
      saving = true;
      try {
        final repo = ref.read(manufacturingRepositoryProvider);
        await repo.deleteExpense(id);
        onDateRangeChanged(dateRange);
      } catch (_) {
        saving = false;
        rethrow;
      }
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}
