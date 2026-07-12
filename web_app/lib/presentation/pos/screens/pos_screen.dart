import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../data/database/models.dart';

class POSScreen extends ConsumerStatefulWidget {
  const POSScreen({super.key});

  @override
  ConsumerState<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends ConsumerState<POSScreen> {
  final List<_CartItem> _cart = [];
  String _searchQuery = '';
  final formatter = NumberFormat.currency(symbol: 'ج.م ', decimalDigits: 2, locale: 'ar_EG');

  double get _subtotal => _cart.fold(0, (sum, item) => sum + (item.product.salePrice * item.quantity));
  double get _total => _subtotal;

  void _addToCart(Product product) {
    setState(() {
      final existingIndex = _cart.indexWhere((item) => item.product.id == product.id);
      if (existingIndex >= 0) {
        _cart[existingIndex] = _cart[existingIndex].copyWith(
          quantity: _cart[existingIndex].quantity + 1,
        );
      } else {
        _cart.add(_CartItem(product: product, quantity: 1));
      }
    });
  }

  void _removeFromCart(int index) {
    setState(() {
      _cart.removeAt(index);
    });
  }

  void _updateQuantity(int index, double quantity) {
    if (quantity <= 0) {
      _removeFromCart(index);
    } else {
      setState(() {
        _cart[index] = _cart[index].copyWith(quantity: quantity);
      });
    }
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('السلة فارغة'), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      final db = ref.read(databaseProvider);
      final authState = ref.read(authProvider);
      
      // Get default warehouse
      final warehouses = await db.getAllWarehouses();
      final defaultWarehouse = warehouses.isNotEmpty ? warehouses.first : null;
      
      if (defaultWarehouse == null) {
        throw Exception('لا يوجد مخزن');
      }

      // Create invoice
      final invoiceNumber = 'INV-${DateTime.now().millisecondsSinceEpoch}';
      final invoiceId = await db.insertSalesInvoice(
        invoiceNumber: invoiceNumber,
        warehouseId: defaultWarehouse.id,
        userId: authState.user?.id ?? 1,
        invoiceDate: DateTime.now(),
        subtotal: _subtotal,
        discount: 0,
        tax: 0,
        total: _total,
        paid: _total,
        paymentMethod: 'cash',
      );

      // Add items
      for (final item in _cart) {
        await db.insertSalesInvoiceItem(
          invoiceId: invoiceId,
          productId: item.product.id,
          quantity: item.quantity,
          unitPrice: item.product.salePrice,
          discount: 0,
          total: item.product.salePrice * item.quantity,
          costPrice: item.product.costPrice,
        );

        // Update stock
        final newStock = item.product.currentStock - item.quantity;
        await db.updateProductStock(item.product.id, newStock);
      }

      // Clear cart
      setState(() => _cart.clear());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إنشاء الفاتورة $invoiceNumber بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(allProductsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Row(
        children: [
          // Products grid
          Expanded(
            flex: 3,
            child: Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'بحث عن منتج...',
                      prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                
                // Products grid
                Expanded(
                  child: productsAsync.when(
                    data: (products) {
                      final filtered = products.where((p) =>
                        p.name.contains(_searchQuery) ||
                        p.code.contains(_searchQuery)
                      ).toList();

                      return GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          childAspectRatio: 1,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final product = filtered[index];
                          return _ProductCard(
                            product: product,
                            onTap: () => _addToCart(product),
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
          ),

          // Cart
          Container(
            width: 350,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(-2, 0),
                ),
              ],
            ),
            child: Column(
              children: [
                // Cart header
                Container(
                  padding: const EdgeInsets.all(16),
                  color: AppColors.primary,
                  child: const Row(
                    children: [
                      Icon(PhosphorIconsBold.shoppingCart, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'السلة',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // Cart items
                Expanded(
                  child: _cart.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(PhosphorIconsBold.shoppingCart, size: 48, color: Colors.grey),
                              SizedBox(height: 8),
                              Text('السلة فارغة', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _cart.length,
                          itemBuilder: (context, index) {
                            final item = _cart[index];
                            return ListTile(
                              title: Text(item.product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(formatter.format(item.product.salePrice)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(PhosphorIconsBold.minus, size: 16),
                                    onPressed: () => _updateQuantity(index, item.quantity - 1),
                                  ),
                                  Text('${item.quantity.toInt()}'),
                                  IconButton(
                                    icon: const Icon(PhosphorIconsBold.plus, size: 16),
                                    onPressed: () => _updateQuantity(index, item.quantity + 1),
                                  ),
                                  IconButton(
                                    icon: const Icon(PhosphorIconsBold.trash, size: 16, color: Colors.red),
                                    onPressed: () => _removeFromCart(index),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),

                // Totals
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    border: Border(top: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('الإجمالي:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(
                            formatter.format(_total),
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _checkout,
                          icon: const Icon(PhosphorIconsBold.shoppingCart),
                          label: const Text('إتمام البيع', style: TextStyle(fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CartItem {
  final Product product;
  final double quantity;

  _CartItem({required this.product, required this.quantity});

  _CartItem copyWith({Product? product, double? quantity}) {
    return _CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: 'ج.م ', decimalDigits: 2, locale: 'ar_EG');

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(PhosphorIconsBold.package, color: AppColors.primary),
              ),
              const SizedBox(height: 8),
              Text(
                product.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                formatter.format(product.salePrice),
                style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold),
              ),
              Text(
                'المخزون: ${product.currentStock.toInt()}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
