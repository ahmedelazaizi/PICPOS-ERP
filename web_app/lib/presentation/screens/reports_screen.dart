import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(todaySalesProvider);
    final productsAsync = ref.watch(allProductsProvider);
    final formatter = NumberFormat.currency(symbol: 'ج.م ', decimalDigits: 2, locale: 'ar_EG');

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('التقارير'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ملخص التقارير',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            // Report cards
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _ReportCard(
                  title: 'إجمالي المبيعات',
                  icon: PhosphorIconsBold.shoppingCart,
                  color: AppColors.success,
                  value: salesAsync.when(
                    data: (sales) => formatter.format(sales.fold(0.0, (sum, s) => sum + s.total)),
                    loading: () => '...',
                    error: (_, _) => '0',
                  ),
                ),
                _ReportCard(
                  title: 'عدد الفواتير',
                  icon: PhosphorIconsBold.receipt,
                  color: AppColors.info,
                  value: salesAsync.when(
                    data: (sales) => sales.length.toString(),
                    loading: () => '...',
                    error: (_, _) => '0',
                  ),
                ),
                _ReportCard(
                  title: 'عدد المنتجات',
                  icon: PhosphorIconsBold.package,
                  color: AppColors.warning,
                  value: productsAsync.when(
                    data: (products) => products.length.toString(),
                    loading: () => '...',
                    error: (_, _) => '0',
                  ),
                ),
                _ReportCard(
                  title: 'قيمة المخزون',
                  icon: PhosphorIconsBold.warehouse,
                  color: AppColors.primary,
                  value: productsAsync.when(
                    data: (products) => formatter.format(
                      products.fold(0.0, (sum, p) => sum + (p.costPrice * p.currentStock))
                    ),
                    loading: () => '...',
                    error: (_, _) => '0',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Sales table
            Text(
              'تفاصيل المبيعات',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            salesAsync.when(
              data: (sales) {
                if (sales.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('لا توجد مبيعات')),
                    ),
                  );
                }
                return Card(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('رقم الفاتورة')),
                      DataColumn(label: Text('التاريخ')),
                      DataColumn(label: Text('الإجمالي'), numeric: true),
                      DataColumn(label: Text('المدفوع'), numeric: true),
                      DataColumn(label: Text('الحالة')),
                    ],
                    rows: sales.take(20).map((sale) {
                      return DataRow(cells: [
                        DataCell(Text(sale.invoiceNumber)),
                        DataCell(Text(DateFormat('dd/MM/yyyy').format(sale.invoiceDate))),
                        DataCell(Text(formatter.format(sale.total))),
                        DataCell(Text(formatter.format(sale.paid))),
                        DataCell(Text(sale.status)),
                      ]);
                    }).toList(),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final String value;

  const _ReportCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
