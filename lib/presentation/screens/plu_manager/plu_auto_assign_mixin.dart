part of '../plu_manager_screen.dart';

mixin _PluAutoAssignMixin on ConsumerState<PluManagerScreen> {
  // Abstract members satisfied by _PluManagerScreenState
  List<Product> get _allProducts;
  int? get _selectedCategoryId;
  PluManagerController get _controller;
  Future<void> _loadData();

  // ═══════════════════════════════════════════════════════════════════
  // AUTO ASSIGN
  // ═══════════════════════════════════════════════════════════════════
  void _showAutoAssignDialog() {
    int startFrom = 1;
    bool onlyUnassigned = true;
    bool onlyWeightItems = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: ui.TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(PhosphorIconsBold.lightning, color: AppColors.warning),
                SizedBox(width: 8),
                Text('ترقيم PLU تلقائي'),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(PhosphorIconsBold.info, color: AppColors.info, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'يقوم بتعيين أرقام PLU تلقائياً للمنتجات المختارة بشكل تسلسلي',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'البداية من رقم',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(text: '1'),
                    onChanged: (v) => startFrom = int.tryParse(v) ?? 1,
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: const Text('فقط الأصناف بدون PLU', style: TextStyle(fontSize: 13)),
                    value: onlyUnassigned,
                    onChanged: (v) => setDialogState(() => onlyUnassigned = v ?? true),
                    dense: true,
                  ),
                  CheckboxListTile(
                    title: const Text('فقط أصناف الوزن', style: TextStyle(fontSize: 13)),
                    value: onlyWeightItems,
                    onChanged: (v) => setDialogState(() => onlyWeightItems = v ?? false),
                    dense: true,
                  ),
                  FutureBuilder<int>(
                    future: _countEligibleProducts(onlyUnassigned, onlyWeightItems),
                    builder: (ctx, snap) {
                      final count = snap.data ?? 0;
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(PhosphorIconsBold.listNumbers, color: AppColors.warning, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'سيتم ترقيم $count صنف (PLU $startFrom → ${startFrom + count - 1})',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _executeAutoAssign(startFrom, onlyUnassigned, onlyWeightItems);
                },
                icon: const Icon(PhosphorIconsBold.lightning, size: 16),
                label: const Text('تنفيذ'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<int> _countEligibleProducts(bool onlyUnassigned, bool onlyWeightItems) async {
    var list = _allProducts.where((p) => p.isActive).toList();
    if (_selectedCategoryId != null) {
      list = list.where((p) => p.categoryId == _selectedCategoryId).toList();
    }
    if (onlyUnassigned) list = list.where((p) => p.scalePluNumber == null).toList();
    if (onlyWeightItems) list = list.where((p) => p.isSoldByWeight).toList();
    return list.length;
  }

  Future<void> _executeAutoAssign(int startFrom, bool onlyUnassigned, bool onlyWeightItems) async {
    var list = _allProducts.where((p) => p.isActive).toList();
    if (_selectedCategoryId != null) {
      list = list.where((p) => p.categoryId == _selectedCategoryId).toList();
    }
    if (onlyUnassigned) list = list.where((p) => p.scalePluNumber == null).toList();
    if (onlyWeightItems) list = list.where((p) => p.isSoldByWeight).toList();

    int plu = startFrom;
    int count = 0;
    for (final p in list) {
      var existing = await _controller.getProductByScalePlu(plu);
      while (existing != null) {
        plu++;
        existing = await _controller.getProductByScalePlu(plu);
      }
      await _controller.updateProductScalePlu(p.id, pluNumber: plu);
      plu++;
      count++;
    }

    await _loadData();
    if (mounted) {
      AppToast.show(
        context,
        'تم ترقيم $count صنف تلقائياً (PLU $startFrom → ${plu - 1})',
        type: ToastType.success,
      );
    }
  }
}
