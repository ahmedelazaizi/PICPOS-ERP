// ═══════════════════════════════════════════════════════════════════════════
// Diagnostic Logger — append-only file log for debugging client/server issues
// ═══════════════════════════════════════════════════════════════════════════
//
// Writes to `Documents/uralcash_login_log.txt`. Used to capture the login +
// navigation flow on CLIENT mode so we can trace why the per-user default
// screen isn't being applied. `debugPrint` output only goes to the console
// which is lost on release builds running outside a developer's IDE.
//
// Usage:
//   await DiagnosticLogger.log('LOGIN', 'attempt user=ahmed client=true');

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../config/brand.dart';

class DiagnosticLogger {
  // Spec 136 ISS-5 — the login log is keyed by deployment mode so each device
  // writes a DISTINCT file (uralcash_login_log_server.txt / _client.txt /
  // _mirror.txt / _standalone.txt). Pre-fix every mode shared the single
  // uralcash_login_log.txt, so field exports collected from different devices
  // were indistinguishable (the "client.txt == mirror.txt byte-identical"
  // observation). NetworkService sets the label whenever the mode is
  // loaded/reconciled/changed.
  static const String _baseName = '${Brand.dbPrefix}_login_log';
  static String _modeLabel = '';

  /// Set the deployment-mode suffix for the log filename. `null`/empty resets
  /// to the unlabelled base file. Sanitised to `[a-z0-9_-]` for filesystem
  /// safety. Called by NetworkService — DiagnosticLogger stays dependency-free.
  static void setModeLabel(String? mode) {
    final m = (mode ?? '').trim().toLowerCase();
    if (m.isEmpty) {
      _modeLabel = '';
      return;
    }
    final safe = m.replaceAll(RegExp(r'[^a-z0-9_-]'), '');
    _modeLabel = safe.isEmpty ? '' : '_$safe';
  }

  static String get _fileName => '$_baseName$_modeLabel.txt';

  /// The current (mode-labelled) login-log filename — used by the Settings
  /// "copy diagnostic log" action so it reads the active file, not a fixed
  /// name.
  static String get currentFileName => _fileName;

  // ── Spec 129 F-OBS — canonical diagnostic codes ────────────────────────────
  // The six codes mandated by Spec 129 §F-OBS for field-smoke triage of mirror
  // broadcast discipline. Pass these as the `tag` argument to [log] so the
  // log file is grep-able by code. Stable strings — do not rename without
  // updating quickstart.md §3 (smoke-matrix evidence trail) and the call
  // sites in api_handler_base / websocket_sync_client / database_startup /
  // adaptive_poll_timer / each autopost DAO.
  static const String wsConnect = 'WS-CONNECT';
  static const String wsDisconnect = 'WS-DISCONNECT';
  static const String broadcastWrap = 'BROADCAST-WRAP';
  static const String gidAutopost = 'GID-AUTOPOST';
  static const String seedSkipSysdefault = 'SEED-SKIP-SYSDEFAULT';
  static const String pollCadence = 'POLL-CADENCE';

  // ── Failure-tracing tags ────────────────────────────────────────────────────
  // Grep-able tags for the field-failure boundaries wired via [logError], so an
  // operator's Documents log shows WHERE a problem originated (boot / migration
  // / sync push / accounting post / scale) instead of a lost console line.
  static const String startup = 'STARTUP';
  static const String migration = 'MIGRATION';
  static const String syncPush = 'SYNC-PUSH';
  static const String accounting = 'ACCOUNTING';
  static const String plu = 'PLU';

  // ── Test-mode capture ──────────────────────────────────────────────────────
  // When enabled, log entries are appended to [testLog] instead of (or in
  // addition to) the file. Call [enableTestMode] in test setUp; the list is
  // cleared on each call so each test starts fresh.
  static bool _testMode = false;
  static final List<String> _testLog = [];

  /// Enable in-memory log capture for tests. Clears previous entries.
  /// Has no effect outside test code — [_testMode] defaults to false.
  @visibleForTesting
  static void enableTestMode() {
    _testMode = true;
    _testLog.clear();
  }

  /// Immutable view of captured log entries. Only populated when
  /// [enableTestMode] has been called.
  @visibleForTesting
  static List<String> get testLog => List.unmodifiable(_testLog);
  // ──────────────────────────────────────────────────────────────────────────

  /// Append a timestamped log entry to `Documents/uralcash_login_log.txt`.
  /// Never throws — file write failures are silently suppressed.
  /// Serializes concurrent file appends. Without this, simultaneous log()
  /// calls from multiple isolates/subsystems interleaved and produced torn
  /// lines in the field logs (observed 2026-06-29). Each write chains onto the
  /// previous one; the chain never rejects (errors are swallowed inside).
  static Future<void> _writeChain = Future<void>.value();

  static Future<void> log(String tag, String message) async {
    final stamp = DateTime.now().toIso8601String();
    final line = '[$stamp] [$tag] $message';
    // Also emit to console for live debugging
    debugPrint(line);
    if (_testMode) {
      _testLog.add(line);
      return; // skip file I/O in tests
    }
    _writeChain = _writeChain.then((_) async {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$_fileName');
        await file.writeAsString('$line\n', mode: FileMode.append);
      } catch (e) {
        // Log file unavailable (permission, disk full, etc.) — ignore
        debugPrint('[DiagnosticLogger] file write failed: $e');
      }
    });
    return _writeChain;
  }

  /// Append a failure entry: `<op> failed: <error>` (plus the first stack line
  /// when available). Use at catch boundaries so field problems are traceable
  /// to their origin in the Documents log. Never throws.
  static Future<void> logError(String tag, String op, Object error,
      [StackTrace? stack]) async {
    final head = stack == null
        ? ''
        : ' @ ${stack.toString().split('\n').first.trim()}';
    await log(tag, '$op failed: $error$head');
  }

  /// Mark a new session in the log for easy navigation through past entries.
  static Future<void> startSession(String sessionTag) async {
    await log('SESSION', '═══ $sessionTag ═══');
  }
}
