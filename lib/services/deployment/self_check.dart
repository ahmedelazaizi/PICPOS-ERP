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

enum SelfCheckId {
  record,
  mode,
  database,
  pairing,
  server,
  deltaPull,
  mainMatch,
  firstSync,
  users,
  noDefaultAdmin,
}

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
  SelfCheckRunner({
    required this.db,
    this.probeServer,
    this.deltaPull,
    this.fetchMainSettings,
    this.deltaPullTimeout = const Duration(seconds: 60),
  });

  final AppDatabase db;

  /// `true` when the main answers. Injected so tests need no network.
  final Future<bool> Function()? probeServer;

  /// Pulls one delta page from the main (`true` = it answered). The runner owns
  /// the 60 s budget ([deltaPullTimeout]); a `null` port = not measurable here.
  final Future<bool> Function()? deltaPull;
  final Duration deltaPullTimeout;

  /// The main's `settings` map (company / currency / plan keys), `null` when
  /// the main did not answer.
  final Future<Map<String, String>?> Function()? fetchMainSettings;

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

    // main server (HQ): the database the app now reads carries the record the
    // setup wrote, flagged as provisioned (a record rebuilt by the boot
    // backfill has no flag, so a half-finished HQ setup cannot pass).
    if (mode == NetworkMode.server) {
      items.add(SelfCheckItem(SelfCheckId.database,
          record.pgConfigured ? SelfCheckStatus.pass : SelfCheckStatus.fail,
          blocking: true,
          detail: record.pgConfigured ? null : 'server database not provisioned'));
    }

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
      items.add(await _deltaPullItem(up));
      items.add(await _mainMatchItem(up));
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

    // the seeded admin/admin must be gone (a networked device retires it; the
    // main server's setup replaced its password - it must not log in with it)
    var seededLeft = await db.authenticateUser('admin', 'admin') != null;
    if (seededLeft && networked) {
      seededLeft = !await retireSeededAdmin(db);
    }
    items.add(SelfCheckItem(SelfCheckId.noDefaultAdmin,
        seededLeft ? SelfCheckStatus.fail : SelfCheckStatus.pass,
        blocking: networked || mode == NetworkMode.server));

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

  /// "A delta pull answers within 60 s". No port => not measurable (skip);
  /// the main down / a failed or slow pull => an honest, non-blocking FAIL.
  Future<SelfCheckItem> _deltaPullItem(bool serverUp) async {
    final pull = deltaPull;
    if (pull == null) {
      return const SelfCheckItem(SelfCheckId.deltaPull, SelfCheckStatus.skip);
    }
    if (!serverUp) {
      return const SelfCheckItem(SelfCheckId.deltaPull, SelfCheckStatus.fail,
          detail: 'main unreachable');
    }
    final secs = deltaPullTimeout.inSeconds;
    try {
      final ok = await pull().timeout(deltaPullTimeout);
      return SelfCheckItem(SelfCheckId.deltaPull,
          ok ? SelfCheckStatus.pass : SelfCheckStatus.fail,
          detail: ok ? null : 'pull refused');
    } on TimeoutException {
      return SelfCheckItem(SelfCheckId.deltaPull, SelfCheckStatus.fail,
          detail: 'no answer within ${secs}s');
    } catch (e) {
      return SelfCheckItem(SelfCheckId.deltaPull, SelfCheckStatus.fail,
          detail: '$e');
    }
  }

  /// Company / currency / plan of this device equal the main's. A key the main
  /// does not have is not compared; a key the main has and this device lacks
  /// (or holds differently) is a mismatch. Non-blocking: the sync repairs it.
  static const _matchKeys = {
    'company_global_id': 'company',
    'system_currency': 'currency',
    'business_profile': 'plan',
  };

  Future<SelfCheckItem> _mainMatchItem(bool serverUp) async {
    final fetch = fetchMainSettings;
    if (fetch == null) {
      return const SelfCheckItem(SelfCheckId.mainMatch, SelfCheckStatus.skip);
    }
    if (!serverUp) {
      return const SelfCheckItem(SelfCheckId.mainMatch, SelfCheckStatus.fail,
          detail: 'main unreachable');
    }
    Map<String, String>? main;
    try {
      main = await fetch().timeout(deltaPullTimeout);
    } catch (_) {}
    if (main == null) {
      return const SelfCheckItem(SelfCheckId.mainMatch, SelfCheckStatus.fail,
          detail: 'main did not answer');
    }
    final diffs = <String>[];
    for (final e in _matchKeys.entries) {
      final theirs = main[e.key]?.trim() ?? '';
      if (theirs.isEmpty) continue;
      final mine = (await db.getSettingValue(e.key))?.trim() ?? '';
      if (mine != theirs) diffs.add(e.value);
    }
    return SelfCheckItem(SelfCheckId.mainMatch,
        diffs.isEmpty ? SelfCheckStatus.pass : SelfCheckStatus.fail,
        detail: diffs.isEmpty ? null : 'differs: ${diffs.join(', ')}');
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
