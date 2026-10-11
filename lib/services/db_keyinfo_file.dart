import 'dart:convert';
import 'dart:io';

import 'db_key_types.dart';

/// تقدّمُ الترحيل داخل keyinfo (علمُ التقدّم). **ليس مصدرَ الحقيقة** —
/// المصدرُ أيُّ مفتاحٍ يفتح أيَّ ملف؛ العلمُ للعرض ولتمييز «الإقلاع التالي».
class KeyMigrationProgress {
  const KeyMigrationProgress({
    required this.state,
    required this.newFingerprint,
    required this.oldKind,
    required this.startedAt,
    this.backup,
    this.committedBy,
    this.confirmedAt,
  });

  /// keyStored | backedUp | exported | verified | swapped |
  /// committedPendingConfirm | done
  final String state;
  final String newFingerprint;
  final String oldKind;
  final String startedAt;
  final String? backup;

  /// معرّفُ العمليّة التي التزمت — M8 لا يُنفَّذ إلّا من عمليّةٍ مختلفة.
  final String? committedBy;
  final String? confirmedAt;

  KeyMigrationProgress copyWith({
    String? state,
    String? backup,
    String? committedBy,
    String? confirmedAt,
  }) =>
      KeyMigrationProgress(
        state: state ?? this.state,
        newFingerprint: newFingerprint,
        oldKind: oldKind,
        startedAt: startedAt,
        backup: backup ?? this.backup,
        committedBy: committedBy ?? this.committedBy,
        confirmedAt: confirmedAt ?? this.confirmedAt,
      );

  Map<String, dynamic> toJson() => {
        'state': state,
        'newFp': newFingerprint,
        'oldKind': oldKind,
        'startedAt': startedAt,
        if (backup != null) 'backup': backup,
        if (committedBy != null) 'committedBy': committedBy,
        if (confirmedAt != null) 'confirmedAt': confirmedAt,
      };

  static KeyMigrationProgress? fromJson(Object? j) {
    if (j is! Map) return null;
    final state = j['state'];
    final fp = j['newFp'];
    final old = j['oldKind'];
    final started = j['startedAt'];
    if (state is! String || fp is! String || old is! String) return null;
    return KeyMigrationProgress(
      state: state,
      newFingerprint: fp,
      oldKind: old,
      startedAt: started is String ? started : '',
      backup: j['backup'] as String?,
      committedBy: j['committedBy'] as String?,
      confirmedAt: j['confirmedAt'] as String?,
    );
  }
}

/// سجلُّ الحالة غير السرّيّ بجانب القاعدة: `<db>.keyinfo.json`.
class KeyInfo {
  const KeyInfo({
    required this.kind,
    required this.createdAt,
    this.fingerprint,
    this.migratedFrom,
    this.recoveryEnvelope,
    this.migration,
    this.version = 1,
  });

  final int version;
  final DbKeyKind kind;
  final String? fingerprint;
  final String createdAt;

  /// `legacyDerived` | `legacyFallback` | null.
  final String? migratedFrom;
  final Map<String, dynamic>? recoveryEnvelope;
  final KeyMigrationProgress? migration;

  /// «القاعدةُ مرحَّلةٌ» كما يراها keyinfo (أساسُ ق-8).
  bool get claimsMigrated => kind == DbKeyKind.rawV2;

  KeyInfo copyWith({
    DbKeyKind? kind,
    String? fingerprint,
    String? migratedFrom,
    Map<String, dynamic>? recoveryEnvelope,
    KeyMigrationProgress? migration,
    bool clearMigration = false,
  }) =>
      KeyInfo(
        version: version,
        kind: kind ?? this.kind,
        fingerprint: fingerprint ?? this.fingerprint,
        createdAt: createdAt,
        migratedFrom: migratedFrom ?? this.migratedFrom,
        recoveryEnvelope: recoveryEnvelope ?? this.recoveryEnvelope,
        migration: clearMigration ? null : (migration ?? this.migration),
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'kind': kind.name,
        if (fingerprint != null) 'fingerprint': fingerprint,
        'createdAt': createdAt,
        'migratedFrom': migratedFrom,
        if (recoveryEnvelope != null) 'recoveryEnvelope': recoveryEnvelope,
        if (migration != null) 'migration': migration!.toJson(),
      };

  static KeyInfo? fromJson(Object? j) {
    if (j is! Map) return null;
    final kindName = j['kind'];
    DbKeyKind? kind;
    for (final k in DbKeyKind.values) {
      if (k.name == kindName) kind = k;
    }
    if (kind == null) return null;
    final env = j['recoveryEnvelope'];
    return KeyInfo(
      version: (j['version'] as num?)?.toInt() ?? 1,
      kind: kind,
      fingerprint: j['fingerprint'] as String?,
      createdAt: (j['createdAt'] as String?) ?? '',
      migratedFrom: j['migratedFrom'] as String?,
      recoveryEnvelope:
          env is Map ? Map<String, dynamic>.from(env) : null,
      migration: KeyMigrationProgress.fromJson(j['migration']),
    );
  }
}

/// قراءةُ/كتابةُ `<db>.keyinfo.json` — الكتابةُ إلى `.tmp` ثم `rename`.
class KeyInfoFile {
  KeyInfoFile._();

  static File of(File db) => File('${db.path}.keyinfo.json');

  /// `null` إن غاب الملفُّ أو تلف (التالفُ يُعامَل كغائبٍ ولا يُرمى).
  static Future<KeyInfo?> read(File db) async {
    try {
      final f = of(db);
      if (!await f.exists()) return null;
      return KeyInfo.fromJson(jsonDecode(await f.readAsString()));
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(File db, KeyInfo info) async {
    final target = of(db);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(info.toJson()),
      flush: true,
    );
    await tmp.rename(target.path);
  }
}
