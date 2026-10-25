// سياسةُ الدخول دون اتصال لأجهزة الفروع (خطة 2026-10-24، P3 / B.1 + B.5).
//
// المقبولُ بلا اتصال: مستخدمٌ **سلّم الرئيسيُّ بصمتَه لهذا الجهاز** (طابعُ
// اعتمادٍ ببصمةٍ مطابقةٍ لما في الصفّ الآن) وما زال ضمن مدة السماح
// (`offline_login_grace_days`، الافتراضيّ 7 أيّام) محسوبةً من وقت الطابع —
// استلامِ البصمة أو آخرِ تأكيدٍ من الرئيسي — لا من آخر جلسة. الطوابع في
// [CredentialStampStore]؛ وهنا القرارُ وأعلى وقتٍ شوهد (مخزنان: التخزين الآمن
// والإعداد المحلي، يؤخذ الأكبر) ضدّ إرجاع ساعة الجهاز.
//
// القرارات: allowed · notProvisioned (لا طابع) · credentialChanged (طابعٌ ببصمةٍ
// أخرى) · rejectedByMain (قال الرئيسي «لا») · expired · clockRolledBack.
// وضعُ التطبيق ([OfflineLoginMode]): في `shadow` لا يُرفض إلا ما كان يُرفض قبل
// P3 (expired، clockRolledBack) + قرارُ الرئيسي الصريح؛ و`notProvisioned` و
// `credentialChanged` يُسجَّلان فقط. وفي `enforce` يُرفض الكلّ.
library;

import 'dart:convert';

import '../secure_storage_service.dart';
import 'credential_stamp_store.dart';

enum OfflineLoginMode {
  shadow,
  enforce;

  /// الإعدادُ المحليّ للجهاز (‏∈ kDeviceLocalSettingKeys). الافتراضيّ shadow.
  static const settingKey = 'offline_login_mode';

  static OfflineLoginMode parse(String? v) =>
      v?.trim().toLowerCase() == 'enforce' ? enforce : shadow;
}

enum OfflineLoginDecision {
  allowed,
  notProvisioned,
  credentialChanged,
  rejectedByMain,
  expired,
  clockRolledBack,
}

class OfflineLoginVerdict {
  const OfflineLoginVerdict(this.decision,
      {required this.graceDays, this.lastVerified, this.source});

  final OfflineLoginDecision decision;
  final int graceDays;
  final DateTime? lastVerified;
  final StampSource? source;

  bool get allowed => decision == OfflineLoginDecision.allowed;

  /// ما يُرفض في كلا الوضعين.
  bool get isHardReject =>
      decision == OfflineLoginDecision.expired ||
      decision == OfflineLoginDecision.clockRolledBack ||
      decision == OfflineLoginDecision.rejectedByMain;

  /// هل يُرفض فعلًا في [mode]؟
  bool rejectedIn(OfflineLoginMode mode) =>
      isHardReject ||
      (mode == OfflineLoginMode.enforce && !allowed);
}

/// مخزنُ أعلى وقتٍ شوهد (والطوابع القديمة) — واجهةٌ كي تُقاس السياسةُ بلا قناة منصّة.
abstract interface class OfflineLoginStore {
  Future<String?> read();
  Future<void> write(String json);
}

/// التخزين الآمن للمنصّة (‏مفتاح `offline_auth_verified_v1`).
class SecureOfflineLoginStore implements OfflineLoginStore {
  SecureOfflineLoginStore([SecureStorageService? storage])
      : _storage = storage ?? SecureStorageService();

  static const key = 'offline_auth_verified_v1';
  final SecureStorageService _storage;

  @override
  Future<String?> read() => _storage.read(key);

  @override
  Future<void> write(String json) => _storage.write(key, json);
}

class OfflineLoginPolicy {
  OfflineLoginPolicy({
    required OfflineLoginStore store,
    required Future<int?> Function() readGraceDays,
    required CredentialStampStore stamps,
    DateTime Function()? clock,
  })  : _store = store,
        _readGraceDays = readGraceDays,
        _stamps = stamps,
        _clock = clock ?? stamps.now;

  static const defaultGraceDays = 7;
  static const maxGraceDays = 365;
  static const clockTolerance = CredentialStampStore.clockTolerance;
  static const _maxSeenKey = '_max_seen';

  final OfflineLoginStore _store;
  final Future<int?> Function() _readGraceDays;
  final CredentialStampStore _stamps;
  final DateTime Function() _clock;

  DateTime now() => _clock();
  CredentialStampStore get stamps => _stamps;

  Future<Map<String, String>> _loadSecure() async {
    try {
      final raw = await _store.read();
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.value is String) '${e.key}': e.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  Future<int> _grace() async {
    final n = await _readGraceDays();
    if (n == null || n < 1) return defaultGraceDays;
    return n > maxGraceDays ? maxGraceDays : n;
  }

  /// الأكبر من المخزنَين (سقوطُ أحدهما لا يمسح الحماية).
  Future<DateTime?> _maxSeen(Map<String, String> secure) async {
    final a = DateTime.tryParse(secure[_maxSeenKey] ?? '');
    final b = await _stamps.readMaxSeen();
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  Future<void> _advanceMaxSeen(Map<String, String> secure, DateTime now) async {
    secure[_maxSeenKey] = now.toUtc().toIso8601String();
    try {
      await _store.write(jsonEncode(secure));
    } catch (_) {}
    await _stamps.writeMaxSeen(now);
  }

  /// الرئيسي أكّد الاعتمادَ الآن (جلسة خادم أو تغيير كلمة) — يبدأ مدّةً جديدة.
  Future<void> recordVerified(int userId, {required String passwordHash, DateTime? serverTime}) async {
    await _stamps.stampSession(userId, passwordHash, serverTime: serverTime);
    final secure = await _loadSecure();
    final now = _clock();
    final seen = await _maxSeen(secure);
    await _advanceMaxSeen(secure, seen != null && seen.isAfter(now) ? seen : now);
  }

  /// هل يُسمح لـ[userId] بالدخول والخادمُ غيرُ متاح؟ [passwordHash] = البصمة
  /// المحلّيّة الحاليّة للصفّ (تُقارَن ببصمة الطابع).
  Future<OfflineLoginVerdict> check(int userId, {required String passwordHash}) async {
    final secure = await _loadSecure();
    final now = _clock();
    final grace = await _grace();
    final seen = await _maxSeen(secure);

    OfflineLoginVerdict verdict(OfflineLoginDecision d, [CredentialStamp? s]) =>
        OfflineLoginVerdict(d, graceDays: grace, lastVerified: s?.at, source: s?.src);

    if (seen != null && now.isBefore(seen.subtract(clockTolerance))) {
      return verdict(OfflineLoginDecision.clockRolledBack);
    }
    // أعلى وقتٍ شوهد يتقدّم دائمًا (لا يتراجع).
    if (seen == null || now.isAfter(seen)) await _advanceMaxSeen(secure, now);

    CredentialStamp? stamp;
    try {
      stamp = await _stamps.read(userId);
      stamp ??= await _adoptLegacy(secure, userId, passwordHash);
    } catch (_) {
      // تعذّرت القراءة: لا سماحَ صامت — «غير مُسلَّم» (يُرفض في enforce).
      return verdict(OfflineLoginDecision.notProvisioned);
    }
    if (stamp == null) return verdict(OfflineLoginDecision.notProvisioned);
    if (stamp.at.isAfter(now.add(clockTolerance))) {
      return verdict(OfflineLoginDecision.clockRolledBack, stamp);
    }
    if (stamp.fp != credentialFingerprint(passwordHash)) {
      return verdict(OfflineLoginDecision.credentialChanged, stamp);
    }
    if (stamp.src == StampSource.rejected) {
      return verdict(OfflineLoginDecision.rejectedByMain, stamp);
    }
    if (now.difference(stamp.at) > Duration(days: grace)) {
      return verdict(OfflineLoginDecision.expired, stamp);
    }
    return verdict(OfflineLoginDecision.allowed, stamp);
  }

  /// طابعُ التخزين الآمن القديم لهذا المستخدم يُحوَّل مرّةً إلى طابع session
  /// ببصمته الحاليّة (التوافق مع ما قبل P3).
  Future<CredentialStamp?> _adoptLegacy(
      Map<String, String> secure, int userId, String passwordHash) async {
    final at = secure['$userId'];
    if (at == null) return null;
    await _stamps.adoptLegacyVerifications({'$userId': at}, {userId: passwordHash});
    return _stamps.read(userId);
  }
}
