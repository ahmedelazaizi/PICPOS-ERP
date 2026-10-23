import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';

/// سجلُّ طاولةٍ واحدةٍ — استعلامٌ على `ActivityLogs` المسلسَل بالهاش
/// (ICR-03)، لا جدولٌ جديد. كلَّ سطرٍ هنا كتبه `TableSessionService` عند
/// انتقالٍ فعليٍّ (فتحٍ، إغلاقٍ، نقلٍ، دمجٍ، خصمٍ، تغييرِ حالة...)، فتزوير
/// السجل يستلزم تعديلَ سلسلة الهاش كاملةً — لا سطراً واحداً.
///
/// **لا يستورد `data/database` مباشرةً**: يمرّ عبر
/// `IActivityLogRepository.logsForEntity`، ويصل إلى نوع `ActivityLog` عبر
/// إعادة تصدير `data/providers/providers.dart` — النمطُ نفسُه الذي تعتمده
/// بقيةُ شاشات الطاولات لأنواع `RestaurantTable`/`TableOrder`، فتبقى القراءةُ
/// مُقيَّسةً بلا حاجةٍ إلى `dynamic` (وما يجرّه من تحذيرات `avoid_dynamic_calls`).
class TableLogSheet extends ConsumerStatefulWidget {
  const TableLogSheet({
    super.key,
    required this.tableId,
    required this.tableName,
  });

  final int tableId;
  final String tableName;

  @override
  ConsumerState<TableLogSheet> createState() => _TableLogSheetState();
}

class _TableLogSheetState extends ConsumerState<TableLogSheet> {
  late Future<List<ActivityLog>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(activityLogRepositoryProvider).logsForEntity(
          entityType: 'table',
          entityId: widget.tableId,
        );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 12, 16, 8),
              child: Row(
                children: [
                  const Icon(
                    PhosphorIconsBold.clockCounterClockwise,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr('سجل {p0}', {'p0': widget.tableName}),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(PhosphorIconsBold.x, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return FutureBuilder<List<ActivityLog>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                tr('تعذّر تحميلُ السجل: {p0}', {'p0': snapshot.error}),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          );
        }

        final logs = snapshot.data ?? const [];
        if (logs.isEmpty) {
          return  Center(
            child: Text(
              tr('لا يوجد سجلٌّ لهذه الطاولة بعد'),
              style: const TextStyle(color: AppColors.textMuted),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: logs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) => _TableLogRow(log: logs[index]),
        );
      },
    );
  }
}

/// سطرٌ واحدٌ من السجل.
class _TableLogRow extends StatelessWidget {
  const _TableLogRow({required this.log});

  final ActivityLog log;

  @override
  Widget build(BuildContext context) {
    final createdAt = log.createdAt;
    final description = log.description;
    final userName = log.userName;
    final action = log.action;
    final amount = log.amount;
    final oldValue = log.oldValue;
    final newValue = log.newValue;

    final time =
        '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
    final color = _colorForAction(action);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Icon(_iconForAction(action), size: 18, color: color),
                const SizedBox(height: 4),
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (oldValue != null || newValue != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${oldValue ?? "—"} ← ${newValue ?? "—"}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      PhosphorIconsBold.user,
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (amount != null) ...[
            const SizedBox(width: 8),
            Text(
              '${amount.toStringAsFixed(AppConstants.decimalPlaces)} '
              '${AppConstants.currencySymbolEn}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: AppColors.success,
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _iconForAction(String action) {
    switch (action) {
      case 'table_open':
        return PhosphorIconsBold.doorOpen;
      case 'table_close':
        return PhosphorIconsBold.checkCircle;
      case 'table_order_cancel':
        return PhosphorIconsBold.xCircle;
      case 'table_status_change':
        return PhosphorIconsBold.arrowsClockwise;
      case 'table_transfer':
        return PhosphorIconsBold.arrowsLeftRight;
      case 'table_merge':
        return PhosphorIconsBold.intersect;
      case 'table_discount':
        return PhosphorIconsBold.percent;
      case 'table_tax':
        return PhosphorIconsBold.receipt;
      default:
        return PhosphorIconsBold.note;
    }
  }

  Color _colorForAction(String action) {
    switch (action) {
      case 'table_open':
        return AppColors.success;
      case 'table_close':
        return const Color(0xFF0EA5E9);
      case 'table_order_cancel':
        return AppColors.error;
      case 'table_status_change':
        return const Color(0xFF6366F1);
      case 'table_transfer':
        return AppColors.booking;
      case 'table_merge':
        return AppColors.warning;
      case 'table_discount':
        return const Color(0xFF06B6D4);
      case 'table_tax':
        return const Color(0xFF8B5CF6);
      default:
        return AppColors.textMuted;
    }
  }
}
