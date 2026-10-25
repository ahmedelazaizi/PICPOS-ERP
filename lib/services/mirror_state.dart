import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted state for `NetworkMode.mirror` — the admin-elevated client
/// mode that bypasses branch isolation and routes writes to the HQ server.
///
/// Mirror mode reuses the existing client connection settings managed by
/// `NetworkService` (`network_server_address`, `network_server_port`,
/// `network_api_token`). [MirrorState] only stores the *additional* fields
/// the badge UI, audit logs, and offline detector need.
///
/// Loaded once during boot from `main_desktop.dart` alongside
/// `NetworkService.loadSettings()`. Subsequent reads are in-memory.
///
/// MM.A scope: persistence only. The wizard step (Commit 4) writes to
/// this; the badge / write-interceptor (MM.B–MM.D) read from it.
class MirrorState {
  MirrorState._();
  static final MirrorState instance = MirrorState._();

  static const _prefServerDisplayName = 'mirror_server_display_name';
  static const _prefLastHandshakeAt = 'mirror_last_handshake_at';
  static const _prefAdminUserId = 'mirror_admin_user_id';

  String? _serverDisplayName;
  DateTime? _lastHandshakeAt;
  int? _adminUserId;

  /// Monotonic counter bumped on every state-changing call (loadSettings,
  /// setPaired, markHandshake, clear). UI components use this as a
  /// `ValueListenable` so the mirror badge rebuilds on each heartbeat
  /// without needing to expose every individual field as its own notifier.
  /// Counter values are not meaningful — only the change events are.
  final ValueNotifier<int> _revision = ValueNotifier(0);
  ValueListenable<int> get revision => _revision;

  /// Friendly server name (e.g. company name returned by `/api/health`),
  /// shown in the mirror-mode badge — "🪞 متصل بـ [name]".
  String? get serverDisplayName => _serverDisplayName;

  /// UTC timestamp of the most recent successful handshake with the HQ
  /// server. Used by the offline banner to show staleness.
  DateTime? get lastHandshakeAt => _lastHandshakeAt;

  /// Local user id of the admin who paired the device for mirror mode.
  /// Persisted for audit log tagging — every mirror write is attributed
  /// to this user even when the session has rotated.
  int? get adminUserId => _adminUserId;

  /// True when the wizard has successfully completed the foundational
  /// handshake — server identity captured and a recent successful contact
  /// recorded. The mode picker can persist `NetworkMode.mirror` without
  /// these being set (intermediate state), but mirror behaviour is gated
  /// on this returning true.
  ///
  /// `adminUserId` is intentionally NOT part of this gate during MM.A —
  /// the foundation step only needs server addressability. Admin-identity
  /// verification (who is acting as HQ) lands in MM.C alongside the
  /// MirrorWriteInterceptor that consumes that field for audit tagging.
  bool get isConfigured =>
      _serverDisplayName != null &&
      _serverDisplayName!.isNotEmpty &&
      _lastHandshakeAt != null;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _serverDisplayName = prefs.getString(_prefServerDisplayName);
    _adminUserId = prefs.getInt(_prefAdminUserId);
    final tsMillis = prefs.getInt(_prefLastHandshakeAt);
    _lastHandshakeAt = tsMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(tsMillis, isUtc: true);
    debugPrint(
      '[MirrorState] loaded: name=$_serverDisplayName admin=$_adminUserId '
      'lastHandshake=$_lastHandshakeAt configured=$isConfigured',
    );
    _revision.value++;
  }

  /// Called by the wizard after a successful handshake against the HQ
  /// server. Stamps `lastHandshakeAt` to "now" automatically.
  ///
  /// [adminUserId] is optional during MM.A — wired in MM.C once the
  /// MirrorWriteInterceptor needs it for audit tagging.
  Future<void> setPaired({
    required String serverDisplayName,
    int? adminUserId,
  }) async {
    _serverDisplayName = serverDisplayName;
    if (adminUserId != null) _adminUserId = adminUserId;
    _lastHandshakeAt = DateTime.now().toUtc();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefServerDisplayName, serverDisplayName);
    if (adminUserId != null) {
      await prefs.setInt(_prefAdminUserId, adminUserId);
    }
    await prefs.setInt(
      _prefLastHandshakeAt,
      _lastHandshakeAt!.millisecondsSinceEpoch,
    );
    _revision.value++;
  }

  /// Update only the handshake timestamp — called from the heartbeat path
  /// in MM.B once the read interceptor lands.
  Future<void> markHandshake() async {
    _lastHandshakeAt = DateTime.now().toUtc();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _prefLastHandshakeAt,
      _lastHandshakeAt!.millisecondsSinceEpoch,
    );
    _revision.value++;
  }

  /// A heartbeat that did NOT get through (M2 / MIR-008). Nothing is stored; the
  /// revision bump makes every listener (status strip, mutation guard) re-judge
  /// the link at once instead of waiting for a success that may never come.
  void markHandshakeFailed() {
    _lastFailureAt = DateTime.now().toUtc();
    _revision.value++;
  }

  DateTime? _lastFailureAt;

  /// When the most recent heartbeat failed (memory only).
  DateTime? get lastFailureAt => _lastFailureAt;

  /// Wipe all mirror state — called when the operator switches away from
  /// `NetworkMode.mirror`. Symmetric with `NetworkService.dispose()` for
  /// client mode.
  Future<void> clear() async {
    _serverDisplayName = null;
    _lastHandshakeAt = null;
    _adminUserId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefServerDisplayName);
    await prefs.remove(_prefLastHandshakeAt);
    await prefs.remove(_prefAdminUserId);
    _revision.value++;
  }

  /// Test-only: synchronously prime in-memory state without touching
  /// SharedPreferences. Mirrors `NetworkService.debugSetModeForTests`.
  @visibleForTesting
  void debugSetForTests({
    String? serverDisplayName,
    int? adminUserId,
    DateTime? lastHandshakeAt,
  }) {
    _serverDisplayName = serverDisplayName;
    _adminUserId = adminUserId;
    _lastHandshakeAt = lastHandshakeAt;
    _revision.value++;
  }
}
