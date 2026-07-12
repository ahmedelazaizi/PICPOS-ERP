import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart' as di;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/trial/trial_policy.dart';
import '../core/trial/trial_state.dart';
import '../data/providers/providers.dart';
import 'secure_storage_service.dart';

/// License Service - Handles Machine ID generation, license key verification,
/// and configurable trial policy management.
class LicenseService {
  final Ref ref;

  LicenseService(this.ref);

  static const String _licenseKeySetting = 'license_key';
  static const String _secretSalt = 'UralCash_Secure_Salt_2026';
  static const String _installDateKey = 'install_date';
  static const String _trialPolicyKey = 'trial_policy';

  /// Whether the app has been verified as activated (read by DAOs to bypass demo limits)
  static bool get isActivatedCached => TrialState.isActivatedCached;

  /// Current trial policy (read by DAOs, guards, and print services)
  static TrialPolicy get activePolicy => TrialState.activePolicy;

  /// Whether the app is in trial mode (not full version)
  static bool get isTrial => TrialState.isTrial;

  /// Whether to show watermark on receipts
  static bool get showWatermark => TrialState.showWatermark;

  /// Installation date (for time-limited trials)
  static DateTime? _installDate;

  /// Get unique identifier for the current machine/device
  Future<String> getMachineId() async {
    final deviceInfo = di.DeviceInfoPlugin();
    String rawId = '';

    if (kIsWeb) {
      rawId = 'WEB_STATION';
    } else if (Platform.isWindows) {
      final windowsInfo = await deviceInfo.windowsInfo;
      rawId =
          '${windowsInfo.deviceId}${windowsInfo.computerName}${windowsInfo.numberOfCores}';
    } else if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      rawId = androidInfo.id;
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      rawId = iosInfo.identifierForVendor ?? 'IOS_DEVICE';
    } else if (Platform.isMacOS) {
      final macosInfo = await deviceInfo.macOsInfo;
      rawId = macosInfo.systemGUID ?? 'MACOS_DEVICE';
    } else if (Platform.isLinux) {
      final linuxInfo = await deviceInfo.linuxInfo;
      rawId = linuxInfo.machineId ?? 'LINUX_DEVICE';
    }

    // Hash the raw ID to create a clean, consistent Machine ID
    final bytes = utf8.encode(rawId);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16).toUpperCase();
  }

  /// Generate a valid license key for a given machine ID (Internal use by developer)
  String generateKey(String machineId) {
    final bytes = utf8.encode('$machineId$_secretSalt');
    final digest = sha256.convert(bytes);
    // Key format: XXXX-XXXX-XXXX-XXXX
    final fullHash = digest.toString().toUpperCase();
    return '${fullHash.substring(0, 4)}-${fullHash.substring(4, 8)}-${fullHash.substring(8, 12)}-${fullHash.substring(12, 16)}';
  }

  /// Verify if a key is valid for this machine
  Future<bool> verifyKey(String key) async {
    final machineId = await getMachineId();
    final expectedKey = generateKey(machineId);
    return key.trim().toUpperCase() == expectedKey;
  }

  /// Check if the application is currently activated
  Future<bool> isActivated() async {
    // 1. Try reading from File-based activation (New Feature for ease of use)
    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;
      final fileNames = ['license.txt', 'activation.key', 'license.key'];
      
      for (final fileName in fileNames) {
        final file = File('$exeDir${Platform.pathSeparator}$fileName');
        if (await file.exists()) {
          final content = await file.readAsString();
          final key = content.trim();
          if (key.isNotEmpty) {
            final isValid = await verifyKey(key);
            if (isValid) {
              debugPrint('[LICENSE] File-based activation successful via $fileName');
              TrialState.isActivatedCached = true;
              // Persist to secure storage for future boots if file removed
              await ref
                  .read(secureStorageServiceProvider)
                  .write(_licenseKeySetting, key.toUpperCase());
              return true;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[LICENSE] File-based activation check failed: $e');
    }

    // 2. Try reading from Secure Storage (Normal Way)
    String? storedKey = await ref
        .read(secureStorageServiceProvider)
        .read(_licenseKeySetting);

    // 2. Migration: If not in secure storage, check Database (Old Way)
    if (storedKey == null) {
      storedKey = await ref
          .read(databaseProvider)
          .getSettingValue(_licenseKeySetting);
      if (storedKey != null && storedKey.isNotEmpty) {
        debugPrint('[LICENSE] Migrating license key to secure storage...');
        await ref
            .read(secureStorageServiceProvider)
            .write(_licenseKeySetting, storedKey);
        // We could delete from DB here, but keeping it as a fallback for now is safer during rollout
      }
    }

    debugPrint(
      '[LICENSE] isActivated() called. storedKey=${storedKey != null ? "${storedKey.substring(0, 4)}..." : "null"}',
    );

    if (storedKey == null || storedKey.isEmpty) {
      TrialState.isActivatedCached = false;
      return false;
    }

    final result = await verifyKey(storedKey);
    TrialState.isActivatedCached = result;
    return result;
  }

  /// Refresh the static cache — call once at app startup.
  /// Also initializes trial policy and install date.
  Future<void> refreshActivationStatus() async {
    TrialState.isActivatedCached = await isActivated();

    // Initialize trial policy
    await _initTrialPolicy();

    // Track installation date for time-limited trials
    await _ensureInstallDate();

    debugPrint(
      '[LICENSE] Status: activated=$TrialState.isActivatedCached, '
      'trial=$isTrial, policy=${TrialState.activePolicy.mode.name}, '
      'remainingDays=${getRemainingTrialDays()}',
    );
  }

  /// Initialize trial policy from stored settings or defaults
  Future<void> _initTrialPolicy() async {
    if (TrialState.isActivatedCached) {
      TrialState.activePolicy = TrialPolicy.fullVersion;
      return;
    }

    // Try loading saved policy
    try {
      final storedPolicy = await ref
          .read(databaseProvider)
          .getSettingValue(_trialPolicyKey);
      if (storedPolicy != null && storedPolicy.isNotEmpty) {
        TrialState.activePolicy = TrialPolicy.decode(storedPolicy);
        return;
      }
    } catch (_) {}

    // Default trial policy
    TrialState.activePolicy = TrialPolicy.defaultTrial;

    // Persist default policy
    try {
      await ref
          .read(databaseProvider)
          .setSetting(_trialPolicyKey, TrialState.activePolicy.encode());
    } catch (_) {}
  }

  /// Ensure installation date is recorded (first launch tracking)
  Future<void> _ensureInstallDate() async {
    try {
      final stored = await ref
          .read(databaseProvider)
          .getSettingValue(_installDateKey);
      if (stored != null && stored.isNotEmpty) {
        _installDate = DateTime.tryParse(stored);
      } else {
        _installDate = DateTime.now();
        await ref
            .read(databaseProvider)
            .setSetting(_installDateKey, _installDate!.toIso8601String());
      }
    } catch (_) {
      _installDate ??= DateTime.now();
    }
  }

  /// Get remaining trial days (-1 = unlimited, 0 = expired)
  static int getRemainingTrialDays() {
    if (TrialState.isActivatedCached) return -1; // Unlimited
    if (TrialState.activePolicy.trialDays == null) return -1; // No time limit

    if (_installDate == null) return TrialState.activePolicy.trialDays!;

    final elapsed = DateTime.now().difference(_installDate!).inDays;
    final remaining = TrialState.activePolicy.trialDays! - elapsed;
    return remaining < 0 ? 0 : remaining;
  }

  /// Whether the trial period has expired
  static bool get isTrialExpired {
    if (TrialState.isActivatedCached) return false;
    if (TrialState.activePolicy.trialDays == null) return false;
    return getRemainingTrialDays() <= 0;
  }

  /// Whether a specific screen is locked by the trial policy
  static bool isScreenLocked(int screenIndex) {
    if (TrialState.isActivatedCached) return false;
    return TrialState.activePolicy.isScreenLocked(screenIndex);
  }

  /// Activate the application with a key
  Future<bool> activate(String key) async {
    debugPrint(
      '[LICENSE] activate() called with key=${key.substring(0, 4)}...',
    );
    final isValid = await verifyKey(key);

    if (isValid) {
      // Store in Secure Storage
      await ref
          .read(secureStorageServiceProvider)
          .write(_licenseKeySetting, key.trim().toUpperCase());

      // Also sync to DB for backward compatibility if needed
      await ref
          .read(databaseProvider)
          .setSetting(_licenseKeySetting, key.trim().toUpperCase());

      TrialState.isActivatedCached = true;
      TrialState.activePolicy = TrialPolicy.fullVersion;
      return true;
    }

    return false;
  }
}

final licenseServiceProvider = Provider((ref) => LicenseService(ref));

/// Provider to watch activation status
final activationStatusProvider = FutureProvider<bool>((ref) {
  return ref.watch(licenseServiceProvider).isActivated();
});

/// Provider for current trial policy
final trialPolicyProvider = Provider<TrialPolicy>((ref) {
  return TrialState.activePolicy;
});
