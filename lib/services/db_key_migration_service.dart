import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;

import 'db_key_manager.dart';
import 'db_key_names.dart';
import 'db_key_types.dart';
import 'db_keyinfo_file.dart';
import 'sqlcipher_engine.dart';

enum DbKeyMigrationStatus {
  /// رُحِّلت القاعدةُ وبانتظار تأكيد الإقلاع التالي (M8).
  migrated,

  /// القاعدةُ بالمفتاح الجديد أصلًا.
  alreadyMigrated,

  /// لم يبدأ الترحيلُ لسببٍ مسبقٍ (M0/M1/M2/M3): الأصلُ لم يُمسّ.
  skipped,

  /// بدأ وفشل: الأصلُ سليمٌ ويفتحه المفتاحُ القديم.
  failed,

  /// عمليّةٌ أخرى تحمل القفلَ الحصريّ.
  busy,
}

class DbKeyMigrationResult {
  const DbKeyMigrationResult(this.status, [this.detail]);
  final DbKeyMigrationStatus status;
  final String? detail;

  bool get ok =>
      status == DbKeyMigrationStatus.migrated ||
      status == DbKeyMigrationStatus.alreadyMigrated;

  @override
  String toString() => 'DbKeyMigrationResult($status${detail == null ? '' : ', $detail'})';
}

class _Abort implements Exception {
  _Abort(this.status, this.detail);
  final DbKeyMigrationStatus status;
  final String detail;
}

final String _defaultProcessId = () {
  final r = Random.secure();
  return bytesToHex(List<int>.generate(8, (_) => r.nextInt(256)));
}();

/// ترحيلُ قاعدةٍ قائمةٍ من المفتاح المشتقّ القديم إلى المفتاح العشوائيّ
/// (E-01 §2) — **صريحٌ فقط**: لا شيءَ هنا يُستدعى تلقائيًّا (ق-7).
///
/// مصدرُ الحقيقة عند أيّ انقطاعٍ هو «أيُّ مفتاحٍ يفتح أيَّ ملف» لا علمُ
/// التقدّم في keyinfo. [recoverInterrupted] ينفّذ جدولَ §2.4 كاملًا.
class DbKeyMigrationService {
  DbKeyMigrationService({
    required this.manager,
    required this.backupsDir,
    String? processId,
    this.stepHook,
    this.freeSpaceBytes,
    this.preMigrationRetention = const Duration(days: 30),
  }) : processId = processId ?? _defaultProcessId;

  /// تركيبةٌ إنتاجيّة؛ [backupsDir] = `Documents/backups`.
  factory DbKeyMigrationService.production(Directory backupsDir) {
    final m = DbKeyManager.production();
    final s = DbKeyMigrationService(manager: m, backupsDir: backupsDir);
    m.beforeResolve = s.recoverInterrupted;
    return s;
  }

  final DbKeyManager manager;
  final Directory backupsDir;

  /// يميّز «العمليّة الحاليّة» عن «الإقلاع التالي» (M8 لا يجري في العمليّة
  /// نفسِها التي التزمت).
  final String processId;

  /// حقنُ انقطاعٍ للاختبار: يُستدعى بعد كلّ خطوةٍ بعد أن تُسجَّل حالتُها.
  final Future<void> Function(String step)? stepHook;

  /// المساحةُ الحرّة بالبايت للمجلد، أو `null` = غير معروفة (لا فحص).
  final Future<int?> Function(Directory dir)? freeSpaceBytes;
  final Duration preMigrationRetention;

  SqlCipherEngine get _engine => manager.engine;

  static const stepKeyStored = 'M1.keyStored';
  static const stepCheckpointed = 'M2.checkpointed';
  static const stepBackedUp = 'M3.backedUp';
  static const stepExported = 'M4.exported';
  static const stepVerified = 'M5.verified';
  static const stepOldRenamed = 'M6a.oldRenamed';
  static const stepSwapped = 'M6.swapped';
  static const stepCommitted = 'M7.committed';

  Directory get preMigrationDir =>
      Directory(p.join(backupsDir.path, 'key-migration'));

  // ───────────────────────── ملفات مساندة ─────────────────────────

  File _v2New(File db) => File('${db.path}.v2-new');
  File _preV2(File db) => File('${db.path}.pre-v2');

  String _stamp() => manager
      .now()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');

  Future<void> _deleteWithSidecars(File f) async {
    for (final path in [f.path, '${f.path}-wal', '${f.path}-shm']) {
      final x = File(path);
      if (await x.exists()) await x.delete();
    }
  }

  Future<File> _uniqueSibling(File base, String suffix) async {
    var candidate = File('${base.path}$suffix');
    var i = 0;
    while (await candidate.exists()) {
      candidate = File('${base.path}$suffix-${++i}');
    }
    return candidate;
  }

  Future<RandomAccessFile?> _acquireLock(File db) async {
    RandomAccessFile? raf;
    try {
      if (!await db.parent.exists()) return null;
      raf = await File('${db.path}.key-migration.lock')
          .open(mode: FileMode.write);
      await raf.lock(FileLock.exclusive);
      return raf;
    } on FileSystemException {
      await raf?.close();
      return null;
    }
  }

  Future<void> _release(RandomAccessFile raf) async {
    try {
      await raf.unlock();
    } catch (_) {}
    await raf.close();
  }

  Future<T> _guard<T>(
    DbKeyMigrationStatus status,
    String what,
    Future<T> Function() body,
  ) async {
    try {
      return await body();
    } on _Abort {
      rethrow;
    } catch (e) {
      throw _Abort(status, '$what: ${e.runtimeType}');
    }
  }

  Future<DbKey?> _legacyOpens(File f) async {
    for (final k in await manager.legacyCandidates()) {
      if (await _engine.canOpen(f, k)) return k;
    }
    return null;
  }

  Future<DbKey?> _newKeyOpens(File f, StoredKeys s) async {
    for (final hex in {s.primary, s.shadow}) {
      if (hex == null) continue;
      final k = DbKey.raw(hex);
      if (await _engine.canOpen(f, k)) return k;
    }
    return null;
  }

  Future<void> _setState(
    File db,
    String state, {
    String? backup,
    String? committedBy,
    String? confirmedAt,
  }) async {
    final info = await KeyInfoFile.read(db);
    final m = info?.migration;
    if (info == null || m == null) return;
    await KeyInfoFile.write(
      db,
      info.copyWith(
        migration: m.copyWith(
          state: state,
          backup: backup,
          committedBy: committedBy,
          confirmedAt: confirmedAt,
        ),
      ),
    );
  }

  // ───────────────────────── migrate ─────────────────────────

  /// يرحّل القاعدةَ صراحةً. لا يرمي لفشلٍ متوقَّع (انظر [DbKeyMigrationStatus]);
  /// أيُّ فشلٍ قبل M6 يترك الأصلَ كما هو.
  Future<DbKeyMigrationResult> migrate(File dbFile) async {
    final lock = await _acquireLock(dbFile);
    if (lock == null) {
      return const DbKeyMigrationResult(
          DbKeyMigrationStatus.busy, 'migration lock held elsewhere');
    }
    try {
      await _recover(dbFile);
      return await _migrateLocked(dbFile);
    } on _Abort catch (a) {
      debugPrint('[DBKEY] migration ${a.status.name}: ${a.detail}');
      return DbKeyMigrationResult(a.status, a.detail);
    } on NotSqlCipherException {
      return const DbKeyMigrationResult(
          DbKeyMigrationStatus.skipped, 'engine is not SQLCipher');
    } finally {
      await _release(lock);
    }
  }

  Future<DbKeyMigrationResult> _migrateLocked(File db) async {
    final name = DbKeyManager.dbNameOf(db);
    const skip = DbKeyMigrationStatus.skipped;
    const fail = DbKeyMigrationStatus.failed;

    // ── M0: شروطٌ مسبقة ──
    if (!await db.exists()) throw _Abort(skip, 'database file missing');
    if (await File('${db.path}.restore-pending').exists()) {
      throw _Abort(skip, 'a restore is pending');
    }
    final opening = await manager.findOpening(db, dbName: name);
    if (opening == null) throw _Abort(skip, 'no candidate key opens the file');
    if (opening.key.kind == DbKeyKind.rawV2) {
      return const DbKeyMigrationResult(DbKeyMigrationStatus.alreadyMigrated);
    }
    final oldKey = opening.key;
    final free = freeSpaceBytes;
    if (free != null) {
      final avail = await free(db.parent);
      var size = await db.length();
      final wal = File('${db.path}-wal');
      if (await wal.exists()) size += await wal.length();
      if (avail != null && avail < (size * 2.2).ceil()) {
        throw _Abort(skip, 'insufficient free space');
      }
    }
    await _guard(skip, 'secure storage probe', () async {
      final probeKey = DbKeyNames.probe(name);
      final probe = manager.generateKeyHex();
      await manager.store.write(probeKey, probe);
      final back = await manager.store.read(probeKey);
      await manager.store.delete(probeKey);
      if (back != probe) throw const DbKeyStoreException('probe mismatch');
    });

    // ── M1: المفتاح الجديد (يُعاد استعمالُه إن وُجد) ──
    final newKey =
        await _guard(skip, 'key storage', () => manager.ensureStoredKey(name));
    final prior = await KeyInfoFile.read(db);
    final env = await _guard(skip, 'recovery envelope', () async {
      final sameKey = prior != null &&
          (prior.fingerprint == newKey.fingerprint ||
              prior.migration?.newFingerprint == newKey.fingerprint);
      if (sameKey && prior.recoveryEnvelope != null) {
        return prior.recoveryEnvelope!;
      }
      return manager.createRecovery(name, newKey);
    });
    final startedAt = manager.now().toIso8601String();
    await _guard(skip, 'keyinfo write', () async {
      await KeyInfoFile.write(
        db,
        KeyInfo(
          // الحقيقةُ الآن: الملفُّ بالمفتاح القديم مهما قال keyinfo سابقًا.
          kind: oldKey.kind,
          createdAt: prior?.createdAt ?? startedAt,
          migratedFrom: prior?.migratedFrom,
          recoveryEnvelope: env,
          migration: KeyMigrationProgress(
            state: 'keyStored',
            newFingerprint: newKey.fingerprint,
            oldKind: oldKey.kind.name,
            startedAt: startedAt,
          ),
        ),
      );
    });
    await stepHook?.call(stepKeyStored);

    // ── M2: تفريغ WAL ──
    final flushed = await _guard(
        skip, 'checkpoint', () => _engine.checkpointTruncate(db, oldKey));
    if (!flushed) throw _Abort(skip, 'WAL checkpoint incomplete (busy)');
    await stepHook?.call(stepCheckpointed);

    // ── M3: نسخةٌ احتياطيّة مسبقة (مجلدٌ فرعيّ لا يمسّه تنظيفُ الـ7) ──
    final backup = await _guard(skip, 'pre-migration backup', () async {
      await preMigrationDir.create(recursive: true);
      var b = File(p.join(preMigrationDir.path, '$name.pre-v2-${_stamp()}.db'));
      var i = 0;
      while (await b.exists()) {
        b = File(p.join(
            preMigrationDir.path, '$name.pre-v2-${_stamp()}-${++i}.db'));
      }
      await db.copy(b.path);
      if (await b.length() != await db.length()) {
        await b.delete();
        throw const FileSystemException('backup size mismatch');
      }
      await KeyInfoFile.write(
        b,
        KeyInfo(
          kind: oldKey.kind,
          createdAt: startedAt,
          migration: null,
        ),
      );
      return b;
    });
    await _setState(db, 'backedUp', backup: backup.path);
    await stepHook?.call(stepBackedUp);

    // ── M4: التصدير إلى ملفٍّ جديد ──
    final v2 = _v2New(db);
    await _guard(fail, 'export', () async {
      try {
        await _deleteWithSidecars(v2);
        await _engine.exportTo(db, oldKey, v2, newKey);
      } catch (_) {
        await _deleteWithSidecars(v2);
        rethrow;
      }
    });
    await _setState(db, 'exported');
    await stepHook?.call(stepExported);

    // ── M5: التحقق بمقبضٍ منفصل ──
    await _guard(fail, 'verification', () async {
      try {
        if (!await _engine.canOpen(v2, newKey)) {
          throw const FormatException('new key does not open the export');
        }
        if (await _engine.canOpen(v2, oldKey)) {
          throw const FormatException('old key opens the export (not encrypted)');
        }
        final a = await _engine.inspect(db, oldKey);
        final b = await _engine.inspect(v2, newKey);
        if (!b.quickCheckOk) throw const FormatException('quick_check failed');
        if (!a.matches(b)) {
          throw const FormatException('row counts/user_version differ');
        }
      } catch (_) {
        await _deleteWithSidecars(v2);
        rethrow;
      }
    });
    await _setState(db, 'verified');
    await stepHook?.call(stepVerified);

    // ── M6: التبديلُ الذرّيّ (نقلان متعاقبان؛ §2.4 يغطّي الانقطاع بينهما) ──
    final pre = _preV2(db);
    await _guard(fail, 'swap', () async {
      if (await pre.exists()) {
        await pre.rename((await _uniqueSibling(pre, '.stale')).path);
      }
      await db.rename(pre.path);
    });
    await stepHook?.call(stepOldRenamed);
    await _guard(fail, 'swap', () async {
      for (final s in ['${db.path}-wal', '${db.path}-shm']) {
        final f = File(s);
        if (await f.exists()) await f.delete();
      }
      try {
        await v2.rename(db.path);
      } catch (_) {
        await pre.rename(db.path); // أعد الأصل
        rethrow;
      }
    });
    await _setState(db, 'swapped');
    await stepHook?.call(stepSwapped);

    // ── M7: فحصٌ نهائيٌّ على المسار الحقيقيّ ثم الالتزام ──
    final good = await _guard(fail, 'final check', () async {
      return await _engine.canOpen(db, newKey) &&
          (await _engine.inspect(db, newKey)).quickCheckOk;
    });
    if (!good) {
      await _revertToPreV2(db, 'final check failed');
      throw _Abort(fail, 'final check on the real path failed; reverted');
    }
    final cur = await KeyInfoFile.read(db);
    await _guard(fail, 'commit', () async {
      await KeyInfoFile.write(
        db,
        KeyInfo(
          kind: DbKeyKind.rawV2,
          fingerprint: newKey.fingerprint,
          createdAt: cur?.createdAt ?? startedAt,
          migratedFrom: oldKey.kind.name,
          recoveryEnvelope: env,
          migration: (cur?.migration ??
                  KeyMigrationProgress(
                    state: 'swapped',
                    newFingerprint: newKey.fingerprint,
                    oldKind: oldKey.kind.name,
                    startedAt: startedAt,
                  ))
              .copyWith(
                  state: 'committedPendingConfirm', committedBy: processId),
        ),
      );
    });
    await stepHook?.call(stepCommitted);
    return const DbKeyMigrationResult(DbKeyMigrationStatus.migrated);
  }

  // ───────────────────────── الرجوع ─────────────────────────

  /// `db → .v2-orphan` (لا يُحذف آليًّا) ثم `.pre-v2 → db`. يعيد `true` إن
  /// فتحه مفتاحٌ قديم.
  Future<bool> _revertToPreV2(File db, String why) async {
    final pre = _preV2(db);
    if (!await pre.exists()) return false;
    if (await _legacyOpens(pre) == null) return false;
    if (await db.exists()) {
      await db.rename((await _uniqueSibling(db, '.v2-orphan')).path);
    }
    for (final s in ['${db.path}-wal', '${db.path}-shm']) {
      final f = File(s);
      if (await f.exists()) await f.delete();
    }
    await pre.rename(db.path);
    final legacy = await _legacyOpens(db);
    final prior = await KeyInfoFile.read(db);
    await KeyInfoFile.write(
      db,
      KeyInfo(
        kind: legacy?.kind ?? DbKeyKind.legacyDerived,
        createdAt: prior?.createdAt ?? manager.now().toIso8601String(),
        recoveryEnvelope: prior?.recoveryEnvelope,
      ),
    );
    debugPrint('[DBKEY] reverted to pre-v2 copy ($why); orphan kept');
    return true;
  }

  /// رجوعٌ صريح (من شاشة الاسترداد) إلى نسخة ما قبل الترحيل، وهو يخسر ما كُتب
  /// بعد الترحيل (يبقى في `.v2-orphan`).
  Future<bool> rollbackToPreMigration(File dbFile) async {
    final lock = await _acquireLock(dbFile);
    if (lock == null) return false;
    try {
      return await _revertToPreV2(dbFile, 'explicit rollback');
    } finally {
      await _release(lock);
    }
  }

  // ───────────────────────── التعافي (§2.4) + M8 ─────────────────────────

  /// يُستدعى من `DbKeyManager.resolveForOpen` قبل أيّ فتح. يتخطّى بصمتٍ إن
  /// حمل القفلَ غيرُه (ترحيلٌ جارٍ في عمليّةٍ أخرى).
  Future<void> recoverInterrupted(File dbFile) async {
    final lock = await _acquireLock(dbFile);
    if (lock == null) return;
    try {
      await _recover(dbFile);
    } finally {
      await _release(lock);
    }
  }

  Future<void> _recover(File db) async {
    final name = DbKeyManager.dbNameOf(db);
    final v2 = _v2New(db);
    final pre = _preV2(db);
    final dbExists = await db.exists();
    final v2Exists = await v2.exists();
    final preExists = await pre.exists();
    if (!v2Exists && !preExists) {
      await purgeExpiredPreMigrationBackups(db);
      return;
    }
    final stored = await manager.readStored(name);
    final info = await KeyInfoFile.read(db);

    if (!dbExists) {
      // لا db: انقطاعٌ بين نقلَي M6 (أو ضياعٌ ما).
      if (v2Exists) {
        final k = await _newKeyOpens(v2, stored);
        if (k != null && (await _engine.inspect(v2, k)).quickCheckOk) {
          await v2.rename(db.path);
          await _commitFromTruth(db, k, info, pre);
          if (preExists) await _setCommittedBy(db, processId);
          return;
        }
        await _deleteWithSidecars(v2);
      }
      if (preExists) {
        await pre.rename(db.path);
        await _resetToLegacy(db, info);
      }
      return;
    }

    if (v2Exists && !preExists) {
      // انقطع أثناء/بعد التصدير قبل التبديل — الملفُّ الجديدُ مشتقٌّ وقابلٌ للإعادة.
      await _deleteWithSidecars(v2);
      return;
    }

    if (preExists) {
      final k = await _newKeyOpens(db, stored);
      if (k != null) {
        final m = info?.migration;
        if (m != null &&
            m.state == 'committedPendingConfirm' &&
            m.committedBy != processId) {
          // M8: المفتاح قُرئ من التخزين في عمليّةٍ جديدة وفتح القاعدة.
          await _deleteWithSidecars(pre);
          await _setState(db, 'done',
              confirmedAt: manager.now().toIso8601String());
        } else if (m == null || m.state != 'committedPendingConfirm') {
          await _commitFromTruth(db, k, info, pre);
          await _setCommittedBy(db, processId);
        }
        await purgeExpiredPreMigrationBackups(db);
        return;
      }
      if (await _legacyOpens(db) != null) return; // pre-v2 متخلّفة؛ لا شيء.
      if (await _legacyOpens(pre) != null) {
        if (info?.migration?.state == 'committedPendingConfirm') {
          // مفتاحٌ التُزم به وتحقّقنا منه ثمّ غاب (حسابُ ويندوز آخر على الأرجح):
          // لا نرجع بصمتٍ إلى نسخةٍ أقدم — يقرّر المدير (DbKeyUnavailable).
          return;
        }
        await _revertToPreV2(db, 'new key lost before confirmation');
      }
    }
  }

  Future<void> _setCommittedBy(File db, String id) =>
      _setState(db, 'committedPendingConfirm', committedBy: id);

  Future<void> _commitFromTruth(
      File db, DbKey newKey, KeyInfo? info, File pre) async {
    final old = await _legacyOpens(pre);
    final oldKind = info?.migration?.oldKind ?? old?.kind.name ?? 'legacyDerived';
    final prior = info;
    await KeyInfoFile.write(
      db,
      KeyInfo(
        kind: DbKeyKind.rawV2,
        fingerprint: newKey.fingerprint,
        createdAt: prior?.createdAt ?? manager.now().toIso8601String(),
        migratedFrom: oldKind,
        recoveryEnvelope: prior?.recoveryEnvelope,
        migration: (prior?.migration ??
                KeyMigrationProgress(
                  state: 'swapped',
                  newFingerprint: newKey.fingerprint,
                  oldKind: oldKind,
                  startedAt: manager.now().toIso8601String(),
                ))
            .copyWith(state: 'swapped'),
      ),
    );
  }

  Future<void> _resetToLegacy(File db, KeyInfo? info) async {
    final legacy = await _legacyOpens(db);
    await KeyInfoFile.write(
      db,
      KeyInfo(
        kind: legacy?.kind ?? DbKeyKind.legacyDerived,
        createdAt: info?.createdAt ?? manager.now().toIso8601String(),
        recoveryEnvelope: info?.recoveryEnvelope,
      ),
    );
  }

  /// ق-5: نسخُ `key-migration/*.pre-v2-*` تُحفَظ [preMigrationRetention] (30
  /// يومًا) ثم تُحذف. تُرجع عددَ ما حُذف.
  Future<int> purgeExpiredPreMigrationBackups(File dbFile) async {
    var deleted = 0;
    try {
      if (!await preMigrationDir.exists()) return 0;
      final prefix = '${DbKeyManager.dbNameOf(dbFile)}.pre-v2-';
      final cutoff = manager.now().subtract(preMigrationRetention);
      await for (final e in preMigrationDir.list()) {
        if (e is! File) continue;
        final n = p.basename(e.path);
        if (!n.startsWith(prefix) || !n.endsWith('.db')) continue;
        if ((await e.lastModified()).isBefore(cutoff)) {
          await e.delete();
          final side = KeyInfoFile.of(e);
          if (await side.exists()) await side.delete();
          deleted++;
        }
      }
    } catch (e) {
      debugPrint('[DBKEY] purge failed: $e');
    }
    return deleted;
  }
}
