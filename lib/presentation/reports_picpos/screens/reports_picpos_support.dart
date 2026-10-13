part of 'reports_picpos_screen.dart';

extension _ReportsPicposDialogs on _ReportsPicposScreenState {
  // -----------------------------------------------------------------------
  // Inline dialog reports (منسوخ حرفياً من legacy launcher الأصلي — بحاجة
  // Directionality خاصة بيها لأنها showDialog منفصل عن شجرة PicPosScreenScaffold).
  // -----------------------------------------------------------------------
  Future<void> _showLowStockReport() async {
    final repo = ref.read(productRepositoryProvider);
    final lowStockProducts = await repo.getLowStockProducts();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.warning, color: AppColors.error),
              const SizedBox(width: 8),
              Text(tr('أصناف منخفضة المخزون')),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 400,
            child: lowStockProducts.isEmpty
                ?  Center(child: Text(tr('لا توجد أصناف منخفضة المخزون 🎉')))
                : ListView.builder(
                    itemCount: lowStockProducts.length,
                    itemBuilder: (context, index) {
                      final p = lowStockProducts[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              AppColors.error.withValues(alpha: 0.1),
                          child: Text(
                            '${p.currentStock.toInt()}',
                            style: const TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(p.name),
                        subtitle: Text(tr('الحد الأدنى: {p0}', {'p0': p.minStock.toInt()})),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: p.currentStock <= 0
                                ? AppColors.error
                                : AppColors.warning,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            p.currentStock <= 0 ? tr('نفذ') : tr('منخفض'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:  Text(tr('إغلاق')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showExpiredProductsReport() async {
    final repo = ref.read(productRepositoryProvider);
    final expiredBatches = await repo.getExpiredBatches();
    final products = ref.read(allProductsProvider).value ?? [];
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.xCircle, color: AppColors.error),
              const SizedBox(width: 8),
              Text(tr('منتجات منتهية الصلاحية')),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 400,
            child: expiredBatches.isEmpty
                ?  Center(
                    child: Text(tr('🎉 لا توجد منتجات منتهية الصلاحية')))
                : ListView.builder(
                    itemCount: expiredBatches.length,
                    itemBuilder: (context, index) {
                      final batch = expiredBatches[index];
                      final product = products
                          .where((p) => p.id == batch.productId)
                          .firstOrNull;
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0x1AEF4444),
                          child: Icon(
                            PhosphorIconsBold.xCircle,
                            color: AppColors.error,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          product?.name ?? tr('منتج #{p0}', {'p0': batch.productId}),
                        ),
                        subtitle: Text(
                          tr('الباتش: {p0} - انتهى في {p1}', {'p0': batch.batchNumber, 'p1': DateFormat('dd/MM/yyyy').format(batch.expiryDate)}),
                        ),
                        trailing: Text(
                          tr('{p0} وحدة', {'p0': batch.quantity.toStringAsFixed(0)}),
                          style: const TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:  Text(tr('إغلاق')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showExpiringProductsReport() async {
    final repo = ref.read(productRepositoryProvider);
    final expiringBatches = await repo.getExpiringBatches(30);
    final products = ref.read(allProductsProvider).value ?? [];
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.clock, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(tr('تنتهي خلال 30 يوم')),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 400,
            child: expiringBatches.isEmpty
                ?  Center(
                    child: Text(tr('🎉 لا توجد منتجات قاربت على الانتهاء')),
                  )
                : ListView.builder(
                    itemCount: expiringBatches.length,
                    itemBuilder: (context, index) {
                      final batch = expiringBatches[index];
                      final product = products
                          .where((p) => p.id == batch.productId)
                          .firstOrNull;
                      final daysLeft = batch.expiryDate
                          .difference(DateTime.now())
                          .inDays;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: daysLeft <= 7
                              ? const Color(0x1AEF4444)
                              : const Color(0x1AF59E0B),
                          child: Text(
                            '$daysLeft',
                            style: TextStyle(
                              color: daysLeft <= 7
                                  ? AppColors.error
                                  : AppColors.warning,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          product?.name ?? tr('منتج #{p0}', {'p0': batch.productId}),
                        ),
                        subtitle: Text(
                          tr('الباتش: {p0} - ينتهي في {p1}', {'p0': batch.batchNumber, 'p1': DateFormat('dd/MM/yyyy').format(batch.expiryDate)}),
                        ),
                        trailing: Text(
                          tr('{p0} وحدة', {'p0': batch.quantity.toStringAsFixed(0)}),
                          style: TextStyle(
                            color: daysLeft <= 7
                                ? AppColors.error
                                : AppColors.warning,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:  Text(tr('إغلاق')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showArReconciliation() async {
    try {
      final result = await ref.read(arReconciliationProvider.future);
      if (!mounted) return;
      if (result == null) {
        showDialog(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title:  Text(tr('تسوية الذمم')),
            content:  Text(
                tr('لم يتم تعيين حساب الذمم (receivables) في الربط المحاسبي.')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child:  Text(tr('حسناً')),
              ),
            ],
          ),
        );
        return;
      }
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title:  Text(tr('تسوية الذمم مع الأستاذ العام')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  tr('حساب الذمم: {p0} — {p1}', {'p0': result.receivablesAccountCode, 'p1': result.receivablesAccountName})),
              const Divider(),
              _reconcRow(tr('رصيد بطاقات العملاء'), result.totalCardBalance),
              _reconcRow(tr('رصيد الأستاذ العام'), result.totalGlBalance),
              const Divider(),
              _reconcRow(tr('الفرق'), result.difference,
                  highlight: !result.isBalanced),
              if (result.isBalanced)
                 Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 16),
                    const SizedBox(width: 4),
                    Text(tr('مُتسوٍّ'), style: const TextStyle(color: Colors.green)),
                  ]),
                )
              else
                 Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    const Icon(Icons.warning, color: Colors.orange, size: 16),
                    const SizedBox(width: 4),
                    Text(tr('يوجد فرق — راجع القيود'),
                        style: const TextStyle(color: Colors.orange)),
                  ]),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child:  Text(tr('إغلاق')),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('خطأ: {e}', {'e': e}))));
    }
  }

  Future<void> _showInventoryGlReconciliation() async {
    try {
      // Read the CHECK provider (not a data-only one): opening the report runs
      // the reconciliation AND fires the diagnostic-log alert when inventory
      // drifts from GL 1136, then shows the same figures.
      final check =
          await ref.read(inventoryGlReconciliationCheckProvider.future);
      final result = check.reconciliation;
      if (!mounted) return;
      if (result == null) {
        showDialog(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title:  Text(tr('تسوية المخزون')),
            content:  Text(
                tr('لم يتم تعيين حساب المخزون (inventory) في الربط المحاسبي.')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child:  Text(tr('حسناً')),
              ),
            ],
          ),
        );
        return;
      }
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title:  Text(tr('تسوية المخزون مع الأستاذ العام')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  tr('حساب المخزون: {p0} — {p1}', {'p0': result.inventoryAccountCode, 'p1': trData(result.inventoryAccountName)})),
              const Divider(),
              _reconcRow(tr('قيمة المخزون (بالتكلفة)'), result.reportValue),
              _reconcRow(tr('رصيد الأستاذ العام'), result.glBalance),
              const Divider(),
              _reconcRow(tr('الفرق'), result.delta, highlight: !result.isBalanced),
              const SizedBox(height: 8),
               Text(tr('مصادر الفروق المحتملة:'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              _reconcRow(tr('فرق أساس التكلفة (متوسط المخزن مقابل التكلفة)'),
                  result.costBasisDivergence),
              _reconcRow(tr('فرق الرصيد الدفتري مقابل حركات المخازن'),
                  result.stockVsLedgerDivergence),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                    tr('أصناف بتكلفة صفر لها رصيد: {p0} صنف (كمية {p1})', {'p0': result.zeroCostItemCount, 'p1': result.zeroCostStockQty.toStringAsFixed(2)})),
              ),
              if (result.isBalanced)
                 Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 16),
                    const SizedBox(width: 4),
                    Text(tr('مُتسوٍّ'), style: const TextStyle(color: Colors.green)),
                  ]),
                )
              else
                 Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    const Icon(Icons.warning, color: Colors.orange, size: 16),
                    const SizedBox(width: 4),
                    Text(tr('يوجد فرق — راجع مصادر الفروق أعلاه'),
                        style: const TextStyle(color: Colors.orange)),
                  ]),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child:  Text(tr('إغلاق')),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('خطأ: {e}', {'e': e}))));
    }
  }

  Widget _reconcRow(String label, double value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value.toStringAsFixed(2),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: highlight ? AppColors.error : null,
            ),
          ),
        ],
      ),
    );
  }
}