import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/providers.dart';
import '../accounting_service.dart';
import '../admin_snapshots/admin_signing_key.dart';
import '../admin_snapshots/admin_user_mirror.dart';
import '../secure_storage_service.dart';
import 'cloud_link_api.dart';
import 'cloud_sync_service.dart';

/// A conflict as shown in Settings › Integrations › cloud link.
class CloudConflictView {
  const CloudConflictView({
    required this.globalId,
    required this.kind,
    this.cloudNumber,
    this.reason,
    required this.attempts,
    required this.retryRequested,
    this.updatedAt,
  });
  final String globalId;
  final String kind;
  final String? cloudNumber;
  final String? reason;
  final int attempts;
  final bool retryRequested;
  final DateTime? updatedAt;
}

/// Everything the cloud link screen shows.
class CloudLinkView {
  const CloudLinkView({
    required this.enabled,
    required this.url,
    required this.linkId,
    required this.hasSecret,
    required this.intervalMinutes,
    this.postingUserId,
    this.lastSyncAt,
    this.lastError,
    this.lastSummary = const {},
    required this.posted,
    required this.conflicts,
  });
  final bool enabled;
  final String url;
  final String linkId;
  final bool hasSecret;
  final int intervalMinutes;
  final int? postingUserId;
  final DateTime? lastSyncAt;
  final String? lastError;
  final Map<String, dynamic> lastSummary;
  final int posted;
  final List<CloudConflictView> conflicts;
}

/// UI-facing facade of the I-3 desktop ↔ cloud link (the presentation layer
/// must not reach `data/database` directly).
class CloudLinkController {
  CloudLinkController(this._db, this._accounting, this._secure);

  final AppDatabase _db;
  final AccountingService _accounting;
  final SecureStorageService _secure;

  late final CloudLinkConfigStore store = CloudLinkConfigStore(
    _db,
    readSecret: _secure.read,
    writeSecret: _secure.write,
  );

  /// Starts the background scheduler (no-op until the link is configured).
  Future<void> startScheduler() async {
    try {
      await CloudSyncScheduler.instance.start(_db, _accounting, store);
    } catch (_) {
      // Secure storage unavailable (tests / headless): stays unscheduled.
    }
  }

  /// [includeSecret] = false keeps secure storage untouched (status rows).
  Future<CloudLinkView> load({bool includeSecret = true}) async {
    final s = await cloudLinkSettings(_db);
    String v(String k) => s[k] ?? '';
    String? secret;
    try {
      if (includeSecret) {
        secret = await _secure.read(CloudLinkConfigStore.secretKey);
      }
    } catch (_) {
      secret = null;
    }
    final counts = await _db.cloudSyncCounts();
    final conflicts = await _db.listCloudSyncConflicts();
    Map<String, dynamic> summary = const {};
    try {
      final d = jsonDecode(v(CloudLinkKeys.lastSummary));
      if (d is Map) summary = d.cast<String, dynamic>();
    } catch (_) {}
    final last = int.tryParse(v(CloudLinkKeys.lastSyncAt));
    return CloudLinkView(
      enabled: v(CloudLinkKeys.enabled) == 'true',
      url: v(CloudLinkKeys.url),
      linkId: v(CloudLinkKeys.linkId),
      hasSecret: secret != null && secret.isNotEmpty,
      intervalMinutes: int.tryParse(v(CloudLinkKeys.intervalMinutes)) ?? 5,
      postingUserId: int.tryParse(v(CloudLinkKeys.postingUserId)),
      lastSyncAt: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
      lastError: v(CloudLinkKeys.lastError).isEmpty ? null : v(CloudLinkKeys.lastError),
      lastSummary: summary,
      posted: counts.posted,
      conflicts: [
        for (final c in conflicts)
          CloudConflictView(
            globalId: c.globalId,
            kind: c.kind,
            cloudNumber: c.cloudNumber,
            reason: c.reason,
            attempts: c.attempts,
            retryRequested: c.retryRequested,
            updatedAt: c.updatedAt,
          ),
      ],
    );
  }

  /// Saves the link; an empty [secret] keeps the stored one.
  Future<void> save({
    required bool enabled,
    required String url,
    required String linkId,
    required String secret,
    required int intervalMinutes,
    required int? postingUserId,
  }) async {
    await store.save(CloudLinkConfig(
      enabled: enabled,
      credentials: CloudLinkCredentials(baseUrl: url, linkId: linkId, secret: secret),
      postingUserId: postingUserId,
      intervalMinutes: intervalMinutes.clamp(1, 1440),
    ));
    await startScheduler();
  }

  /// Test connection with the entered values (an empty [secret] uses the
  /// stored one). Returns the cloud's company name and pending counts.
  Future<Map<String, dynamic>> testConnection({
    required String url,
    required String linkId,
    required String secret,
  }) async {
    final stored = secret.trim().isNotEmpty
        ? secret
        : await _secure.read(CloudLinkConfigStore.secretKey) ?? '';
    final api = CloudLinkApi(
        CloudLinkCredentials(baseUrl: url, linkId: linkId, secret: stored),
        timeout: const Duration(seconds: 15));
    try {
      return await api.ping();
    } finally {
      api.close();
    }
  }

  /// Runs a sync now; null when the link is not configured (or one is
  /// already running).
  Future<CloudSyncRunResult?> syncNow({bool fullPush = false}) async {
    await startScheduler();
    return CloudSyncScheduler.instance.syncNow(fullPush: fullPush);
  }

  Future<void> retry(String globalId) => _db.requestCloudSyncRetry(globalId);

  Future<List<({String globalId, String name})>> adminUsers() async => [
        for (final entry in await _db.getAllUsersWithRoles())
          if ((entry.user.globalId ?? '').isNotEmpty)
            (globalId: entry.user.globalId!, name: entry.user.displayName),
      ];

  Future<void> setAdminMobilePassword(String userGlobalId, String password) async {
    await AdminUserMirror(_db).setMobilePassword(userGlobalId, password);
    await syncNow();
  }

  Future<void> disableAdminMobile(String userGlobalId) async {
    await AdminUserMirror(_db).disableMobile(userGlobalId);
    await syncNow();
  }

  Future<Map<String, dynamic>> issueAdminPairingCode(String userGlobalId) async {
    final config = await store.load();
    if (!config.enabled || !config.credentials.isComplete) {
      throw CloudLinkException(0, 'link_not_configured');
    }
    final api = CloudLinkApi(config.credentials);
    try {
      final signer = await AdminSigningKey(store).load();
      await api.pushAdminSigningKey(await signer.publicKeyBase64());
      await AdminUserMirror(_db).push(api);
      final code = await api.adminPairingCode(userGlobalId);
      return {
        ...code,
        'cloudUrl': config.credentials.baseUrl,
        'desktopSigningKey': await signer.publicKeyBase64(),
      };
    } finally {
      api.close();
    }
  }

  Future<List<Map<String, dynamic>>> listAdminDevices() async {
    final config = await store.load();
    if (!config.enabled || !config.credentials.isComplete) return [];
    final api = CloudLinkApi(config.credentials);
    try {
      return await api.adminDevices();
    } finally {
      api.close();
    }
  }

  /// SEC-017: rotates the desktop's Ed25519 signing key and revokes every paired
  /// admin phone (they must re-pair and pin the new key). Returns how many
  /// phones were revoked.
  Future<int> rotateAdminSigningKey() async {
    final config = await store.load();
    if (!config.enabled || !config.credentials.isComplete) {
      throw CloudLinkException(0, 'link_not_configured');
    }
    final api = CloudLinkApi(config.credentials);
    try {
      var revoked = 0;
      await AdminSigningKey(store).rotate(
        publish: (key) async => revoked = await api.rotateAdminSigningKey(key),
      );
      return revoked;
    } finally {
      api.close();
    }
  }

  Future<void> revokeAdminDevice(String deviceId) async {
    final config = await store.load();
    if (!config.enabled || !config.credentials.isComplete) {
      throw CloudLinkException(0, 'link_not_configured');
    }
    final api = CloudLinkApi(config.credentials);
    try {
      await api.revokeAdminDevice(deviceId);
    } finally {
      api.close();
    }
  }

  /// J4 — issues a rep-app pairing code for the employee [employeeGlobalId]
  /// over the configured link (`POST /desktop/pairing-codes`). `null` when
  /// the link is not enabled/complete — the caller points to its settings.
  Future<Map<String, dynamic>?> issueRepPairingCode(String employeeGlobalId,
      {String? pin}) async {
    final config = await store.load();
    if (!config.enabled || !config.credentials.isComplete) return null;
    final api = CloudLinkApi(config.credentials,
        timeout: const Duration(seconds: 15));
    try {
      return await api.pairingCode(employeeGlobalId, pin: pin);
    } finally {
      api.close();
    }
  }

  /// Settings › Linked devices — rep-app devices paired on the cloud for this
  /// company. `null` when the link is not enabled/complete.
  Future<List<CloudRepDeviceView>?> listRepDevices() async {
    final config = await store.load();
    if (!config.enabled || !config.credentials.isComplete) return null;
    final api = CloudLinkApi(config.credentials,
        timeout: const Duration(seconds: 15));
    try {
      return [
        for (final d in await api.devices()) CloudRepDeviceView.fromJson(d),
      ];
    } finally {
      api.close();
    }
  }

  /// Revokes a rep-app device on the cloud (the app is signed out and wipes
  /// its local data). Throws when the link is not configured.
  Future<void> revokeRepDevice(String deviceId) async {
    final config = await store.load();
    if (!config.enabled || !config.credentials.isComplete) {
      throw CloudLinkException(0, 'link_not_configured');
    }
    final api = CloudLinkApi(config.credentials,
        timeout: const Duration(seconds: 15));
    try {
      await api.revokeDevice(deviceId);
    } finally {
      api.close();
    }
  }
}

/// A rep-app device as listed by `GET /desktop/devices`.
class CloudRepDeviceView {
  const CloudRepDeviceView({
    required this.deviceId,
    this.deviceName,
    this.employeeName,
    this.pairedAt,
    this.lastSeenAt,
    required this.revoked,
  });

  factory CloudRepDeviceView.fromJson(Map<String, dynamic> j) {
    DateTime? at(Object? v) =>
        v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    return CloudRepDeviceView(
      deviceId: '${j['deviceId'] ?? ''}',
      deviceName: j['deviceName'] as String?,
      employeeName: j['employeeName'] as String?,
      pairedAt: at(j['pairedAt']),
      lastSeenAt: at(j['lastSeenAt']),
      revoked: j['revoked'] == true,
    );
  }

  final String deviceId;
  final String? deviceName;
  final String? employeeName;
  final DateTime? pairedAt;
  final DateTime? lastSeenAt;
  final bool revoked;
}

final cloudLinkControllerProvider = Provider<CloudLinkController>((ref) =>
    CloudLinkController(
      ref.read(databaseProvider),
      ref.read(accountingServiceProvider),
      ref.read(secureStorageServiceProvider),
    ));
