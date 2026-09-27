import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:device_info_plus/device_info_plus.dart' as di;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/trial/trial_policy.dart';
import '../core/utils/license_encoding.dart';
import '../core/trial/trial_state.dart';
import '../data/providers/providers.dart';
import 'secure_storage_service.dart';

/// Verifies PP2 licenses without exposing signing capabilities to the app.
class LicenseVerifier {
  final String publicKeyB64;
  final Ed25519 _algorithm;

  LicenseVerifier(this.publicKeyB64, {Ed25519? algorithm})
      : _algorithm = algorithm ?? Ed25519();

  Future<bool> verify(String encodedKey, String machineId) async {
    if (publicKeyB64 == 'REPLACE_WITH_ED25519_PUBLIC_KEY') return false;
    final parts = encodedKey.replaceAll(RegExp(r'\s'), '').split('.');
    if (parts.length != 2 || !parts[0].startsWith('PP2-')) return false;

    try {
      final payloadText = parts[0].substring(4);
      final payloadBytes = _decodeUnpaddedBase64(payloadText);
      final signatureBytes = _decodeUnpaddedBase64(parts[1]);
      if (signatureBytes.length != 64) return false;
      final payload = jsonDecode(utf8.decode(payloadBytes));
      if (payload is! Map ||
          payload['v'] != 2 ||
          payload['machineId'] != machineId ||
          payload['issuedAt'] is! String ||
          DateTime.tryParse(payload['issuedAt'] as String) == null) {
        return false;
      }

      final publicKeyBytes = _decodePublicKey(publicKeyB64);
      if (publicKeyBytes.length != 32) return false;
      final publicKey = SimplePublicKey(
        publicKeyBytes,
        type: KeyPairType.ed25519,
      );
      return await _algorithm.verify(
        payloadBytes,
        signature: Signature(signatureBytes, publicKey: publicKey),
      );
    } on FormatException {
      return false;
    } on StateError {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  List<int> _decodeUnpaddedBase64(String value) {
    final isBase64Url = RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);
    if (value.isEmpty || value.contains('=') || !isBase64Url) {
      throw const FormatException('Invalid unpadded base64url');
    }
    return base64Url.decode(value.padRight((value.length + 3) ~/ 4 * 4, '='));
  }

  List<int> _decodePublicKey(String value) {
    final unpadded = value.replaceAll('=', '');
    return _decodeUnpaddedBase64(unpadded);
  }
}

/// License Service - Handles Machine ID generation, license key verification,
/// and configurable trial policy management.
class LicenseService {
  final Ref ref;

  LicenseService(this.ref);

  static const String _licenseKeySetting = 'license_key';
  static const String _installDateKey = 'install_date';
  static const String _licensePublicKeyB64 =
      'zNa-GOFZ-av7sGIjeJmc3u60rSWSvST0G8DbNqMer1s';
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

  /// Verify a signed license key against this installation's machine ID.
  Future<bool> verifyKey(String key) async {
    final machineId = await getMachineId();
    return LicenseVerifier(_licensePublicKeyB64).verify(key, machineId);
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
                  .write(_licenseKeySetting, key.replaceAll(RegExp(r'\s'), ''));
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
      '[LICENSE] isActivated() called. storedKey=${storedKey != null ? "present" : "null"}',
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
    debugPrint('[LICENSE] activate() called');
    final normalizedKey = key.replaceAll(RegExp(r'\s'), '');
    final isValid = await verifyKey(normalizedKey);

    if (isValid) {
      // Store in Secure Storage
      await ref
          .read(secureStorageServiceProvider)
          .write(_licenseKeySetting, normalizedKey);

      // Also sync to DB for backward compatibility if needed
      await ref
          .read(databaseProvider)
          .setSetting(_licenseKeySetting, normalizedKey);

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
