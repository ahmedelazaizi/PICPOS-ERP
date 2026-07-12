import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../services/network_service.dart';
import '../../../services/offline_sync_worker.dart';

/// Inline banner that surfaces the count of unsynced invoices for a given
/// source table (`sales`, `purchase_invoices`, `sales_returns`,
/// `purchase_returns`). Shows a one-tap "force sync" button so the
/// operator does not have to wait for the next backoff tick when they
/// know connectivity has been restored.
///
/// Renders nothing in non-client modes and when the per-table pending
/// count is zero — the banner is information-only, never decorative.
class SyncPendingBanner extends ConsumerWidget {
  const SyncPendingBanner({
    super.key,
    required this.tableName,
    required this.label,
  });

  /// Outbox `target_table` to scope the count to (e.g. `'sales'`).
  final String tableName;

  /// User-facing Arabic word used in the banner sentence (e.g. "فاتورة
  /// مبيعات", "فاتورة مشتريات"). Inserted as-is.
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!NetworkService.instance.isClient) return const SizedBox.shrink();
    final db = ref.watch(databaseProvider);
    return StreamBuilder<int>(
      stream: db.watchSyncPendingCountForTable(tableName),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        if (count <= 0) return const SizedBox.shrink();
        return _SyncPendingBannerView(
          count: count,
          label: label,
          onForceSync: () async {
            AppToast.show(
              context,
              'جارى محاولة المزامنة...',
              type: ToastType.info,
            );
            // BUG-U34: report the outcome — the banner itself stays visible if
            // items remain, but surface drain failures explicitly.
            try {
              await OfflineSyncWorker.instance.drainOutbox(force: true);
              if (context.mounted) {
                // Outcome is unknown here (drainOutbox returns no counts) and
                // the banner stays visible while items remain — keep this
                // neutral (info, not green success) so it doesn't imply the
                // outbox fully drained.
                AppToast.show(context, 'انتهت محاولة المزامنة — تحقّق من المؤشر',
                    type: ToastType.info);
              }
            } catch (e) {
              if (context.mounted) {
                AppToast.show(context, friendlyError(e, context: 'FORCE-SYNC'),
                    type: ToastType.error);
              }
            }
          },
        );
      },
    );
  }
}

class _SyncPendingBannerView extends StatelessWidget {
  const _SyncPendingBannerView({
    required this.count,
    required this.label,
    required this.onForceSync,
  });

  final int count;
  final String label;
  final VoidCallback onForceSync;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        border: Border.all(color: Colors.amber.shade700, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsBold.cloudArrowUp,
              color: Colors.amber.shade800, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'يوجد $count $label فى انتظار المزامنة مع السيرفر',
              style: TextStyle(
                color: Colors.amber.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onForceSync,
            icon: const Icon(PhosphorIconsBold.arrowClockwise, size: 16),
            label: const Text('إعادة المزامنة'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
