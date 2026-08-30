import 'package:flutter/foundation.dart';

import '../data/repositories/settings_repository_cached.dart';
import 'api/server_login_throttle.dart';
import 'audit_log.dart';
import 'security_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ADMIN PASSWORD SERVICE — hashed storage for the invoice-deletion password
// ═══════════════════════════════════════════════════════════════════════════
//
// Storage format: Argon2id PHC string in `admin_password_hash`. The salt is
// embedded in the PHC string, so `admin_password_salt` is cleared on upgrade
// and only ever read to verify a *legacy* PBKDF2-SHA256 hash.
// Keys used:
//   - `admin_password_hash`  (Argon2id PHC, or legacy base64)
//   - `admin_password_salt`  (legacy base64 — empty/absent once upgraded)
//
// Legacy plaintext key `admin_password` is kept only during the migration
// window: `verify()` falls back to it when no hash is stored, and
// `migrateIfNeeded()` promotes it to hashed on first boot after upgrade.
//
// ── لماذا Argon2id هنا ────────────────────────────────────────────────────
//
// 🔴 كان الـKDF سلسلةَ SHA-256 مكرَّرةً — الملحُ يدخل الدورةَ الأولى وحدَها —
// رغم أنّ التعليقَ كان يسمّيها PBKDF2. وهذه الكلمةُ هي بوّابةُ تجاوزِ
// الصلاحيّات كلِّها، فكسرُها دون اتّصالٍ كان رخيصاً لمن بلغ القرص.
//
// والترقيةُ **شفّافة**: هاشٌ قديمٌ يُقبَل مرّةً واحدةً ثمّ يُعاد سكُّه
// Argon2id فوراً — فلا تنصيبةَ تنكسر ولا مشغّلَ يُعيد ضبطَ كلمته.
//
// ⚠️ ولزومُ الملحِ أُرخيَ عن قصد: كان `_verifyInner` يشترط ملحاً غيرَ فارغ،
// وArgon2id يُفرغه (الملحُ داخلَ الـPHC). فلولا هذا الإرخاءُ لسقط التحقّقُ
// إلى الفرع القديم بعد أوّلِ إعادةِ سكٍّ ورفض كلمةَ المرور الصحيحة.
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
    final hash = await SecurityService.hashPasswordArgon2(trimmed);
    await _settings.save(_hashKey, hash);
    // Argon2id embeds its salt in the PHC string — the legacy column would
    // only mislead a later reader into thinking it is still meaningful.
    await _settings.remove(_saltKey);
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
  Future<bool> verify(String plaintext) async {
    if (ServerLoginThrottle.isLockedOut(throttleKey)) {
      // ignore: discarded_futures — أثرٌ تدقيقيٌّ لا ننتظره.
      AuditLog.record('admin_password_locked_out', level: AuditLevel.critical);
      return false;
    }
    try {
      final ok = await _verifyInner(plaintext);
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

  Future<bool> _verifyInner(String plaintext) async {
    final hash = _settings.get(_hashKey);
    if (hash != null && hash.isNotEmpty) {
      // ⚠️ الملحُ لا يُشترَط: Argon2id يحمله داخلَ الـPHC ويُفرغ العمود.
      // واشتراطُه هنا كان سيرفض كلَّ كلمةٍ صحيحةٍ بعد أوّلِ إعادةِ سكّ.
      final salt = _settings.get(_saltKey) ?? '';
      final result = await SecurityService.verifyPasswordFull(
        plaintext.trim(),
        salt,
        hash,
      );
      if (result.verified && result.needsRehash) {
        await _rehashToArgon2(plaintext.trim());
      }
      return result.verified;
    }
    // Legacy fallback — plaintext comparison during migration window
    final legacy = _settings.get(_legacyKey);
    if (legacy != null && legacy.isNotEmpty) {
      return legacy == plaintext.trim();
    }
    return false;
  }

  /// Silently upgrade the stored hash PBKDF2-SHA256 → Argon2id after a
  /// successful verify against the old format.
  ///
  /// ⚠️ يبتلع أخطاءَه عن قصد: إخفاقُ الترقية يجب ألّا يُحوِّل كلمةَ مرورٍ
  /// **صحيحةً** إلى رفض. المستخدمُ دخل، والترقيةُ تُعاد في المرّة التالية.
  Future<void> _rehashToArgon2(String plaintext) async {
    try {
      final newHash = await SecurityService.hashPasswordArgon2(plaintext);
      await _settings.save(_hashKey, newHash);
      await _settings.remove(_saltKey);
      debugPrint('[ADMIN-AUTH] ✅ Argon2id rehash complete');
    } catch (e) {
      debugPrint('[ADMIN-AUTH] Argon2id rehash failed (kept legacy hash): $e');
    }
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
