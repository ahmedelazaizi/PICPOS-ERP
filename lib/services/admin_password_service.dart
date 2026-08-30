import 'package:flutter/foundation.dart';

import '../data/repositories/settings_repository_cached.dart';
import 'api/server_login_throttle.dart';
import 'audit_log.dart';
import 'security_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ADMIN PASSWORD SERVICE — hashed storage for the invoice-deletion password
// ═══════════════════════════════════════════════════════════════════════════
//
// Storage format: (salt, hash) using PBKDF2-SHA256 via SecurityService.
// Keys used:
//   - `admin_password_salt`  (base64)
//   - `admin_password_hash`  (base64)
//
// Legacy plaintext key `admin_password` is kept only during the migration
// window: `verify()` falls back to it when no hash is stored, and
// `migrateIfNeeded()` promotes it to hashed on first boot after upgrade.
// ═══════════════════════════════════════════════════════════════════════════

class AdminPasswordService {
  static const String _saltKey = 'admin_password_salt';
  static const String _hashKey = 'admin_password_hash';
  static const String _legacyKey = 'admin_password';

  final SettingsRepositoryCached _settings;

  AdminPasswordService(this._settings);

  /// True once admin password has been stored as a hash.
  bool get isConfigured {
    final hash = _settings.get(_hashKey);
    return hash != null && hash.isNotEmpty;
  }

  /// Hash and persist a new admin password. Removes the legacy plaintext key.
  Future<void> setPassword(String plaintext) async {
    final trimmed = plaintext.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Admin password must not be empty');
    }
    final salt = SecurityService.generateSalt();
    final hash = SecurityService.hashPassword(trimmed, salt);
    await _settings.save(_saltKey, salt);
    await _settings.save(_hashKey, hash);
    await _settings.remove(_legacyKey);
    await AuditLog.record('admin_password_changed', level: AuditLevel.critical);
  }

  /// مفتاحُ حدِّ المحاولات. ثابتٌ لا يتبع مستخدماً: كلمةُ مرور المدير
  /// اعتمادٌ واحدٌ للتنصيبة كلِّها، فالحدُّ عليها لا على من يجرّبها.
  static const String throttleKey = 'admin_password';

  /// True while the admin password is locked out after repeated failures.
  /// الواجهةُ تقرؤها لتعرض مدّةَ الانتظار بدل «كلمة مرور خاطئة» المضلِّلة.
  static bool get isLockedOut => ServerLoginThrottle.isLockedOut(throttleKey);

  /// Verify a candidate password. Falls back to legacy plaintext comparison
  /// for installs that haven't migrated yet.
  ///
  /// ── حدُّ المحاولات ────────────────────────────────────────────────────
  ///
  /// 🔴 لم يكن هنا أيُّ حدّ. وعشرةُ مواضعَ في الواجهة تنادي هذه الدالّة —
  /// شاشةُ القفل، وتصعيدُ المسؤول، وإغلاقُ الوردية، وتعديلُ فاتورةٍ
  /// مقفلة — فكان بالإمكان تجريبُ آلافِ الكلمات في دقيقةٍ على الجهاز نفسِه
  /// بلا قفلٍ ولا أثر. وهذه الكلمةُ هي بوّابةُ تجاوز الصلاحيّات كلِّها.
  ///
  /// ويُستعمَل [ServerLoginThrottle] لا [LoginRateLimiter] عن قصد: الأخيرُ
  /// يُصفَّر عند كلِّ خروجٍ (`auth_providers`)، فكان الخروجُ والدخولُ يمسحان
  /// القفلَ — أي حدٌّ يُلتَفُّ عليه بضغطتَين. والأوّلُ معزولٌ لهذا السبب
  /// بالضبط، وتوثيقُه يقول ذلك.
  bool verify(String plaintext) {
    if (ServerLoginThrottle.isLockedOut(throttleKey)) {
      // ignore: discarded_futures — أثرٌ تدقيقيٌّ لا ننتظره.
      AuditLog.record('admin_password_locked_out', level: AuditLevel.critical);
      return false;
    }
    try {
      final ok = _verifyInner(plaintext);
      if (ok) {
        ServerLoginThrottle.recordSuccess(throttleKey);
      } else {
        ServerLoginThrottle.recordFailure(throttleKey);
      }
      return ok;
    } catch (e, st) {
      debugPrint('[ADMIN-AUTH] verify error: $e\n$st');
      return false;
    }
  }

  bool _verifyInner(String plaintext) {
    final hash = _settings.get(_hashKey);
    final salt = _settings.get(_saltKey);
    if (hash != null && hash.isNotEmpty && salt != null && salt.isNotEmpty) {
      return SecurityService.verifyPassword(plaintext.trim(), salt, hash);
    }
    // Legacy fallback — plaintext comparison during migration window
    final legacy = _settings.get(_legacyKey);
    if (legacy != null && legacy.isNotEmpty) {
      return legacy == plaintext.trim();
    }
    return false;
  }

  /// If a plaintext `admin_password` exists but no hash, hash and migrate it.
  /// Safe to call every boot: no-op when already hashed.
  Future<void> migrateIfNeeded() async {
    if (isConfigured) return;
    final legacy = _settings.get(_legacyKey);
    if (legacy == null || legacy.isEmpty) return;
    await setPassword(legacy);
    debugPrint('[ADMIN-AUTH] plaintext admin_password migrated to hash');
  }
}
