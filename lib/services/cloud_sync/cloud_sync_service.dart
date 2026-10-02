import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../data/database/database.dart';
import '../../data/database/sync_interceptor.dart';
import '../accounting_service.dart';
import 'cloud_document_poster.dart';
import 'cloud_link_api.dart';
import 'cloud_master_exporter.dart';

/// Settings keys of the company cloud link (Settings › Integrations).
/// The link secret is NOT a setting: it lives in secure storage
/// ([CloudLinkConfigStore.secretKey]).
class CloudLinkKeys {
  static const enabled = 'cloud_link_enabled';
  static const url = 'cloud_link_url';
  static const linkId = 'cloud_link_id';
  static const postingUserId = 'cloud_link_posting_user_id';
  static const intervalMinutes = 'cloud_link_interval_minutes';
  static const lastSyncAt = 'cloud_link_last_sync_at';
  static const lastError = 'cloud_link_last_error';
  static const lastSummary = 'cloud_link_last_summary';
  static const masterWatermark = 'cloud_link_master_watermark';
  static const lastFullPushAt = 'cloud_link_last_full_push_at';
}

/// Every `cloud_link_*` setting as a map.
Future<Map<String, String>> cloudLinkSettings(AppDatabase db) async => {
      for (final s in await db.getSettingsByPrefix('cloud_link_'))
        if (s.value != null) s.key: s.value!,
    };

class CloudLinkConfig {
  const CloudLinkConfig({
    required this.enabled,
    required this.credentials,
    this.postingUserId,
    this.intervalMinutes = 5,
  });

  final bool enabled;
  final CloudLinkCredentials credentials;
  final int? postingUserId;
  final int intervalMinutes;

  bool get isUsable =>
      enabled && credentials.isComplete && postingUserId != null;
}

/// Reads/writes the link configuration. The secret store is injectable so
/// the service runs headless in tests (production: flutter_secure_storage).
class CloudLinkConfigStore {
  CloudLinkConfigStore(this.db,
      {required this.readSecret, required this.writeSecret});

  static const secretKey = 'cloud_link_secret';

  final AppDatabase db;
  final Future<String?> Function(String key) readSecret;
  final Future<void> Function(String key, String value) writeSecret;

  Future<CloudLinkConfig> load() async {
    final s = await cloudLinkSettings(db);
    String v(String k) => s[k] ?? '';
    final enabled = v(CloudLinkKeys.enabled) == 'true';
    return CloudLinkConfig(
      enabled: enabled,
      credentials: CloudLinkCredentials(
        baseUrl: v(CloudLinkKeys.url),
        linkId: v(CloudLinkKeys.linkId),
        // Secure storage is only touched once the link is switched on.
        secret: enabled ? await readSecret(secretKey) ?? '' : '',
      ),
      postingUserId: int.tryParse(v(CloudLinkKeys.postingUserId)),
      intervalMinutes:
          (int.tryParse(v(CloudLinkKeys.intervalMinutes)) ?? 5).clamp(1, 1440),
    );
  }

  Future<void> save(CloudLinkConfig c) async {
    await db.saveSettings({
      CloudLinkKeys.enabled: '${c.enabled}',
      CloudLinkKeys.url: c.credentials.baseUrl.trim(),
      CloudLinkKeys.linkId: c.credentials.linkId.trim(),
      CloudLinkKeys.postingUserId: c.postingUserId?.toString() ?? '',
      CloudLinkKeys.intervalMinutes: '${c.intervalMinutes}',
    });
    if (c.credentials.secret.trim().isNotEmpty) {
      await writeSecret(secretKey, c.credentials.secret.trim());
    }
  }
}

/// Outcome of one sync run.
class CloudSyncRunResult {
  int posted = 0;
  int reAcked = 0;
  int conflicts = 0;
  int skippedConflicts = 0;
  int masterRows = 0;
  List<Map<String, dynamic>> masterSkipped = const [];
  String? error;

  bool get ok => error == null;

  Map<String, Object?> toJson() => {
        'posted': posted,
        'reAcked': reAcked,
        'conflicts': conflicts,
        'skippedConflicts': skippedConflicts,
        'masterRows': masterRows,
        'masterSkipped': masterSkipped.length,
        if (error != null) 'error': error,
      };
}

/// One desktop ↔ cloud sync run (I-3): pull the accepted field documents,
/// post each through the desktop paths ([CloudDocumentPoster]), acknowledge
/// them, then push master data. Order matters: documents are posted and
/// acknowledged **before** balances and stock are pushed, so the cloud never
/// counts a document twice.
class CloudSyncService {
  CloudSyncService({
    required this.db,
    required this.api,
    required AccountingService accounting,
    required int postingUserId,
    this.fullPushEvery = const Duration(hours: 24),
  })  : poster = CloudDocumentPoster(db, accounting, postingUserId: postingUserId),
        exporter = CloudMasterExporter(db);

  final AppDatabase db;
  final CloudLinkApi api;
  final CloudDocumentPoster poster;
  final CloudMasterExporter exporter;
  final Duration fullPushEvery;

  Future<CloudSyncRunResult> runOnce({bool fullPush = false}) async {
    final r = CloudSyncRunResult();
    try {
      await _pullAndPost(r);
      await _pushMaster(r, full: fullPush);
    } on CloudLinkException catch (e) {
      r.error = '${e.code}${e.message == null ? '' : ': ${e.message}'}';
    } catch (e) {
      r.error = '$e';
    }
    await db.saveSettings({
      if (r.ok)
        CloudLinkKeys.lastSyncAt: '${DateTime.now().millisecondsSinceEpoch}',
      CloudLinkKeys.lastError: r.error ?? '',
      CloudLinkKeys.lastSummary: jsonEncode(r.toJson()),
    });
    return r;
  }

  Future<void> _pullAndPost(CloudSyncRunResult r) async {
    final docs = await api.pendingDocuments(limit: 200);
    final acks = <Map<String, Object?>>[];
    for (final doc in docs) {
      final gid = doc['globalId'];
      final kind = doc['kind'];
      if (gid is! String || kind is! String) continue;
      final local = await db.cloudSyncDocument(gid);
      if (local != null && local.isPosted) {
        // Posted before but the ack was lost: acknowledge again, never re-post.
        acks.add(_posted(kind, gid, local.desktopRef, local.desktopNumber));
        r.reAcked++;
        continue;
      }
      if (local != null && local.isConflict && !local.retryRequested) {
        // Waits for the operator's retry; the cloud keeps it pending and
        // shows the reason (re-sent: the earlier ack may have been lost).
        acks.add({
          'kind': kind,
          'globalId': gid,
          'status': 'failed',
          'reason': local.reason ?? 'conflict',
        });
        r.skippedConflicts++;
        continue;
      }
      try {
        final ref = await poster.post(doc);
        await db.recordCloudSyncPosted(
          globalId: gid,
          kind: kind,
          cloudNumber: doc['number'] as String?,
          desktopRef: ref.desktopRef,
          desktopNumber: ref.desktopNumber,
        );
        acks.add(_posted(kind, gid, ref.desktopRef, ref.desktopNumber));
        r.posted++;
      } catch (e) {
        final reason = e is CloudPostingException ? e.reason : 'desktop_error: $e';
        debugPrint('[CLOUD-SYNC] $kind $gid → conflict: $reason');
        await db.recordCloudSyncConflict(
          globalId: gid,
          kind: kind,
          cloudNumber: doc['number'] as String?,
          reason: reason,
          payload: jsonEncode(doc),
        );
        acks.add({'kind': kind, 'globalId': gid, 'status': 'failed', 'reason': reason});
        r.conflicts++;
      }
    }
    await api.ack(acks);
  }

  static Map<String, Object?> _posted(
          String kind, String gid, String? ref, String? number) =>
      {
        'kind': kind,
        'globalId': gid,
        'status': 'posted',
        'desktopId': ref,
        'desktopNumber': number,
      };

  Future<void> _pushMaster(CloudSyncRunResult r, {required bool full}) async {
    final s = await cloudLinkSettings(db);
    final watermark = int.tryParse(s[CloudLinkKeys.masterWatermark] ?? '');
    final lastFull = int.tryParse(s[CloudLinkKeys.lastFullPushAt] ?? '') ?? 0;
    final startedAt = DateTime.now();
    final doFull = full ||
        watermark == null ||
        startedAt.millisecondsSinceEpoch - lastFull > fullPushEvery.inMilliseconds;
    final batch = await exporter.build(
        since: doFull ? null : DateTime.fromMillisecondsSinceEpoch(watermark));
    final res = await api.pushMaster(batch);
    r.masterRows = ((res['applied'] as Map?) ?? const {})
        .values
        .whereType<num>()
        .fold(0, (a, b) => a + b.toInt());
    r.masterSkipped = [
      for (final x in (res['skipped'] as List? ?? const []))
        if (x is Map) x.cast<String, dynamic>(),
    ];
    await db.saveSettings({
      // A second of overlap: rows touched while the batch was read re-send.
      CloudLinkKeys.masterWatermark:
          '${startedAt.millisecondsSinceEpoch - 1000}',
      if (doFull) CloudLinkKeys.lastFullPushAt: '${startedAt.millisecondsSinceEpoch}',
    });
  }
}

/// Background scheduler (interval from the link settings) + manual
/// "sync now". Runs on the main/standalone desktop only — never on a LAN
/// client, which has no ledger of its own.
class CloudSyncScheduler {
  CloudSyncScheduler._();
  static final CloudSyncScheduler instance = CloudSyncScheduler._();

  AppDatabase? _db;
  AccountingService? _accounting;
  CloudLinkConfigStore? _store;
  Timer? _timer;
  bool _running = false;

  /// Last run (null until the first one finishes in this session).
  final ValueNotifier<CloudSyncRunResult?> lastRun = ValueNotifier(null);
  final ValueNotifier<bool> busy = ValueNotifier(false);

  Future<void> start(AppDatabase db, AccountingService accounting,
      CloudLinkConfigStore store) async {
    _db = db;
    _accounting = accounting;
    _store = store;
    await reschedule();
  }

  /// Re-reads the settings (call after saving them).
  Future<void> reschedule() async {
    _timer?.cancel();
    _timer = null;
    final store = _store;
    if (store == null || SyncInterceptor.isClientMode) return;
    final config = await store.load();
    if (!config.isUsable) return;
    _timer = Timer.periodic(Duration(minutes: config.intervalMinutes),
        (_) => unawaited(syncNow()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Runs one sync now (skipped while one is running). Returns null when the
  /// link is not configured.
  Future<CloudSyncRunResult?> syncNow({bool fullPush = false}) async {
    final db = _db, accounting = _accounting, store = _store;
    if (db == null || accounting == null || store == null || _running) {
      return null;
    }
    final config = await store.load();
    if (!config.isUsable) return null;
    _running = true;
    busy.value = true;
    final client = http.Client();
    try {
      final result = await CloudSyncService(
        db: db,
        api: CloudLinkApi(config.credentials, client: client),
        accounting: accounting,
        postingUserId: config.postingUserId!,
      ).runOnce(fullPush: fullPush);
      lastRun.value = result;
      return result;
    } finally {
      client.close();
      _running = false;
      busy.value = false;
    }
  }
}
