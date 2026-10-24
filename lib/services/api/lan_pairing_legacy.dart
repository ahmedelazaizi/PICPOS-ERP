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

/// In-process counters, fed by [LanPairingService.recordLegacyDevice].
class LegacyTokenTelemetry {
  LegacyTokenTelemetry._();
  static final LegacyTokenTelemetry instance = LegacyTokenTelemetry._();

  int _requests = 0;
  final Map<String, int> _byDevice = {};

  int get requests => _requests;
  Map<String, int> get requestsByDevice => Map.unmodifiable(_byDevice);

  void record(String deviceId) {
    _requests++;
    _byDevice[deviceId] = (_byDevice[deviceId] ?? 0) + 1;
  }

  @visibleForTesting
  void reset() {
    _requests = 0;
    _byDevice.clear();
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
}
