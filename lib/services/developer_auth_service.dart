// ═══════════════════════════════════════════════════════════════════════════
// DEVELOPER AUTH SERVICE — gate for profile / mode / feature-override changes
// ═══════════════════════════════════════════════════════════════════════════
//
// A SEPARATE credential from the end-user admin password. Knowledge of
// this password belongs to the developer/integrator only — even a user
// with the `system_admin` role cannot change the business profile, the
// deployment mode, or individual feature overrides without entering it.
//
// Storage format: Argon2id PHC string via `SecurityService`. The salt lives
// inside the PHC string; the legacy salt key is cleared on upgrade and is
// only ever read to verify an older PBKDF2-SHA256 hash.
//
// Two settings keys are used:
//   - `developer_password_hash`  (Argon2id PHC, or legacy base64)
//   - `developer_password_salt`  (legacy base64 — empty/absent once upgraded)
//
// ⚠️ **`isConfigured` و`verify` لم يعودا يشترطان ملحاً.** كانا يشترطانه،
// وArgon2id يُفرغه — فلولا هذا الإرخاءُ لأبلغت بوّابتا السنة المالية
// «لم تُعَدّ كلمةُ مرور المطوّر» على كلِّ تنصيبةٍ بعد أوّلِ إعادةِ سكّ،
// وأُغلق البابُ إغلاقاً تامّاً. الهاشُ وحدَه هو الدليل.
//
// Recovery: the desktop launcher accepts `--reset-dev-password` /
// `URAL_RESET_DEV_PASSWORD=1`. When observed at startup the bootstrap
// code calls `DeveloperAuthService.clear()` and emits an
// `AuditLog.critical` entry. The developer then sets a new password on
// first access to the developer-tools screen.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';

import '../core/config/support_env.dart';
import '../data/repositories/settings_repository_cached.dart';
import 'api/server_login_throttle.dart';
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
    // ⚠️ الهاشُ وحدَه — لا الملح. Argon2id يُفرغ عمودَ الملح، فاشتراطُه
    // كان يجعل كلَّ تنصيبةٍ مرقّاةٍ تبدو «بلا كلمةِ مطوّر».
    final hash = _settings.get(_hashKey);
    return hash != null && hash.isNotEmpty;
  }

  /// Persists a new developer password. Refuses an empty password —
  /// the wizard UI should validate this before calling but we guard
  /// here too. Always audit-logs at **critical** severity.
  Future<void> setPassword(String plaintext) async {
    final trimmed = plaintext.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Developer password must not be empty');
    }
    final hash = await SecurityService.hashPasswordArgon2(trimmed);
    await _settings.save(_hashKey, hash);
    // Argon2id embeds its salt in the PHC string.
    await _settings.remove(_saltKey);
    await AuditLog.record(
      'developer_password_set',
      level: AuditLevel.critical,
    );
  }

  /// مفتاحُ حدِّ المحاولات. ثابتٌ لا يتبع مستخدماً: كلمةُ مرور المطوّر
  /// اعتمادٌ واحدٌ للتنصيبة كلِّها، فالحدُّ عليها لا على من يجرّبها.
  static const String throttleKey = 'developer_password';

  /// True while the developer password is locked out after repeated failures.
  static bool get isLockedOut => ServerLoginThrottle.isLockedOut(throttleKey);

  /// Verifies a candidate password in constant time. Returns `false`
  /// silently on any lookup error so a half-configured install can't
  /// leak state through timing or exception stacks.
  /// ── حدُّ المحاولات ────────────────────────────────────────────────────
  ///
  /// 🔴 لم يكن هنا أيُّ حدّ — بخلاف نظيرتها في [AdminPasswordService]. وهذه
  /// الكلمةُ تحرس نمطَ العمل وأوضاعَ النشر وتجاوزاتِ الميزات، فكان بالإمكان
  /// تجريبُ آلافِ الكلمات على الجهاز نفسِه بلا قفلٍ ولا أثر.
  Future<bool> verify(String plaintext) async {
    if (ServerLoginThrottle.isLockedOut(throttleKey)) {
      // ignore: discarded_futures — أثرٌ تدقيقيٌّ لا ننتظره.
      AuditLog.record(
        'developer_password_locked_out',
        level: AuditLevel.critical,
      );
      return false;
    }
    try {
      final hash = _settings.get(_hashKey);
      if (hash == null || hash.isEmpty) return false;
      // ⚠️ الملحُ لا يُشترَط — Argon2id يحمله داخلَ الـPHC.
      final salt = _settings.get(_saltKey) ?? '';
      final result = await SecurityService.verifyPasswordFull(
        plaintext.trim(),
        salt,
        hash,
      );
      if (result.verified) {
        ServerLoginThrottle.recordSuccess(throttleKey);
        if (result.needsRehash) await _rehashToArgon2(plaintext.trim());
      } else {
        ServerLoginThrottle.recordFailure(throttleKey);
      }
      return result.verified;
    } catch (e, st) {
      debugPrint('[DEV-AUTH] verify error: $e\n$st');
      return false;
    }
  }

  /// Silently upgrade PBKDF2-SHA256 → Argon2id after a successful verify.
  /// ⚠️ يبتلع أخطاءَه: إخفاقُ الترقية يجب ألّا يرفض كلمةً صحيحة.
  Future<void> _rehashToArgon2(String plaintext) async {
    try {
      final newHash = await SecurityService.hashPasswordArgon2(plaintext);
      await _settings.save(_hashKey, newHash);
      await _settings.remove(_saltKey);
      debugPrint('[DEV-AUTH] ✅ Argon2id rehash complete');
    } catch (e) {
      debugPrint('[DEV-AUTH] Argon2id rehash failed (kept legacy hash): $e');
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
    final fromEnv = supportEnvFlag(env, 'RESET_DEV_PASSWORD');
    if (!fromCli && !fromEnv) return;
    await service.clear();
    debugPrint('[DEV-AUTH] recovery flag observed — developer password cleared');
  }
}
