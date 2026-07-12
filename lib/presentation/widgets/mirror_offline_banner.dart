import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../services/mirror_state.dart';
import '../../services/network_service.dart';

/// Mirror-mode offline banner — Feature 006 / MM.D.
///
/// Mounted at the top of the AppShell body in mirror mode. Becomes
/// visible (collapses to zero height when not) the moment the most
/// recent handshake is older than 5 minutes — the same threshold the
/// `mutationGuardProvider` uses to flip the device into read-only.
///
/// Visual contract:
///   • Hidden when not in mirror mode.
///   • Hidden when the handshake is fresh (< 5 minutes old).
///   • Red-tinted bar with a wifi-slash glyph + Arabic message when
///     the threshold is crossed. The bar disappears the moment
///     `MirrorState.markHandshake()` brings the timestamp back inside
///     the window (no manual dismiss needed).
///
/// Pure widget — listens directly to `MirrorState.revision` so it
/// rebuilds on every heartbeat tick without a Riverpod ref. Lets the
/// banner sit anywhere in the tree (above or outside Riverpod scope).
class MirrorOfflineBanner extends StatefulWidget {
  const MirrorOfflineBanner({super.key});

  /// Same threshold the mutationGuardProvider uses. Mirroring it here
  /// (rather than importing the provider) keeps the banner usable in
  /// widget tests that don't pull in Riverpod.
  static const Duration offlineThreshold = Duration(minutes: 5);

  /// Test seam — mirrors `MirrorBadge.classify` style. True when the
  /// device should show the banner given the current mode + last
  /// handshake. Public so widget tests can assert without driving the
  /// full timer + clock dance.
  static bool shouldShow({
    required NetworkMode mode,
    required DateTime? lastHandshakeAt,
    required DateTime now,
  }) {
    if (mode != NetworkMode.mirror) return false;
    if (lastHandshakeAt == null) return true;
    return now.toUtc().difference(lastHandshakeAt.toUtc()) > offlineThreshold;
  }

  @override
  State<MirrorOfflineBanner> createState() => _MirrorOfflineBannerState();
}

class _MirrorOfflineBannerState extends State<MirrorOfflineBanner> {
  // Periodic re-check so the banner appears even when no other state
  // changes — e.g. the heartbeat is failing silently and the operator
  // is just sitting on a list view. Tied to the widget's lifetime.
  late final Stream<int> _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Stream<int>.periodic(
      const Duration(seconds: 15),
      (i) => i,
    ).asBroadcastStream();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MirrorState.instance.revision,
      builder: (_, _, _) {
        return StreamBuilder<int>(
          stream: _ticker,
          builder: (_, _) {
            final visible = MirrorOfflineBanner.shouldShow(
              mode: NetworkService.instance.mode,
              lastHandshakeAt: MirrorState.instance.lastHandshakeAt,
              now: DateTime.now(),
            );
            if (!visible) return const SizedBox.shrink();
            return Material(
              color: AppColors.error.withValues(alpha: 0.95),
              child: const SafeArea(
                top: false,
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        PhosphorIconsBold.wifiSlash,
                        color: Colors.white,
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'فقد الاتصال بـ HQ-Server — التعديلات معطّلة '
                          'حتى يُستعاد الاتصال',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
