part of 'operational_expenses_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TAB 1: EXPENSE CATEGORIES — فئات المصروفات
// ═══════════════════════════════════════════════════════════════════════════

class _CategoriesTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(expenseCategoriesProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCategoryDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('فئة جديدة'),
        backgroundColor: AppColors.primary,
      ),
      body: categoriesAsync.when(
        data: (categories) {
          if (categories.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsBold.folder,
                      size: 64, color: AppColors.textMuted.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  const Text('لا توجد فئات مصروفات بعد',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 16)),
                  const SizedBox(height: 8),
                  const Text('أضف فئات مثل: إيجار، رواتب، كهرباء، صيانة',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: categories.length,
            itemBuilder: (context, index) =>
                _CategoryCard(category: categories[index]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: $e')),
      ),
    );
  }

  void _showCategoryDialog(BuildContext context, WidgetRef ref,
      {OpExpenseCategoryData? existing}) {
    showDialog(
      context: context,
      builder: (context) => OpexCategoryEditDialog(existing: existing),
    );
  }
}

class _CategoryCard extends ConsumerWidget {
  final OpExpenseCategoryData category;
  const _CategoryCard({required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typeLabels = {
      'direct': 'مباشرة',
      'indirect': 'غير مباشرة',
      'fixed': 'ثابتة',
      'variable': 'متغيرة',
    };
    final allocationLabels = {
      'per_unit': 'لكل وحدة',
      'per_hour': 'بالساعة',
      'per_order': 'لكل أمر',
      'fixed_monthly': 'شهري ثابت',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: category.isProductionRelated
                ? Colors.blue.withValues(alpha: 0.2)
                : Colors.grey.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: category.isProductionRelated
                  ? Colors.blue.withValues(alpha: 0.1)
                  : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              category.isProductionRelated
                  ? PhosphorIconsBold.factory
                  : PhosphorIconsBold.buildings,
              color: category.isProductionRelated ? Colors.blue : Colors.grey,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    _chip(typeLabels[category.type] ?? category.type,
                        Colors.purple),
                    _chip(
                        allocationLabels[category.allocationMethod] ??
                            category.allocationMethod,
                        Colors.teal),
                    if (category.isProductionRelated)
                      _chip('إنتاج', Colors.blue),
                    if (!category.isActive) _chip('معطلة', AppColors.error),
                  ],
                ),
              ],
            ),
          ),
          if (category.defaultRate > 0)
            Text(
              '${category.defaultRate.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange),
            ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              // Find parent and call edit with existing data
              final parent = context
                  .findAncestorWidgetOfExactType<_CategoriesTab>();
              parent?._showCategoryDialog(context, ref, existing: category);
            },
            icon: const Icon(PhosphorIconsBold.pencil, size: 18),
            color: AppColors.textMuted,
          ),
          IconButton(
            onPressed: () => _confirmDelete(context, ref),
            icon: const Icon(PhosphorIconsBold.trash, size: 18),
            color: AppColors.error,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف الفئة'),
          content: Text('هل أنت متأكد من حذف فئة "${category.name}"؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        final repo = ref.read(manufacturingRepositoryProvider);
        await repo.deleteExpenseCategory(category.id);
        ref.invalidate(expenseCategoriesProvider);
        if (context.mounted) {
          AppToast.show(context, 'تم حذف الفئة بنجاح', type: ToastType.success);
        }
      } catch (e) {
        if (context.mounted) {
          AppToast.show(context, 'خطأ في الحذف: $e', type: ToastType.error);
        }
      }
    }
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style:
              TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
