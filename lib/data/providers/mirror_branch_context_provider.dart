// Riverpod side of the branch-manager console's CURRENT BRANCH (plan 2026-10-24,
// M2 / MIR-012). Logic lives in `MirrorBranchContext` (services).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/mirror_branch_context.dart';
import '../../services/network_service.dart';
import '../../services/server_proxy.dart';
import 'auth_providers.dart';
import 'providers.dart' show databaseProvider;

/// The branch the console works in (null off a mirror / before a context).
/// Re-evaluates when the manager switches branch.
final mirrorCurrentBranchProvider = Provider<int?>((ref) {
  final n = MirrorBranchContext.instance.current;
  void listener() => ref.invalidateSelf();
  n.addListener(listener);
  ref.onDispose(() => n.removeListener(listener));
  return n.value;
});

/// Asks the main for the signed-in manager's scope and applies it. Keep it
/// alive while a mirror user is signed in (the app shell watches it).
final mirrorConsoleContextProvider =
    FutureProvider<MirrorConsoleContext?>((ref) async {
  final uid = ref.watch(authProvider.select((s) => s.user?.id));
  final ctx = MirrorBranchContext.instance;
  if (!NetworkService.instance.isMirror || uid == null) {
    ctx.reset();
    return null;
  }
  final db = ref.read(databaseProvider);
  await ctx.restore(db);
  final answer = await ServerProxy.instance.fetchMirrorContext();
  if (answer != null) await ctx.applyContext(answer, db: db);
  return answer;
});
