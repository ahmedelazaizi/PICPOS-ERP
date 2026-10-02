import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/providers.dart';
import '../accounting_service.dart';
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
}

final cloudLinkControllerProvider = Provider<CloudLinkController>((ref) =>
    CloudLinkController(
      ref.read(databaseProvider),
      ref.read(accountingServiceProvider),
      ref.read(secureStorageServiceProvider),
    ));
