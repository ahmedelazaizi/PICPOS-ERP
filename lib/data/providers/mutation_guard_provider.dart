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
import '../../services/mirror_connectivity.dart';
import '../../services/mirror_state.dart';
import '../../services/network_service.dart';
import 'auth_providers.dart';

export '../../core/mutation_guard.dart';

/// Combines [authProvider.isCrossBranchElevated] with
/// [serverConnectionLiveProvider] (Feature 004) and the console's link state
/// ([MirrorConnectivity], plan 2026-10-24 M2 / MIR-008) to decide whether
/// mutating writes are allowed. The result is mirrored into
/// [MutationGuard.current] so DAO write paths can short-circuit cheaply.
///
/// Order of precedence — console read-only wins because the console has no
/// outbox: a user must be blocked the instant the main goes away, otherwise the
/// write would vanish into a MirrorOfflineException at the bottom of the stack.
///
/// The provider is re-evaluated (1) by a TIMER set for the exact moment the link
/// crosses the read-only threshold, so a console left alone on a list view turns
/// read-only without any interaction, and (2) on every [MirrorState] change — a
/// successful heartbeat, or a failed one ([MirrorState.markHandshakeFailed]).
/// The write path itself (`ClientWriteInterceptor`) consults the same
/// [MirrorConnectivity], so the UI state and the refusal can never disagree.
final mutationGuardProvider = Provider<MutationGuard>((ref) {
  final auth = ref.watch(authProvider);
  final live = ref.watch(serverConnectionLiveProvider);
  ref.watch(mirrorRevisionProvider);

  final left = MirrorConnectivity.untilReadOnly;
  if (NetworkService.instance.isMirror && left != null && left > Duration.zero) {
    final timer = Timer(left + const Duration(seconds: 1), ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }

  final MutationGuard guard;
  if (MirrorConnectivity.isReadOnly) {
    guard = MutationGuard.readOnly(
      reason:
          'فقد الاتصال بالسيرفر الرئيسي — المرآة للقراءة فقط حتى يعود الاتصال.',
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
