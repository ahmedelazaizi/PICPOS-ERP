import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show debugPrint, visibleForTesting;
import 'package:path/path.dart' as p;

import 'db_key_manager.dart';
import 'db_key_migration_service.dart';
import 'db_key_types.dart';
import 'db_keyinfo_file.dart';
import 'security_service.dart' show DatabaseKeyUnavailableException;

/// قاعدةٌ لا يمكن فتحُها بأمان (مفتاحٌ مفقودٌ لقاعدةٍ مرحَّلة…): يُحجب الإقلاعُ
/// بشاشةٍ صريحة. **لا تُنشأ قاعدةٌ فارغةٌ أبدًا** في هذه الحالة.
///
/// يرث [DatabaseKeyUnavailableException] كي يلتقطه أيُّ `catch` قائمٌ لها.
class DbKeyBlockedException extends DatabaseKeyUnavailableException {
  const DbKeyBlockedException(this.resolution, this.dbPath);

  final DbKeyUnavailable resolution;
  final String dbPath;

  @override
  String toString() => 'DbKeyBlockedException(${resolution.reason.name})';
}

typedef ProcessRunner = Future<ProcessResult> Function(
    String exe, List<String> args);

/// قياسُ المساحة الحرّة بلا FFI: ويندوز عبر PowerShell (`DriveInfo`)، وغيرُه
/// عبر `df`. `null` = تعذّر القياس (لا يُخمَّن).
class DiskSpace {
  DiskSpace._();

  static Future<int?> freeBytes(
    Directory dir, {
    ProcessRunner? runner,
    bool? isWindows,
  }) async {
    final run = runner ?? ((e, a) => Process.run(e, a));
    final windows = isWindows ?? Platform.isWindows;
    try {
      if (windows) {
        final root = p.rootPrefix(p.absolute(dir.path));
        final m = RegExp(r'^([A-Za-z]):').firstMatch(root);
        if (m == null) return null; // UNC أو مسارٌ غريب
        final r = await run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          "(New-Object System.IO.DriveInfo('${m.group(1)}')).AvailableFreeSpace",
        ]).timeout(const Duration(seconds: 20));
        if (r.exitCode != 0) return null;
        final v = int.tryParse(r.stdout.toString().trim());
        return v != null && v >= 0 ? v : null;
      }
      final r = await run('df', ['-Pk', dir.path])
          .timeout(const Duration(seconds: 10));
      if (r.exitCode != 0) return null;
      final lines = r.stdout
          .toString()
          .trim()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.length < 2) return null;
      final cols = lines.last.trim().split(RegExp(r'\s+'));
      if (cols.length < 4) return null;
      final kb = int.tryParse(cols[3]);
      return kb == null ? null : kb * 1024;
    } catch (_) {
      return null;
    }
  }
}

/// نتيجةُ فحص المساحة قبل الترحيل: المطلوبُ ≥ 3× (القاعدة + WAL).
class MigrationSpaceCheck {
  const MigrationSpaceCheck({
    required this.dbBytes,
    required this.requiredBytes,
    this.freeBytes,
  });

  static const int factor = 3;

  final int dbBytes;
  final int requiredBytes;

  /// `null` = تعذّر القياس.
  final int? freeBytes;

  bool get known => freeBytes != null;
  bool get ok => known && freeBytes! >= requiredBytes;

  static Future<MigrationSpaceCheck> measure(
    File db, {
    Future<int?> Function(Directory dir)? freeBytes,
  }) async {
    var size = await db.exists() ? await db.length() : 0;
    final wal = File('${db.path}-wal');
    if (await wal.exists()) size += await wal.length();
    final free = await (freeBytes ?? DiskSpace.freeBytes)(db.parent);
    return MigrationSpaceCheck(
      dbBytes: size,
      requiredBytes: size * factor,
      freeBytes: free,
    );
  }
}

/// طلبُ ترحيلٍ **مؤجَّل**: يُسجَّل من واجهة المدير ويُنفَّذ في الإقلاع التالي
/// قبل فتح أيّ مقبض (نفس منطق `PendingRestore`). ملفٌّ مجاور للقاعدة:
/// `<db>.key-migration.request.json`. يُمسح قبل التنفيذ (طلبٌ لمرّةٍ واحدة)
/// فلا يتكرّر ترحيلٌ فاشلٌ في كلّ إقلاع.
class DbKeyMigrationRequest {
  const DbKeyMigrationRequest({
    required this.requestedAt,
    this.spaceConfirmedByAdmin = false,
  });

  final DateTime requestedAt;

  /// القياسُ تعذّر وأكّد المدير صراحةً وجودَ مساحةٍ كافية.
  final bool spaceConfirmedByAdmin;

  static File fileOf(File db) => File('${db.path}.key-migration.request.json');

  static Future<DbKeyMigrationRequest?> read(File db) async {
    try {
      final f = fileOf(db);
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return null;
      final at = DateTime.tryParse('${j['requestedAt']}');
      if (at == null) return null;
      return DbKeyMigrationRequest(
        requestedAt: at,
        spaceConfirmedByAdmin: j['spaceConfirmedByAdmin'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(File db) async {
    final target = fileOf(db);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'version': 1,
        'requestedAt': requestedAt.toIso8601String(),
        'spaceConfirmedByAdmin': spaceConfirmedByAdmin,
      }),
      flush: true,
    );
    await tmp.rename(target.path);
  }

  static Future<void> clear(File db) async {
    final f = fileOf(db);
    if (await f.exists()) await f.delete();
  }
}

enum DbKeyBootOutcomeKind { migrated, skipped, failed }

/// ما جرى لطلب الترحيل المؤجَّل في هذا الإقلاع (للعرض في إعدادات الأمان).
class DbKeyBootOutcome {
  const DbKeyBootOutcome(this.kind, [this.detail]);
  final DbKeyBootOutcomeKind kind;
  final String? detail;
}

/// تجهيزُ مفتاح فتح القاعدة عند الإقلاع:
///  1. طلبُ ترحيلٍ مؤجَّل ⇒ فحصُ المساحة ثم `DbKeyMigrationService.migrate`
///     (الذي يتكفّل بالنسخة المسبقة M3 ويفشل بأمان).
///  2. `resolveForOpen` (يستدعي `recoverInterrupted`: التعافي وتأكيد M8 في
///     الإقلاع التالي).
///  3. ترميمُ keyinfo قديمٍ يدّعي «مرحَّلة» بينما فتحها مفتاحٌ قديم (بعد رجوعٍ).
///
/// **لا ترحيلَ تلقائيّ أبدًا**: لا يعمل شيءٌ هنا بلا طلبٍ صريحٍ من المدير.
class DbKeyBoot {
  DbKeyBoot({
    required this.manager,
    required this.service,
    Future<int?> Function(Directory dir)? freeSpace,
    bool Function()? migrationDisabled,
  })  : _freeSpace = freeSpace,
        _disabled = migrationDisabled ?? _cliDisabled;

  /// تركيبةٌ إنتاجيّة؛ [backupsDir] = `Documents/backups`.
  factory DbKeyBoot.production(Directory backupsDir, {String? processId}) {
    final m = DbKeyManager.production();
    final s = DbKeyMigrationService(
      manager: m,
      backupsDir: backupsDir,
      processId: processId ?? processIdOverride,
    );
    m.beforeResolve = s.recoverInterrupted;
    return DbKeyBoot(manager: m, service: s);
  }

  /// للاختبار: يحاكي «إقلاعًا جديدًا» بمعرّف عمليّةٍ مختلف.
  @visibleForTesting
  static String? processIdOverride;

  /// للاختبار فقط: يستبدل التركيبةَ الإنتاجيّة في resolveDatabaseKey.
  static DbKeyBoot Function(File dbFile)? factoryOverride;

  final DbKeyManager manager;
  final DbKeyMigrationService service;
  final Future<int?> Function(Directory dir)? _freeSpace;
  final bool Function() _disabled;

  /// آخرُ نتيجةٍ لطلبٍ مؤجَّل في هذه العمليّة (أو `null` إن لم يكن طلب).
  static DbKeyBootOutcome? lastOutcome;

  static bool _cliDisabled() {
    try {
      return Platform.executableArguments.contains('--no-db-key-migration');
    } catch (_) {
      return false;
    }
  }

  static final Map<String, Future<DbKeyResolution>> _memo = {};

  /// يُنفَّذ الجسمُ مرّةً لكلّ مسارٍ في العمليّة (البوّابةُ في `main` ثم
  /// `openConnection` يتشاركان النتيجة)؛ [resetMemo] يُجبر إعادةَ المحاولة.
  static Future<DbKeyResolution> memoized(
      String path, Future<DbKeyResolution> Function() body) {
    final existing = _memo[path];
    if (existing != null) return existing;
    final f = body();
    _memo[path] = f;
    f.catchError((Object _) {
      _memo.remove(path);
      return const DbKeyUnavailable(DbKeyUnavailableReason.noCandidateOpens);
    });
    return f;
  }

  static void resetMemo() => _memo.clear();

  Future<DbKeyResolution> prepare(File db) async {
    await _runDeferredMigration(db);
    final res = await manager.resolveForOpen(db);
    if (res is DbKeyReady) await _healStaleKeyinfo(db, res);
    return res;
  }

  Future<void> _runDeferredMigration(File db) async {
    final req = await DbKeyMigrationRequest.read(db);
    if (req == null) return;
    // لمرّةٍ واحدة: يُمسح قبل التنفيذ فلا يتكرّر فشلٌ في كلّ إقلاع.
    try {
      await DbKeyMigrationRequest.clear(db);
    } catch (_) {}

    DbKeyBootOutcome skip(String why) {
      debugPrint('[DBKEY] deferred migration skipped: $why');
      return DbKeyBootOutcome(DbKeyBootOutcomeKind.skipped, why);
    }

    if (_disabled()) {
      lastOutcome = skip('disabled by --no-db-key-migration');
      return;
    }
    final MigrationSpaceCheck space;
    try {
      space = await MigrationSpaceCheck.measure(db, freeBytes: _freeSpace);
    } catch (_) {
      lastOutcome = skip('space check failed');
      return;
    }
    if (space.known && !space.ok) {
      lastOutcome = skip('insufficient free space');
      return;
    }
    if (!space.known && !req.spaceConfirmedByAdmin) {
      lastOutcome = skip('free space unknown and not confirmed');
      return;
    }
    try {
      final r = await service.migrate(db);
      lastOutcome = switch (r.status) {
        DbKeyMigrationStatus.migrated ||
        DbKeyMigrationStatus.alreadyMigrated =>
          DbKeyBootOutcome(DbKeyBootOutcomeKind.migrated, r.detail),
        DbKeyMigrationStatus.failed =>
          DbKeyBootOutcome(DbKeyBootOutcomeKind.failed, r.detail),
        _ => DbKeyBootOutcome(DbKeyBootOutcomeKind.skipped, r.detail),
      };
    } catch (e) {
      // لا يُحجب الإقلاعُ بسبب ترحيلٍ فشل: الأصلُ سليمٌ ويُفتح بالقديم.
      lastOutcome = DbKeyBootOutcome(
          DbKeyBootOutcomeKind.failed, 'unexpected: ${e.runtimeType}');
    }
  }

  /// keyinfo يقول «مرحَّلة» لكنّ مفتاحًا قديمًا هو الذي فتحها وليس ثمّة ترحيلٌ
  /// جارٍ ⇒ استُعيدت نسخةُ ما قبل الترحيل: يُصحَّح السجلّ كي لا يضلّل الواجهة
  /// ولا يُظنّ فقدُ مفتاحٍ لاحقًا.
  Future<void> _healStaleKeyinfo(File db, DbKeyReady res) async {
    if (!res.key.kind.isLegacy) return;
    try {
      final info = await KeyInfoFile.read(db);
      if (info == null || !info.claimsMigrated) return;
      if (await File('${db.path}.pre-v2').exists() ||
          await File('${db.path}.v2-new').exists()) {
        return;
      }
      await KeyInfoFile.write(
        db,
        KeyInfo(
          kind: res.key.kind,
          createdAt: info.createdAt,
          recoveryEnvelope: info.recoveryEnvelope,
        ),
      );
    } catch (_) {}
  }
}
