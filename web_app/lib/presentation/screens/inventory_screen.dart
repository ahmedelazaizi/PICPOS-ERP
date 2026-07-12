import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movementsAsync = ref.watch(stockMovementsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('المخزون'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: movementsAsync.when(
        data: (movements) {
          if (movements.isEmpty) {
            return const Center(child: Text('لا توجد حركات مخزون'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: movements.length,
            itemBuilder: (context, index) {
              final movement = movements[index];
              final isIn = movement.quantity > 0;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isIn ? AppColors.success : AppColors.danger,
                    child: Icon(
                      isIn ? PhosphorIconsBold.arrowDown : PhosphorIconsBold.arrowUp,
                      color: Colors.white,
                    ),
                  ),
                  title: Text('كمية: ${movement.quantity.abs()}'),
                  subtitle: Text('النوع: ${movement.movementType}'),
                  trailing: Text(
                    'الرصيد: ${movement.balanceAfter}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: $e')),
      ),
    );
  }
}
