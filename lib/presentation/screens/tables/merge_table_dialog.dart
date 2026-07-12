import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/database/database.dart';

/// Dialog to select a target table for merging orders
class MergeTableDialog extends StatelessWidget {
  final RestaurantTable sourceTable;
  final List<RestaurantTable> otherOccupiedTables;
  final Function(RestaurantTable targetTable) onMerge;

  const MergeTableDialog({
    super.key,
    required this.sourceTable,
    required this.otherOccupiedTables,
    required this.onMerge,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.intersect, color: AppColors.warning),
            SizedBox(width: 8),
            Text('دمج الطاولات'),
          ],
        ),
        content: SizedBox(
          width: 400,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'سيتم نقل جميع أصناف "${sourceTable.name}" إلى الطاولة التي ستختارها:',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: otherOccupiedTables.isEmpty
                    ? const Center(
                        child: Text('لا توجد طاولات مشغولة أخرى للدمج معها'),
                      )
                    : ListView.separated(
                        itemCount: otherOccupiedTables.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, index) {
                          final table = otherOccupiedTables[index];
                          return ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                PhosphorIconsBold.circlesThree,
                                color: AppColors.error,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              table.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text('السعة: ${table.capacity} أشخاص'),
                            onTap: () {
                              Navigator.pop(context);
                              onMerge(table);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }
}
