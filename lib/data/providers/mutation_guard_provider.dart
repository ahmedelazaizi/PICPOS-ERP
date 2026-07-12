// ═══════════════════════════════════════════════════════════════════════════
// MUTATION GUARD PROVIDER — Feature 004 (Multi-Branch Governance, US3)
// ═══════════════════════════════════════════════════════════════════════════
//
// Riverpod-side of the mutation guard. The data classes ([MutationGuard],
// [MutationDeniedException]) live in `lib/core/mutation_guard.dart` so they
// can be imported by the Drift database layer without pulling Flutter/
// Riverpod into the schema module.
//
// Reference: contracts/admin-elevation.md.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mutation_guard.dart';
import '../../services/mirror_state.dart';
import '../../services/network_service.dart';
import 'auth_providers.dart';

export '../../core/mutation_guard.dart';

/// True when the device is in mirror mode AND the most recent handshake
/// is older than 5 minutes (or never recorded). Mirrors the
/// `MirrorBadge.classify` "offline" tier so the badge color and the
/// guard agree on what "offline" means.
///
/// Using a 5-minute threshold (not the badge's 30s "online" tier)
/// avoids flapping read-only state every time a heartbeat is briefly
/// late — the operator only loses write access when HQ has clearly
/// gone away, not on a transient hiccup.
bool _isMirrorOffline() {
  if (!NetworkService.instance.isMirror) return false;
  final stamp = MirrorState.instance.lastHandshakeAt;
  if (stamp == null) return true;
  return DateTime.now().toUtc().difference(stamp.toUtc()) >
      const Duration(minutes: 5);
}

/// Provider that combines [authProvider.isCrossBranchElevated] with
/// [serverConnectionLiveProvider] (Feature 004) and the mirror-mode
/// offline detector (Feature 006 / MM.D) to decide whether mutating
/// writes are allowed in the current session. Mirrors the result into
/// [MutationGuard.current] so DAO write paths can short-circuit cheaply.
///
/// Order of precedence — mirror-offline wins because it has no outbox:
/// even a non-elevated user on a mirror device must be blocked the
/// instant HQ goes away, otherwise their writes vanish into
/// MirrorOfflineException at the bottom of the stack with no UI hook
/// to undo the optimistic state.
final mutationGuardProvider = Provider<MutationGuard>((ref) {
  final auth = ref.watch(authProvider);
  final live = ref.watch(serverConnectionLiveProvider);
  // Re-evaluate on every MirrorState change so a heartbeat tick that
  // crosses the 5-minute threshold flips the guard immediately. The
  // counter value is irrelevant — only the change event matters.
  ref.watch(mirrorRevisionProvider);

  final MutationGuard guard;
  if (_isMirrorOffline()) {
    guard = MutationGuard.readOnly(
      reason:
          'فقد الاتصال بـ HQ-Server — وضع المرآة معطّل للكتابة حتى يُستعاد الاتصال',
    );
  } else if (auth.isCrossBranchElevated && !live) {
    guard = MutationGuard.readOnly(
      reason:
          'تم فقد الاتصال — جلسة الإدارة فى وضع القراءة فقط حتى استعادة الاتصال',
    );
  } else {
    guard = MutationGuard.allow();
  }
  // Mirror into the static snapshot so DAO write paths (which can't read
  // Riverpod refs from a Drift extension) can short-circuit cheaply.
  MutationGuard.current = guard;
  return guard;
});

/// Bridges `MirrorState.revision` (a `ValueListenable<int>`) into
/// Riverpod so [mutationGuardProvider] can `ref.watch` it and rebuild
/// when the heartbeat ticker stamps a fresh `lastHandshakeAt`.
final mirrorRevisionProvider = StreamProvider<int>((ref) async* {
  final notifier = MirrorState.instance.revision;
  yield notifier.value;
  final controller = StreamController<int>();
  void listener() => controller.add(notifier.value);
  notifier.addListener(listener);
  ref.onDispose(() {
    notifier.removeListener(listener);
    controller.close();
  });
  yield* controller.stream;
});
