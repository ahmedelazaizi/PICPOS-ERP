import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';

/// A compact badge that communicates the outbox sync state.
///
/// Visual contract:
/// * **Hidden**  — both [pendingCount] and [deadLetterCount] are zero.
/// * **Warning** (yellow) — there are pending operations waiting to be synced.
/// * **Error**   (red)    — at least one operation has permanently failed
///                          (dead-letter queue is non-empty).
///
/// The badge is intentionally a pure [StatelessWidget] — it receives counts
/// as plain integers so it can be driven by [ValueListenableBuilder] in the
/// app-shell or stubbed with literal values in tests.
class SyncStatusBadge extends StatelessWidget {
  /// Number of outbox operations waiting to be sent to the server.
  final int pendingCount;

  /// Number of outbox operations that have exhausted all retries.
  final double deadLetterCount;

  /// Optional tap handler — typically opens the sync-management dialog.
  final VoidCallback? onTap;

  const SyncStatusBadge({
    super.key,
    required this.pendingCount,
    this.deadLetterCount = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (pendingCount == 0 && deadLetterCount == 0) {
      return const SizedBox.shrink();
    }

    final hasDeadLetter = deadLetterCount > 0;
    final badgeColor = hasDeadLetter
        ? AppColors.error.withValues(alpha: 0.9)
        : AppColors.warning.withValues(alpha: 0.9);
    final icon = hasDeadLetter
        ? PhosphorIconsBold.cloudSlash
        : PhosphorIconsBold.cloudArrowUp;
    final label = hasDeadLetter
        ? '${deadLetterCount.toInt()} !'
        : pendingCount.toString();

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: badge);
    }
    return badge;
  }
}
