import 'package:picpos_erp/core/i18n/tr.dart';
// ═══════════════════════════════════════════════════════════════════════════
// ADMIN ELEVATION BANNER — Feature 004 (Multi-Branch Governance, US3)
// ═══════════════════════════════════════════════════════════════════════════
//
// Top-of-screen banner shown when the System Admin's elevated session is in
// read-only mode (connection to the server has dropped). Mounted at the app
// shell level so it appears uniformly across every screen. Hides itself when
// the guard reports `canMutate = true`.
//
// Feature 005 Phase 8 (2026-05-03) — added a manual "إعادة المحاولة الآن"
// button. Pre-005 the banner was passive: the WebSocket reconnect schedule
// follows an exponential 5/10/30/60 s curve, so a transient network blip
// could leave the user staring at the orange banner for up to a minute even
// after the network was back. The button calls
// `WebSocketSyncClient.forceReconnectNow()` which cancels the pending
// timer, resets the attempt counter, and dials the server immediately. Once
// the server accepts and emits `event: 'connected'`, `connected.value` flips
// to `true` and the mutation guard re-evaluates synchronously, hiding the
// banner.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/providers/mutation_guard_provider.dart';
import '../../services/websocket_sync_client.dart';

class AdminElevationBanner extends ConsumerStatefulWidget {
  const AdminElevationBanner({super.key});

  @override
  ConsumerState<AdminElevationBanner> createState() =>
      _AdminElevationBannerState();
}

class _AdminElevationBannerState extends ConsumerState<AdminElevationBanner> {
  bool _retrying = false;

  Future<void> _retryNow() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      WebSocketSyncClient.instance.forceReconnectNow();
      // Give the handshake ~3 s to land before re-enabling the button. The
      // mutationGuardProvider listens to `connected` directly, so it'll flip
      // back to `canMutate` automatically the moment the server confirms.
      await Future.delayed(const Duration(seconds: 3));
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final guard = ref.watch(mutationGuardProvider);
    if (guard.canMutate) return const SizedBox.shrink();
    return Material(
      color: Colors.orange.shade100,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          children: [
            const Icon(PhosphorIconsBold.cloudSlash, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr(guard.reason),
                style: TextStyle(
                  color: Colors.orange.shade900,
                  fontWeight: FontWeight.w600,
                ),
                textDirection: TextDirection.rtl,
              ),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: _retrying ? null : _retryNow,
              icon: _retrying
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(PhosphorIconsBold.arrowsClockwise, size: 16),
              label: Text(
                _retrying ? tr('جارى المحاولة…') : tr('إعادة المحاولة الآن'),
                textDirection: TextDirection.rtl,
              ),
              style: TextButton.styleFrom(
                foregroundColor: Colors.orange.shade900,
                backgroundColor: Colors.white.withValues(alpha: 0.6),
                padding: const EdgeInsets.symmetric(
                    vertical: 4, horizontal: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
