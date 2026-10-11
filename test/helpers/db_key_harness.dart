// عُدّة اختبار مفتاح القاعدة (E-01): محاكي محرّك + تخزين وهمي + ملفات حقيقيّة
// في مجلدٍ مؤقّت. `flutter test` يحمّل sqlite3 العاديّ لا SQLCipher، فكلّ
// المنطق يُختبَر عبر الواجهة المجرّدة `SqlCipherEngine`.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ural_erp/services/db_key_manager.dart';
import 'package:ural_erp/services/db_key_migration_service.dart';
import 'package:ural_erp/services/db_key_types.dart';
import 'package:ural_erp/services/secret_store.dart';
import 'package:ural_erp/services/sqlcipher_engine.dart';

/// محاكي SQLCipher: الملفُّ = ترويسة `FAKEDB` + معرّف المفتاح الفعليّ +
/// user_version + عدّادات الجداول. «يفتح» إن طابق `effectiveId` المفتاح.
class FakeSqlCipherEngine implements SqlCipherEngine {
  /// نتيجةُ `checkpointTruncate`.
  bool checkpointOk = true;

  /// يُرمى عند أوّل `exportTo` (مرّة) لمحاكاة فشل التصدير.
  bool throwOnExport = false;

  /// تخريبُ المُصدَّر: `none` | `sameKeyAsSource` (لم يُشفَّر) | `dropRows` |
  /// `wrongUserVersion` | `corruptQuickCheck`.
  String tamper = 'none';

  /// عدّادُ الاستدعاءات.
  int exportCalls = 0;

  static Future<void> create(
    File f,
    DbKey key, {
    Map<String, int> tables = const {'settings': 3, 'users': 2},
    int userVersion = 42,
    bool quickCheckOk = true,
  }) async {
    await f.writeAsString(jsonEncode({
      'magic': 'FAKEDB',
      'key': key.effectiveId,
      'uv': userVersion,
      'tables': tables,
      'qc': quickCheckOk,
    }));
  }

  static Map<String, dynamic>? _read(File f) {
    try {
      if (!f.existsSync()) return null;
      final m = jsonDecode(f.readAsStringSync());
      return m is Map<String, dynamic> && m['magic'] == 'FAKEDB' ? m : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> canOpen(File db, DbKey key) async {
    final m = _read(db);
    return m != null && m['key'] == key.effectiveId;
  }

  @override
  Future<DbInspection> inspect(File db, DbKey key) async {
    final m = _read(db);
    if (m == null || m['key'] != key.effectiveId) {
      throw StateError('cannot open');
    }
    return DbInspection(
      quickCheckOk: m['qc'] == true,
      userVersion: (m['uv'] as num).toInt(),
      tableRowCounts: Map<String, int>.from(
          (m['tables'] as Map).map((k, v) => MapEntry(k as String, (v as num).toInt()))),
    );
  }

  @override
  Future<bool> checkpointTruncate(File db, DbKey key) async => checkpointOk;

  @override
  Future<void> exportTo(File src, DbKey srcKey, File dst, DbKey dstKey) async {
    exportCalls++;
    final m = _read(src);
    if (m == null || m['key'] != srcKey.effectiveId) {
      throw StateError('source does not open');
    }
    if (throwOnExport) throw StateError('export failed');
    final tables = Map<String, int>.from(
        (m['tables'] as Map).map((k, v) => MapEntry(k as String, (v as num).toInt())));
    var uv = (m['uv'] as num).toInt();
    var qc = true;
    var keyId = dstKey.effectiveId;
    switch (tamper) {
      case 'sameKeyAsSource':
        keyId = srcKey.effectiveId;
      case 'dropRows':
        tables.updateAll((k, v) => v > 0 ? v - 1 : v);
      case 'wrongUserVersion':
        uv = 0;
      case 'corruptQuickCheck':
        qc = false;
    }
    await dst.writeAsString(jsonEncode({
      'magic': 'FAKEDB',
      'key': keyId,
      'uv': uv,
      'tables': tables,
      'qc': qc,
    }));
  }
}

/// تخزينٌ يسلك سلوكَ ويندوز السيّئ: `null` بدل القيمة، أو رميٌ، أو بترٌ.
class FlakySecretStore implements SecretStore {
  FlakySecretStore(this.inner);
  final MemorySecretStore inner;

  /// تُرجع `null` لكلّ قراءة.
  bool readsReturnNull = false;

  /// ترمي في كلّ قراءة.
  bool readsThrow = false;

  /// ترمي في كلّ كتابة.
  bool writesThrow = false;

  /// تُسقط الكتابةَ بصمت (تُبلَع) — يكشفها «القراءة بعد الكتابة».
  bool writesSilentlyDropped = false;

  /// تقطع القيمةَ المكتوبة إلى نصفها (بترٌ غير ذرّيّ).
  bool writesTruncate = false;

  int writeCount = 0;

  @override
  Future<String?> read(String key) async {
    if (readsThrow) throw StateError('read failure');
    if (readsReturnNull) return null;
    return inner.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    writeCount++;
    if (writesThrow) throw StateError('write failure');
    if (writesSilentlyDropped) return;
    await inner.write(
        key, writesTruncate ? value.substring(0, value.length ~/ 2) : value);
  }

  @override
  Future<void> delete(String key) => inner.delete(key);
}

const String kLegacyHex =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class DbKeyHarness {
  DbKeyHarness({String dbName = 'picpos_unified.db'}) {
    dir = Directory.systemTemp.createTempSync('picpos_dbkey_');
    db = File('${dir.path}${Platform.pathSeparator}$dbName');
    backups = Directory('${dir.path}${Platform.pathSeparator}backups');
  }

  late final Directory dir;
  late final File db;
  late final Directory backups;
  final MemorySecretStore memory = MemorySecretStore();
  late final FlakySecretStore flaky = FlakySecretStore(memory);
  final FakeSqlCipherEngine engine = FakeSqlCipherEngine();
  final DbKey legacyKey = const DbKey(DbKeyKind.legacyDerived, kLegacyHex);
  String? legacyDerived = kLegacyHex;
  int _seed = 1;

  void dispose() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }

  List<int> _rnd(int n) {
    final r = Random(_seed++);
    return List<int>.generate(n, (_) => r.nextInt(256));
  }

  /// مديرٌ جديد = «إقلاعٌ جديد» على نفس التخزين والملفات.
  DbKeyManager manager({SecretStore? store}) => DbKeyManager(
        store: store ?? flaky,
        engine: engine,
        legacyDerive: () async => legacyDerived,
        randomBytes: _rnd,
        delay: (_) async {},
        recoveryMemoryKb: 64,
        recoveryIterations: 1,
      );

  DbKeyMigrationService service({
    String? processId,
    Future<void> Function(String step)? hook,
    DbKeyManager? mgr,
    Duration retention = const Duration(days: 30),
    DateTime Function()? now,
  }) {
    final m = mgr ?? manager();
    final s = DbKeyMigrationService(
      manager: m,
      backupsDir: backups,
      processId: processId ?? 'proc-${_seed++}',
      stepHook: hook,
      preMigrationRetention: retention,
    );
    m.beforeResolve = s.recoverInterrupted;
    return s;
  }

  Future<void> createLegacyDb({
    Map<String, int> tables = const {'settings': 3, 'users': 2},
    int userVersion = 42,
  }) =>
      FakeSqlCipherEngine.create(db, legacyKey,
          tables: tables, userVersion: userVersion);

  String get path => db.path;
  File sibling(String suffix) => File('${db.path}$suffix');
}

/// استثناءٌ يحاكي موتَ العمليّة عند خطوةٍ ما.
class SimulatedCrash implements Exception {
  SimulatedCrash(this.step);
  final String step;
  @override
  String toString() => 'SimulatedCrash($step)';
}
