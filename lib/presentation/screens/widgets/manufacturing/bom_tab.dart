part of '../../manufacturing_screen.dart';

// زرار «قائمة مواد جديدة» — `manufacturing_manage`. مستخرج كدالة top-level
// مستقلة عن الشاشة كلها عشان يتبنى في اختبار widget خفيف (Task 6a) —
// تركيب الشاشة كلها بقاعدة بيانات حقيقية علّق الاختبارات.
@visibleForTesting
Widget buildManufacturingManageBomButton({required VoidCallback onPressed}) {
  return PermissionGuard(
    permission: PermissionCodes.manufacturingManage,
    allowManagerOverride: true,
    actionName: 'إنشاء قائمة مواد',
    onGranted: onPressed,
    child: ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(PhosphorIconsBold.plus, size: 18),
      label: const Text('قائمة مواد جديدة'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 1: BOM MANAGEMENT — قوائم المكونات
// ═══════════════════════════════════════════════════════════════════════════

class _BomTab extends ConsumerWidget {
  const _BomTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bomsAsync = ref.watch(allBomsProvider);
    final productsAsync = ref.watch(allProductsProvider);

    return bomsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (boms) {
        final products = productsAsync.value ?? [];
        return Column(
          children: [
            // Toolbar
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    '${boms.length} قائمة مواد',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  buildManufacturingManageBomButton(
                    onPressed: () =>
                        _showBomDialog(context, ref, products, null),
                  ),
                ],
              ),
            ),

            // BOM List
            Expanded(
              child: boms.isEmpty
                  ? _buildEmptyState(
                      context,
                      icon: PhosphorIconsBold.listDashes,
                      title: 'لا توجد قوائم مواد',
                      subtitle:
                          'أضف أول قائمة مواد لتحديد المكونات اللازمة لتصنيع المنتجات',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: boms.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final bom = boms[index];
                        final product = products
                            .where((p) => p.id == bom.finishedProductId)
                            .firstOrNull;
                        return _BomCard(
                          bom: bom,
                          productName: product?.name ?? 'غير معروف',
                          onEdit: () => _showBomDialog(context, ref, products, bom),
                          onDelete: () => _deleteBom(context, ref, bom.id),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  void _showBomDialog(BuildContext context, WidgetRef ref,
      List<ProductEntity> products, BillOfMaterialData? existing) {
    showDialog(
      context: context,
      builder: (ctx) => _BomDialog(products: products, existing: existing),
    );
  }

  Future<void> _deleteBom(BuildContext context, WidgetRef ref, int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف قائمة المواد'),
          content: const Text('هل أنت متأكد من حذف قائمة المواد هذه؟'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('حذف', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
    if (confirm == true) {
      final mfgRepo = ref.read(manufacturingRepositoryProvider);
      await mfgRepo.deleteBOM(id);
      ref.invalidate(allBomsProvider);
    }
  }
}

// ─── BOM Card ────────────────────────────────────────────────────────────

class _BomCard extends ConsumerWidget {
  final BillOfMaterialData bom;
  final String productName;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BomCard({
    required this.bom,
    required this.productName,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final componentsAsync = ref.watch(bomComponentsProvider(bom.id));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: const Border(),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(PhosphorIconsBold.listDashes,
              color: AppColors.primary, size: 20),
        ),
        title: Text(
          productName,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Row(
          children: [
            _chip('كود: ${bom.bomCode}', Colors.blue),
            const SizedBox(width: 8),
            _chip('الناتج: ${bom.expectedQuantity}', Colors.green),
            const SizedBox(width: 8),
            _chip(
                'التكلفة: ${bom.estimatedCost.toStringAsFixed(AppConstants.decimalPlaces)}', Colors.orange),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PermissionGuard(
              permission: PermissionCodes.manufacturingManage,
              allowManagerOverride: true,
              actionName: 'تعديل قائمة مواد',
              onGranted: onEdit,
              child: IconButton(
                icon: const Icon(PhosphorIconsBold.pencilSimple, size: 18, color: AppColors.primary),
                onPressed: onEdit,
                tooltip: 'تعديل',
              ),
            ),
            PermissionGuard(
              permission: PermissionCodes.manufacturingManage,
              allowManagerOverride: true,
              actionName: 'حذف قائمة مواد',
              onGranted: onDelete,
              child: IconButton(
                icon: const Icon(PhosphorIconsBold.trash, size: 18, color: Colors.red),
                onPressed: onDelete,
                tooltip: 'حذف',
              ),
            ),
          ],
        ),
        children: [
          componentsAsync.when(
            loading: () =>
                const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
            error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('$e')),
            data: (components) {
              if (components.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لا توجد مكونات',
                      style: TextStyle(color: AppColors.textMuted)),
                );
              }
              return _buildComponentsTable(context, ref, components);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildComponentsTable(
      BuildContext context, WidgetRef ref, List<BomComponentData> components) {
    final products = ref.watch(allProductsProvider).value ?? [];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Table(
        border: TableBorder.all(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
        columnWidths: const {
          0: FlexColumnWidth(3),
          1: FlexColumnWidth(1.5),
          2: FlexColumnWidth(1),
          3: FlexColumnWidth(1.5),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey.shade50),
            children: const [
              _TableHeader('المادة الخام'),
              _TableHeader('الكمية'),
              _TableHeader('الوحدة'),
              _TableHeader('هالك %'),
            ],
          ),
          ...components.map((c) {
            final product =
                products.where((p) => p.id == c.rawMaterialId).firstOrNull;
            return TableRow(
              children: [
                _TableCell(product?.name ?? 'غير معروف'),
                _TableCell(c.quantity.toStringAsFixed(2)),
                _TableCell(c.unit),
                _TableCell('${c.wastagePercent.toStringAsFixed(1)}%'),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _TableHeader extends StatelessWidget {
  final String text;
  const _TableHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppColors.textSecondary)),
      );
}

class _TableCell extends StatelessWidget {
  final String text;
  const _TableCell(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
      );
}

// ─── BOM Create/Edit Dialog ──────────────────────────────────────────────

class _BomDialog extends ConsumerStatefulWidget {
  final List<ProductEntity> products;
  final BillOfMaterialData? existing;
  const _BomDialog({required this.products, this.existing});

  @override
  ConsumerState<_BomDialog> createState() => _BomDialogState();
}

class _BomDialogState extends ConsumerState<_BomDialog> {
  final _codeController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _notesController = TextEditingController();
  int? _selectedProductId;
  final List<Map<String, dynamic>> _components = [];

  // Feature 009 / T022 — auto-deplete toggle. Mirrors the BOM row's two
  // new columns. The depletion-policy dropdown lands in T037 (US4); for
  // US1 MVP this widget always sets `always_auto_deplete` under the hood
  // so users never see the InvalidPolicyException for `prefer_finished_stock`.
  bool _autoDepleteOnSale = false;
  bool _isActive = true;
  // Feature 009 / T037 — user-selectable depletion policy. Default for new
  // BOMs is `always_auto_deplete` (matches T022's previous hard-coded
  // value so existing flows keep working). The hybrid `prefer_finished_stock`
  // path (T036) is now picked here.
  String _depletionPolicy = 'always_auto_deplete';

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _codeController.text = widget.existing!.bomCode;
      _qtyController.text = widget.existing!.expectedQuantity.toString();
      _selectedProductId = widget.existing!.finishedProductId;
      _notesController.text = widget.existing!.notes ?? '';
      _autoDepleteOnSale = widget.existing!.autoDepleteOnSale;
      _isActive = widget.existing!.isActive;
      // Honour the existing row's policy on edit. Defaults to
      // `always_auto_deplete` if the column was somehow null/blank
      // (legacy rows pre-T037).
      final existingPolicy = widget.existing!.depletionPolicy;
      _depletionPolicy = existingPolicy.isEmpty
          ? 'always_auto_deplete'
          : existingPolicy;
      // Load existing components
      _loadExistingComponents();
    }
  }

  Future<void> _loadExistingComponents() async {
    final mfgRepo = ref.read(manufacturingRepositoryProvider);
    final comps = await mfgRepo.getBOMComponents(widget.existing!.id);
    if (mounted) {
      setState(() {
        _components.clear();
        for (final c in comps) {
          _components.add({
            'rawMaterialId': c.rawMaterialId,
            'quantity': c.quantity,
            'unit': c.unit,
            'quantityInBase': c.quantityInBase,
            'wastagePercent': c.wastagePercent,
            'cost': 0.0,
          });
        }
      });
      // Update costs for each component
      for (final comp in _components) {
        await _updateComponentCost(comp);
      }
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _qtyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _addComponent() {
    setState(() {
      _components.add({
        'rawMaterialId': null,
        'quantity': 1.0,
        'unit': 'قطعة',
        'quantityInBase': 1.0,
        'wastagePercent': 0.0,
        'cost': 0.0,
      });
    });
  }

  /// Lookup last purchase price for a material and update the component cost
  Future<void> _updateComponentCost(Map<String, dynamic> comp) async {
    final materialId = comp['rawMaterialId'] as int?;
    if (materialId == null) return;

    final mfgRepo = ref.read(manufacturingRepositoryProvider);
    final lastPrice = await mfgRepo.getLastPurchasePrice(materialId);
    if (lastPrice != null && lastPrice > 0) {
      setState(() => comp['cost'] = lastPrice);
    } else {
      // Fallback to product.costPrice
      final productRepo = ref.read(productRepositoryProvider);
      final product = await productRepo.getProductById(materialId);
      if (product != null) {
        setState(() => comp['cost'] = product.costPrice);
      }
    }
  }

  /// The BOM's expected output quantity per batch — read from the
  /// controller live so per-unit-cost preview and warnings stay in sync
  /// with what the operator is typing.
  double get _expectedOutputQty {
    final v = double.tryParse(_qtyController.text);
    return (v != null && v > 0) ? v : 1.0;
  }

  /// Cost-per-output-unit — total cost ÷ expected output qty. Lets the
  /// operator immediately see whether the BOM ratio matches their mental
  /// model (e.g., "should one سيخ really cost 9.18 ج?") without doing
  /// the arithmetic in their head. Per-batch BOMs are easy to misread.
  double get _perUnitCost {
    final qty = _expectedOutputQty;
    if (qty <= 0) return 0;
    return _totalEstimatedCost / qty;
  }

  double get _totalEstimatedCost {
    double total = 0;
    for (final c in _components) {
      final cost = (c['cost'] as num?)?.toDouble() ?? 0;
      final qty = (c['quantity'] as num?)?.toDouble() ?? 1;
      final factor = (c['quantityInBase'] as num?)?.toDouble() ?? 1;
      final wastage = (c['wastagePercent'] as num?)?.toDouble() ?? 0;
      // cost is per-unit, qty is in selected unit; factor converts to base
      total += cost * qty * factor * (1 + wastage / 100);
    }
    return total;
  }

  Future<void> _save() async {
    if (_selectedProductId == null || _codeController.text.isEmpty) {
      AppToast.show(context, 'يرجى ملء جميع الحقول المطلوبة', type: ToastType.info);
      return;
    }
    if (_components.isEmpty || _components.any((c) => c['rawMaterialId'] == null)) {
      AppToast.show(context, 'يرجى إضافة مكون واحد على الأقل', type: ToastType.info);
      return;
    }

    try {
      final mfgRepo = ref.read(manufacturingRepositoryProvider);
      // Feature 009 / T037 — depletion policy now picked by the user
      // (dropdown below the auto-deplete checkbox). Falls back to the
      // legacy default for safety on the create path.
      final activePolicy = _autoDepleteOnSale
          ? _depletionPolicy
          : 'always_auto_deplete';
      if (widget.existing != null) {
        // Update existing BOM
        await mfgRepo.updateBOM(
          bomId: widget.existing!.id,
          finishedProductId: _selectedProductId!,
          bomCode: _codeController.text.trim(),
          expectedQuantity: double.tryParse(_qtyController.text) ?? 1,
          notes: _notesController.text.isEmpty ? null : _notesController.text,
          components: _components,
          autoDepleteOnSale: _autoDepleteOnSale,
          depletionPolicy: _autoDepleteOnSale ? activePolicy : null,
        );
      } else {
        // Create new BOM
        await mfgRepo.createBOM(
          finishedProductId: _selectedProductId!,
          bomCode: _codeController.text.trim(),
          expectedQuantity: double.tryParse(_qtyController.text) ?? 1,
          notes: _notesController.text.isEmpty ? null : _notesController.text,
          components: _components,
          autoDepleteOnSale: _autoDepleteOnSale,
          depletionPolicy: activePolicy,
        );
      }
      ref.invalidate(allBomsProvider);
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Row(
                  children: [
                    const Icon(PhosphorIconsBold.listDashes,
                        color: AppColors.primary),
                    const SizedBox(width: 10),
                    Text(
                      widget.existing == null
                          ? 'قائمة مواد جديدة'
                          : 'تعديل قائمة المواد',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(PhosphorIconsBold.x),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Finished Product + BOM Code + Output Qty
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Autocomplete<ProductEntity>(
                        initialValue: _selectedProductId != null
                            ? TextEditingValue(
                                text: widget.products
                                    .where((p) => p.id == _selectedProductId)
                                    .map((p) => p.name)
                                    .firstOrNull ?? '')
                            : TextEditingValue.empty,
                        displayStringForOption: (p) => p.name,
                        optionsBuilder: (textEditingValue) {
                          if (textEditingValue.text.isEmpty) {
                            return widget.products;
                          }
                          final query = textEditingValue.text.toLowerCase();
                          return widget.products.where((p) =>
                              p.name.toLowerCase().contains(query) ||
                              p.code.toLowerCase().contains(query));
                        },
                        fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                          return TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: 'المنتج التام *',
                              hintText: 'ابحث بالاسم أو الكود...',
                              border: OutlineInputBorder(),
                              isDense: true,
                              prefixIcon: Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                            ),
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topRight,
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(8),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 250, maxWidth: 400),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (context, index) {
                                    final p = options.elementAt(index);
                                    return ListTile(
                                      dense: true,
                                      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      subtitle: Text(p.code, style: const TextStyle(fontSize: 11)),
                                      onTap: () => onSelected(p),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                        onSelected: (product) {
                          setState(() => _selectedProductId = product.id);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _codeController,
                        decoration: const InputDecoration(
                          labelText: 'كود BOM *',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _qtyController,
                        decoration: InputDecoration(
                          labelText: 'الناتج (لكل دفعة)',
                          helperText: 'اضبطه = 1 إذا كانت الخامات لكل وحدة',
                          helperStyle: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                          border: const OutlineInputBorder(),
                          isDense: true,
                          // Quick reference for users who hover the i icon.
                          suffixIcon: const Tooltip(
                            triggerMode: TooltipTriggerMode.tap,
                            message:
                                'الناتج = كم وحدة تنتجها الدفعة الواحدة من '
                                'هذه الخامات.\n'
                                'مثال: لو ضبطت الناتج=12 واللحمة=1كجم، '
                                'يبقى 12 سيخ يحتاج 1كجم لحمة (≈ 83 جرام لكل سيخ).\n'
                                'لو عايز "1 سيخ = 1كجم لحمة" — اضبط الناتج=1.',
                            child: Icon(PhosphorIconsBold.info,
                                size: 16, color: Colors.grey),
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        // Trigger setState so the per-unit cost preview
                        // and the auto-deplete-ratio warning re-evaluate
                        // as the operator types.
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Components header
                Row(
                  children: [
                    const Text('المواد الخام',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _addComponent,
                      icon: const Icon(PhosphorIconsBold.plus, size: 16),
                      label: const Text('إضافة مكون'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Components list
                Expanded(
                  child: _components.isEmpty
                      ? Center(
                          child: Text('اضغط "إضافة مكون" لإضافة المواد الخام',
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 13)),
                        )
                      : ListView.separated(
                          itemCount: _components.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final comp = _components[i];
                            return Row(
                              children: [
                                // Product search (Autocomplete)
                                Expanded(
                                  flex: 3,
                                  child: Autocomplete<ProductEntity>(
                                    initialValue: comp['rawMaterialId'] != null
                                        ? TextEditingValue(
                                            text: widget.products
                                                .where((p) => p.id == comp['rawMaterialId'])
                                                .map((p) => p.name)
                                                .firstOrNull ?? '')
                                        : TextEditingValue.empty,
                                    displayStringForOption: (p) => p.name,
                                    optionsBuilder: (textEditingValue) {
                                      if (textEditingValue.text.isEmpty) {
                                        return widget.products;
                                      }
                                      final query = textEditingValue.text.toLowerCase();
                                      return widget.products.where((p) =>
                                          p.name.toLowerCase().contains(query) ||
                                          p.code.toLowerCase().contains(query));
                                    },
                                    fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                                      return TextFormField(
                                        controller: controller,
                                        focusNode: focusNode,
                                        decoration: const InputDecoration(
                                          labelText: 'المادة الخام',
                                          hintText: 'ابحث...',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                          prefixIcon: Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
                                        ),
                                      );
                                    },
                                    optionsViewBuilder: (context, onSelected, options) {
                                      return Align(
                                        alignment: Alignment.topRight,
                                        child: Material(
                                          elevation: 4,
                                          borderRadius: BorderRadius.circular(8),
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(maxHeight: 200, maxWidth: 350),
                                            child: ListView.builder(
                                              padding: EdgeInsets.zero,
                                              shrinkWrap: true,
                                              itemCount: options.length,
                                              itemBuilder: (context, index) {
                                                final p = options.elementAt(index);
                                                return ListTile(
                                                  dense: true,
                                                  title: Text(p.name, overflow: TextOverflow.ellipsis),
                                                  subtitle: Text(p.code, style: const TextStyle(fontSize: 10)),
                                                  onTap: () => onSelected(p),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                    onSelected: (product) {
                                      setState(() => comp['rawMaterialId'] = product.id);
                                      _updateComponentCost(comp);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Quantity
                                Expanded(
                                  child: TextFormField(
                                    initialValue: comp['quantity'].toString(),
                                    decoration: const InputDecoration(
                                      labelText: 'الكمية',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    keyboardType: TextInputType.number,
                                    // setState so `_totalEstimatedCost`
                                    // re-evaluates and the cost-display
                                    // text widget repaints. Without it,
                                    // changing qty leaves the total stale.
                                    onChanged: (v) => setState(() {
                                      comp['quantity'] =
                                          double.tryParse(v) ?? 1;
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Unit — dropdown from product units
                                Expanded(
                                  child: FutureBuilder<List<ProductUnit>>(
                                    future: comp['rawMaterialId'] != null
                                        ? ref.read(productRepositoryProvider).getProductUnits(comp['rawMaterialId'] as int)
                                        : Future.value([]),
                                    builder: (context, snapshot) {
                                      final rawUnits = snapshot.data ?? [];
                                      // Dedupe by unitName: a product can end up with
                                      // duplicate rows (sync collision, manual edits)
                                      // and DropdownButtonFormField asserts on dupes.
                                      final dedupedUnits = <String, ProductUnit>{};
                                      for (final u in rawUnits) {
                                        dedupedUnits.putIfAbsent(u.unitName, () => u);
                                      }
                                      final units = dedupedUnits.values.toList();
                                      if (units.isEmpty) {
                                        return TextFormField(
                                          initialValue: comp['unit'] as String,
                                          decoration: const InputDecoration(
                                            labelText: 'الوحدة',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                          onChanged: (v) => comp['unit'] = v,
                                        );
                                      }
                                      // Validate `comp['unit']` is actually one of the
                                      // available unit names. The default 'قطعة' from
                                      // _addComponent doesn't always exist in the
                                      // product's unit table; falling back to the first
                                      // unit prevents the dropdown assertion crash.
                                      final unitNames = units.map((u) => u.unitName).toSet();
                                      final currentUnit = comp['unit'] as String?;
                                      final effectiveUnit = (currentUnit != null &&
                                              unitNames.contains(currentUnit))
                                          ? currentUnit
                                          : units.first.unitName;
                                      if (effectiveUnit != currentUnit) {
                                        // Sync the row's stored unit so the dropdown
                                        // and the saved record stay consistent.
                                        comp['unit'] = effectiveUnit;
                                        comp['quantityInBase'] = units.first.quantityInBase;
                                      }
                                      return DropdownButtonFormField<String>(
                                        initialValue: effectiveUnit,
                                        decoration: const InputDecoration(
                                          labelText: 'الوحدة',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        items: units.map((u) => DropdownMenuItem(
                                          value: u.unitName,
                                          child: Text('${u.unitName} (×${u.quantityInBase.toStringAsFixed(0)})',
                                            overflow: TextOverflow.ellipsis),
                                        )).toList(),
                                        onChanged: (v) {
                                          final selectedUnit = units.firstWhere((u) => u.unitName == v);
                                          setState(() {
                                            comp['unit'] = v;
                                            comp['quantityInBase'] = selectedUnit.quantityInBase;
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Wastage %
                                SizedBox(
                                  width: 80,
                                  child: TextFormField(
                                    initialValue:
                                        comp['wastagePercent'].toString(),
                                    decoration: const InputDecoration(
                                      labelText: 'هالك%',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    keyboardType: TextInputType.number,
                                    // setState so the cost preview
                                    // (which multiplies by 1+wastage/100)
                                    // updates as the operator types.
                                    onChanged: (v) => setState(() {
                                      comp['wastagePercent'] =
                                          double.tryParse(v) ?? 0;
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                // Delete
                                IconButton(
                                  icon: const Icon(PhosphorIconsBold.trash,
                                      size: 16, color: Colors.red),
                                  onPressed: () =>
                                      setState(() => _components.removeAt(i)),
                                ),
                                const SizedBox(width: 4),
                                // Cost (auto-calculated, read-only)
                                SizedBox(
                                  width: 80,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    child: Text(
                                      ((comp['cost'] as num?)?.toDouble() ?? 0).toStringAsFixed(1),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: (comp['cost'] as num?)?.toDouble() != null && (comp['cost'] as num).toDouble() > 0
                                            ? AppColors.primary
                                            : Colors.grey,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),

                const SizedBox(height: 16),

                // Total estimated cost
                if (_components.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'إجمالي التكلفة التقديرية (لكل دفعة): ',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                        Text(
                          _totalEstimatedCost.toStringAsFixed(AppConstants.decimalPlaces),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // (B) Per-unit cost line — total ÷ expected output. Hidden
                  // when output = 1 (the per-unit price equals the total
                  // and the line would be redundant).
                  if (_expectedOutputQty > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'تكلفة الوحدة الواحدة (≈ ÷ ${_expectedOutputQty.toStringAsFixed(_expectedOutputQty.truncateToDouble() == _expectedOutputQty ? 0 : 2)}): ',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600),
                          ),
                          Text(
                            _perUnitCost.toStringAsFixed(
                                AppConstants.decimalPlaces),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // (C) Smart warning when auto-deplete is on AND the BOM
                  // is per-batch (output > 1). 90% of the time this is a
                  // misconfiguration — the operator probably wanted a
                  // per-unit BOM. Catches the mistake at edit time, not
                  // at sale time when stock is already wrong.
                  if (_autoDepleteOnSale && _expectedOutputQty > 1)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        border: Border.all(color: Colors.amber.shade300),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(PhosphorIconsBold.warning,
                              size: 18, color: Colors.amber.shade800),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'تنبيه: الناتج = ${_expectedOutputQty.toStringAsFixed(_expectedOutputQty.truncateToDouble() == _expectedOutputQty ? 0 : 2)}'
                              ' يعنى أن الخامات أعلاه لـ "دفعة" تنتج '
                              '${_expectedOutputQty.toStringAsFixed(_expectedOutputQty.truncateToDouble() == _expectedOutputQty ? 0 : 2)} '
                              'وحدة. عند البيع، يتم خصم الخامات بنسبة '
                              '(الكمية المباعة ÷ الناتج). إذا كنت تريد '
                              '"1 وحدة = الكميات المذكورة بالضبط"، اضبط '
                              'الناتج = 1.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.amber.shade900,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],

                // Notes + Save button
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                // Feature 009 / T022 — auto-deplete toggle. Disabled when
                // the BOM is inactive (FR-004) so admins can't combine
                // (active=false + auto=true) through the UI; the DAO
                // enforces the same rule as defense-in-depth.
                CheckboxListTile(
                  value: _autoDepleteOnSale,
                  onChanged: _isActive
                      ? (v) => setState(() => _autoDepleteOnSale = v ?? false)
                      : null,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'خصم الخامات تلقائيًا عند البيع',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _isActive
                        ? 'عند بيع هذا الصنف، يتم خصم خاماته من المخزون مباشرة دون أمر إنتاج.'
                        : 'لا يمكن تفعيل الخصم التلقائي على قائمة تصنيع غير مفعّلة.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
                // Feature 009 / T037 — depletion policy. Visible only when
                // auto-deplete is enabled (no other policy applies otherwise).
                if (_autoDepleteOnSale) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _depletionPolicy,
                    decoration: const InputDecoration(
                      labelText: 'سياسة الخصم',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'always_auto_deplete',
                        child: Text('الخامات دائمًا'),
                      ),
                      DropdownMenuItem(
                        value: 'prefer_finished_stock',
                        child: Text('الافتراضى من المنتج التام'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _depletionPolicy = v);
                      }
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _depletionPolicy == 'always_auto_deplete'
                        ? 'كل الكمية المباعة تُخصم من الخامات. مناسب للمنتجات التى لا يُحفظ منها مخزون تام (مثل: الساندوتش الطازج).'
                        : 'إذا توفر مخزون من المنتج التام يُخصم منه أولاً، والباقى من الخامات. مناسب للمنتجات المُجهَّزة مسبقًا.',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        height: 1.4),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('حفظ',
                        style: TextStyle(
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
