part of 'lan_pairing_service.dart';

/// Telemetry of the legacy shared bearer token (SEC-006).
///
/// The shared token may only be closed (`endLegacyTransition`) once NO device
/// still uses it. [legacyUsage] answers that from the device table (so it
/// survives a restart); [LegacyTokenTelemetry] adds the in-process request
/// counters. Nothing here closes the token by itself.
class LegacyUsage {
  const LegacyUsage({
    required this.devices,
    required this.requestsSinceStart,
    required this.window,
  });

  /// Devices seen on the shared token inside [window], most recent first.
  final List<LanPairingDevice> devices;

  /// Requests carrying the shared token since this process started.
  final int requestsSinceStart;
  final Duration window;

  int get deviceCount => devices.length;
  bool get inUse => devices.isNotEmpty;
}

/// Server setting (`settings` table): the legacy shared bearer on/off.
/// Absent = ON (a server provisioned before this key existed); written as
/// `false` by [LanPairingService.initializeLegacyTransition] on a NEW server.
const String legacyTokenEnabledKey = 'lan_legacy_token_enabled';

/// One device/address that presented the shared bearer (accepted or refused).
class LegacyAttempt {
  LegacyAttempt(this.deviceId);
  final String deviceId;
  String name = '';
  String ip = '';
  String userAgent = '';
  DateTime? lastSeen;
  int accepted = 0;
  int refused = 0;
}

/// In-process counters, fed by the auth middleware (accepted AND refused).
class LegacyTokenTelemetry {
  LegacyTokenTelemetry._();
  static final LegacyTokenTelemetry instance = LegacyTokenTelemetry._();
  static const int _maxTracked = 200;

  int _requests = 0;
  int _refused = 0;
  final Map<String, int> _byDevice = {};
  final Map<String, LegacyAttempt> _attempts = {};

  int get requests => _requests;
  int get refusedRequests => _refused;
  Map<String, int> get requestsByDevice => Map.unmodifiable(_byDevice);

  /// Most recent first.
  List<LegacyAttempt> get attempts => _attempts.values.toList()
    ..sort((a, b) => (b.lastSeen ?? DateTime(0)).compareTo(a.lastSeen ?? DateTime(0)));

  void record(String deviceId) {
    _requests++;
    _byDevice[deviceId] = (_byDevice[deviceId] ?? 0) + 1;
  }

  /// Counts one use of the shared bearer. [refused] = the server turned it away.
  void note({
    required String deviceId,
    String name = '',
    String ip = '',
    String userAgent = '',
    required bool refused,
    required DateTime at,
  }) {
    final key = deviceId.isEmpty ? 'legacy@$ip' : deviceId;
    // Accepted uses are counted by [record] (LanPairingService.recordLegacyDevice).
    if (refused) _refused++;
    if (!_attempts.containsKey(key) && _attempts.length >= _maxTracked) return;
    final a = _attempts.putIfAbsent(key, () => LegacyAttempt(key));
    a.name = name;
    a.ip = ip;
    a.userAgent = userAgent;
    a.lastSeen = at;
    refused ? a.refused++ : a.accepted++;
  }

  @visibleForTesting
  void reset() {
    _requests = 0;
    _refused = 0;
    _byDevice.clear();
    _attempts.clear();
  }
}
extension LanPairingLegacy on LanPairingService {
  Future<LegacyUsage> legacyUsage({
    Duration window = const Duration(days: 30),
  }) async {
    final cutoff = _now().subtract(window);
    final used = (await listDevices())
        .where((d) => d.legacySeen && (d.lastSeenAt?.isAfter(cutoff) ?? false))
        .toList()
      ..sort((a, b) => b.lastSeenAt!.compareTo(a.lastSeenAt!));
    return LegacyUsage(
      devices: used,
      requestsSinceStart: LegacyTokenTelemetry.instance.requests,
      window: window,
    );
  }

  /// Ends the legacy-token window ONLY when no device used it inside
  /// [window]. Returns whether the window was closed.
  Future<bool> endLegacyTransitionIfUnused({
    Duration window = const Duration(days: 30),
  }) async {
    if ((await legacyUsage(window: window)).inUse) return false;
    await endLegacyTransition();
    return true;
  }

  /// Is the shared bearer switched on? Missing key = ON (existing servers).
  Future<bool> legacyTokenEnabled() async {
    if (_db == null) return true;
    return (await _db.getSettingValue(legacyTokenEnabledKey)) != 'false';
  }

  /// Switches the shared bearer on/off. Needs `devices_pair_manage` and is
  /// audited. Turning it ON also restarts the transition window so a window
  /// that already elapsed does not silently keep the switch ineffective.
  Future<void> setLegacyTokenEnabled(
    bool enabled, {
    required int? actorUserId,
  }) async {
    await _authz.require(
      actorUserId,
      action: enabled ? 'legacy_token_on' : 'legacy_token_off',
    );
    if (_db == null) return;
    await _db.setSetting(legacyTokenEnabledKey, enabled ? 'true' : 'false');
    if (enabled) {
      await _db.setSetting(LanPairingService.transitionEndedKey, 'false');
      await _db.setSetting(
        LanPairingService.transitionStartedKey,
        '${_now().millisecondsSinceEpoch}',
      );
    }
  }

  /// Telemetry hook for the middleware: one shared-bearer use.
  void noteLegacyAttempt({
    required String deviceId,
    required String name,
    required String ip,
    required String userAgent,
    required bool refused,
  }) => LegacyTokenTelemetry.instance.note(
    deviceId: deviceId,
    name: name,
    ip: ip,
    userAgent: userAgent,
    refused: refused,
    at: _now(),
  );
}