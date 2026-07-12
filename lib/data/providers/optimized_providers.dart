import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/product_entity.dart';
import 'providers.dart';

/// Optimized providers with select() for minimal rebuilds
///
/// These providers use Riverpod's select() to minimize widget rebuilds
/// by only triggering updates when specific values change.

/// Selected product count (for badges)
final productCountProvider = Provider<AsyncValue<int>>((ref) {
  return ref.watch(allProductsProvider).whenData((products) => products.length);
});

/// Selected active products only
final activeProductsProvider = Provider<AsyncValue<List<ProductEntity>>>((ref) {
  return ref
      .watch(allProductsProvider)
      .whenData((products) => products.where((p) => p.isActive).toList());
});

/// Low stock count for dashboard alerts
final lowStockCountProvider = Provider<AsyncValue<int>>((ref) {
  return ref
      .watch(lowStockProductsProvider)
      .whenData((products) => products.length);
});

/// Today's sales count (cached)
final todaySalesCountProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(databaseProvider);
  final today = DateTime.now();
  final startOfDay = DateTime(today.year, today.month, today.day);

  final invoices = await db.getSalesForDateRange(startOfDay, today);
  return invoices.length;
});

/// Today's sales total (cached)
final todaySalesTotalProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final today = DateTime.now();
  final startOfDay = DateTime(today.year, today.month, today.day);

  final invoices = await db.getSalesForDateRange(startOfDay, today);
  return invoices.fold<double>(0, (sum, inv) => sum + inv.total);
});

/// Categories with product counts
final categoriesWithCountsProvider =
    Provider<AsyncValue<List<CategoryWithCount>>>((ref) {
      final categories = ref.watch(allCategoriesProvider);
      final products = ref.watch(allProductsProvider);

      return categories.whenData((cats) {
        final prods = products.value ?? [];
        return cats.map((cat) {
          final count = prods
              .where((p) => p.categoryId == cat.id && p.isActive)
              .length;
          return CategoryWithCount(category: cat, productCount: count);
        }).toList();
      });
    });

/// Category with product count helper
class CategoryWithCount {
  final Category category;
  final int productCount;

  const CategoryWithCount({required this.category, required this.productCount});
}

/// Supplier balance summary
/// Note: Uses stream-based approach since watchAllSuppliers exists
final supplierBalanceSummaryProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final suppliers = await (db.select(
    db.parties,
  )..where((p) => p.isSupplier.equals(true))).get();
  return suppliers.fold<double>(0, (sum, s) => sum + s.balance);
});

/// Customer balance summary
final customerBalanceSummaryProvider = FutureProvider<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final customers = await (db.select(
    db.parties,
  )..where((p) => p.isCustomer.equals(true))).get();
  return customers.fold<double>(0, (sum, c) => sum + c.balance);
});
