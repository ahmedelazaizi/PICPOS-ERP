// Providers behind the offline-login screens (leftover #1): the device-local
// shadow/enforce switch, what shadow would have refused, and the signed-in
// user's "days left" standing for the branch-device banner. The presentation
// layer reads these - it never touches the database type.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth/credential_stamp_store.dart';
import '../../services/auth/offline_login_policy.dart';
import '../../services/auth/offline_login_standing.dart';
import '../../services/auth/shadow_login_log.dart';
import '../../services/network_service.dart';
import '../repositories/auth_session_gate.dart';
import 'providers.dart';

/// Look-back window of the shadow summary shown before switching to `enforce`.
const kShadowSummaryDays = 30;

/// The same policy the login uses (secure store + stamps + grace days).
final offlineLoginPolicyProvider = Provider<OfflineLoginPolicy>((ref) {
  final db = ref.read(databaseProvider);
  return OfflineLoginPolicy(
    store: SecureOfflineLoginStore(),
    stamps: CredentialStampStore.forDb(db),
    readGraceDays: () async =>
        int.tryParse(await db.getSettingValue('offline_login_grace_days') ?? ''),
  );
});

/// The device-local switch (`offline_login_mode`, default shadow).
final offlineLoginModeProvider =
    FutureProvider.autoDispose<OfflineLoginMode>((ref) async {
  try {
    return OfflineLoginMode.parse(
        await ref.read(databaseProvider).getSettingValue(OfflineLoginMode.settingKey));
  } catch (_) {
    return OfflineLoginMode.shadow;
  }
});

/// What shadow mode allowed in the last [kShadowSummaryDays] days that
/// `enforce` would have refused.
final offlineShadowSummaryProvider =
    FutureProvider.autoDispose<ShadowLoginSummary>((ref) =>
        ShadowLoginLog(ref.read(databaseProvider)).summary(days: kShadowSummaryDays));

/// Writes behind the settings tile (the ONE place the switch is flipped).
class OfflineLoginModeActions {
  OfflineLoginModeActions(this._ref);
  final Ref _ref;

  Future<void> setMode(OfflineLoginMode mode) async {
    await AuthSessionGate.setMode(_ref.read(databaseProvider), mode);
    _ref.invalidate(offlineLoginModeProvider);
  }

  Future<void> clearShadowLog() async {
    await ShadowLoginLog(_ref.read(databaseProvider)).clear();
    _ref.invalidate(offlineShadowSummaryProvider);
  }
}

final offlineLoginModeActionsProvider =
    Provider<OfflineLoginModeActions>(OfflineLoginModeActions.new);

/// How often the banner re-evaluates (the stamp ages with the wall clock).
const kOfflineStandingRefresh = Duration(minutes: 15);

/// The signed-in user's offline standing; hidden on every device that is not a
/// branch device (client / mirror) and for everybody not signed in.
final offlineStandingProvider =
    FutureProvider.autoDispose<OfflineStanding>((ref) async {
  final mode = ref.watch(syncRepositoryProvider).mode;
  if (mode != NetworkMode.client && mode != NetworkMode.mirror) {
    return OfflineStanding.hiddenStanding;
  }
  final user = ref.watch(authProvider.select((a) => a.userWithRole?.user));
  if (user == null) return OfflineStanding.hiddenStanding;
  final timer = Timer(kOfflineStandingRefresh, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  try {
    return await ref
        .read(offlineLoginPolicyProvider)
        .standing(user.id, passwordHash: user.passwordHash);
  } catch (_) {
    return OfflineStanding.hiddenStanding;
  }
});
