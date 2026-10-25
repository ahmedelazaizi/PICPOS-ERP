// طوابعُ الاعتماد لكلّ مستخدمٍ على جهاز فرعٍ (خطة 2026-10-24، P3 / B.3 + B.5).
//
// الطابعُ يقول: «هذه البصمةُ بعينها وصلت أو أُكِّدت من النظام الرئيسي في الوقت
// `at`». يُخزَّن في إعدادٍ محليٍّ للجهاز (`offline_cred_stamps_v1` ∈
// kDeviceLocalSettingKeys — لا يُرفع ولا يُسحب) بلا أيّ تغيير في المخطط:
//
//   { "<userId>": { "at": "<ISO-8601 UTC>", "fp": "<16 hex>", "src": "<src>" } }
//
//   fp  = أوّل 16 خانة hex من sha256(passwordHash)  ← يربط الطابعَ بالبصمة: أيّ
//         تعديلٍ محليٍّ للبصمة (شفاء admin، إعادة تجزئة، قاعدة معدَّلة) يُبطله.
//   src = sync | session | upgrade | breakglass | rejected
//         rejected = قال الرئيسي «لا» لهذه البصمة مباشرةً: يبقى الرفضُ ساريًا
//         حتى لو انقطع الاتصال لاحقًا، إلى أن تصل بصمةٌ جديدةٌ أو يؤكّد الرئيسي.
//
// قواعد السلامة: كلُّ كتابةٍ تعديلٌ واحدٌ ذرّيٌّ لقيمةٍ واحدة (قراءة-تعديل-كتابة
// تحت قفلٍ) فالانقطاع لا يترك حالةً نصفيّة؛ والتخزين التالف يُقرأ فارغًا (أصرم
// اتجاهٍ ممكن)؛ وكتابةُ طابعٍ بنفس البصمة لا تُرجع `at` إلى الخلف.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../data/database/database.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../security_service.dart';

enum StampSource { sync, session, upgrade, breakglass, rejected }

class CredentialStamp {
  const CredentialStamp(this.at, this.fp, this.src);
  final DateTime at;
  final String fp;
  final StampSource src;

  @override
  bool operator ==(Object other) =>
      other is CredentialStamp &&
      other.at == at &&
      other.fp == fp &&
      other.src == src;
  @override
  int get hashCode => Object.hash(at, fp, src);

  Map<String, String> toJson() =>
      {'at': at.toUtc().toIso8601String(), 'fp': fp, 'src': src.name};

  static CredentialStamp? tryParse(Object? v) {
    if (v is! Map) return null;
    final at = DateTime.tryParse('${v['at']}');
    final fp = v['fp'];
    final src = StampSource.values.where((s) => s.name == v['src']);
    if (at == null || fp is! String || src.isEmpty) return null;
    return CredentialStamp(at, fp, src.first);
  }
}

/// أوّل 16 خانة hex من sha256 للبصمة.
String credentialFingerprint(String passwordHash) =>
    sha256.convert(utf8.encode(passwordHash)).toString().substring(0, 16);

/// بصمةٌ لا تُدخِل أحدًا: Argon2id بملحٍ غير فارغ هو علامة UnusableCredential
/// (صفوف Argon2id الحقيقيّة ملحُها فارغ).
bool isUnusableCredentialRow(String hash, String salt) =>
    hash.startsWith(r'$argon2') && salt.isNotEmpty;

/// منفذُ التخزين — قابلٌ للحقن كي تُختبر حالاتُ فشل الكتابة بلا قاعدة.
abstract interface class StampBacking {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class DbStampBacking implements StampBacking {
  DbStampBacking(this._db);
  final AppDatabase _db;
  @override
  Future<String?> read(String key) => _db.getSettingValue(key);
  @override
  Future<void> write(String key, String value) => _db.setSetting(key, value);
}

class CredentialStampStore {
  CredentialStampStore(this._backing, {DateTime Function()? clock, AppDatabase? db})
      : _clock = clock,
        _db = db;

  /// With [db] every stamp write first runs the one-time upgrade bootstrap: a
  /// user the device already trusted is blessed BEFORE the first new-style stamp
  /// exists, so no stamping sync can strand the users it did not re-deliver.
  factory CredentialStampStore.forDb(AppDatabase db, {DateTime Function()? clock}) =>
      CredentialStampStore(DbStampBacking(db), clock: clock, db: db);

  static const stampsKey = 'offline_cred_stamps_v1';
  static const bootstrappedKey = 'offline_cred_stamps_bootstrapped_v1';
  static const maxSeenKey = 'offline_login_max_seen_v1';
  static const clockTolerance = Duration(minutes: 10);

  /// ساعةُ الاختبار العامّة (الاستراتيجيّات تبني المخزن بنفسها).
  @visibleForTesting
  static DateTime Function()? debugClock;

  final StampBacking _backing;
  final DateTime Function()? _clock;
  final AppDatabase? _db;
  bool _bootChecked = false;

  Future<void> _ensureBootstrapped() async {
    final db = _db;
    if (db == null || _bootChecked) return;
    _bootChecked = true;
    try {
      await bootstrapIfNeeded(db);
    } catch (e) {
      _bootChecked = false;
      unawaited(DiagnosticLogger.log('AUTH', 'stamp bootstrap failed: $e'));
    }
  }

  // قفلٌ واحدٌ للعمليّة: قراءة-تعديل-كتابة متتابعة فلا يضيع طابعٌ بين مزامنةٍ ودخول.
  static Future<void> _tail = Future<void>.value();
  static Future<T> _locked<T>(Future<T> Function() body) {
    final run = _tail.then((_) => body());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  DateTime now() => (_clock ?? debugClock ?? DateTime.now)();

  /// وقتُ الخادم يُعتمد فقط إن اقترب من ساعة الجهاز (≤ التسامح)، وإلا فساعةُ
  /// الجهاز: انحرافُ ساعةٍ كبير لا يجوز أن يقفل الكاشير ولا أن يمدّد مدّته.
  DateTime _at(DateTime? serverTime) {
    final n = now();
    if (serverTime != null && serverTime.difference(n).abs() <= clockTolerance) {
      return serverTime;
    }
    return n;
  }

  Future<Map<int, CredentialStamp>> _load() async {
    try {
      final raw = await _backing.read(stampsKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <int, CredentialStamp>{};
      for (final e in decoded.entries) {
        final id = int.tryParse('${e.key}');
        final st = CredentialStamp.tryParse(e.value);
        if (id != null && st != null) out[id] = st;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(Map<int, CredentialStamp> m) => _backing.write(
        stampsKey,
        jsonEncode({for (final e in m.entries) '${e.key}': e.value.toJson()}),
      );

  /// القراءة تُرمي إن فشل التخزين نفسُه (يميّز «لا طابع» عن «تعذّرت القراءة»).
  Future<CredentialStamp?> read(int userId) async {
    final raw = await _backing.read(stampsKey);
    if (raw == null || raw.isEmpty) return null;
    return (await _load())[userId];
  }

  Future<Map<int, CredentialStamp>> readAll() => _load();

  Future<void> _put(int userId, String hash, StampSource src, DateTime at) =>
      _locked(() async {
        final m = await _load();
        final fp = credentialFingerprint(hash);
        final old = m[userId];
        if (old != null &&
            old.fp == fp &&
            old.src != StampSource.rejected &&
            src != StampSource.breakglass &&
            old.at.isAfter(at)) {
          return; // لا رجوعَ بـ`at` إلى الخلف لنفس البصمة
        }
        m[userId] = CredentialStamp(at.toUtc(), fp, src);
        await _save(m);
      });

  /// بصمةٌ سلّمها الرئيسي فعلًا (استجابةٌ سلّمت الاعتماد).
  Future<void> stampFromSync(int userId, String passwordHash, {DateTime? serverTime}) async {
    await _ensureBootstrapped();
    await _put(userId, passwordHash, StampSource.sync, _at(serverTime));
  }

  /// الرئيسي قبل هذا الاعتماد الآن (جلسةٌ أو تغيير كلمة).
  Future<void> stampSession(int userId, String passwordHash, {DateTime? serverTime}) async {
    await _ensureBootstrapped();
    await _put(userId, passwordHash, StampSource.session, _at(serverTime));
  }

  /// قال الرئيسي «لا» لهذه البصمة: رفضٌ يبقى بلا اتصال.
  Future<void> markRejected(int userId, String passwordHash) => _locked(() async {
        final m = await _load();
        m[userId] = CredentialStamp(
            now().toUtc(), credentialFingerprint(passwordHash), StampSource.rejected);
        await _save(m);
      });

  Future<void> revoke(int userId) => _locked(() async {
        final m = await _load();
        if (m.remove(userId) != null) await _save(m);
      });

  /// لقطةٌ كاملةٌ سلّمت الاعتماد: كلُّ مستخدمٍ محليٍّ غائبٌ عنها يفقد طابعه
  /// (يُحذف الطابع لا الصفّ: FK الفواتير).
  Future<int> reconcileSnapshot(Set<int> deliveredIds, Iterable<int> localIds) =>
      _locked(() async {
        final m = await _load();
        var removed = 0;
        for (final id in localIds) {
          if (!deliveredIds.contains(id) && m.remove(id) != null) removed++;
        }
        if (removed > 0) await _save(m);
        return removed;
      });

  // ── أعلى وقتٍ شوهد (المخزن الثاني؛ الأوّل في التخزين الآمن) ─────────────────
  Future<DateTime?> readMaxSeen() async {
    try {
      final s = await _backing.read(maxSeenKey);
      return s == null ? null : DateTime.tryParse(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeMaxSeen(DateTime t) async {
    try {
      await _backing.write(maxSeenKey, t.toUtc().toIso8601String());
    } catch (_) {}
  }

  // ── الترحيل عند الترقية (B.5) ───────────────────────────────────────────────
  /// أوّل تشغيلٍ بعد الترقية على عميلٍ/مرآة: يُختم كلُّ مستخدمٍ نشطٍ غير مقفولٍ
  /// بصمتُه صالحة (src=upgrade، at=الآن) فلا يُقفل أحدٌ قبل انقضاء المدة. لا
  /// يُختم: بصمةٌ غير قابلةٍ للاستعمال، ولا من عليه تغيير كلمةٍ مؤقّتة، ولا
  /// `admin` ما زالت كلمتُه الافتراضيّة. idempotent: يملأ الناقص فقط ولا يمسّ
  /// طابعًا موجودًا؛ والعلمُ يُكتب أخيرًا فانقطاعٌ في المنتصف يُعاد بلا ضرر.
  Future<int> bootstrapIfNeeded(AppDatabase db) async {
    try {
      if (await _backing.read(bootstrappedKey) == 'true') return 0;
    } catch (_) {
      return 0;
    }
    final rows = (await db.select(db.users).get())
        .where((u) => u.isActive && !u.isLocked);
    final candidates = <User>[];
    for (final u in rows) {
      if (u.passwordHash.isEmpty ||
          isUnusableCredentialRow(u.passwordHash, u.passwordSalt) ||
          u.forcePasswordChange) {
        continue;
      }
      if (u.username == 'admin') {
        final r = await SecurityService.verifyPasswordFull(
            'admin', u.passwordSalt, u.passwordHash);
        if (r.verified) continue; // admin/admin المزروع لا يُختم
      }
      candidates.add(u);
    }
    final stamped = await _locked(() async {
      final m = await _load();
      var n = 0;
      final at = now().toUtc();
      for (final u in candidates) {
        final fp = credentialFingerprint(u.passwordHash);
        final old = m[u.id];
        if (old != null && old.fp == fp) continue;
        m[u.id] = CredentialStamp(at, fp, StampSource.upgrade);
        n++;
      }
      if (n > 0) await _save(m);
      return n;
    });
    await _backing.write(bootstrappedKey, 'true');
    unawaited(DiagnosticLogger.log(
        'AUTH', 'credential stamps bootstrapped at upgrade: $stamped user(s)'));
    return stamped;
  }

  /// تحويل `offline_auth_verified_v1` القديم (userId → ISO في التخزين الآمن) إلى
  /// طوابع session ببصمة المستخدم الحاليّة، مرّةً واحدة لكلّ مستخدم.
  Future<int> adoptLegacyVerifications(
      Map<String, String> legacy, Map<int, String> currentHashByUser) =>
      _locked(() async {
        final m = await _load();
        var n = 0;
        for (final e in legacy.entries) {
          final id = int.tryParse(e.key);
          final at = DateTime.tryParse(e.value);
          final hash = id == null ? null : currentHashByUser[id];
          if (id == null || at == null || hash == null || hash.isEmpty) continue;
          final fp = credentialFingerprint(hash);
          final old = m[id];
          if (old != null && old.fp == fp && !old.at.isBefore(at)) continue;
          m[id] = CredentialStamp(at.toUtc(), fp, StampSource.session);
          n++;
        }
        if (n > 0) await _save(m);
        return n;
      });
}
