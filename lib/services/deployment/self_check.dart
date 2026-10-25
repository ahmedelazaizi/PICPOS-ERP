// A1 (adoption contract §C.7-5): the self-check shown ONCE, before the login,
// after a networked setup finished and the app restarted. It reads the RUNNING
// system (not the setup draft) and compares it with the device record.
//
// Blocking failures (mode / pairing / first sync) forbid the login; the rest
// are warnings. Every FAIL offers "retry" and "re-provision this device".
library;

import 'dart:async';

import '../../core/logging/diagnostic_logger.dart';
import '../../data/database/database.dart';
import '../mirror_state.dart';
import '../network_service.dart';
import '../setup/seeded_admin_retire.dart';
import 'provisioning_applier.dart';
import 'provisioning_record.dart';
import 'settings_keys.dart';

enum SelfCheckId { record, mode, pairing, server, firstSync, users, noDefaultAdmin }

enum SelfCheckStatus { pass, fail, skip }

class SelfCheckItem {
  const SelfCheckItem(this.id, this.status, {this.blocking = false, this.detail});
  final SelfCheckId id;
  final SelfCheckStatus status;

  /// A FAIL of a blocking item forbids the login.
  final bool blocking;
  final String? detail;
  bool get failed => status == SelfCheckStatus.fail;
}

class SelfCheckReport {
  const SelfCheckReport(this.items);
  final List<SelfCheckItem> items;

  bool get canContinue => !items.any((i) => i.failed && i.blocking);
  bool get allPass => !items.any((i) => i.failed);

  /// The pairing identity is damaged / the token is gone: re-pair is the fix.
  bool get needsRePair => items.any(
      (i) => i.id == SelfCheckId.pairing && i.failed);
}

class SelfCheckRunner {
  SelfCheckRunner({required this.db, this.probeServer});

  final AppDatabase db;

  /// `true` when the main answers. Injected so tests need no network.
  final Future<bool> Function()? probeServer;

  Future<SelfCheckReport> run() async {
    final items = <SelfCheckItem>[];
    final record = await ProvisioningStore.read(db);
    if (record == null) {
      items.add(const SelfCheckItem(SelfCheckId.record, SelfCheckStatus.fail,
          blocking: true, detail: 'missing'));
      return _done(items);
    }
    items.add(const SelfCheckItem(SelfCheckId.record, SelfCheckStatus.pass));
    final mode = record.networkMode;
    final networked = record.isNetworked;

    // mode: memory, DB keys and record agree
    final dbMode = (await db.getSettingValue(DeploymentSettingsKeys.networkMode))
        ?.trim();
    final depMode = (await db.getSettingValue('deployment_mode'))?.trim();
    final modeOk = NetworkService.instance.mode == mode &&
        dbMode == record.mode &&
        depMode == record.mode;
    items.add(SelfCheckItem(SelfCheckId.mode,
        modeOk ? SelfCheckStatus.pass : SelfCheckStatus.fail,
        blocking: true,
        detail: modeOk
            ? null
            : 'memory=${NetworkService.instance.mode.name} db=$dbMode '
                'deployment=$depMode record=${record.mode}'));

    // pairing identity
    if (!networked) {
      items.add(const SelfCheckItem(SelfCheckId.pairing, SelfCheckStatus.skip));
    } else {
      final addr = NetworkService.instance.serverAddress ?? '';
      final identity = mode == NetworkMode.mirror
          ? MirrorState.instance.isConfigured
          : record.branchId != null;
      final ok = addr.isNotEmpty &&
          identity &&
          !ProvisioningApplier.last.rePairRequired;
      items.add(SelfCheckItem(SelfCheckId.pairing,
          ok ? SelfCheckStatus.pass : SelfCheckStatus.fail,
          blocking: true,
          detail: ok
              ? null
              : ProvisioningApplier.last.rePairRequired
                  ? 'device token lost'
                  : 'identity incomplete'));
    }

    // the main answers
    if (!networked || probeServer == null) {
      items.add(const SelfCheckItem(SelfCheckId.server, SelfCheckStatus.skip));
    } else {
      var up = false;
      try {
        up = await probeServer!();
      } catch (_) {}
      items.add(SelfCheckItem(SelfCheckId.server,
          up ? SelfCheckStatus.pass : SelfCheckStatus.fail));
    }

    // first sync flag + master data present
    if (!networked) {
      items.add(const SelfCheckItem(SelfCheckId.firstSync, SelfCheckStatus.skip));
    } else {
      final flag = mode == NetworkMode.mirror
          ? DeploymentSettingsKeys.mirrorFirstSyncCompleted
          : DeploymentSettingsKeys.clientFirstSyncCompleted;
      final done = (await db.getSettingValue(flag))?.trim() == 'true';
      final branches = await _count('branches');
      final warehouses = await _count('warehouses');
      final ok = done && branches > 0 && warehouses > 0;
      items.add(SelfCheckItem(SelfCheckId.firstSync,
          ok ? SelfCheckStatus.pass : SelfCheckStatus.fail,
          blocking: true,
          detail: ok ? null : 'flag=$done branches=$branches warehouses=$warehouses'));
    }

    // the seeded admin/admin must be gone (a networked device retires it)
    var seededLeft = await db.authenticateUser('admin', 'admin') != null;
    if (seededLeft && networked) {
      seededLeft = !await retireSeededAdmin(db);
    }
    items.add(SelfCheckItem(SelfCheckId.noDefaultAdmin,
        seededLeft ? SelfCheckStatus.fail : SelfCheckStatus.pass,
        blocking: networked));

    // the credentials of the first user arrived (networked devices)
    if (!networked) {
      items.add(const SelfCheckItem(SelfCheckId.users, SelfCheckStatus.skip));
    } else {
      final usable = await db.customSelect(
        "SELECT COUNT(*) AS n FROM users WHERE is_active = 1 AND password_hash <> ''",
      ).getSingle();
      final ok =
          record.credentialsDeliveredAt != null && usable.read<int>('n') > 0;
      items.add(SelfCheckItem(SelfCheckId.users,
          ok ? SelfCheckStatus.pass : SelfCheckStatus.fail,
          detail: ok ? null : 'credentials not delivered'));
    }
    return _done(items);
  }

  Future<int> _count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
          .read<int>('n');

  SelfCheckReport _done(List<SelfCheckItem> items) {
    final report = SelfCheckReport(items);
    unawaited(DiagnosticLogger.log(
        'setup_self_check',
        report.items
            .map((i) => '${i.id.name}=${i.status.name}'
                '${i.detail == null ? '' : '(${i.detail})'}')
            .join(' ')));
    return report;
  }
}

/// A passed self-check ends the pending state: it is shown once.
Future<void> markSelfCheckPassedIn(AppDatabase db) async {
  final r = await ProvisioningStore.read(db);
  if (r != null && r.selfCheckPending) {
    await ProvisioningStore.write(db, r.copyWith(selfCheckPending: false));
  }
  ProvisioningApplier.last = AdoptReport(
    record: r,
    backfilled: ProvisioningApplier.last.backfilled,
  );
}
