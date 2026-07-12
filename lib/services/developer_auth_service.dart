// ═══════════════════════════════════════════════════════════════════════════
// DEVELOPER AUTH SERVICE — gate for profile / mode / feature-override changes
// ═══════════════════════════════════════════════════════════════════════════
//
// A SEPARATE credential from the end-user admin password. Knowledge of
// this password belongs to the developer/integrator only — even a user
// with the `system_admin` role cannot change the business profile, the
// deployment mode, or individual feature overrides without entering it.
//
// Storage format: (salt, hash) using the existing `SecurityService`
// PBKDF2-SHA256 primitive. No bcrypt dependency to add.
//
// Two settings keys are used:
//   - `developer_password_salt`  (base64)
//   - `developer_password_hash`  (base64)
//
// Recovery: the desktop launcher accepts `--reset-dev-password` /
// `URAL_RESET_DEV_PASSWORD=1`. When observed at startup the bootstrap
// code calls `DeveloperAuthService.clear()` and emits an
// `AuditLog.critical` entry. The developer then sets a new password on
// first access to the developer-tools screen.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';

import '../data/repositories/settings_repository_cached.dart';
import 'audit_log.dart';
import 'security_service.dart';

class DeveloperAuthService {
  static const String _saltKey = 'developer_password_salt';
  static const String _hashKey = 'developer_password_hash';

  final SettingsRepositoryCached _settings;

  DeveloperAuthService(this._settings);

  /// `true` once a developer password has been set. The wizard's
  /// developer-password step reads this to decide whether to show
  /// "Create password" vs "Confirm password" copy.
  bool get isConfigured {
    final salt = _settings.get(_saltKey);
    final hash = _settings.get(_hashKey);
    return salt != null &&
        salt.isNotEmpty &&
        hash != null &&
        hash.isNotEmpty;
  }

  /// Persists a new developer password. Refuses an empty password —
  /// the wizard UI should validate this before calling but we guard
  /// here too. Always audit-logs at **critical** severity.
  Future<void> setPassword(String plaintext) async {
    final trimmed = plaintext.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Developer password must not be empty');
    }
    final salt = SecurityService.generateSalt();
    final hash = SecurityService.hashPassword(trimmed, salt);
    await _settings.save(_saltKey, salt);
    await _settings.save(_hashKey, hash);
    await AuditLog.record(
      'developer_password_set',
      level: AuditLevel.critical,
    );
  }

  /// Verifies a candidate password in constant time. Returns `false`
  /// silently on any lookup error so a half-configured install can't
  /// leak state through timing or exception stacks.
  bool verify(String plaintext) {
    try {
      final salt = _settings.get(_saltKey);
      final hash = _settings.get(_hashKey);
      if (salt == null || hash == null || salt.isEmpty || hash.isEmpty) {
        return false;
      }
      return SecurityService.verifyPassword(plaintext.trim(), salt, hash);
    } catch (e, st) {
      debugPrint('[DEV-AUTH] verify error: $e\n$st');
      return false;
    }
  }

  /// Wipes the stored credential so the next attempt prompts for a new
  /// one. Called by the CLI/env recovery path ONLY — never exposed in
  /// the UI. Audit-logs critical.
  Future<void> clear() async {
    await _settings.remove(_saltKey);
    await _settings.remove(_hashKey);
    await AuditLog.record(
      'developer_password_reset',
      level: AuditLevel.critical,
    );
  }

  // ─── Startup CLI / env-flag handling ─────────────────────────────────

  /// Checks process args + environment for the recovery signal and,
  /// if set, clears the stored password. Safe to call every boot: it's
  /// a no-op unless the flag is present.
  ///
  /// Recognised signals:
  ///   * CLI arg `--reset-dev-password`
  ///   * Environment variable `URAL_RESET_DEV_PASSWORD=1`
  static Future<void> maybeHandleRecoverySignal({
    required List<String> args,
    required Map<String, String> env,
    required DeveloperAuthService service,
  }) async {
    final fromCli = args.contains('--reset-dev-password');
    final fromEnv = env['URAL_RESET_DEV_PASSWORD'] == '1';
    if (!fromCli && !fromEnv) return;
    await service.clear();
    debugPrint('[DEV-AUTH] recovery flag observed — developer password cleared');
  }
}
