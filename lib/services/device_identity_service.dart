import 'package:flutter/foundation.dart';
import '../core/utils/uuid_v7.dart';
import '../data/repositories/settings_repository_cached.dart';
import 'secure_storage_service.dart';

/// Stable per-device identity, generated on first launch.
///
/// Feature 009 / T012d (FR-033). The `device_id` is a UUIDv7 stored in
/// `flutter_secure_storage` so it survives app reinstalls but resets on
/// OS reinstall / data wipe. It is mirrored into `app_settings.device_id`
/// at warmup so the server can observe it via the regular settings sync
/// channel — needed by [PosTerminalRegistrationService] (T012f) to bind
/// this device to a `pos_terminals` row.
///
/// Lifecycle:
///   1. App boot calls [warmup] once (T012e).
///   2. warmup reads from secure storage; if missing, generates a UUIDv7
///      and writes it back. Then mirrors into the encrypted SQLite
///      settings table.
///   3. After warmup, [getCurrentDeviceId] returns the cached id
///      synchronously for any caller (orchestrators, shift open,
///      registration service).
///
/// Failure handling:
///   - Secure storage may fail (permissions, missing keystore, sandbox).
///     In that case warmup falls back to an in-memory id and logs a
///     warning. The id won't persist across launches but the app stays
///     functional. Production reports of this should be rare.
class DeviceIdentityService {
  static const String _settingsKey = 'device_id';
  static const String _secureStorageKey = 'device_id';

  static DeviceIdentityService? _instance;

  /// Singleton accessor.
  static DeviceIdentityService get instance =>
      _instance ??= DeviceIdentityService._internal();

  DeviceIdentityService._internal();

  String? _cachedDeviceId;
  bool _warmedUp = false;

  /// True after [warmup] has run successfully at least once.
  bool get isWarmedUp => _warmedUp;

  /// Returns the warmed-up device id. Throws [StateError] if called
  /// before [warmup] completed — by convention, [warmup] runs in app
  /// bootstrap so post-bootstrap callers can rely on this.
  String getCurrentDeviceId() {
    final id = _cachedDeviceId;
    if (id == null) {
      throw StateError(
        'DeviceIdentityService.getCurrentDeviceId() called before warmup() — '
        'call DeviceIdentityService.instance.warmup(settingsRepo) at boot.',
      );
    }
    return id;
  }

  /// Same as [getCurrentDeviceId] but returns null if not warmed up.
  /// Use this for non-critical paths (e.g., diagnostics) where the
  /// caller wants to avoid throwing during startup.
  String? tryGetDeviceId() => _cachedDeviceId;

  /// One-shot async initialization. Called once at app boot via
  /// [warmup]. Subsequent calls are no-ops (idempotent).
  ///
  /// [secureStorage] is injected so the test suite can substitute a fake.
  /// In production callers pass a fresh [SecureStorageService] instance.
  ///
  /// The `settings` argument is typed as [SettingsRepositoryCached] (not the
  /// abstract [ISettingsRepository]) because that's what main.dart preloads
  /// before runApp — the cached wrapper isn't a full ISettingsRepository
  /// implementation, just a thin two-method DAO cache. Decoupling here
  /// keeps the call site simple.
  Future<void> warmup(
    SettingsRepositoryCached settings, {
    SecureStorageService? secureStorage,
  }) async {
    if (_warmedUp && _cachedDeviceId != null) return;
    final storage = secureStorage ?? SecureStorageService();

    String? id;
    // 1. Try secure storage (the source of truth — survives DB wipe).
    try {
      id = await storage.read(_secureStorageKey);
    } catch (e) {
      debugPrint('[DeviceIdentity] secure storage read failed: $e');
    }

    if (id == null || id.isEmpty) {
      // 2. Fallback to a value the server may have written to settings
      //    (rare — mostly for migrating an install that lost secure
      //    storage but not its DB).
      try {
        final fromSettings = await settings.getAsync(_settingsKey);
        if (fromSettings != null && fromSettings.isNotEmpty) {
          id = fromSettings;
          // Re-seed secure storage so future launches don't take the
          // settings path again.
          try {
            await storage.write(_secureStorageKey, id);
          } catch (_) {/* best effort */}
        }
      } catch (e) {
        debugPrint('[DeviceIdentity] settings read failed: $e');
      }
    }

    if (id == null || id.isEmpty) {
      // 3. Fresh device — mint a new UUIDv7.
      id = UuidV7.generate();
      try {
        await storage.write(_secureStorageKey, id);
      } catch (e) {
        debugPrint(
            '[DeviceIdentity] secure storage write failed; using in-memory id: $e');
      }
    }

    _cachedDeviceId = id;

    // 4. Mirror into app_settings so the server can observe via sync.
    //    This is best-effort — the id remains usable even if persistence fails.
    try {
      final existing = await settings.getAsync(_settingsKey);
      if (existing != id) {
        await settings.save(_settingsKey, id);
      }
    } catch (e) {
      debugPrint('[DeviceIdentity] mirror-to-settings failed: $e');
    }

    _warmedUp = true;
    debugPrint('[DeviceIdentity] warmed up — device_id=$id');
  }

  /// Test-only: clears the cached id so a subsequent [warmup] re-reads
  /// or re-generates. Production code should never call this.
  @visibleForTesting
  void resetForTest() {
    _cachedDeviceId = null;
    _warmedUp = false;
  }
}
