import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../services/mirror_state.dart';

/// Mirror-mode badge — Feature 006 (MM.B).
///
/// Visual contract:
///   • Hidden       — when [serverDisplayName] is null/empty.
///   • Green dot    — handshake within the last 30s ("متصل").
///   • Amber dot    — handshake 30s–5min ago ("بطىء").
///   • Red dot      — handshake >5min ago, or no handshake recorded
///                    ("خارج الاتصال").
///
/// Pure [StatelessWidget] — receives the two pieces of state it needs as
/// plain values so it can be driven by a `ValueListenableBuilder` in the
/// app-shell or fed literal values in widget tests. The host is
/// responsible for triggering rebuilds on heartbeat ticks; this widget
/// renders whatever [lastHandshakeAt] it was given.
class MirrorBadge extends StatelessWidget {
  /// Friendly name of the HQ server the device is mirrored against —
  /// e.g. company name, or `<host>:<port>` until [serverDisplayName] is
  /// populated by a richer `/api/health` response. Hidden state when null.
  final String? serverDisplayName;

  /// Most recent successful handshake timestamp from [MirrorState].
  /// `null` is treated as "خارج الاتصال" (red dot).
  final DateTime? lastHandshakeAt;

  /// Tap handler — typically opens a mirror diagnostics dialog. Optional.
  final VoidCallback? onTap;

  const MirrorBadge({
    super.key,
    required this.serverDisplayName,
    required this.lastHandshakeAt,
    this.onTap,
  });

  /// Visible to tests: classify the handshake age into one of three
  /// staleness tiers. Public so the test suite can assert without
  /// pulling at colours / phosphor icons through a widget tree.
  static MirrorConnectivity classify(DateTime? lastHandshakeAt,
      {DateTime? now}) {
    if (lastHandshakeAt == null) return MirrorConnectivity.offline;
    // now is injectable so exact-boundary tests are deterministic (the real
    // elapsed time between building a "30s ago" timestamp and calling now()
    // otherwise tips a slow CI runner just past the inclusive boundary).
    final age =
        (now ?? DateTime.now()).toUtc().difference(lastHandshakeAt.toUtc());
    if (age <= const Duration(seconds: 30)) {
      return MirrorConnectivity.online;
    }
    if (age <= const Duration(minutes: 5)) {
      return MirrorConnectivity.slow;
    }
    return MirrorConnectivity.offline;
  }

  @override
  Widget build(BuildContext context) {
    final name = serverDisplayName;
    if (name == null || name.isEmpty) return const SizedBox.shrink();

    final connectivity = classify(lastHandshakeAt);
    final dotColor = switch (connectivity) {
      MirrorConnectivity.online => AppColors.success,
      MirrorConnectivity.slow => AppColors.warning,
      MirrorConnectivity.offline => AppColors.error,
    };
    final statusLabel = switch (connectivity) {
      MirrorConnectivity.online => 'الآن',
      MirrorConnectivity.slow => 'بطىء',
      MirrorConnectivity.offline => 'خارج الاتصال',
    };

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.25),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mirror glyph — kept as a leading character (not an icon font)
          // so the badge stays self-contained and translatable. The "🪞"
          // emoji is the same one used in the project's design notes for
          // mirror mode.
          const Text(
            '🪞 ',
            style: TextStyle(fontSize: 11, height: 1.0),
          ),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            statusLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w500,
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

/// Connectivity tier surfaced by [MirrorBadge.classify]. Public so widget
/// tests can assert against the same enum the production code uses.
enum MirrorConnectivity { online, slow, offline }
