part of '../../manufacturing_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TAB 2: PRODUCTION ORDERS — أوامر الإنتاج
// ═══════════════════════════════════════════════════════════════════════════

class _ProductionOrdersTab extends ConsumerWidget {
  const _ProductionOrdersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(manufacturingOrdersProvider);
    final bomsAsync = ref.watch(allBomsProvider);
    final productsAsync = ref.watch(allProductsProvider);

    return ordersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(tr('خطأ: {e}', {'e': e}))),
      data: (orders) {
        final boms = bomsAsync.value ?? [];
        final products = productsAsync.value ?? [];

        return Column(
          children: [
            // Toolbar
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Status filter chips
                  ..._statusFilters(context, ref, orders),
                  const Spacer(),
                  PermissionGuard(
                    permission: PermissionCodes.manufacturingManage,
                    allowManagerOverride: true,
                    actionName: tr('إنشاء أمر إنتاج'),
                    onGranted: boms.isEmpty
                        ? null
                        : () => _showOrderDialog(context, ref, boms, products),
                    child: ElevatedButton.icon(
                      onPressed: boms.isEmpty
                          ? null
                          : () =>
                              _showOrderDialog(context, ref, boms, products),
                      icon: const Icon(PhosphorIconsBold.plus, size: 18),
                      label:  Text(tr('أمر إنتاج جديد')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Orders list
            Expanded(
              child: orders.isEmpty
                  ? _buildEmptyState(
                      context,
                      icon: PhosphorIconsBold.gearSix,
                      title: tr('لا توجد أوامر إنتاج'),
                      subtitle:
                          tr('أنشئ أول أمر إنتاج لبدء تحويل الخامات إلى منتجات تامة'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: orders.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final order = orders[index];
                        final bom = boms
                            .where((b) => b.id == order.bomId)
                            .firstOrNull;
                        final product = bom != null
                            ? products
                                .where(
                                    (p) => p.id == bom.finishedProductId)
                                .firstOrNull
                            : null;

                        return _ProductionOrderCard(
                          order: order,
                          productName: product?.name ?? tr('غير معروف'),
                          bomCode: bom?.bomCode ?? '-',
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _statusFilters(
      BuildContext context, WidgetRef ref, List<ManufacturingOrderData> orders) {
    final statuses = {
      null: tr('الكل ({p0})', {'p0': orders.length}),
      'draft': 'مسودة (${orders.where((o) => o.status == 'draft').length})',
      'in_progress':
          'قيد التنفيذ (${orders.where((o) => o.status == 'in_progress').length})',
      'completed':
          'مكتمل (${orders.where((o) => o.status == 'completed').length})',
    };

    final selectedFilter = ref.watch(manufacturingStatusFilterProvider);

    return statuses.entries.map((e) {
      final isSelected = e.key == selectedFilter;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: FilterChip(
          label: Text(e.value, style: const TextStyle(fontSize: 12)),
          selected: isSelected,
          onSelected: (_) =>
              ref.read(manufacturingStatusFilterProvider.notifier).set(e.key),
          selectedColor: AppColors.primary.withValues(alpha: 0.15),
          checkmarkColor: AppColors.primary,
          backgroundColor: Colors.grey.shade100,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }).toList();
  }

  void _showOrderDialog(BuildContext context, WidgetRef ref,
      List<BillOfMaterialData> boms, List<ProductEntity> products,
      [ManufacturingOrderData? existingOrder]) {
    showDialog(
      context: context,
      builder: (ctx) => _ProductionOrderDialog(
          boms: boms, products: products, existingOrder: existingOrder),
    );
  }
}

// ─── Production Order Card ───────────────────────────────────────────────

class _ProductionOrderCard extends ConsumerWidget {
  final ManufacturingOrderData order;
  final String productName;
  final String bomCode;

  const _ProductionOrderCard({
    required this.order,
    required this.productName,
    required this.bomCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final costsAsync = ref.watch(mfgOrderCostBreakdownProvider(order.id));
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _statusColor(order.status).withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Status indicator
              Container(
                width: 4,
                height: 60,
                decoration: BoxDecoration(
                  color: _statusColor(order.status),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(order.orderNumber,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 14)),
                        const SizedBox(width: 10),
                        _StatusChip(status: order.status),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(PhosphorIconsBold.package,
                            size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(productName,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textSecondary)),
                        const SizedBox(width: 16),
                        const Icon(PhosphorIconsBold.listDashes,
                            size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text('BOM: $bomCode',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textMuted)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                            tr('الكمية المطلوبة: {p0}', {'p0': order.orderedQty.toStringAsFixed(0)}),
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 16),
                        Text(
                            tr('المنتج: {p0}', {'p0': order.producedQty.toStringAsFixed(0)}),
                            style: TextStyle(
                                fontSize: 12,
                                color: order.producedQty > 0
                                    ? Colors.green
                                    : AppColors.textMuted)),
                        if (order.totalCost > 0) ...[
                          const SizedBox(width: 16),
                          Text(tr('التكلفة: {p0}', {'p0': order.totalCost.toStringAsFixed(AppConstants.decimalPlaces)}),
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.orange)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Actions
              _buildActions(context, ref),
            ],
          ),
          // Cost breakdown chips
          costsAsync.when(
            data: (breakdown) {
              if (breakdown.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsetsDirectional.only(top: 10, start: 18),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: breakdown.entries.map((e) {
                    final label = _costTypeLabel(e.key);
                    final color = _costTypeColor(e.key);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '$label: ${e.value.toStringAsFixed(AppConstants.decimalPlaces)}',
                        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  String _costTypeLabel(String type) {
    switch (type) {
      case 'raw_material': return tr('خامات');
      case 'labor': return tr('عمالة');
      case 'overhead': return tr('تكاليف غير مباشرة');
      case 'depreciation': return tr('إهلاك');
      case 'utility': return tr('مرافق');
      default: return 'أخرى';
    }
  }

  Color _costTypeColor(String type) {
    switch (type) {
      case 'raw_material': return Colors.blue;
      case 'labor': return Colors.green;
      case 'overhead': return Colors.orange;
      case 'depreciation': return Colors.purple;
      case 'utility': return Colors.teal;
      default: return Colors.grey;
    }
  }

  Widget _buildActions(BuildContext context, WidgetRef ref) {
    switch (order.status) {
      case 'draft':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PermissionGuard(
              permission: PermissionCodes.manufacturingManage,
              allowManagerOverride: true,
              actionName: tr('تعديل أمر إنتاج'),
              onGranted: () => _editOrder(context, ref),
              child: _actionButton(
                context,
                ref,
                icon: PhosphorIconsBold.pencilSimple,
                label: tr('تعديل'),
                color: AppColors.primary,
                onTap: () => _editOrder(context, ref),
              ),
            ),
            const SizedBox(width: 8),
            _actionButton(
              context,
              ref,
              icon: PhosphorIconsBold.plus,
              label: tr('تكلفة'),
              color: Colors.orange,
              onTap: () => _showAddCostDialog(context, ref),
            ),
            const SizedBox(width: 8),
            _actionButton(
              context,
              ref,
              icon: PhosphorIconsBold.play,
              label: tr('بدء'),
              color: Colors.blue,
              onTap: () => _startProduction(context, ref),
            ),
            const SizedBox(width: 8),
            _actionButton(
              context,
              ref,
              icon: PhosphorIconsBold.x,
              label: tr('إلغاء'),
              color: AppColors.error,
              onTap: () => _cancelOrder(context, ref),
            ),
          ],
        );
      case 'in_progress':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _actionButton(
              context,
              ref,
              icon: PhosphorIconsBold.plus,
              label: tr('تكلفة'),
              color: Colors.orange,
              onTap: () => _showAddCostDialog(context, ref),
            ),
            const SizedBox(width: 8),
            _actionButton(
              context,
              ref,
              icon: PhosphorIconsBold.check,
              label: tr('إتمام'),
              color: Colors.green,
              onTap: () => _completeProduction(context, ref),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _actionButton(
    BuildContext context,
    WidgetRef ref, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editOrder(BuildContext context, WidgetRef ref) async {
    final bomsAsync = ref.read(allBomsProvider);
    final productsAsync = ref.read(allProductsProvider);
    final boms = bomsAsync.value ?? [];
    final products = productsAsync.value ?? [];
    if (boms.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => _ProductionOrderDialog(
        boms: boms,
        products: products,
        existingOrder: order,
      ),
    );
  }

  Future<void> _startProduction(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:  Text(tr('بدء التصنيع')),
          content: Text(
              tr('سيتم سحب المواد الخام من المخزن.\nالمنتج: {productName}\nالكمية: {p0}\n\nهل تريد المتابعة؟', {'productName': productName, 'p0': order.orderedQty.toStringAsFixed(0)})),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child:  Text(tr('إلغاء'))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child:  Text(tr('بدء التصنيع')),
            ),
          ],
        ),
      ),
    );
    if (confirm == true) {
      try {
        final mfgRepo = ref.read(manufacturingRepositoryProvider);
        await mfgRepo.startProduction(order.id);
        ref.invalidate(manufacturingOrdersProvider);
        if (context.mounted) {
          AppToast.show(context, tr('✅ تم بدء التصنيع — تم سحب المواد الخام'));
        }
      } catch (e) {
        if (context.mounted) {
          AppToast.show(context, tr('❌ خطأ: {e}', {'e': e}), type: ToastType.error);
        }
      }
    }
  }

  Future<void> _completeProduction(BuildContext context, WidgetRef ref) async {
    final qtyController =
        TextEditingController(text: order.orderedQty.toStringAsFixed(0));

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:  Text(tr('إتمام الإنتاج')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('المنتج: {productName}', {'productName': productName})),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                decoration:  InputDecoration(
                  labelText: tr('الكمية المنتجة فعلاً'),
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child:  Text(tr('إلغاء'))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child:  Text(tr('إتمام')),
            ),
          ],
        ),
      ),
    );
    if (confirm == true) {
      try {
        final mfgRepo = ref.read(manufacturingRepositoryProvider);
        final producedQty = double.tryParse(qtyController.text);
        await mfgRepo.completeProduction(order.id,
            actualProducedQty: producedQty);
        ref.invalidate(manufacturingOrdersProvider);
        if (context.mounted) {
          AppToast.show(context, tr('✅ تم إتمام الإنتاج — تم إضافة المنتج التام للمخزن'));
        }
      } catch (e) {
        if (context.mounted) {
          AppToast.show(context, tr('❌ خطأ: {e}', {'e': e}), type: ToastType.error);
        }
      }
    }
    qtyController.dispose();
  }

  Future<void> _cancelOrder(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:  Text(tr('إلغاء أمر الإنتاج')),
          content:  Text(tr('هل أنت متأكد من إلغاء أمر الإنتاج هذا؟')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child:  Text(tr('رجوع'))),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                   Text(tr('إلغاء الأمر'), style: const TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      ),
    );
    if (confirm == true) {
      try {
        final mfgRepo = ref.read(manufacturingRepositoryProvider);
        await mfgRepo.cancelManufacturingOrder(order.id);
        ref.invalidate(manufacturingOrdersProvider);
      } catch (e) {
        if (context.mounted) {
          AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
        }
      }
    }
  }

  Future<void> _showAddCostDialog(BuildContext context, WidgetRef ref) async {
    final amountController = TextEditingController();
    final descController = TextEditingController();
    String selectedType = 'labor';

    final costTypes = {
      'labor': tr('عمالة مباشرة'),
      'utility': tr('كهرباء / ماء / وقود'),
      'overhead': tr('تكاليف غير مباشرة'),
      'depreciation': tr('إهلاك معدات'),
      'other': tr('أخرى'),
    };

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Row(
              children: [
                const Icon(PhosphorIconsBold.money, color: Colors.orange),
                const SizedBox(width: 8),
                Text(tr('إضافة تكلفة — {p0}', {'p0': order.orderNumber})),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration:  InputDecoration(
                      labelText: tr('نوع التكلفة'),
                      border: const OutlineInputBorder(),
                    ),
                    items: costTypes.entries
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => selectedType = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    decoration: InputDecoration(
                      labelText: tr('المبلغ'),
                      border: const OutlineInputBorder(),
                      suffixText: AppConstants.currencySymbol,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    decoration:  InputDecoration(
                      labelText: tr('الوصف (اختياري)'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child:  Text(tr('إلغاء')),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.add),
                label:  Text(tr('إضافة')),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true) {
      final amount = double.tryParse(amountController.text) ?? 0;
      if (amount <= 0) return;
      try {
        final mfgRepo = ref.read(manufacturingRepositoryProvider);
        await mfgRepo.addMfgOrderCost(
          orderId: order.id,
          costType: selectedType,
          description: descController.text.isNotEmpty
              ? descController.text
              : costTypes[selectedType] ?? selectedType,
          amount: amount,
        );
        // Update the additionalCosts on the order
        final currentAdditional = order.additionalCosts;
        await mfgRepo.updateManufacturingOrderCosts(
            order.id, currentAdditional + amount);
        ref.invalidate(manufacturingOrdersProvider);
        ref.invalidate(mfgOrderCostBreakdownProvider(order.id));

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    tr('✅ تمت إضافة {p0} بقيمة {p1}', {'p0': costTypes[selectedType], 'p1': amount.toStringAsFixed(AppConstants.decimalPlaces)}))),
          );
        }
      } catch (e) {
        if (context.mounted) {
          AppToast.show(context, tr('❌ خطأ: {e}', {'e': e}), type: ToastType.error);
        }
      }
    }
    amountController.dispose();
    descController.dispose();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'draft':
        return Colors.grey;
      case 'in_progress':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return AppColors.error;
      default:
        return Colors.grey;
    }
  }
}

// ─── Status Chip ─────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'draft' => (tr('مسودة'), Colors.grey),
      'in_progress' => (tr('قيد التنفيذ'), Colors.blue),
      'completed' => (tr('مكتمل'), Colors.green),
      'cancelled' => (tr('ملغي'), AppColors.error),
      _ => (tr('غير معروف'), Colors.grey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style:
              TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
