import 'package:picpos_erp/core/i18n/tr.dart';
// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../data/providers/repository_providers.dart';
import '../../core/theme/app_colors.dart';

class FieldAuditHistoryWidget extends ConsumerWidget {
  final String entityType;
  final int entityId;

  const FieldAuditHistoryWidget({
    super.key,
    required this.entityType,
    required this.entityId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(activityLogRepositoryProvider);

    return FutureBuilder<List<dynamic>>(
      future: repo.getFieldHistory(entityType: entityType, entityId: entityId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(),
          ));
        }

        if (snapshot.hasError) {
          return Center(child: Text(tr('خطأ في تحميل تفاصيل الحقول: {p0}', {'p0': snapshot.error})));
        }

        final changes = snapshot.data ?? [];
        if (changes.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Divider(),
            ),
             Row(
              children: [
                const Icon(PhosphorIconsBold.listMagnifyingGlass, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  tr('تفاصيل التغييرات على الحقول:'),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: changes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final change = changes[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                       color: Theme.of(context).colorScheme.outlineVariant,
                     ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            change.fieldName ?? change.fieldKey,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            _formatDate(change.createdAt),
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _ValueBox(
                              label: tr('من'),
                              value: change.oldValue ?? tr('(فارغ)'),
                              color: AppColors.error,
                              textColor: AppColors.error,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Icon(Icons.arrow_forward, size: 14, color: Colors.grey),
                          ),
                          Expanded(
                            child: _ValueBox(
                              label: tr('إلى'),
                              value: change.newValue ?? tr('(فارغ)'),
                              color: Colors.green.shade50,
                              textColor: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                      if (change.changeReason != null && change.changeReason!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          tr('السبب: {p0}', {'p0': change.changeReason}),
                          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey.shade700),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} - ${date.day}/${date.month}/${date.year}';
  }
}

class _ValueBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color textColor;

  const _ValueBox({
    required this.label,
    required this.value,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: textColor.withValues(alpha: 0.7))),
          Text(
            value,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textColor),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}