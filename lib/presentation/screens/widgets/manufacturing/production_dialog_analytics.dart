part of '../../manufacturing_screen.dart';

// ─── Production Order Create Dialog ──────────────────────────────────────

class _ProductionOrderDialog extends ConsumerStatefulWidget {
  final List<BillOfMaterialData> boms;
  final List<ProductEntity> products;
  final ManufacturingOrderData? existingOrder;
  const _ProductionOrderDialog({
    required this.boms,
    required this.products,
    this.existingOrder,
  });

  @override
  ConsumerState<_ProductionOrderDialog> createState() =>
      _ProductionOrderDialogState();
}

class _ProductionOrderDialogState
    extends ConsumerState<_ProductionOrderDialog> {
  final _orderNumberController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _notesController = TextEditingController();
  int? _selectedBomId;
  int? _selectedWarehouseId;

  bool get _isEditing => widget.existingOrder != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final order = widget.existingOrder!;
      _orderNumberController.text = order.orderNumber;
      _qtyController.text = order.orderedQty.toStringAsFixed(0);
      _notesController.text = order.notes ?? '';
      _selectedBomId = order.bomId;
      _selectedWarehouseId = order.warehouseId;
    }
  }

  @override
  void dispose() {
    _orderNumberController.dispose();
    _qtyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _generateOrderNumber() {
    final now = DateTime.now();
    return 'MFG-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    if (_selectedBomId == null) {
      AppToast.show(context, 'يرجى اختيار قائمة المواد (BOM)', type: ToastType.info);
      return;
    }
    if (_selectedWarehouseId == null) {
      AppToast.show(context, 'يرجى اختيار المستودع', type: ToastType.info);
      return;
    }

    try {
      final mfgRepo = ref.read(manufacturingRepositoryProvider);
      if (_isEditing) {
        await mfgRepo.updateManufacturingOrder(
          orderId: widget.existingOrder!.id,
          bomId: _selectedBomId,
          orderedQty: double.tryParse(_qtyController.text) ?? 1,
          warehouseId: _selectedWarehouseId,
          notes: _notesController.text.isEmpty ? null : _notesController.text,
        );
      } else {
        await mfgRepo.createManufacturingOrder(
          bomId: _selectedBomId!,
          orderedQty: double.tryParse(_qtyController.text) ?? 1,
          warehouseId: _selectedWarehouseId!,
          startDate: DateTime.now(),
          notes: _notesController.text.isEmpty ? null : _notesController.text,
        );
      }
      ref.invalidate(manufacturingOrdersProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final warehousesAsync = ref.watch(allWarehousesProvider);
    final warehousesList = warehousesAsync.value ?? [];

    // Auto-select first warehouse if none selected and warehouses available
    if (_selectedWarehouseId == null && warehousesList.isNotEmpty) {
      _selectedWarehouseId = warehousesList.first.id;
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(PhosphorIconsBold.gearSix,
                        color: Color(0xFF14B8A6)),
                    const SizedBox(width: 10),
                    Text(_isEditing ? 'تعديل أمر الإنتاج' : 'أمر إنتاج جديد',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(PhosphorIconsBold.x),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(height: 24),

                // BOM Selection
                DropdownButtonFormField<int>(
                  initialValue: _selectedBomId,
                  decoration: const InputDecoration(
                    labelText: 'قائمة المواد (BOM) *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: widget.boms.map((bom) {
                    final product = widget.products
                        .where((p) => p.id == bom.finishedProductId)
                        .firstOrNull;
                    return DropdownMenuItem(
                      value: bom.id,
                      child: Text(
                          '${product?.name ?? 'غير معروف'} (${bom.bomCode})'),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedBomId = v),
                ),
                const SizedBox(height: 16),

                // Warehouse Selection
                DropdownButtonFormField<int>(
                  initialValue: _selectedWarehouseId,
                  decoration: const InputDecoration(
                    labelText: 'مستودع سحب الخامات *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: warehousesList.map((w) {
                    return DropdownMenuItem(
                      value: w.id,
                      child: Text(w.name),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedWarehouseId = v),
                ),
                const SizedBox(height: 16),

                // Order Number + Quantity
                Row(
                  children: [
                    if (!_isEditing)
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _orderNumberController,
                          decoration: InputDecoration(
                            labelText: 'رقم الأمر',
                            hintText: _generateOrderNumber(),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    if (!_isEditing) const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _qtyController,
                        decoration: const InputDecoration(
                          labelText: 'الكمية',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Notes
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF14B8A6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(_isEditing ? 'حفظ التعديلات' : 'إنشاء أمر الإنتاج',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED HELPERS
// ═══════════════════════════════════════════════════════════════════════════

Widget _buildEmptyState(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
}) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text(title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Text(subtitle,
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 13, color: Colors.grey.shade500)),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 3: MANUFACTURING ANALYTICS — تحليلات التصنيع
// ═══════════════════════════════════════════════════════════════════════════

class _MfgAnalyticsTab extends ConsumerWidget {
  const _MfgAnalyticsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(manufacturingOrdersProvider);
    final bomsAsync = ref.watch(allBomsProvider);

    return ordersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (orders) {
        final boms = bomsAsync.value ?? [];

        // Compute analytics
        final completed = orders.where((o) => o.status == 'completed').toList();
        final inProgress =
            orders.where((o) => o.status == 'in_progress').toList();
        final planned = orders.where((o) => o.status == 'planned').toList();

        final totalPlannedQty =
            orders.fold<double>(0, (s, o) => s + o.orderedQty);
        final totalProducedQty =
            completed.fold<double>(0, (s, o) => s + o.producedQty);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // KPI Row 1
              Row(
                children: [
                  _kpiCard('أوامر مكتملة', '${completed.length}',
                      PhosphorIconsBold.checkCircle, const Color(0xFF059669)),
                  const SizedBox(width: 16),
                  _kpiCard('قيد التنفيذ', '${inProgress.length}',
                      PhosphorIconsBold.gearSix, const Color(0xFF2563EB)),
                  const SizedBox(width: 16),
                  _kpiCard('مخطط', '${planned.length}',
                      PhosphorIconsBold.calendar, const Color(0xFFF59E0B)),
                  const SizedBox(width: 16),
                  _kpiCard('إجمالي BOMs', '${boms.length}',
                      PhosphorIconsBold.listDashes, AppColors.primary),
                ],
              ),
              const SizedBox(height: 16),

              // KPI Row 2 — Production Quantities
              Row(
                children: [
                  _kpiCard(
                      'كمية مخططة',
                      totalPlannedQty.toStringAsFixed(0),
                      PhosphorIconsBold.target,
                      const Color(0xFF6366F1)),
                  const SizedBox(width: 16),
                  _kpiCard(
                      'كمية منتجة',
                      totalProducedQty.toStringAsFixed(0),
                      PhosphorIconsBold.package,
                      const Color(0xFF059669)),
                  const SizedBox(width: 16),
                  _kpiCard(
                      'نسبة الإنجاز',
                      totalPlannedQty > 0
                          ? '${(totalProducedQty / totalPlannedQty * 100).toStringAsFixed(1)}%'
                          : 'N/A',
                      PhosphorIconsBold.percent,
                      const Color(0xFF7C3AED)),
                  const SizedBox(width: 16),
                  const Expanded(child: SizedBox()),
                ],
              ),

              const SizedBox(height: 24),

              // Order Status Breakdown
              Text('ملخص حالة الأوامر',
                  style: GoogleFonts.cairo(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (orders.isNotEmpty)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _statusBar(
                            'مكتمل', completed.length, orders.length,
                            const Color(0xFF059669)),
                        const SizedBox(height: 8),
                        _statusBar(
                            'قيد التنفيذ', inProgress.length, orders.length,
                            const Color(0xFF2563EB)),
                        const SizedBox(height: 8),
                        _statusBar(
                            'مخطط', planned.length, orders.length,
                            const Color(0xFFF59E0B)),
                      ],
                    ),
                  ),
                )
              else
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('لا توجد أوامر إنتاج بعد',
                        style: GoogleFonts.cairo(color: AppColors.textMuted)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _kpiCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(value,
                style: GoogleFonts.cairo(
                    fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            Text(title,
                style: GoogleFonts.cairo(
                    fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _statusBar(String label, int count, int total, Color color) {
    final pct = total > 0 ? count / total : 0.0;
    return Row(
      children: [
        SizedBox(
            width: 80,
            child: Text(label,
                style: GoogleFonts.cairo(
                    fontSize: 12, fontWeight: FontWeight.w600))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 16,
              backgroundColor: color.withValues(alpha: 0.05),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: Text('$count (${(pct * 100).toStringAsFixed(0)}%)',
              style: GoogleFonts.cairo(
                  fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
