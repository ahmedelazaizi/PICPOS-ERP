// A1 (adoption contract, plan 2026-10-23 §C.7): the ONE device record.
//
// `device_provisioning_v1` (JSON in `settings`, device-local) is the single
// source of truth for "what is this device": mode, kind, server, pin, branch,
// pairing identity, first-sync and completion stamps. `network_mode`,
// `deployment_mode`, `*_first_sync_completed`, `client_branch_id`, the mirror
// prefs ... are DERIVED from it (see `ProvisioningApplier`); prefs are only a
// cache. The committer writes it in the same DB transaction as the derived
// keys, so a crash can never leave them disagreeing.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../data/database/database.dart';
import '../device_identity_service.dart';
import '../mirror_state.dart';
import '../network_service.dart';
import '../tls_trust.dart';
import 'settings_keys.dart';

class ProvisioningRecord {
  const ProvisioningRecord({
    this.version = currentVersion,
    required this.mode,
    required this.deviceKind,
    this.serverHost,
    this.serverPort,
    this.tlsPin,
    this.deviceId,
    this.branchId,
    this.pairedAt,
    this.firstSyncAt,
    this.setupCompletedAt,
    this.appVersion,
    this.mirrorServerName,
    this.mirrorAdminUserId,
    this.selfCheckPending = false,
    this.credentialsDeliveredAt,
  });

  static const currentVersion = 1;

  final int version;

  /// A [NetworkMode] name: standalone | server | client | mirror.
  final String mode;

  /// standalone | server | client | pos | mirror (what the main bound us to).
  final String deviceKind;
  final String? serverHost;
  final int? serverPort;
  final String? tlsPin;
  final String? deviceId;
  final int? branchId;
  final DateTime? pairedAt;
  final DateTime? firstSyncAt;
  final DateTime? setupCompletedAt;
  final String? appVersion;

  /// Pairing identity of a mirror (restores `MirrorState` after a prefs loss).
  final String? mirrorServerName;
  final int? mirrorAdminUserId;

  /// Set at commit for networked modes; cleared by a PASSED self-check.
  final bool selfCheckPending;

  /// When the first user's verification delivered the branch credentials.
  final DateTime? credentialsDeliveredAt;

  NetworkMode get networkMode => NetworkMode.values.firstWhere(
        (m) => m.name == mode,
        orElse: () => NetworkMode.standalone,
      );

  bool get isNetworked =>
      networkMode == NetworkMode.client || networkMode == NetworkMode.mirror;

  ProvisioningRecord copyWith({
    DateTime? setupCompletedAt,
    bool? selfCheckPending,
    DateTime? credentialsDeliveredAt,
    int? branchId,
    String? serverHost,
    int? serverPort,
    String? mirrorServerName,
    int? mirrorAdminUserId,
  }) =>
      ProvisioningRecord(
        version: version,
        mode: mode,
        deviceKind: deviceKind,
        serverHost: serverHost ?? this.serverHost,
        serverPort: serverPort ?? this.serverPort,
        tlsPin: tlsPin,
        deviceId: deviceId,
        branchId: branchId ?? this.branchId,
        pairedAt: pairedAt,
        firstSyncAt: firstSyncAt,
        setupCompletedAt: setupCompletedAt ?? this.setupCompletedAt,
        appVersion: appVersion,
        mirrorServerName: mirrorServerName ?? this.mirrorServerName,
        mirrorAdminUserId: mirrorAdminUserId ?? this.mirrorAdminUserId,
        selfCheckPending: selfCheckPending ?? this.selfCheckPending,
        credentialsDeliveredAt:
            credentialsDeliveredAt ?? this.credentialsDeliveredAt,
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'mode': mode,
        'deviceKind': deviceKind,
        'serverHost': serverHost,
        'serverPort': serverPort,
        'tlsPin': tlsPin,
        'deviceId': deviceId,
        'branchId': branchId,
        'pairedAt': pairedAt?.toUtc().toIso8601String(),
        'firstSyncAt': firstSyncAt?.toUtc().toIso8601String(),
        'setupCompletedAt': setupCompletedAt?.toUtc().toIso8601String(),
        'appVersion': appVersion,
        'mirrorServerName': mirrorServerName,
        'mirrorAdminUserId': mirrorAdminUserId,
        'selfCheckPending': selfCheckPending,
        'credentialsDeliveredAt':
            credentialsDeliveredAt?.toUtc().toIso8601String(),
      };

  /// `null` for anything that is not a valid record (never throws).
  static ProvisioningRecord? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return null;
      final mode = j['mode'];
      if (mode is! String ||
          !NetworkMode.values.any((m) => m.name == mode)) {
        return null;
      }
      DateTime? t(String k) =>
          j[k] is String ? DateTime.tryParse(j[k] as String) : null;
      return ProvisioningRecord(
        version: (j['version'] as num?)?.toInt() ?? currentVersion,
        mode: mode,
        deviceKind: (j['deviceKind'] as String?) ?? mode,
        serverHost: j['serverHost'] as String?,
        serverPort: (j['serverPort'] as num?)?.toInt(),
        tlsPin: j['tlsPin'] as String?,
        deviceId: j['deviceId'] as String?,
        branchId: (j['branchId'] as num?)?.toInt(),
        pairedAt: t('pairedAt'),
        firstSyncAt: t('firstSyncAt'),
        setupCompletedAt: t('setupCompletedAt'),
        appVersion: j['appVersion'] as String?,
        mirrorServerName: j['mirrorServerName'] as String?,
        mirrorAdminUserId: (j['mirrorAdminUserId'] as num?)?.toInt(),
        selfCheckPending: j['selfCheckPending'] == true,
        credentialsDeliveredAt: t('credentialsDeliveredAt'),
      );
    } catch (_) {
      return null;
    }
  }

  /// The record for [mode] built from the live system (the committer calls this
  /// after pairing / first sync succeeded, right before the atomic write).
  static Future<ProvisioningRecord> capture(
    NetworkMode mode, {
    ProvisioningRecord? previous,
    String? deviceKind,
    DateTime? now,
    bool firstSyncDone = true,
    bool? selfCheckPending,
    DateTime? setupCompletedAt,
  }) async {
    final at = (now ?? DateTime.now()).toUtc();
    final ns = NetworkService.instance;
    final networked =
        mode == NetworkMode.client || mode == NetworkMode.mirror;
    final host = networked ? ns.serverAddress : null;
    String? pin;
    if (host != null && host.isNotEmpty) {
      final uri = Uri.tryParse(ns.buildServerUrl());
      if (uri != null && uri.host.isNotEmpty) {
        pin = TlsTrust.pinFor(uri.host, uri.port);
      }
    }
    int? branch;
    // strict-client OK: only a branch client has a branch id; a mirror is a full replica (its identity is mirrorServerName/mirrorAdminUserId below, restored by ProvisioningApplier)
    if (mode == NetworkMode.client) {
      branch = (await SharedPreferences.getInstance()).getInt('client_branch_id');
    }
    final mirror = MirrorState.instance;
    return ProvisioningRecord(
      mode: mode.name,
      deviceKind: deviceKind ??
          (previous?.mode == mode.name ? previous?.deviceKind : null) ??
          mode.name,
      serverHost: host,
      serverPort: mode == NetworkMode.standalone ? null : ns.serverPort,
      tlsPin: pin,
      deviceId: DeviceIdentityService.instance.tryGetDeviceId(),
      branchId: branch,
      pairedAt: networked ? (previous?.pairedAt ?? at) : null,
      firstSyncAt: networked && firstSyncDone ? at : null,
      setupCompletedAt: setupCompletedAt ?? previous?.setupCompletedAt,
      appVersion: AppConfig.version,
      mirrorServerName:
          mode == NetworkMode.mirror ? mirror.serverDisplayName : null,
      mirrorAdminUserId:
          mode == NetworkMode.mirror ? mirror.adminUserId : null,
      selfCheckPending: selfCheckPending ?? mode != NetworkMode.standalone,
      credentialsDeliveredAt: previous?.credentialsDeliveredAt,
    );
  }

  /// The `settings` keys derived from this record (record wins over them).
  Map<String, String> get derivedSettings {
    final m = networkMode;
    return {
      DeploymentSettingsKeys.networkMode: mode,
      'deployment_mode': mode,
      DeploymentSettingsKeys.lastCommittedMode: mode,
      'setup_completed': 'true',
      if (m == NetworkMode.standalone)
        DeploymentSettingsKeys.standaloneSetupCompleted: 'true',
      if (m == NetworkMode.server)
        DeploymentSettingsKeys.serverSetupCompleted: 'true',
      if (m == NetworkMode.client && firstSyncAt != null)
        DeploymentSettingsKeys.clientFirstSyncCompleted: 'true',
      if (m == NetworkMode.mirror && firstSyncAt != null)
        DeploymentSettingsKeys.mirrorFirstSyncCompleted: 'true',
      if (m == NetworkMode.client && branchId != null)
        'client_branch_id': '$branchId',
    };
  }
}

/// Reads / writes the record in `settings`.
abstract final class ProvisioningStore {
  static Future<ProvisioningRecord?> read(AppDatabase db) async {
    final raw = await db.getSettingValue(DeploymentSettingsKeys.deviceProvisioning);
    final parsed = ProvisioningRecord.tryParse(raw);
    if (parsed == null && raw != null && raw.trim().isNotEmpty) {
      await DiagnosticLogger.log(
          'ADOPT-CORRUPT', 'device_provisioning_v1 unreadable - ignored');
    }
    return parsed;
  }

  static Future<void> write(AppDatabase db, ProvisioningRecord record) =>
      db.setSetting(
        DeploymentSettingsKeys.deviceProvisioning,
        jsonEncode(record.toJson()),
      );
}
