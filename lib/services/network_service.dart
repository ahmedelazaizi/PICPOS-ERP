import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/logging/diagnostic_logger.dart';
import '../data/database/database.dart';
import 'api/api_handler.dart';
import 'e_invoicing/e_invoice_submission_worker.dart';
import 'api/api_auth_middleware.dart';
import 'api/api_session_token.dart';
import 'api/lan_pairing_api_handler.dart';
import 'api/lan_pairing_service.dart';
import 'api/lan_pairing_client.dart';
import 'api/table_bill_token.dart';
import 'api/api_rate_limiter.dart';
import 'deployment/reconcile_result.dart';
import 'deployment/settings_keys.dart';
import 'mirror_state.dart';
import 'security_service.dart';
import 'tls_trust.dart';
import 'server_proxy.dart';
import 'sync/mirror_settings_keys.dart';
import 'sync_service.dart';
import '../core/config/brand.dart';

/// Network operation mode for the application
enum NetworkMode {
  standalone, // مستقل — single device, no networking
  server, // سيرفر — hosts data, accepts client connections
  client, // عميل — connects to a server for data
  mirror, // مرآة — admin laptop acting as a remote HQ console
  // (Feature 006 #3 / MM.A). Behavior layered on top of
  // client mode in later milestones (MM.B–MM.D); for
  // MM.A this value is reserved and has no behavioral
  // effect beyond being a persistable mode option.
}

/// Manages the network mode of the application, including
/// starting/stopping the embedded HTTP server and client connections.
class NetworkService {
  NetworkService._();
  static final instance = NetworkService._();

  // Current state
  NetworkMode _mode = NetworkMode.standalone;
  HttpServer? _httpServer;
  String? _serverAddress;
  int _serverPort = 8080;
  final _connectedClients = <String, DateTime>{};
  DateTime? _serverStartTime;

  // TLS configuration (optional — for LAN HTTPS)
  bool _tlsEnabled = false;
  String? _tlsCertPath;
  String? _tlsKeyPath;
  String? _tlsKeyPassword;
  bool _activeServerIsTls = false;

  /// بصمةُ شهادةِ **هذا الخادم** — تُحسَب عند الإقلاع وتُنشَر في
  /// `/api/health` داخلَ نافذة الاقتران وحدَها.
  String? _serverCertFingerprint;

  /// هل يعمل **الخادمُ البعيد** بـTLS؟ سؤالٌ مختلفٌ عن [_activeServerIsTls].
  ///
  /// 🔴 هذا هو الحقلُ الذي كان غائباً، وغيابُه سببُ أنّ [buildServerUrl]
  /// يبني `http://` صلباً. و[_activeServerIsTls] **لا يصلح بديلاً**: هو
  /// حالةُ الخادم عن **نفسِه**، وعلى جهازِ عميلٍ لا خادمَ يعمل أصلاً
  /// فقيمتُه `false` دائماً. فربطُ المخطَّط به يُنتج علَماً ميّتاً على كلِّ
  /// عميل — إصلاحٌ يبدو صحيحاً ولا يفعل شيئاً.
  bool _remoteServerIsTls = false;

  // Prefs keys
  static const _prefMode = 'network_mode';
  static const _prefServerAddress = 'network_server_address';
  static const _prefServerPort = 'network_server_port';
  static const _prefApiToken = 'network_api_token';
  static const _prefTlsEnabled = 'network_tls_enabled';
  static const _prefTlsCertPath = 'network_tls_cert_path';
  static const _prefTlsKeyPath = 'network_tls_key_path';
  static const _prefTlsKeyPassword = 'network_tls_key_password';
  /// هل الخادمُ **البعيد** يعمل بـTLS — علَمُ العميل لا الخادم.
  static const _prefRemoteTls = 'network_remote_tls';

  // Getters
  NetworkMode get mode => _mode;
  bool get isServer => _mode == NetworkMode.server;
  bool get isClient => _mode == NetworkMode.client;
  bool get isStandalone => _mode == NetworkMode.standalone;
  bool get isMirror => _mode == NetworkMode.mirror;

  /// الجهازُ محصورُ النطاق: عميلٌ أو مرآة — وهما الجهازان اللذان تُقفلهما
  /// سابقةُ المالك 2026-08-04 («الأجهزةُ اللي بتسرّب فعلاً هي العميلُ
  /// والمرآة؛ والجهازُ المستقلُّ يبقى بسلوكه القديم عن قصد»).
  ///
  /// وهو سؤالُ **هويّةِ الجهاز**، غيرُ سؤالِ **توجيهِ الكتابة** الذي يجيبه
  /// `SyncInterceptor.isClientMode`. والفرقُ ليس نظرياً: ذاك يساوي
  /// `isClient || WriteRouter.isMirrorActive`، و`isMirrorActive` تشترط
  /// `MirrorState.isConfigured`، والمعترِضُ نفسُه معدومٌ قبل
  /// `ClientWriteInterceptor.setup()`. فكان يُخطئ إلى **الانفتاح** في
  /// نافذتين — مرآةٌ لم يكتمل تصافحُها، وأيُّ قراءةٍ قبل التهيئة — فيُعامَل
  /// جهازٌ محصورٌ معاملةَ المستقلّ ويأخذ المستخدمُ سيّئُ التزويد كلَّ
  /// المخازن بدل صفر.
  ///
  /// ⇒ لقراراتِ النطاقِ والصلاحية: هذا. ولتوجيهِ الكتابة: المعترِض.
  bool get isBranchScopedDevice => isClient || isMirror;

  bool get isServerRunning => _httpServer != null;
  String? get serverAddress => _serverAddress;
  int get serverPort => _serverPort;
  Map<String, DateTime> get connectedClients => _connectedClients;
  DateTime? get serverStartTime => _serverStartTime;

  // TLS getters
  bool get tlsEnabled => _tlsEnabled;
  String? get tlsCertPath => _tlsCertPath;
  String? get tlsKeyPath => _tlsKeyPath;
  bool get isServerUsingTls => _activeServerIsTls;
  String? get serverCertFingerprint => _serverCertFingerprint;

  /// ⚠️ **هذان مخطَّطا الخادمِ عن نفسِه** — لعرضِ عنوانه للمشغّل ولسجلّاته.
  /// لا تبنِ بهما رابطاً لخادمٍ **بعيد**: على العميل قيمتُهما `http`/`ws`
  /// دائماً لأنّ خادمَه المحلّيَّ لا يعمل. استعمل [remoteHttpScheme].
  String get httpScheme => _activeServerIsTls ? 'https' : 'http';
  String get wsScheme => _activeServerIsTls ? 'wss' : 'ws';

  /// مخطَّطُ مخاطبةِ الخادم **البعيد** — هذا هو الذي تبني به الروابط.
  bool get remoteServerIsTls => _remoteServerIsTls;
  String get remoteHttpScheme => _remoteServerIsTls ? 'https' : 'http';
  String get remoteWsScheme => _remoteServerIsTls ? 'wss' : 'ws';

  // API handler reference for broadcasting
  ApiHandler? _apiHandler;
  LanPairingService? _lanPairing;

  LanPairingService? get lanPairingService => _lanPairing;

  /// Get count of active clients (auto-prunes stale entries > 60s)
  int get connectedClientCount {
    _connectedClients.removeWhere(
      (_, lastSeen) => DateTime.now().difference(lastSeen).inSeconds > 60,
    );
    return _connectedClients.length;
  }

  /// Load saved network mode from SharedPreferences
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString(_prefMode) ?? 'standalone';
    _mode = NetworkMode.values.firstWhere(
      (m) => m.name == modeStr,
      orElse: () => NetworkMode.standalone,
    );
    // Spec 136 ISS-5 — label the diagnostic log by deployment mode so each
    // device writes a distinct uralcash_login_log_<mode>.txt file.
    DiagnosticLogger.setModeLabel(_mode.name);
    _serverAddress = prefs.getString(_prefServerAddress);
    _serverPort = prefs.getInt(_prefServerPort) ?? 8080;
    _tlsEnabled = prefs.getBool(_prefTlsEnabled) ?? false;
    _tlsCertPath = prefs.getString(_prefTlsCertPath);
    _tlsKeyPath = prefs.getString(_prefTlsKeyPath);
    _tlsKeyPassword = prefs.getString(_prefTlsKeyPassword);
    _remoteServerIsTls = prefs.getBool(_prefRemoteTls) ?? false;

    // ⚠️ تحميلُ البصمة المثبَّتة **هنا** لا عند أوّلِ فحصِ اتّصالٍ فقط.
    // `TlsTrust` تقبل أيَّ شهادةٍ لمضيفٍ لا بصمةَ له في الذاكرة — فلو
    // انتظرنا الفحصَ لكانت كلُّ مزامنةٍ بعد إقلاعٍ بارد (وهي تبدأ فوراً)
    // تجري **بلا إنفاذ**: تثبيتٌ محفوظٌ على القرص لا يحرس شيئاً.
    if (_serverAddress != null && _serverAddress!.isNotEmpty) {
      final pinUri = Uri.tryParse(buildServerUrl());
      if (pinUri != null && pinUri.host.isNotEmpty) {
        await TlsTrust.loadPin(pinUri.host, pinUri.port);
      }
    }
    debugPrint('[NetworkService] Loaded mode=$_mode (raw=$modeStr), addr=$_serverAddress, port=$_serverPort, tls=$_tlsEnabled');

    // Restore API token for client OR mirror mode. Cluster 030 / Bug E:
    // the previous condition only matched `client`, so a mirror device
    // booted with a null `_apiToken` and EVERY write to the server
    // (activity_logs, commercial papers, etc.) failed with 401
    // "Missing or invalid Authorization header" until the user
    // re-paired. Mirror needs the same auth as client — both push to
    // the central HQ server through the same Bearer-token middleware.
    final savedToken = prefs.getString(_prefApiToken);
    if (savedToken != null &&
        (_mode == NetworkMode.client || _mode == NetworkMode.mirror)) {
      ServerProxy.instance.setApiToken(savedToken);
      debugPrint('[NetworkService] Restored API token from prefs (mode=${_mode.name})');
    }
  }

  /// Spec 089 — Reconcile `network_mode` between SharedPreferences (legacy)
  /// and the DB `settings` table (canonical). Call once on every boot,
  /// immediately after the AppDatabase opens but before any code branches
  /// on `isClient`/`isMirror`.
  ///
  /// **Why this exists**: `network_mode` was historically persisted to
  /// SharedPreferences only. Other parts of the boot (`_isClientMode()`
  /// in database_startup.dart) read from the DB `settings` table — a
  /// separate store. When an operator deletes
  /// `%USERPROFILE%\Documents\UralCash\*` to "start fresh", the DB clears
  /// but the SharedPreferences file in
  /// `%APPDATA%\Roaming\<vendor>\<app>` survives. Next boot the system
  /// runs as a client (from prefs) while the DB-side code thinks it's
  /// standalone (from settings). Bug: 2026-05-22 incident — user wiped
  /// Documents, picked standalone in the wizard, and the app still
  /// showed the CLIENT-mode offline banner with empty permissions.
  ///
  /// **Rules**:
  /// - DB has a value → DB wins. Update in-memory state + mirror into prefs.
  /// - DB empty AND prefs in {client, server, mirror} → stale prefs from
  ///   a wiped install. Force standalone, clear prefs, log a warning so
  ///   field support can recognise the case. The setup wizard runs next
  ///   (because setup_completed is also missing) and writes the real
  ///   mode.
  /// - DB empty AND prefs is 'standalone' or null → no conflict;
  ///   propagate 'standalone' to the DB so future boots short-circuit.
  Future<ReconcileResult> reconcileWithDb(AppDatabase db) async {
    String? dbValue;
    try {
      dbValue = (await db.getSettingValue('network_mode'))?.trim();
      if (dbValue?.isEmpty ?? false) dbValue = null;
    } catch (e) {
      unawaited(DiagnosticLogger.log(
        'RECONCILE-FAIL',
        'DB_READ_ERROR: $e',
      ));
      return const ReconcileInconsistent(
        reasonAr: 'تعذّر قراءة إعدادات النظام. قد تكون قاعدة البيانات تالفة. '
            'تواصل مع الدعم الفنى مع تصوير هذه الشاشة.',
        reasonCode: ReconcileReasonCode.dbReadError,
        dbMode: NetworkMode.standalone,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final prefsValue = prefs.getString(_prefMode);

    // ─── Case 1: DB has a value — run Spec 125 consistency checks ─────
    if (dbValue != null) {
      // Parse network_mode. Unknown → fail loud (per Spec 125 FR-013).
      final dbMode = NetworkMode.values
          .where((m) => m.name == dbValue)
          .firstOrNull;
      if (dbMode == null) {
        unawaited(DiagnosticLogger.log(
          'RECONCILE-FAIL',
          'UNKNOWN_MODE: dbValue="$dbValue"',
        ));
        return ReconcileInconsistent(
          reasonAr:
              'إعدادات النظام تالفة (وضع نشر غير معروف: $dbValue). '
              'يرجى إعادة اعداد البدء.',
          reasonCode: ReconcileReasonCode.unknownMode,
          dbMode: NetworkMode.standalone,
        );
      }

      // Mirror in-memory state + propagate to prefs (Spec 089).
      if (dbMode != _mode) {
        unawaited(DiagnosticLogger.log(
          'NETMODE-RECONCILE',
          'DB=$dbValue prefs=$prefsValue in-memory=${_mode.name} '
              '→ DB wins (spec 089)',
        ));
        _mode = dbMode;
        DiagnosticLogger.setModeLabel(_mode.name); // Spec 136 ISS-5
      }
      if (prefsValue != dbValue) {
        await prefs.setString(_prefMode, dbValue);
      }

      // ─── Spec 125 consistency checks ────────────────────────────────
      final inconsistency = await _checkConsistency(db, dbMode);
      if (inconsistency != null) {
        unawaited(DiagnosticLogger.log(
          'RECONCILE-FAIL',
          '${inconsistency.reasonCode}: ${inconsistency.reasonAr}',
        ));
        return inconsistency;
      }

      unawaited(DiagnosticLogger.log(
        'RECONCILE-OK',
        'mode=${dbMode.name}',
      ));

      // Spec 131 (A5 upgrade trigger) — on a mirror that's otherwise
      // consistent (first-sync completed, pairing present) but has NOT yet
      // applied the Spec 131 cache-integrity fix, force one silent re-sync
      // on the next launcher pass. Sets `forceFirstSync=true` on the OK
      // result; main.dart picks it up and runs performFirstSync BEFORE the
      // regular UI launches. The flag is set by performFirstSync itself
      // on success, so this branch fires exactly once per install lifetime.
      if (dbMode == NetworkMode.mirror) {
        final applied =
            (await db.getSettingValue(kMirrorCacheIntegrityV1AppliedFlag))
                ?.trim();
        if (applied != 'true') {
          unawaited(DiagnosticLogger.log(
            'MIRROR-UPGRADE-FORCED-SYNC',
            'triggered_at_boot reason=upgrade',
          ));
          return ReconcileOk(dbMode, forceFirstSync: true);
        }
      }
      return ReconcileOk(dbMode);
    }

    // ─── Case 2: both empty → fresh install. Wizard will set both. ────
    if (prefsValue == null) {
      // Fresh install. Treat as standalone-not-yet-completed so the wizard
      // is expected to run. We return Ok(standalone) because the wizard
      // is part of normal first-boot flow, not a Fatal scenario.
      unawaited(DiagnosticLogger.log(
        'RECONCILE-OK',
        'fresh install — DB and prefs both empty; wizard will set mode',
      ));
      return const ReconcileOk(NetworkMode.standalone);
    }

    // ─── Case 3: DB empty, prefs=standalone → propagate to DB ─────────
    if (prefsValue == 'standalone') {
      try {
        await db.setSetting('network_mode', 'standalone');
      } catch (e) {
        debugPrint('[NetworkService] reconcileWithDb: DB write failed: $e');
      }
      unawaited(DiagnosticLogger.log(
        'RECONCILE-OK',
        'mode=standalone (propagated from prefs to DB)',
      ));
      return const ReconcileOk(NetworkMode.standalone);
    }

    // ─── Case 4: DB empty, prefs=client/server/mirror → STALE PREFS ───
    // Spec 125 preserves the existing Spec 089 silent-cleanup behavior
    // for THIS specific case because it represents "user wiped Documents
    // for fresh start" — not a corruption to alert them about.
    unawaited(DiagnosticLogger.log(
      'NETMODE-RECONCILE',
      'STALE PREFS detected: prefs=$prefsValue DB=empty → forcing '
          'standalone (spec 089). The setup wizard will set the true mode.',
    ));

    await prefs.remove(_prefMode);
    await prefs.remove(_prefServerAddress);
    await prefs.remove(_prefApiToken);
    await prefs.remove('client_branch_id');

    _mode = NetworkMode.standalone;
    _serverAddress = null;

    try {
      ServerProxy.instance.setApiToken('');
    } catch (_) {}

    return const ReconcileOk(NetworkMode.standalone);
  }

  /// Spec 125 FR-012: per-mode consistency checks. Returns null if state
  /// is consistent, or [ReconcileInconsistent] with a specific reason.
  ///
  /// For backward compat with installs from before Spec 125 (where
  /// `*_setup_completed` flags didn't exist), we fall back to the legacy
  /// `setup_completed` flag — if it's 'true' the install is considered
  /// complete and we backfill the new flag on the spot.
  Future<ReconcileInconsistent?> _checkConsistency(
    AppDatabase db,
    NetworkMode dbMode,
  ) async {
    final legacySetupCompleted =
        (await db.getSettingValue('setup_completed'))?.trim() == 'true';

    switch (dbMode) {
      case NetworkMode.standalone:
        final flag = (await db.getSettingValue(
                DeploymentSettingsKeys.standaloneSetupCompleted))
            ?.trim();
        if (flag != 'true') {
          if (legacySetupCompleted) {
            // Backfill: existing standalone install pre-Spec-125.
            await db.setSetting(
                DeploymentSettingsKeys.standaloneSetupCompleted, 'true');
            return null;
          }
          return ReconcileInconsistent(
            reasonAr: 'النظام مسجّل كمستقل لكن اعداد البدء لم يكتمل. '
                'يرجى إعادة تشغيل اعداد البدء.',
            reasonCode: ReconcileReasonCode.standaloneSetupIncomplete,
            dbMode: dbMode,
          );
        }
        return null;

      case NetworkMode.server:
        final flag = (await db.getSettingValue(
                DeploymentSettingsKeys.serverSetupCompleted))
            ?.trim();
        if (flag != 'true') {
          // Backfill from legacy: a working server install pre-Spec-125
          // has setup_completed=true and a valid server port in prefs.
          if (legacySetupCompleted && _serverPort > 0) {
            await db.setSetting(
                DeploymentSettingsKeys.serverSetupCompleted, 'true');
            return null;
          }
          return ReconcileInconsistent(
            reasonAr: 'النظام مسجّل كسيرفر لكن الإعداد لم يكتمل '
                '(منفذ الخادم أو ملف الإعداد مفقود). '
                'يرجى إعادة تشغيل اعداد البدء.',
            reasonCode: ReconcileReasonCode.serverSetupIncomplete,
            dbMode: dbMode,
          );
        }
        return null;

      case NetworkMode.client:
        final firstSync = (await db.getSettingValue(
                DeploymentSettingsKeys.clientFirstSyncCompleted))
            ?.trim();
        if (firstSync != 'true') {
          return ReconcileInconsistent(
            reasonAr: 'النظام مسجّل كعميل لكن المزامنة الأولى مع السيرفر '
                'لم تكتمل. يرجى إعادة اعداد البدء أو إصلاح الاتصال '
                'بالسيرفر.',
            reasonCode: ReconcileReasonCode.clientFirstSyncIncomplete,
            dbMode: dbMode,
          );
        }
        final hasServerAddr =
            (_serverAddress != null && _serverAddress!.trim().isNotEmpty);
        if (!hasServerAddr) {
          return ReconcileInconsistent(
            reasonAr: 'النظام مسجّل كعميل لكن إعدادات الاتصال بالسيرفر '
                'مفقودة. يرجى إعادة اعداد البدء.',
            reasonCode: ReconcileReasonCode.clientPairingMissing,
            dbMode: dbMode,
          );
        }
        return null;

      case NetworkMode.mirror:
        final firstSync = (await db.getSettingValue(
                DeploymentSettingsKeys.mirrorFirstSyncCompleted))
            ?.trim();
        if (firstSync != 'true') {
          return ReconcileInconsistent(
            reasonAr: 'النظام مسجّل كمرآة لكن المزامنة الأولى مع السيرفر '
                'لم تكتمل. يرجى إعادة اعداد البدء أو إصلاح الاتصال '
                'بالسيرفر.',
            reasonCode: ReconcileReasonCode.mirrorFirstSyncIncomplete,
            dbMode: dbMode,
          );
        }
        // MirrorState.loadSettings() runs from main_desktop's
        // initPlatform; by the time reconcileWithDb is called, the
        // in-memory state reflects what's on disk.
        if (!MirrorState.instance.isConfigured) {
          return ReconcileInconsistent(
            reasonAr: 'النظام مسجّل كمرآة لكن ارتباط السيرفر مفقود '
                '(لم يتم التحقق من السيرفر بنجاح). '
                'ادخل خيارات المطور لإعادة الربط أو أعد اعداد البدء.',
            reasonCode: ReconcileReasonCode.mirrorPairingMissing,
            dbMode: dbMode,
          );
        }
        return null;
    }
  }

  /// Save network mode to SharedPreferences
  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefMode, _mode.name);
    if (_serverAddress != null) {
      await prefs.setString(_prefServerAddress, _serverAddress!);
    }
    await prefs.setInt(_prefServerPort, _serverPort);
    await prefs.setBool(_prefTlsEnabled, _tlsEnabled);
    await prefs.setBool(_prefRemoteTls, _remoteServerIsTls);
    if (_tlsCertPath != null) {
      await prefs.setString(_prefTlsCertPath, _tlsCertPath!);
    }
    if (_tlsKeyPath != null) {
      await prefs.setString(_prefTlsKeyPath, _tlsKeyPath!);
    }
    if (_tlsKeyPassword != null) {
      await prefs.setString(_prefTlsKeyPassword, _tlsKeyPassword!);
    }
  }

  /// Configure TLS (call before startServer). Empty cert/key paths disable TLS.
  Future<void> configureTls({
    required bool enabled,
    String? certPath,
    String? keyPath,
    String? keyPassword,
  }) async {
    _tlsEnabled = enabled;
    _tlsCertPath = certPath;
    _tlsKeyPath = keyPath;
    // 🔴 كان `= keyPassword` بلا شرط، ومنادِيا الواجهة يحذفان الوسيط —
    // فكلُّ لمسةٍ للمفتاح في الشاشة تمسح كلمةَ مرور المفتاح من الذاكرة،
    // و`saveSettings` لا تكتب إلّا حين `!= null` فيبقى في prefs مفتاحٌ
    // بائتٌ لا يُقرأ. أي أنّ مفتاحاً مشفَّراً كان **غيرَ قابلٍ للاستعمال**
    // من الواجهة إطلاقاً. الآن: لا يُمسّ إلّا حين يُمرَّر صراحةً.
    if (keyPassword != null) _tlsKeyPassword = keyPassword;
    await saveSettings();
  }

  /// Validate that TLS cert & key files exist and are readable.
  /// Returns null if OK, or a human-readable error message.
  String? validateTlsConfig() {
    if (!_tlsEnabled) return null;
    if (_tlsCertPath == null || _tlsCertPath!.isEmpty) {
      return 'مسار شهادة TLS غير محدد.';
    }
    if (_tlsKeyPath == null || _tlsKeyPath!.isEmpty) {
      return 'مسار مفتاح TLS غير محدد.';
    }
    if (!File(_tlsCertPath!).existsSync()) {
      return 'ملف شهادة TLS غير موجود: $_tlsCertPath';
    }
    if (!File(_tlsKeyPath!).existsSync()) {
      return 'ملف مفتاح TLS غير موجود: $_tlsKeyPath';
    }
    return null;
  }

  /// **Hard reset** to standalone mode.
  /// Clears ALL network-related SharedPreferences, stops the server,
  /// resets the API token, and deletes pg_config.json if present.
  /// Must be called when the user explicitly chooses "مستقل" in Setup Wizard.
  ///
  /// Spec 089: pass [db] to also write `network_mode = 'standalone'` into
  /// the DB `settings` table, keeping prefs and DB in agreement.
  Future<void> resetToStandalone({AppDatabase? db}) async {
    // 1. Stop server if running
    await stopServer();

    // 2. Reset internal state
    _mode = NetworkMode.standalone;
    _serverAddress = null;
    _serverPort = 8080;
    _connectedClients.clear();
    _serverStartTime = null;

    // 3. Persist to DB first so a crash mid-call doesn't strand prefs
    //    ahead of the canonical store (Spec 089).
    if (db != null) {
      try {
        await db.setSetting('network_mode', 'standalone');
      } catch (e) {
        debugPrint('[NetworkService] resetToStandalone: DB write failed: $e');
      }
    }

    // 4. Clear ALL network prefs from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefMode);
    await prefs.remove(_prefServerAddress);
    await prefs.remove(_prefServerPort);
    await prefs.remove(_prefApiToken);
    await prefs.remove('client_branch_id');
    // Write explicit standalone to prevent stale values
    await prefs.setString(_prefMode, 'standalone');

    // 6. Clear API token from ServerProxy
    try {
      ServerProxy.instance.setApiToken('');
    } catch (_) {}

    // 7. Delete pg_config.json if it exists (prevents PostgreSQL auto-connect)
    try {
      final dir = File(Platform.resolvedExecutable).parent;
      final pgConfigFile = File('${dir.path}/pg_config.json');
      if (await pgConfigFile.exists()) {
        await pgConfigFile.delete();
        debugPrint('[NetworkService] 🗑️ Deleted pg_config.json');
      }
    } catch (e) {
      debugPrint('[NetworkService] pg_config cleanup: $e');
    }

    debugPrint('[NetworkService] ♻️ Reset to standalone — all network settings cleared');
  }

  /// Test-only: synchronously override the in-memory mode without touching
  /// SharedPreferences or starting/stopping any servers. Used by unit tests
  /// to exercise mode-conditional code paths (e.g. Feature 004 US2's
  /// PasswordCollisionScanner.isClient gate).
  @visibleForTesting
  void debugSetModeForTests(NetworkMode mode) {
    _mode = mode;
  }

  /// Set network mode (does not start/stop server automatically).
  ///
  /// Spec 089: pass [db] to also persist the mode to the DB `settings`
  /// table (canonical store). Callers that have a DB handle (wizard,
  /// settings screen) MUST pass it so the prefs and DB cannot drift.
  /// Legacy callers without a DB handle still update prefs only; the
  /// next boot's `reconcileWithDb()` will mirror the value into the DB.
  Future<void> setMode(NetworkMode newMode, {AppDatabase? db}) async {
    if (_mode == newMode) {
      if (db != null) {
        try {
          await db.setSetting('network_mode', newMode.name);
        } catch (e) {
          debugPrint('[NetworkService] setMode: DB write failed: $e');
        }
      }
      await saveSettings();
      return;
    }

    // Stop existing services
    if (_mode == NetworkMode.server) {
      await stopServer();
    }

    // strict-client OK: clear SyncService when leaving strict-client mode;
    // mirror does not own a SyncService instance via this path.
    if (_mode == NetworkMode.client && newMode != NetworkMode.client) {
      SyncService.clearInstance();
    }

    _mode = newMode;
    DiagnosticLogger.setModeLabel(_mode.name); // Spec 136 ISS-5

    // Persist to DB first (canonical) so a crash mid-call doesn't strand
    // prefs ahead of the DB.
    if (db != null) {
      try {
        await db.setSetting('network_mode', newMode.name);
      } catch (e) {
        debugPrint('[NetworkService] setMode: DB write failed: $e');
      }
    }

    await saveSettings();
  }

  /// Start the embedded HTTP server (server mode)
  Future<bool> startServer(AppDatabase db, {int? port}) async {
    if (_httpServer != null) {
      debugPrint('[NetworkService] Server already running');
      return true;
    }

    final serverPort = port ?? _serverPort;

    try {
      final pairing = LanPairingService(db);
      await pairing.initialize();
      await pairing.initializeLegacyTransition();
      _lanPairing = pairing;
      ApiAuthMiddleware.setPairingService(pairing);
      LanPairingApiHandler.setService(pairing);
      final apiHandler = ApiHandler(db);
      _apiHandler = apiHandler;
      final router = apiHandler.buildRouter();

      // Generate API auth token from machine-unique encryption key
      final machineSeed = await SecurityService.getDatabaseEncryptionKey();
      ApiAuthMiddleware.generateToken(machineSeed);
      // Spec 151 (P1-8): derive the server-only session-signing key from the
      // SAME machine seed (distinct salt). Used to mint/verify per-user session
      // tokens that replace the forgeable X-User-Id header.
      ApiSessionToken.deriveKey(machineSeed);
      // حسابُ الطاولة (2026-09-12): نفسُ البذرة بملحٍ ثالث. وبلا هذا السطر
      // تُرفَض كلُّ رموز الطاولات — الفشلُ مغلقٌ عمداً — فيبدو الـQR المطبوعُ
      // معطّلاً بلا سببٍ ظاهر. والملحُ ثابتٌ فالرموزُ المطبوعةُ تبقى صالحةً
      // عبر إعادات التشغيل.
      TableBillToken.deriveKey(machineSeed);
      debugPrint('[NetworkService] API auth + session token keys generated');

      final handler = const Pipeline()
          .addMiddleware(_corsMiddleware())
          .addMiddleware(ApiRateLimiter.createMiddleware())  // Week-10: rate limit before auth
          .addMiddleware(ApiAuthMiddleware.createMiddleware())
          .addMiddleware(_logMiddleware())
          .addHandler(router.call);

      SecurityContext? securityContext;
      if (_tlsEnabled) {
        final validationError = validateTlsConfig();
        if (validationError != null) {
          debugPrint('[NetworkService] ❌ TLS misconfigured: $validationError');
          return false;
        }
        try {
          securityContext = SecurityContext()
            ..useCertificateChain(_tlsCertPath!)
            ..usePrivateKey(_tlsKeyPath!, password: _tlsKeyPassword);
        } catch (e) {
          debugPrint('[NetworkService] ❌ Failed to load TLS cert/key: $e');
          return false;
        }
      }

      _httpServer = await shelf_io.serve(
        handler,
        InternetAddress.anyIPv4,
        serverPort,
        securityContext: securityContext,
      );
      _httpServer!.autoCompress = true;
      _serverPort = serverPort;
      _serverStartTime = DateTime.now();
      _activeServerIsTls = securityContext != null;
      // بصمةُ الشهادةِ تُحسَب مرّةً هنا لا عند كلِّ نداءِ `/api/health`:
      // قراءةُ ملفٍّ وتجزئتُه في مسارِ طلبٍ معفًى من حدِّ المعدّل تفتح
      // بابَ إرهاقٍ رخيصاً.
      _serverCertFingerprint = securityContext != null && _tlsCertPath != null
          ? TlsTrust.fingerprintOfPemFile(_tlsCertPath!)
          : null;

      // Get the local IP for display (WiFi/Ethernet preferred)
      _serverAddress = await getLocalIpAddress();

      debugPrint(
        '[NetworkService] ✅ Server running at $httpScheme://$_serverAddress:$serverPort',
      );

      // الخادمُ وحدَه يقدّم المستنداتِ الضريبيّة — وهذا موضعُ تعليق النبضة.
      await _startEInvoiceWorker(db);
      return true;
    } catch (e) {
      debugPrint('[NetworkService] ❌ Failed to start server: $e');
      return false;
    }
  }

  /// A-SEC-1: open a device-pairing window so a NEW client/mirror can read the
  /// API token from `/api/health` during setup. In steady state the token is
  /// omitted from health so a passive LAN peer can't impersonate a device.
  void openDevicePairingWindow([Duration ttl = const Duration(minutes: 5)]) {
    ApiAuthMiddleware.openPairingWindow(ttl);
    debugPrint(
        '[NetworkService] Device pairing window opened for ${ttl.inMinutes} min');
  }

  PairingOffer? issueLanPairingCode() {
    final pairing = _lanPairing;
    if (pairing == null || !pairing.isInitialized) return null;
    return pairing.issuePairingCode(
      serverHost: _serverAddress ?? 'localhost',
      port: _serverPort,
      serverFingerprint: _serverCertFingerprint,
    );
  }

  Future<List<LanPairingDevice>> unpairedLanDevices() async {
    final pairing = _lanPairing;
    return pairing == null ? const [] : pairing.listUnpairedDevices();
  }

  Future<void> revokeLanDevice(String deviceId) async {
    await _lanPairing?.revoke(deviceId);
  }

  Future<void> endLegacyLanTransition() async {
    await _lanPairing?.endLegacyTransition();
  }

  Future<Map<String, dynamic>> pairLanClient({
    required String address,
    required int port,
    required String code,
    String? deviceName,
  }) =>
      LanPairingClient.pair(
        address: address,
        port: port,
        code: code,
        deviceName: deviceName,
      );

  /// نبضةُ تقديم الفاتورة الإلكترونيّة — **على الخادم وحدَه**.
  ///
  /// قرارُ المالك: الخادمُ وحدَه يحمل السرَّ ويرسل. والفواتيرُ تصل بالمزامنة
  /// من كلّ كاشير، فالمسحُ هو ما يلتقطها — لا خُطّافٌ عند إنشاء الفاتورة.
  Timer? _eInvoiceTimer;
  static const _eInvoiceSweepInterval = Duration(minutes: 2);

  Future<void> _startEInvoiceWorker(AppDatabase db) async {
    _eInvoiceTimer?.cancel();
    _eInvoiceTimer = null;
    try {
      final worker = await EInvoiceSubmissionWorker.forServer(db);
      if (worker == null) {
        debugPrint('[NetworkService] E-invoicing not configured — no sweep');
        return;
      }
      // نبضةٌ أولى فوراً ثمّ دوريّاً — فلا ينتظر أوّلُ مستندٍ دورةً كاملة.
      unawaited(worker.runOnce());
      _eInvoiceTimer = Timer.periodic(
        _eInvoiceSweepInterval,
        (_) => unawaited(worker.runOnce()),
      );
      debugPrint('[NetworkService] E-invoice sweep armed');
    } catch (e) {
      // إقلاعُ الخادم لا يسقط لأنّ الفوترةَ الإلكترونيّة تعثّرت.
      debugPrint('[NetworkService] E-invoice worker failed to start: $e');
    }
  }

  /// Stop the embedded HTTP server
  Future<void> stopServer() async {
    _eInvoiceTimer?.cancel();
    _eInvoiceTimer = null;
    if (_httpServer != null) {
      await _httpServer!.close(force: true);
      _httpServer = null;
      _serverStartTime = null;
      _apiHandler = null;
      _lanPairing = null;
      ApiAuthMiddleware.clearPairingService();
      LanPairingApiHandler.clearService();
      _activeServerIsTls = false;
      _connectedClients.clear();
      debugPrint('[NetworkService] Server stopped');
    }
  }

  /// Set server address for client mode
  void setServerAddress(String address, {int? port}) {
    _serverAddress = address;
    if (port != null) _serverPort = port;
  }

  /// Build the full HTTP base URL from the saved address.
  /// Supports both plain IP (e.g. 192.168.1.100) and full URLs
  /// (e.g. https://abc.ngrok-free.app).
  ///
  /// 🔴 **كان يبني `http://` صلباً.** فمشغّلٌ يُشغّل TLS على الخادم كان
  /// يقطع كلَّ أجهزته: الخادمُ ينتظر مصافحةً والعملاءُ يخاطبونه بنصٍّ
  /// صريح. أي أنّ «تشغيل الأمان» كان انقطاعاً لا أماناً.
  ///
  /// والمخطَّطُ الآن من [_remoteServerIsTls] — علَمُ **الخادم البعيد**، لا
  /// [_activeServerIsTls] الذي يصف الخادمَ المحلّيَّ ويساوي `false` على
  /// كلِّ عميل. وعنوانٌ مكتوبٌ بمخطَّطٍ صريحٍ يبقى مُحترَماً كما كان
  /// (الأنفاق).
  String buildServerUrl({String? address, int? port}) {
    final addr = (address ?? _serverAddress ?? 'localhost').trim();
    final p = port ?? _serverPort;
    // If the address already looks like a URL, use it as-is
    if (addr.startsWith('http://') || addr.startsWith('https://')) {
      // Strip trailing slash
      return addr.endsWith('/') ? addr.substring(0, addr.length - 1) : addr;
    }
    return '$remoteHttpScheme://$addr:$p';
  }

  /// Build the WebSocket URL from the saved address.
  String buildWsUrl({String? address, int? port}) {
    final addr = (address ?? _serverAddress ?? 'localhost').trim();
    final p = port ?? _serverPort;
    if (addr.startsWith('https://')) {
      // HTTPS → WSS
      final base = addr.endsWith('/') ? addr.substring(0, addr.length - 1) : addr;
      return '${base.replaceFirst('https://', 'wss://')}/ws';
    }
    if (addr.startsWith('http://')) {
      final base = addr.endsWith('/') ? addr.substring(0, addr.length - 1) : addr;
      return '${base.replaceFirst('http://', 'ws://')}/ws';
    }
    return '$remoteWsScheme://$addr:$p/ws';
  }

  /// Whether the current address is a tunnel/URL (not a plain IP)
  bool get isTunnelUrl {
    final addr = _serverAddress ?? '';
    return addr.startsWith('http://') || addr.startsWith('https://');
  }

  /// Test connection to a server (client mode)
  /// On success, automatically extracts and persists the API token.
  /// Accepts either a plain IP or a full URL (e.g. https://abc.ngrok-free.app).
  Future<Map<String, dynamic>> testServerConnection(
    String address,
    int port,
  ) async {
    try {
      // ── اكتشافُ المخطَّط ─────────────────────────────────────────────
      //
      // العنوانُ يُدخَل **مجرَّداً** في كلِّ مسارات الاقتران الثلاثة (شاشةُ
      // الإعدادات · معالجُ البدء · اقترانُ المرآة)، ولا اكتشافَ خادمٍ في
      // المستودع يملأه. فلا سبيلَ لمعرفة المخطَّط سلفاً — نجرّب المحفوظَ
      // أوّلاً ثمّ الآخر، ونثبّت ما نجح.
      //
      // وهذا يجعل تشغيلَ TLS على الخادم **لا يتطلّب لمسَ أيِّ عميل**:
      // أوّلُ فحصِ اتّصالٍ يكتشف التبدّلَ ويصحّح نفسَه.
      final schemes = _remoteServerIsTls
          ? <bool>[true, false]
          : <bool>[false, true];
      final isExplicitUrl =
          address.trim().startsWith('http://') ||
          address.trim().startsWith('https://');

      Object? lastError;
      for (final useTls in schemes) {
        // عنوانٌ مكتوبٌ بمخطَّطٍ صريحٍ يُحترَم كما هو ولا يُجرَّب مرّتين.
        if (isExplicitUrl && useTls != schemes.first) break;
        final previous = _remoteServerIsTls;
        if (!isExplicitUrl) _remoteServerIsTls = useTls;
        try {
          final result = await _probeHealth(address, port);
          if (!isExplicitUrl && useTls != previous) {
            // نجح مخطَّطٌ مختلفٌ عن المحفوظ — ثبّته للنداءات التالية.
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(_prefRemoteTls, useTls);
            debugPrint('[NetworkService] 🔁 remote scheme → '
                '${useTls ? "https" : "http"}');
          }
          return result;
        } catch (e) {
          lastError = e;
          _remoteServerIsTls = previous;
        }
      }
      return {'success': false, 'error': lastError.toString()};
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// فحصُ `/api/health` بمخطَّطٍ واحد. يرمي عند فشل الشبكة ليجرّب المنادي
  /// المخطَّطَ الآخر.
  Future<Map<String, dynamic>> _probeHealth(String address, int port) async {
      final baseUrl = buildServerUrl(address: address, port: port);
      final healthUrl = '$baseUrl/api/health';
      debugPrint('[NetworkService] Testing connection to $healthUrl');

      final uri = Uri.parse(healthUrl);
      // البصمةُ المثبَّتةُ لهذا المضيف — إن وُجدت رُفضت أيُّ شهادةٍ سواها.
      await TlsTrust.loadPin(uri.host, uri.port);
      final client = TlsTrust.ioClient(
        connectionTimeout: const Duration(seconds: 15),
      );

      final request = await client.getUrl(uri);
      // Skip ngrok free-tier interstitial browser warning page
      request.headers.set('ngrok-skip-browser-warning', 'true');
      request.headers.set('User-Agent', '${Brand.name}-Client');

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200) {
        final data = json.decode(body) as Map<String, dynamic>;

        // ── تثبيتُ بصمةِ الشهادة ────────────────────────────────────────
        //
        // تُسلَّم في نافذة الاقتران وحدَها، تماماً كالتوكن. وبعدها يرفض
        // هذا الجهازُ أيَّ شهادةٍ أخرى لهذا المضيف — وهذا ما يمنع الرجلَ
        // في المنتصف على الشبكة المحلّيّة.
        final fingerprint = data['certFingerprint'] as String?;
        if (fingerprint != null && fingerprint.isNotEmpty) {
          await TlsTrust.pin(uri.host, uri.port, fingerprint);
        }

        // ── Extract and persist API token from health handshake ──
        final apiToken = data['apiToken'] as String?;
        if (apiToken != null) {
          ServerProxy.instance.setApiToken(apiToken);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefApiToken, apiToken);
          debugPrint('[NetworkService] ✅ API token extracted and persisted');
        } else {
          // A-SEC-1: the server only exposes the token during an operator-opened
          // pairing window. If this device has no token yet, pairing can't
          // complete — tell the operator to open the window on the server.
          final prefs = await SharedPreferences.getInstance();
          final existing = prefs.getString(_prefApiToken);
          if (existing == null || existing.isEmpty) {
            return {
              'success': false,
              'error': 'الخادم غير مفتوح لاقتران جهاز جديد. من جهاز الخادم '
                  'افتح «نافذة اقتران جهاز جديد» ثم أعد المحاولة.',
            };
          }
        }

        return {'success': true, 'data': data};
      } else {
        // Include response body snippet for diagnostics
        final snippet = body.length > 200 ? body.substring(0, 200) : body;
        debugPrint('[NetworkService] ❌ ${response.statusCode}: $snippet');
        return {
          'success': false,
          'error': 'Server returned ${response.statusCode}: $snippet',
        };
      }
  }
  // ⚠️ بلا `catch` هنا عن قصد: إخفاقُ الشبكة يجب أن **يُرمى** ليجرّب
  // [testServerConnection] المخطَّطَ الآخر. وابتلاعُه هنا كان سيُعيد
  // «فشل» على أوّل محاولةٍ فيموت اكتشافُ المخطَّط قبل أن يبدأ.

  /// Register a client connection (called by API handler)
  void registerClient(String clientId) {
    _connectedClients[clientId] = DateTime.now();
    // Auto-prune stale clients (not seen in 60s)
    _connectedClients.removeWhere(
      (_, lastSeen) => DateTime.now().difference(lastSeen).inSeconds > 60,
    );
  }

  /// Get the best local IPv4 address (WiFi/Ethernet preferred over Bluetooth/VPN)
  static Future<String> getLocalIpAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );

    String? wifiIp, ethernetIp, fallbackIp;
    for (final iface in interfaces) {
      final name = iface.name.toLowerCase();
      // Skip virtual, Bluetooth, VPN adapters
      if (name.contains('bluetooth') ||
          name.contains('vmware') ||
          name.contains('virtualbox') ||
          name.contains('vethernet') ||
          name.contains('loopback') ||
          name.contains('vpn')) {
        continue;
      }

      for (final addr in iface.addresses) {
        if (addr.isLoopback) continue;
        if (name.contains('wi-fi') ||
            name.contains('wifi') ||
            name.contains('wlan')) {
          wifiIp ??= addr.address;
        } else if (name.contains('ethernet') || name.contains('eth')) {
          ethernetIp ??= addr.address;
        } else {
          fallbackIp ??= addr.address;
        }
      }
    }
    final result = wifiIp ?? ethernetIp ?? fallbackIp ?? 'localhost';
    debugPrint(
      '[NetworkService] Detected IP: $result (wifi=$wifiIp, eth=$ethernetIp, fallback=$fallbackIp)',
    );
    return result;
  }

  // ═══════════════════════════════════════════════════════════════
  // Middleware
  // ═══════════════════════════════════════════════════════════════

  /// CORS middleware to allow cross-origin requests from trusted clients.
  ///
  /// A-SEC-5 (M-3): reflect the request Origin only when it is a trusted
  /// loopback/private-LAN origin, instead of the old blanket `*`. A wildcard
  /// ACAO alongside `Authorization` let any public website's JS read this LAN
  /// API from a victim's browser. Non-browser desktop clients send no Origin
  /// and are unaffected.
  static Middleware _corsMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        final headers = _corsHeadersFor(request.headers['origin']);
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: headers);
        }
        final response = await handler(request);
        return response.change(headers: headers);
      };
    };
  }

  static Map<String, String> _corsHeadersFor(String? origin) {
    return {
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Vary': 'Origin',
      if (origin != null && isAllowedCorsOrigin(origin))
        'Access-Control-Allow-Origin': origin,
    };
  }

  /// Whether a browser Origin is trusted enough to reflect in CORS.
  /// Loopback and RFC-1918 private ranges only — a public site must not be
  /// able to read the LAN API from a victim's browser.
  static bool isAllowedCorsOrigin(String origin) {
    final host = Uri.tryParse(origin)?.host ?? '';
    if (host.isEmpty) return false;
    if (host == 'localhost' || host == '::1') return true;
    // F-SEC-1: match a full dotted-quad IPv4 LITERAL, not a string prefix.
    // A bare startsWith('10.')/('192.168.') let an attacker-registered public
    // DNS name like `10.evil.com` / `192.168.evil.com` (and an unanchored
    // 172.x check `172.16.evil.com`) pass as trusted LAN, so its Origin got
    // reflected in Access-Control-Allow-Origin. Requiring an anchored numeric
    // IPv4 rejects any hostname.
    final m = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(host);
    if (m == null) return false;
    final o = [1, 2, 3, 4].map((i) => int.parse(m.group(i)!)).toList();
    if (o.any((x) => x > 255)) return false; // reject e.g. 999.x.x.x
    if (o[0] == 127) return true; // loopback 127.0.0.0/8
    if (o[0] == 10) return true; // 10.0.0.0/8
    if (o[0] == 192 && o[1] == 168) return true; // 192.168.0.0/16
    if (o[0] == 172 && o[1] >= 16 && o[1] <= 31) return true; // 172.16.0.0/12
    return false;
  }

  /// Simple logging middleware
  static Middleware _logMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        final sw = Stopwatch()..start();
        final response = await handler(request);
        sw.stop();
        debugPrint(
          '[API] ${request.method} ${request.requestedUri.path} → ${response.statusCode} (${sw.elapsedMilliseconds}ms)',
        );
        return response;
      };
    };
  }

  Future<void> dispose() async {
    await stopServer();
  }

  /// Broadcast a data_changed WebSocket event to all connected clients.
  /// Use from server-side screens after modifying branches, cost centers, accounts, etc.
  void broadcastChange(String table, {int? branchId}) {
    _apiHandler?.broadcastChange(table, branchId: branchId);
  }
}
