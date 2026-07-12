import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../../data/database/models.dart';

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  String _searchQuery = '';
  final formatter = NumberFormat.currency(symbol: 'ج.م ', decimalDigits: 2, locale: 'ar_EG');

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(allProductsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('المنتجات'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsBold.plus),
            onPressed: () => _showAddProductDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'بحث عن منتج...',
                prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),

          // Products list
          Expanded(
            child: productsAsync.when(
              data: (products) {
                final filtered = products.where((p) =>
                  p.name.contains(_searchQuery) ||
                  p.code.contains(_searchQuery)
                ).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('لا توجد منتجات'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final product = filtered[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(PhosphorIconsBold.package, color: AppColors.primary),
                        ),
                        title: Text(product.name),
                        subtitle: Text('الكود: ${product.code} | المخزون: ${product.currentStock.toInt()}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatter.format(product.salePrice),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success),
                            ),
                            Text(
                              'التكلفة: ${formatter.format(product.costPrice)}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                        onTap: () => _showEditProductDialog(context, product),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddProductDialog(BuildContext context) {
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    final salePriceController = TextEditingController();
    final costPriceController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة منتج جديد'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                decoration: const InputDecoration(labelText: 'الكود'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'الاسم'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: salePriceController,
                decoration: const InputDecoration(labelText: 'سعر البيع'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: costPriceController,
                decoration: const InputDecoration(labelText: 'سعر التكلفة'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final db = ref.read(databaseProvider);
                await db.insertProduct(ProductsCompanion(
                  code: Value(codeController.text),
                  name: Value(nameController.text),
                  salePrice: Value(double.tryParse(salePriceController.text) ?? 0),
                  costPrice: Value(double.tryParse(costPriceController.text) ?? 0),
                ));
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم إضافة المنتج بنجاح'), backgroundColor: AppColors.success),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.danger),
                );
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _showEditProductDialog(BuildContext context, Product product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تفاصيل المنتج: ${product.name}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('الكود: ${product.code}'),
              const SizedBox(height: 8),
              Text('سعر البيع: ${formatter.format(product.salePrice)}'),
              const SizedBox(height: 8),
              Text('سعر التكلفة: ${formatter.format(product.costPrice)}'),
              const SizedBox(height: 8),
              Text('المخزون الحالي: ${product.currentStock}'),
              const SizedBox(height: 8),
              Text('الحد الأدنى: ${product.minStock}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}
