part of '../distribution_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// COLLECTIONS TAB
// ═══════════════════════════════════════════════════════════════════════════

class _CollectionsTab extends StatefulWidget {
  final WidgetRef ref;
  final String searchQuery;
  const _CollectionsTab({required this.ref, this.searchQuery = ''});
  @override
  State<_CollectionsTab> createState() => _CollectionsTabState();
}

class _CollectionsTabState extends State<_CollectionsTab> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now().add(const Duration(days: 1));
  final _fmt = DateFormat('yyyy/MM/dd', 'ar');

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ref.watch(distributionControllerProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(PhosphorIconsBold.money, color: AppColors.primary),
              const SizedBox(width: 8),
               Text(
                tr('التحصيلات'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDateRange: DateTimeRange(start: _from, end: _to),
                  );
                  if (range != null) {
                    setState(() {
                      _from = range.start;
                      _to = range.end.add(const Duration(days: 1));
                    });
                  }
                },
                icon: const Icon(PhosphorIconsBold.calendar, size: 18),
                label: Text(
                  '${_fmt.format(_from)} - ${_fmt.format(_to)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(width: 8),
              // نفس صلاحية إدارة التوزيع — راجع نفس التعليق في
              // distribution_visits_tab.dart. التحصيل كمان أثره مالي مباشر
              // (يتربط بحساب المندوب)، فلا شك إنه نفس فئة إدارة التوزيع.
              PermissionGuard(
                permission: PermissionCodes.distributionManage,
                allowManagerOverride: true,
                actionName: tr('إضافة تحصيل'),
                onGranted: () => _showAddCollectionDialog(context, ctrl),
                child: ElevatedButton.icon(
                  onPressed: () => _showAddCollectionDialog(context, ctrl),
                  icon: const Icon(PhosphorIconsBold.plus, size: 18),
                  label:  Text(tr('إضافة تحصيل')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<SalesRepCollection>>(
            stream: ctrl.watchAllCollections(_from, _to),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final cols = snapshot.data!;
              if (cols.isEmpty) {
                return Center(
                  child: Text(
                    tr('لا توجد تحصيلات'),
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                );
              }
              final total = cols.fold(0.0, (sum, c) => sum + c.amount);
              return Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          PhosphorIconsBold.currencyCircleDollar,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          tr('إجمالي التحصيلات: {p0} {p1}', {'p0': total.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbol}),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: cols.length,
                      itemBuilder: (context, i) {
                        final c = cols[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.green.withValues(
                                alpha: 0.1,
                              ),
                              child: const Icon(
                                PhosphorIconsBold.money,
                                color: Colors.green,
                              ),
                            ),
                            title: FutureBuilder<Party?>(
                              future: ctrl.getPartyById(c.customerId),
                              builder: (ctx, snap) => Text(
                                snap.data?.name ?? tr('عميل #{p0}', {'p0': c.customerId}),
                              ),
                            ),
                            subtitle: Text(
                              '${_paymentName(c.paymentMethod)}'
                              '${c.referenceNumber != null ? " - ${c.referenceNumber}" : ""}',
                            ),
                            trailing: Text(
                              '${c.amount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbol}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
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
    );
  }

  void _showAddCollectionDialog(
    BuildContext context,
    DistributionController ctrl,
  ) {
    int? selectedRepId;
    int? selectedCustomerId;
    String paymentMethod = 'cash';
    final amountCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title:  Text(tr('إضافة تحصيل')),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
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
                        onChanged: (v) =>
                            setDialogState(() => selectedRepId = v),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<List<Party>>(
                    future: ctrl.getAllCustomers(),
                    builder: (ctx, snap) {
                      final customers = snap.data ?? [];
                      return DropdownButtonFormField<int>(
                        initialValue: selectedCustomerId,
                        decoration:  InputDecoration(
                          labelText: tr('العميل'),
                          border: const OutlineInputBorder(),
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
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: tr('المبلغ ({p0})', {'p0': AppConstants.currencySymbol}),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: paymentMethod,
                    decoration:  InputDecoration(
                      labelText: tr('طريقة الدفع'),
                      border: const OutlineInputBorder(),
                    ),
                    items:  [
                      DropdownMenuItem(value: 'cash', child: Text(tr('نقدي'))),
                      DropdownMenuItem(value: 'check', child: Text(tr('شيك'))),
                      DropdownMenuItem(
                        value: 'transfer',
                        child: Text(tr('تحويل بنكي')),
                      ),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => paymentMethod = v ?? 'cash'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: refCtrl,
                    decoration:  InputDecoration(
                      labelText: tr('رقم المرجع (اختياري)'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    decoration:  InputDecoration(
                      labelText: tr('ملاحظات (اختياري)'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
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
                      if (selectedRepId == null ||
                          selectedCustomerId == null) return;
                      final amount = double.tryParse(amountCtrl.text) ?? 0;
                      if (amount <= 0) return;
                      setDialogState(() => saving = true);
                      try {
                        await ctrl.createCollection(
                          SalesRepCollectionsCompanion(
                            salesRepId: Value(selectedRepId!),
                            customerId: Value(selectedCustomerId!),
                            amount: Value(amount),
                            paymentMethod: Value(paymentMethod),
                            referenceNumber: Value(
                              refCtrl.text.isNotEmpty ? refCtrl.text : null,
                            ),
                            notes: Value(
                              notesCtrl.text.isNotEmpty
                                  ? notesCtrl.text
                                  : null,
                            ),
                          ),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          AppToast.show(context, tr('تم تسجيل التحصيل'));
                        }
                      } finally {
                        if (ctx.mounted) setDialogState(() => saving = false);
                      }
                    },
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child:  Text(tr('إضافة')),
            ),
          ],
        ),
      ),
    );
  }

  String _paymentName(String m) => switch (m) {
    'cash' => tr('نقدي'),
    'check' => tr('شيك'),
    'transfer' => tr('تحويل'),
    _ => m,
  };
}
