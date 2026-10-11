import 'dart:convert';

import 'package:crypto/crypto.dart';

/// نوعُ مفتاح القاعدة — يحدّد **صيغة** `PRAGMA key` فلا يُمرَّر نصٌّ عارٍ.
enum DbKeyKind {
  /// المشتقّ القديم من معرّف الجهاز (عبارةُ مرور نصّيّة، PBKDF2 داخل SQLCipher).
  legacyDerived,

  /// المفتاحُ الاحتياطيّ القديم العشوائيّ (عبارةُ مرور نصّيّة أيضًا).
  legacyFallback,

  /// المفتاح الجديد: 256-بت عشوائيّ خام `x'..'`.
  rawV2,

  /// كلمةُ مرورٍ للتصدير المحمول (عبارةُ مرور).
  passphrase;

  bool get isLegacy => this == legacyDerived || this == legacyFallback;
}

final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

bool isValidRawKeyHex(String? s) => s != null && _hex64.hasMatch(s);

List<int> hexToBytes(String hex) => [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];

String bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// مفتاحُ قاعدةٍ + نوعُه. لا يطبع قيمتَه أبدًا.
class DbKey {
  const DbKey(this.kind, this.value);

  /// مفتاحٌ خام جديد؛ يتحقّق من الشكل `^[0-9a-f]{64}$`.
  factory DbKey.raw(String hex) {
    if (!isValidRawKeyHex(hex)) {
      throw ArgumentError('raw db key must be 64 lowercase hex chars');
    }
    return DbKey(DbKeyKind.rawV2, hex);
  }

  final DbKeyKind kind;
  final String value;

  /// معرّفٌ فعليٌّ للمفتاح كما يراه SQLCipher: الخام ≠ العبارة النصّيّة ولو
  /// تطابقت الحروف. المفتاحان القديمان يشتركان في صيغة العبارة.
  String get effectiveId => kind == DbKeyKind.rawV2 ? 'x:$value' : 'p:$value';

  /// الحرفيّةُ بعد `PRAGMA key =` / `ATTACH … KEY`. آمنةٌ من الحقن: الخام
  /// مُتحقَّقٌ من شكله، والعبارةُ تُضاعَف فيها علامةُ الاقتباس المفردة.
  String get pragmaLiteral {
    if (kind == DbKeyKind.rawV2) return "\"x'$value'\"";
    return "'${value.replaceAll("'", "''")}'";
  }

  /// بصمةٌ غير سرّيّة: أوّل 8 بايت من `HMAC-SHA256(key, "picpos-dbkey-fp-v1")`.
  String get fingerprint => fingerprintOf(this);

  static String fingerprintOf(DbKey key) {
    final keyBytes = key.kind == DbKeyKind.rawV2
        ? hexToBytes(key.value)
        : utf8.encode(key.value);
    final mac = Hmac(sha256, keyBytes)
        .convert(utf8.encode('picpos-dbkey-fp-v1'))
        .bytes;
    return bytesToHex(mac.sublist(0, 8));
  }

  @override
  bool operator ==(Object other) =>
      other is DbKey && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => 'DbKey($kind, fp=$fingerprint)';
}

/// أين وُجد المفتاحُ الذي فتح القاعدة.
enum DbKeySource {
  freshInstall,
  primarySlot,
  shadowSlot,
  legacyDerived,
  legacyFallback,
  recoveryCode,
}

enum DbKeyUnavailableReason {
  /// التخزينُ الآمن رمى/تعذّر بعد إعادة المحاولة.
  storeFailure,

  /// القاعدةُ مرحَّلةٌ (keyinfo) لكنّ مفتاحَها غائبٌ عن التخزين الآمن لهذا
  /// الحساب — الحالةُ الكلاسيكيّة: حسابُ ويندوز آخر أو اعتمادٌ محذوف.
  keyMissing,

  /// المفتاحُ موجودٌ في التخزين لكنّه لا يفتح الملف.
  wrongKey,

  /// قاعدةٌ نصٌّ صريح (`SQLite format 3`) — خارج نطاق هذا الترحيل.
  plaintextDatabase,

  /// لا مرشّحَ يفتح الملف ولا معلومةَ كافيةً لتصنيف السبب.
  noCandidateOpens,

  /// الملفُّ غائبٌ لكنّ keyinfo يقول إنّ قاعدةً مرحَّلةً كانت هنا ولا مفتاحَ.
  databaseMissingKeyinfoPresent,

  /// رمزُ استردادٍ خاطئ أو غلافٌ تالف أو مفتاحٌ مفكوكٌ لا يفتح الملف.
  recoveryFailed,
}

/// نتيجةُ تحديد مفتاح الفتح. **لا توليدَ لمفتاحٍ جديدٍ في أيٍّ من حالات
/// [DbKeyUnavailable]**.
sealed class DbKeyResolution {
  const DbKeyResolution();
}

class DbKeyReady extends DbKeyResolution {
  const DbKeyReady(this.key, this.source);

  final DbKey key;
  final DbKeySource source;

  /// القاعدةُ ما زالت بالمفتاح القديم ⇒ تنتظر استدعاءً صريحًا لـ
  /// `DbKeyMigrationService.migrate()` (ق-7: لا ترحيلَ تلقائيًّا).
  bool get needsMigration => key.kind.isLegacy;
}

class DbKeyUnavailable extends DbKeyResolution {
  const DbKeyUnavailable(
    this.reason, {
    this.canRecoverWithCode = false,
    this.preMigrationCopyAvailable = false,
    this.detail,
  });

  final DbKeyUnavailableReason reason;

  /// keyinfo يحوي غلافَ استرداد ⇒ تصلح `DbKeyManager.recoverWithCode`.
  final bool canRecoverWithCode;

  /// نسخةُ `.pre-v2` ما زالت بجانب القاعدة ⇒ يصلح
  /// `DbKeyMigrationService.rollbackToPreMigration`.
  final bool preMigrationCopyAvailable;
  final String? detail;

  @override
  String toString() => 'DbKeyUnavailable($reason, code=$canRecoverWithCode, '
      'preV2=$preMigrationCopyAvailable${detail == null ? '' : ', $detail'})';
}

/// فشلٌ في كتابة المفتاح أو إعادة قراءته ومقارنته.
class DbKeyStoreException implements Exception {
  const DbKeyStoreException(this.message);
  final String message;
  @override
  String toString() => 'DbKeyStoreException: $message';
}
