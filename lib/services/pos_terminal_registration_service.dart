import 'dart:io';
import 'package:flutter/foundation.dart';
import '../data/database/database.dart';
import 'device_identity_service.dart';
import 'network_service.dart';
import 'server_proxy.dart';

/// Resolves and caches the [int] `pos_terminals.id` for the running
/// device. Lives as a singleton so any caller (orchestrators, shift
/// open, settings UI) gets the same value without async hops.
///
/// Feature 009 / T012f (FR-034). Two resolution paths:
///   1. **Local lookup** — query `pos_terminals` for a row whose
///      `deviceId` equals [DeviceIdentityService.getCurrentDeviceId].
///      Hit on the second app launch onwards (after the first sync
///      pulls the row back).
///   2. **Server registration** — POST `/api/pos-terminals/register`
///      with the device id + a default name. The server creates the
///      row and (asynchronously) the row syncs back via T012c's
///      [PosTerminalSyncStrategy]. Best-effort: if the endpoint is
///      missing or the network is offline, the service logs and
///      defers; T012g re-tries on every reconnect.
///
/// Mirror/client mode behavior: the server is the only place where
/// new terminal rows are created. Standalone (single-device) installs
/// don't need a registered terminal — the per-terminal policy tier is
/// simply skipped at sale time.
class PosTerminalRegistrationService {
  static const String _registerEndpoint = '/api/pos-terminals/register';

  static PosTerminalRegistrationService? _instance;

  /// Singleton accessor. The service is db-scoped — call [initialize]
  /// once at boot before [registerIfNeeded].
  static PosTerminalRegistrationService get instance =>
      _instance ??= PosTerminalRegistrationService._internal();

  PosTerminalRegistrationService._internal();

  AppDatabase? _db;
  int? _cachedTerminalId;
  bool _registrationInFlight = false;

  /// True when [getCurrentTerminalId] would return a non-null value.
  bool get isRegistered => _cachedTerminalId != null;

  /// Wires the database. Safe to call multiple times.
  void initialize(AppDatabase db) {
    _db = db;
  }

  /// Returns the cached terminal id, or null if the device hasn't yet
  /// been bound to a `pos_terminals` row. Sync — does not trigger I/O.
  int? getCurrentTerminalId() => _cachedTerminalId;

  /// Test-only reset.
  @visibleForTesting
  void resetForTest() {
    _cachedTerminalId = null;
    _registrationInFlight = false;
  }

  /// Idempotent. Safe to call from multiple paths (boot, online hook,
  /// shift open). Sequence:
  ///   1. If already cached, return immediately.
  ///   2. Try the local DB lookup. If a row with our device_id exists,
  ///      cache its id and return.
  ///   3. If we're in client/mirror mode, attempt server registration.
  ///      If the server replies with the id, cache and return.
  ///   4. Otherwise, leave cache null. The shift-open path falls back
  ///      to a NULL `pos_terminal_id` (graceful degradation) until the
  ///      next reconnect re-runs this method.
  Future<void> registerIfNeeded() async {
    if (_cachedTerminalId != null) return;
    if (_registrationInFlight) return;
    final db = _db;
    if (db == null) {
      debugPrint('[PosTerminalReg] not initialized — skipping registerIfNeeded');
      return;
    }
    if (!DeviceIdentityService.instance.isWarmedUp) {
      debugPrint(
          '[PosTerminalReg] DeviceIdentityService not warmed up — skipping');
      return;
    }
    final deviceId = DeviceIdentityService.instance.getCurrentDeviceId();

    _registrationInFlight = true;
    try {
      // 1. Local lookup — succeeds on second-and-later launches after the
      //    server's row has been pulled back via PosTerminalSyncStrategy.
      final localRow = await (db.select(db.posTerminals)
            ..where((t) => t.deviceId.equals(deviceId))
            ..limit(1))
          .getSingleOrNull();
      if (localRow != null) {
        _cachedTerminalId = localRow.id;
        debugPrint(
            '[PosTerminalReg] resolved locally — id=${localRow.id} name=${localRow.name}');
        return;
      }

      // 2. Server registration — only meaningful in client/mirror modes.
      //    Standalone installs have no server to register against; the
      //    per-terminal policy tier just stays inactive for them.
      final ns = NetworkService.instance;
      if (!ns.isClient && !ns.isMirror) {
        debugPrint(
            '[PosTerminalReg] standalone mode — skipping server registration');
        return;
      }

      final defaultName = await _resolveDefaultName(db);
      try {
        final response = await ServerProxy.instance.post(
          _registerEndpoint,
          {
            'deviceId': deviceId,
            'name': defaultName,
            'hostname': Platform.localHostname,
            'platform': Platform.operatingSystem,
          },
          idempotencyKey: deviceId,
        );
        final serverId = response['id'] ?? response['terminalId'];
        if (serverId is int) {
          _cachedTerminalId = serverId;
          debugPrint(
              '[PosTerminalReg] registered with server — id=$serverId');
        } else {
          debugPrint(
              '[PosTerminalReg] server response missing id field: $response');
        }
      } catch (e) {
        // Server endpoint missing (404), network down, etc. Defer. The
        // online-reconnect hook (T012g) will retry. Shift open in the
        // interim sees a null terminal id and falls back to NULL row
        // (Constitution I — preserve legacy behavior for unregistered).
        debugPrint('[PosTerminalReg] server registration failed: $e');
      }
    } finally {
      _registrationInFlight = false;
    }
  }

  /// Default human-readable name. Uses the OS hostname so admins can
  /// recognize the terminal in the management UI. Falls back to a
  /// short prefix of the device_id if the hostname is unavailable.
  Future<String> _resolveDefaultName(AppDatabase db) async {
    try {
      return Platform.localHostname;
    } catch (_) {
      final id = DeviceIdentityService.instance.tryGetDeviceId() ?? 'unknown';
      // First 8 chars of the UUIDv7 are good enough for human display.
      return 'POS-${id.length > 8 ? id.substring(0, 8) : id}';
    }
  }
}
