// A1 (adoption contract §C.7-4): re-applies the device record at EVERY boot,
// idempotently, BEFORE `NetworkService.reconcileWithDb` judges consistency.
//
//  * record present + setup finished  -> the RECORD wins: any derived DB key,
//    pref, `MirrorState` or server address that disagrees is repaired and
//    logged (`ADOPT-REPAIR key=... from=... to=...`).
//  * record absent + `setup_completed=='true'` (an install from before the
//    record) -> built once from the current keys (`ADOPT-BACKFILL`), nothing
//    else changes.
//  * record present but the device token is gone (cleared prefs / secure
//    storage lost) -> the identity is restored but [AdoptReport.rePairRequired]
//    is raised: the gate shows a clear "re-pair this device" prompt, never the
//    Fatal screen and never a silent fall back to another mode.
//  * no record and setup unfinished -> nothing (first run).
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/diagnostic_logger.dart';
import '../../data/database/database.dart';
import '../mirror_state.dart';
import '../network_service.dart';
import '../server_proxy.dart';
import 'provisioning_record.dart';
import 'settings_keys.dart';

class AdoptReport {
  const AdoptReport({
    this.record,
    this.backfilled = false,
    this.repairs = const [],
    this.rePairRequired = false,
  });

  final ProvisioningRecord? record;
  final bool backfilled;

  /// `key: from -> to` lines (empty when nothing had to be repaired).
  final List<String> repairs;

  /// The pairing identity is intact but the device token is lost.
  final bool rePairRequired;
}

abstract final class ProvisioningApplier {
  /// The result of the latest boot application (read by the gate / self-check).
  static AdoptReport last = const AdoptReport();

  static Future<AdoptReport> ensure(AppDatabase db) async {
    try {
      return last = await _ensure(db);
    } catch (e) {
      // Never block a boot on the adopter itself: reconcile then judges the
      // raw keys exactly as before.
      await DiagnosticLogger.log('ADOPT-FAIL', '$e');
      return last = const AdoptReport();
    }
  }

  static Future<AdoptReport> _ensure(AppDatabase db) async {
    var record = await ProvisioningStore.read(db);
    final completed =
        (await db.getSettingValue('setup_completed'))?.trim() == 'true';
    var backfilled = false;

    if (record == null) {
      if (!completed) return const AdoptReport();
      final mode = await _modeFromKeys(db);
      final flag = switch (mode) {
        NetworkMode.client => DeploymentSettingsKeys.clientFirstSyncCompleted,
        NetworkMode.mirror => DeploymentSettingsKeys.mirrorFirstSyncCompleted,
        _ => null,
      };
      final synced =
          flag == null || (await db.getSettingValue(flag))?.trim() == 'true';
      record = await ProvisioningRecord.capture(
        mode,
        firstSyncDone: synced,
        selfCheckPending: false,
        setupCompletedAt: DateTime.now().toUtc(),
      );
      await ProvisioningStore.write(db, record);
      await DiagnosticLogger.log('ADOPT-BACKFILL', 'mode=${record.mode}');
      backfilled = true; // then applied below: the derived keys are completed
    }

    if (record.setupCompletedAt == null) {
      if (!completed) return AdoptReport(record: record); // mid-setup
      record = record.copyWith(setupCompletedAt: DateTime.now().toUtc());
      await ProvisioningStore.write(db, record);
    }

    final repairs = <String>[];
    for (final e in record.derivedSettings.entries) {
      final cur = (await db.getSettingValue(e.key))?.trim();
      if (cur == e.value) continue;
      await db.setSetting(e.key, e.value);
      repairs.add('${e.key}: ${cur ?? '-'} -> ${e.value}');
    }
    repairs.addAll(await _repairCache(record));
    for (final r in repairs) {
      await DiagnosticLogger.log('ADOPT-REPAIR', r);
    }

    var rePair = false;
    if (record.isNetworked) {
      await ServerProxy.instance.restoreToken();
      final token = ServerProxy.instance.apiToken;
      rePair = token == null || token.isEmpty;
      if (rePair) {
        await DiagnosticLogger.log(
            'ADOPT-REPAIR', 'device token missing - re-pair required');
      }
    }
    return AdoptReport(
        record: record,
        backfilled: backfilled,
        repairs: repairs,
        rePairRequired: rePair);
  }

  static Future<NetworkMode> _modeFromKeys(AppDatabase db) async {
    final raw = (await db.getSettingValue(DeploymentSettingsKeys.networkMode))
        ?.trim();
    return NetworkMode.values.firstWhere((m) => m.name == raw,
        orElse: () => NetworkMode.standalone);
  }

  /// prefs / MirrorState / server address are a CACHE of the record.
  static Future<List<String>> _repairCache(ProvisioningRecord r) async {
    final out = <String>[];
    final prefs = await SharedPreferences.getInstance();
    final ns = NetworkService.instance;
    if (r.isNetworked && (r.serverHost ?? '').isNotEmpty) {
      final addr = ns.serverAddress ?? '';
      if (addr.isEmpty || addr != r.serverHost || ns.serverPort != r.serverPort) {
        ns.setServerAddress(r.serverHost!, port: r.serverPort);
        await ns.saveSettings();
        out.add('server_address: $addr -> ${r.serverHost}:${r.serverPort}');
      }
    }
    if (r.networkMode == NetworkMode.client && r.branchId != null) {
      if (prefs.getInt('client_branch_id') != r.branchId) {
        await prefs.setInt('client_branch_id', r.branchId!);
        out.add('prefs.client_branch_id -> ${r.branchId}');
      }
    }
    if (r.networkMode == NetworkMode.mirror &&
        !MirrorState.instance.isConfigured &&
        (r.mirrorServerName ?? '').isNotEmpty) {
      await MirrorState.instance.setPaired(
        serverDisplayName: r.mirrorServerName!,
        adminUserId: r.mirrorAdminUserId,
      );
      out.add('MirrorState restored from record (${r.mirrorServerName})');
    }
    return out;
  }
}
