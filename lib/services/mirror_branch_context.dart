// ═══════════════════════════════════════════════════════════════════════════
// Branch-manager console: the CURRENT BRANCH (plan 2026-10-24, M2 / MIR-012).
//
// A manager who works in several branches picks the one he is "in" on the
// console. That choice (a device-local setting, never synced) feeds
//   * `activeBranchIdProvider` on the mirror (what the screens query),
//   * the `X-Branch-Id` header of every server call (ServerProxy),
//   * the `branchId` of a write that carries none (WriteRouter),
// and the MAIN checks every one of them against the manager's own scope.
//
// The list of selectable branches always comes from the main
// (`GET /api/mirror/context`), so the selector can never offer a branch the
// server would refuse. No assigned branch => an explicit empty state, never a
// silent "all".
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/foundation.dart';

import '../data/database/database.dart';

class MirrorBranch {
  const MirrorBranch({required this.id, required this.name, this.code});

  factory MirrorBranch.fromJson(Map<String, dynamic> j) => MirrorBranch(
        id: (j['id'] as num).toInt(),
        name: (j['name'] as String?) ?? '',
        code: j['code'] as String?,
      );

  final int id;
  final String name;
  final String? code;
}

/// What `GET /api/mirror/context` answered.
class MirrorConsoleContext {
  const MirrorConsoleContext({
    required this.userId,
    required this.fullAccess,
    required this.canConsole,
    required this.branches,
    this.defaultBranchId,
  });

  factory MirrorConsoleContext.fromJson(Map<String, dynamic> j) =>
      MirrorConsoleContext(
        userId: (j['userId'] as num).toInt(),
        fullAccess: j['fullAccess'] == true,
        canConsole: j['canConsole'] == true,
        defaultBranchId: (j['defaultBranchId'] as num?)?.toInt(),
        branches: [
          for (final b in (j['branches'] as List? ?? const []))
            MirrorBranch.fromJson(Map<String, dynamic>.from(b as Map))
        ],
      );

  final int userId;
  final bool fullAccess;
  final bool canConsole;
  final List<MirrorBranch> branches;
  final int? defaultBranchId;
}

class MirrorBranchContext {
  MirrorBranchContext._();
  static final MirrorBranchContext instance = MirrorBranchContext._();

  /// Device-local setting (∈ `kDeviceLocalSettingKeys`).
  static const String settingKey = 'mirror_current_branch_id';

  /// The branch the console works in; null until a context is applied.
  final ValueNotifier<int?> current = ValueNotifier<int?>(null);

  /// Branches in the signed-in manager's scope, as the main reported them.
  final ValueNotifier<List<MirrorBranch>> branches =
      ValueNotifier<List<MirrorBranch>>(const []);

  /// True once the main answered for the signed-in user.
  final ValueNotifier<bool> loaded = ValueNotifier<bool>(false);

  int? _persisted;

  int? get currentBranchId => current.value;

  /// The signed-in manager has been told by the main that he has no branch.
  bool get hasNoBranches => loaded.value && branches.value.isEmpty;

  MirrorBranch? get currentBranch {
    final id = current.value;
    for (final b in branches.value) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Reads the last choice from the local settings (before the main answers).
  Future<void> restore(AppDatabase db) async {
    final raw = await db.getSettingValue(settingKey);
    _persisted = int.tryParse(raw ?? '');
    current.value ??= _persisted;
  }

  /// Applies the main's answer: the persisted choice survives only while it is
  /// still inside the scope, else the main's default (else nothing).
  Future<void> applyContext(MirrorConsoleContext ctx, {AppDatabase? db}) async {
    branches.value = ctx.branches;
    final ids = ctx.branches.map((b) => b.id).toSet();
    final keep = [current.value, _persisted].firstWhere(
      (c) => c != null && ids.contains(c),
      orElse: () => null,
    );
    final next = keep ?? (ids.contains(ctx.defaultBranchId) ? ctx.defaultBranchId : null);
    current.value = next;
    loaded.value = true;
    if (db != null && next != null && next != _persisted) {
      _persisted = next;
      await db.setSetting(settingKey, '$next');
    }
  }

  /// Switches the branch. Refused (false) for a branch outside the scope.
  Future<bool> select(int branchId, {AppDatabase? db}) async {
    if (!branches.value.any((b) => b.id == branchId)) return false;
    current.value = branchId;
    _persisted = branchId;
    if (db != null) await db.setSetting(settingKey, '$branchId');
    return true;
  }

  /// On sign-out: the next manager gets his own branches (the stored choice
  /// stays, and is re-validated against his scope).
  void reset() {
    branches.value = const [];
    loaded.value = false;
    current.value = null;
  }

  @visibleForTesting
  void debugSet({List<MirrorBranch> branches = const [], int? current, bool loaded = true}) {
    this.branches.value = branches;
    this.current.value = current;
    this.loaded.value = loaded;
  }
}
