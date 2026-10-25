// A1 (adoption contract §C.7-3): the ONLY place a first-run / re-provision
// commits a deployment mode. It wraps [DeploymentModeCommitter] and adds the
// guarantees the old flow lacked:
//
//  * the mode that is committed is the mode that was CHOSEN ([ActivationPlan.mode],
//    derived from the path by the caller) - never whatever a half-finished
//    earlier attempt left in `network_mode`;
//  * the pairing the device holds must MATCH that mode (a mirror needs
//    `MirrorState`; a client must not keep a stale mirror identity);
//  * after the commit the result is VERIFIED against the live system (memory,
//    DB key, device record, mirror identity) - a mismatch is a failure, never
//    a silent fallback to another mode;
//  * the device record is written by the committer in the same transaction as
//    the derived keys, then the credentials-delivered stamp is added.
library;

import 'dart:async';

import '../../core/logging/diagnostic_logger.dart';
import '../../data/database/database.dart';
import '../mirror_state.dart';
import '../network_service.dart';
import 'commit_result.dart';
import 'deployment_mode_committer.dart';
import 'provisioning_record.dart';

/// Facts the earlier first-run steps learned and the commit must record.
/// Cleared after every commit (success or not).
class ActivationHints {
  ActivationHints._();

  /// What the main bound this device to (`client` | `pos` | `mirror`).
  static String? deviceKind;

  /// Set by the first-user verification when the branch credentials arrived.
  static DateTime? credentialsDeliveredAt;

  static void clear() {
    deviceKind = null;
    credentialsDeliveredAt = null;
  }
}

class ActivationPlan {
  const ActivationPlan({
    required this.mode,
    this.port = 8080,
    this.host,
    this.deviceKind,
  });

  final NetworkMode mode;
  final int port;
  final String? host;
  final String? deviceKind;
}

class ModeActivator {
  ModeActivator({required this.db, DeploymentModeCommitter? committer})
      : _committer = committer ?? DeploymentModeCommitter(db: db);

  final AppDatabase db;
  final DeploymentModeCommitter _committer;

  Future<CommitResult> commit(
    ActivationPlan plan, {
    CommitProgressCallback? onProgress,
    bool forceResync = false,
  }) async {
    final kind = plan.deviceKind ?? ActivationHints.deviceKind;
    final delivered = ActivationHints.credentialsDeliveredAt;
    final pre = await _preflight(plan);
    if (pre != null) return pre;
    final contract = _committer.buildContract(
      target: plan.mode,
      serverPort: plan.port,
      serverHost: plan.host ?? NetworkService.instance.serverAddress,
    );
    final result = await _committer.commit(
      contract: contract,
      onProgress: onProgress,
      forceResync: forceResync,
      deviceKind: kind,
    );
    // A failed attempt keeps the hints: the retry still needs them.
    if (result is! CommitOk) return result;
    final mismatch = await _verify(plan);
    if (mismatch != null) return mismatch;
    if (delivered != null) {
      final rec = await ProvisioningStore.read(db);
      if (rec != null) {
        await ProvisioningStore.write(
            db, rec.copyWith(credentialsDeliveredAt: delivered));
      }
    }
    ActivationHints.clear();
    return result;
  }

  Future<CommitFailed?> _preflight(ActivationPlan plan) async {
    if (plan.mode == NetworkMode.mirror && !MirrorState.instance.isConfigured) {
      return _fail(CommitStep.pairing, 'MIRROR_NOT_PAIRED',
          'هذا الجهاز غير مقترن كمرآة. أعد الإقران برمز المرآة ثم أعد المحاولة.');
    }
    if (plan.mode == NetworkMode.client && MirrorState.instance.isConfigured) {
      // A stale mirror identity from an abandoned attempt must not survive in
      // a client device.
      await MirrorState.instance.clear();
      unawaited(DiagnosticLogger.log(
          'ACTIVATE-CLEAN', 'stale mirror identity dropped for client'));
    }
    return null;
  }

  Future<CommitFailed?> _verify(ActivationPlan plan) async {
    final rec = await ProvisioningStore.read(db);
    final dbMode = (await db.getSettingValue('network_mode'))?.trim();
    final ok = NetworkService.instance.mode == plan.mode &&
        dbMode == plan.mode.name &&
        rec?.mode == plan.mode.name &&
        (plan.mode != NetworkMode.mirror || MirrorState.instance.isConfigured);
    if (ok) return null;
    unawaited(DiagnosticLogger.log(
        'ACTIVATE-MISMATCH',
        'wanted=${plan.mode.name} memory=${NetworkService.instance.mode.name} '
            'db=$dbMode record=${rec?.mode}'));
    return _fail(CommitStep.finalDbCommit, 'MODE_MISMATCH',
        'لم يُعتمد النمط المختار على هذا الجهاز. أعد المحاولة أو أعد توفير الجهاز.');
  }

  CommitFailed _fail(CommitStep step, String code, String ar) =>
      CommitFailed(failedAtStep: step, reasonAr: ar, reasonCode: code);
}
