import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';

class TreasuryScreen extends ConsumerWidget {
  const TreasuryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safesAsync = ref.watch(allSafesProvider);
    final totalBalance = ref.watch(totalCashBalanceProvider);
    final formatter = NumberFormat.currency(symbol: 'ج.م ', decimalDigits: 2, locale: 'ar_EG');

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('الخزينة'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Total balance card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.7)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  'إجمالي رصيد الخزائن',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 8),
                totalBalance.when(
                  data: (balance) => Text(
                    formatter.format(balance),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  loading: () => const CircularProgressIndicator(color: Colors.white),
                  error: (_, _) => const Text('0', style: TextStyle(color: Colors.white, fontSize: 32)),
                ),
              ],
            ),
          ),

          // Safes list
          Expanded(
            child: safesAsync.when(
              data: (safes) {
                if (safes.isEmpty) {
                  return const Center(child: Text('لا توجد خزائن'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: safes.length,
                  itemBuilder: (context, index) {
                    final safe = safes[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: safe.isDefault ? AppColors.success : AppColors.info,
                          child: const Icon(PhosphorIconsBold.bank, color: Colors.white),
                        ),
                        title: Text(safe.name),
                        subtitle: safe.isDefault ? const Text('الخزينة الافتراضية') : null,
                        trailing: Text(
                          formatter.format(safe.balance),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
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
}
