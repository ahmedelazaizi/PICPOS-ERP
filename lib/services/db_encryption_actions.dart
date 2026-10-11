import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../data/database/connection.dart' as conn;
import 'db_backup_sidecars.dart';
import 'db_key_boot.dart';
import 'db_key_manager.dart';
import 'db_key_portable_export.dart';
import 'db_keyinfo_file.dart';

/// حالةُ تشفير القاعدة المحلية كما تراها واجهةُ المدير.
enum DbEncryptionState {
  /// ما زالت بالمفتاح المشتقّ القديم من الجهاز.
  legacy,

  /// طلبُ ترحيلٍ مؤجَّل مسجَّل — ينتظر إعادةَ تشغيل التطبيق.
  requested,

  /// رُحِّلت وتنتظر تأكيدَ الإقلاع التالي (M8).
  pendingConfirm,

  /// مرحَّلة ومؤكَّدة (مفتاحٌ عشوائيّ في التخزين الآمن).
  migrated,

  /// تعذّرت قراءةُ الحالة.
  unavailable,
}

class DbEncryptionStatus {
  const DbEncryptionStatus({
    required this.state,
    this.recoveryCodePending = false,
    this.preMigrationUntil,
    this.lastOutcome,
  });

  final DbEncryptionState state;

  /// رمزُ استردادٍ لم يؤكّد المدير حفظَه بعد.
  final bool recoveryCodePending;

  /// آخرُ يومٍ تتوفّر فيه نسخةُ ما قبل الترحيل (30 يومًا) أو `null`.
  final DateTime? preMigrationUntil;

  /// ما جرى لطلبٍ مؤجَّل في هذا الإقلاع.
  final DbKeyBootOutcome? lastOutcome;

  bool get canRollback =>
      preMigrationUntil != null && state != DbEncryptionState.requested;
}

/// ما تفعله كتلةُ «تشفير قاعدة البيانات». مجرّدٌ كي تُختبر الواجهةُ بلا قاعدةٍ
/// ولا تخزينٍ آمن.
abstract class DbEncryptionActions {
  Future<DbEncryptionStatus> status();

  /// الفحصُ المسبق: مساحةٌ حرّةٌ ≥ 3× حجم القاعدة (أو «غير معروفة»).
  Future<MigrationSpaceCheck> preflight();

  /// يسجّل طلبَ الترحيل المؤجَّل (يُنفَّذ قبل فتح أيّ مقبض في الإقلاع التالي).
  Future<void> requestMigration({required bool spaceConfirmed});

  Future<void> cancelRequest();

  Future<String?> pendingRecoveryCode();
  Future<void> acknowledgeRecoveryCode();

  /// مجلدٌ للتصدير المحمول (`null` = أُلغي).
  Future<String?> pickExportDirectory();

  /// تصديرٌ محمولٌ بكلمة مرور؛ يعيد مسارَ الملف.
  Future<String> exportPortable({
    required String password,
    required String directory,
  });

  /// يجدول الاستعادةَ من نسخة ما قبل الترحيل (تُطبَّق في الإقلاع التالي).
  Future<bool> scheduleRollback();

  /// يكتب حدثًا في سجلّ النشاط؛ لا يرمي.
  Future<void> audit(String action, String description);
}

/// التنفيذُ الإنتاجيّ فوق ملف القاعدة المحلي.
class ProductionDbEncryptionActions implements DbEncryptionActions {
  ProductionDbEncryptionActions({
    required Future<void> Function(String action, String description) audit,
    DbKeyManager? manager,
  })  : _audit = audit,
        _manager = manager ?? DbKeyManager.production();

  final Future<void> Function(String action, String description) _audit;
  final DbKeyManager _manager;

  Future<File> _db() async => File(await conn.getDatabasePath());
  Directory _backups(File db) => Directory(p.join(db.parent.path, 'backups'));

  @override
  Future<DbEncryptionStatus> status() async {
    try {
      final db = await _db();
      final name = DbKeyManager.dbNameOf(db);
      final info = await KeyInfoFile.read(db);
      final req = await DbKeyMigrationRequest.read(db);
      final state = req != null
          ? DbEncryptionState.requested
          : info?.migration?.state == 'committedPendingConfirm'
              ? DbEncryptionState.pendingConfirm
              : (info?.claimsMigrated ?? false)
                  ? DbEncryptionState.migrated
                  : DbEncryptionState.legacy;
      return DbEncryptionStatus(
        state: state,
        recoveryCodePending: await _manager.pendingRecoveryCode(name) != null,
        preMigrationUntil:
            await PreMigrationBackups.availableUntil(_backups(db), name),
        lastOutcome: DbKeyBoot.lastOutcome,
      );
    } catch (_) {
      return const DbEncryptionStatus(state: DbEncryptionState.unavailable);
    }
  }

  @override
  Future<MigrationSpaceCheck> preflight() async =>
      MigrationSpaceCheck.measure(await _db());

  @override
  Future<void> requestMigration({required bool spaceConfirmed}) async {
    final db = await _db();
    await DbKeyMigrationRequest(
      requestedAt: DateTime.now(),
      spaceConfirmedByAdmin: spaceConfirmed,
    ).write(db);
  }

  @override
  Future<void> cancelRequest() async =>
      DbKeyMigrationRequest.clear(await _db());

  @override
  Future<String?> pendingRecoveryCode() async =>
      _manager.pendingRecoveryCode(DbKeyManager.dbNameOf(await _db()));

  @override
  Future<void> acknowledgeRecoveryCode() async =>
      _manager.acknowledgeRecoveryCode(DbKeyManager.dbNameOf(await _db()));

  @override
  Future<String?> pickExportDirectory() => FilePicker.getDirectoryPath();

  @override
  Future<String> exportPortable({
    required String password,
    required String directory,
  }) async {
    final db = await _db();
    final name = DbKeyManager.dbNameOf(db);
    final key = await _manager.findOpeningKey(db, dbName: name);
    if (key == null) {
      throw const PortableExportException('no key opens the database');
    }
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final out = File(p.join(directory, '${name}_portable_$stamp.db'));
    await PortableExport(_manager.engine).export(
      src: db,
      srcKey: key,
      out: out,
      password: password,
    );
    return out.path;
  }

  @override
  Future<bool> scheduleRollback() async {
    final db = await _db();
    final copy = await PreMigrationBackups.latest(
        _backups(db), DbKeyManager.dbNameOf(db));
    if (copy == null) return false;
    await DbKeyMigrationRequest.clear(db);
    return conn.restoreDatabaseBackup(copy.path);
  }

  @override
  Future<void> audit(String action, String description) async {
    try {
      await _audit(action, description);
    } catch (_) {}
  }
}
