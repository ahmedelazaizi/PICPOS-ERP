import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(allProductsProvider);
    final salesAsync = ref.watch(todaySalesProvider);
    final cashBalance = ref.watch(totalCashBalanceProvider);
    final formatter = NumberFormat.currency(symbol: 'ج.م ', decimalDigits: 2, locale: 'ar_EG');

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('لوحة التحكم'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              ref.watch(themeModeProvider) 
                  ? PhosphorIconsBold.sun 
                  : PhosphorIconsBold.moon,
            ),
            onPressed: () {
              ref.read(themeModeProvider.notifier).toggle();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome message
            Text(
              'مرحباً بك في نظام UralCash',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              DateFormat('EEEE، d MMMM yyyy', 'ar').format(DateTime.now()),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 32),

            // Stats cards
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                // Products count
                _StatCard(
                  title: 'المنتجات',
                  value: productsAsync.when(
                    data: (products) => products.length.toString(),
                    loading: () => '...',
                    error: (_, _) => '0',
                  ),
                  icon: PhosphorIconsBold.package,
                  color: AppColors.info,
                ),

                // Today's sales
                _StatCard(
                  title: 'مبيعات اليوم',
                  value: salesAsync.when(
                    data: (sales) {
                      final todaySales = sales.where((s) {
                        final today = DateTime.now();
                        return s.invoiceDate.year == today.year &&
                               s.invoiceDate.month == today.month &&
                               s.invoiceDate.day == today.day;
                      });
                      return formatter.format(
                        todaySales.fold(0.0, (sum, s) => sum + s.total)
                      );
                    },
                    loading: () => '...',
                    error: (_, _) => formatter.format(0),
                  ),
                  icon: PhosphorIconsBold.shoppingCart,
                  color: AppColors.success,
                ),

                // Invoice count today
                _StatCard(
                  title: 'فواتير اليوم',
                  value: salesAsync.when(
                    data: (sales) {
                      final today = DateTime.now();
                      return sales.where((s) =>
                        s.invoiceDate.year == today.year &&
                        s.invoiceDate.month == today.month &&
                        s.invoiceDate.day == today.day
                      ).length.toString();
                    },
                    loading: () => '...',
                    error: (_, _) => '0',
                  ),
                  icon: PhosphorIconsBold.receipt,
                  color: AppColors.warning,
                ),

                // Cash balance
                _StatCard(
                  title: 'رصيد الخزينة',
                  value: cashBalance.when(
                    data: (balance) => formatter.format(balance),
                    loading: () => '...',
                    error: (_, _) => formatter.format(0),
                  ),
                  icon: PhosphorIconsBold.bank,
                  color: AppColors.primary,
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Recent sales section
            Text(
              'آخر المبيعات',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            salesAsync.when(
              data: (sales) {
                if (sales.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text('لا توجد مبيعات اليوم'),
                      ),
                    ),
                  );
                }

                final recentSales = sales.take(10).toList();
                return Card(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('رقم الفاتورة')),
                      DataColumn(label: Text('التاريخ')),
                      DataColumn(label: Text('المبلغ'), numeric: true),
                      DataColumn(label: Text('طريقة الدفع')),
                    ],
                    rows: recentSales.map((sale) {
                      return DataRow(cells: [
                        DataCell(Text(sale.invoiceNumber)),
                        DataCell(Text(DateFormat('dd/MM/yyyy HH:mm').format(sale.invoiceDate))),
                        DataCell(Text(formatter.format(sale.total))),
                        DataCell(Text(_getPaymentMethodLabel(sale.paymentMethod))),
                      ]);
                    }).toList(),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(child: Text('خطأ في تحميل البيانات: $e')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getPaymentMethodLabel(String method) {
    switch (method) {
      case 'cash':
        return 'نقدي';
      case 'card':
        return 'بطاقة';
      case 'credit':
        return 'آجل';
      default:
        return method;
    }
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
