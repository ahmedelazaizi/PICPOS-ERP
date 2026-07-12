import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/database/database.dart';
import '../inventory_notifier.dart';

class InventoryFiltersBar extends ConsumerWidget {
  final TabController tabController;
  final TextEditingController searchController;
  final AsyncValue<List<Category>> categoriesAsync;

  const InventoryFiltersBar({
    super.key,
    required this.tabController,
    required this.searchController,
    required this.categoriesAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(inventoryNotifierProvider);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 350,
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: tabController,
                  indicator: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: AppColors.textMuted,
                  tabs: const [
                    Tab(text: 'أرصدة المستودع'),
                    Tab(text: 'حركة الأصناف'),
                  ],
                ),
              ),
              const Spacer(),
              _buildSearchField(context, ref),
              const SizedBox(width: 12),
              _buildCategoryFilter(context, ref),
              const SizedBox(width: 12),
              _buildLowStockToggle(ref, state),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 250,
      child: TextField(
        controller: searchController,
        onChanged: (v) =>
            ref.read(inventoryNotifierProvider.notifier).setSearchQuery(v),
        decoration: InputDecoration(
          hintText: 'بحث عن صنف أو كود...',
          prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
          filled: true,
          fillColor: Theme.of(context).scaffoldBackgroundColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildCategoryFilter(BuildContext context, WidgetRef ref) {
    return categoriesAsync.when(
      data: (cats) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int?>(
            value: ref.watch(inventoryNotifierProvider).selectedCategoryId,
            hint: const Text('كل التصنيفات'),
            items: [
              const DropdownMenuItem(value: null, child: Text('كل التصنيفات')),
              ...cats.map(
                (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
              ),
            ],
            onChanged: (v) =>
                ref.read(inventoryNotifierProvider.notifier).setCategory(v),
          ),
        ),
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildLowStockToggle(WidgetRef ref, InventoryState state) {
    return FilterChip(
      label: const Text('نواقص المخزون'),
      selected: state.showLowStockOnly,
      onSelected: (v) =>
          ref.read(inventoryNotifierProvider.notifier).toggleLowStock(v),
      selectedColor: AppColors.warning.withValues(alpha: 0.2),
      checkmarkColor: AppColors.warning,
      labelStyle: TextStyle(
        color: state.showLowStockOnly ? AppColors.warning : AppColors.textMuted,
        fontWeight: state.showLowStockOnly
            ? FontWeight.bold
            : FontWeight.normal,
      ),
    );
  }
}
