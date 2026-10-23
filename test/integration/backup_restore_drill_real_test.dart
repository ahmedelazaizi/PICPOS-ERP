// Audit B BKP-001 — executable restore drill on the REAL encrypted path.
//
//   1. create an encrypted database with data through the real open path
//      (`openConnection()` -> key resolution -> SQLCipher, full app schema);
//   2. take a backup with the real `createDatabaseBackup`;
//   3. change the live database;
//   4. schedule the restore with the real `restoreDatabaseBackup`;
//   5. "reboot": the real open path applies the pending restore before opening;
//   6. reopen with the key and assert the ORIGINAL rows, integrity_check and
//      user_version; the safety copy (.pre-restore) is cleaned up.
//
// Skips itself loudly without SQLCipher (plain `flutter test` loads plain
// sqlite3). Real run (swaps the SQLCipher DLL into the hook cache):
//   powershell -NoProfile -ExecutionPolicy Bypass -File tool\run_sqlcipher_tests.ps1 test/integration/backup_restore_drill_real_test.dart
// Also covers BKP-002: a backup from a NEWER schema is rejected at schedule time.
import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:picpos_erp/data/database/connection_io.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/pending_restore.dart';
import 'package:picpos_erp/data/database/schema_version_limit.dart';
import 'package:picpos_erp/data/database/wal_checkpoint.dart';
import 'package:picpos_erp/services/db_key_boot.dart';
import 'package:picpos_erp/services/legacy_device_seed.dart';
import 'package:picpos_erp/services/sqlcipher_engine.dart' show DbInspection;

import '../helpers/sqlcipher_real.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.docs);
  final String docs;
  @override
  Future<String?> getApplicationDocumentsPath() async => docs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  late File dbFile;
  final savedProvider = LegacyDeviceSeed.deviceIdProvider;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('picpos_restore_drill_');
    PathProviderPlatform.instance = _FakePathProvider(docs.path);
    FlutterSecureStorage.setMockInitialValues({});
    LegacyDeviceSeed.deviceIdProvider = () async => 'TEST-DEVICE-ID-BKP001';
    dbFile = File(p.join(docs.path, getDatabaseFileName()));
    DbKeyBoot.resetMemo();
    DbKeyBoot.lastOutcome = null;
    DbKeyBoot.factoryOverride = null;
  });

  tearDown(() {
    LegacyDeviceSeed.deviceIdProvider = savedProvider;
    DbKeyBoot.processIdOverride = null;
    DbKeyBoot.resetMemo();
    try {
      docs.deleteSync(recursive: true);
    } catch (_) {}
  });

  void boot(String id) {
    DbKeyBoot.resetMemo();
    DbKeyBoot.processIdOverride = id;
  }

  // The startup path schedules a background phase (integrity checks + auto
  // backup) right after beforeOpen. Closing the database underneath it raises an
  // unhandled error, so every open waits for its completion marker first.
  late Completer<void> deferredDone;
  final savedDebugPrint = debugPrint;
  setUpAll(() {
    debugPrint = (String? m, {int? wrapWidth}) {
      if (m != null && m.contains('Deferred phase 6 complete')) {
        if (!deferredDone.isCompleted) deferredDone.complete();
      }
    };
  });
  tearDownAll(() => debugPrint = savedDebugPrint);

  /// Opens the app database over the real encrypted connection.
  AppDatabase openApp() {
    deferredDone = Completer<void>();
    return AppDatabase.withExecutor(openConnection());
  }

  Future<void> settle(AppDatabase db) async {
    await db.customSelect('SELECT 1').get(); // force open
    // The marker is printed only when the deferred phase completes WITHOUT an
    // error; a regression of the root-zone fix (database_startup.dart) times out
    // here / leaks "Bad state: No element" and fails the drill.
    await deferredDone.future.timeout(const Duration(seconds: 60));
  }

  Future<int> scalar(AppDatabase db, String sql) async =>
      ((await db.customSelect(sql).getSingle()).data.values.first as num).toInt();

  test('BKP-001: encrypted backup -> modify -> restore -> reboot -> original data',
      () async {
    if (!await requireSqlCipher()) return;

    // (1) create + populate through the real open path.
    boot('drill-1');
    var db = openApp();
    await settle(db);
    final partyId = await db.insertParty(PartiesCompanion.insert(
        name: 'DRILL-ORIGINAL', isCustomer: const Value(true), balance: const Value(250)));
    final partiesAtBackup = await scalar(db, 'SELECT COUNT(*) FROM parties');
    final jeAtBackup = await scalar(db, 'SELECT COUNT(*) FROM journal_entries');
    final linesAtBackup = await scalar(db, 'SELECT COUNT(*) FROM journal_entry_lines');
    final versionAtBackup = await scalar(db, 'PRAGMA user_version');
    expect(jeAtBackup, greaterThan(0), reason: 'opening-balance JE exists');
    expect(looksPlain(dbFile), isFalse, reason: 'database must be encrypted');

    // (2) real backup, with a real WAL checkpoint while the database is open.
    final backupPath =
        await createDatabaseBackup(checkpoint: () => walCheckpointTruncate(db));
    expect(backupPath, isNotNull);
    expect(looksPlain(File(backupPath!)), isFalse, reason: 'backup stays encrypted');

    // (3) damage the live database after the backup.
    await db.customStatement("DELETE FROM parties WHERE id = $partyId");
    await db.insertParty(PartiesCompanion.insert(name: 'DRILL-AFTER-BACKUP'));
    expect(await scalar(db, "SELECT COUNT(*) FROM parties WHERE name = 'DRILL-ORIGINAL'"), 0);
    await db.close();

    // (4) schedule the restore (verified against the known key first).
    expect(await restoreDatabaseBackup(backupPath), isTrue);
    expect(await hasPendingRestore(), isTrue);

    // (5)+(6) reboot: the real open path applies it, then we reopen with the key.
    boot('drill-2');
    db = openApp();
    await settle(db);
    expect(await scalar(db, "SELECT COUNT(*) FROM parties WHERE name = 'DRILL-ORIGINAL'"), 1,
        reason: 'original row is back');
    expect(await scalar(db, "SELECT COUNT(*) FROM parties WHERE name = 'DRILL-AFTER-BACKUP'"), 0,
        reason: 'post-backup change is gone');
    expect(await scalar(db, 'SELECT COUNT(*) FROM parties'), partiesAtBackup);
    expect(await scalar(db, 'SELECT COUNT(*) FROM journal_entries'), jeAtBackup);
    expect(await scalar(db, 'SELECT COUNT(*) FROM journal_entry_lines'), linesAtBackup);
    expect(await scalar(db, 'PRAGMA user_version'), versionAtBackup);
    final integrity = await db.customSelect('PRAGMA integrity_check').get();
    expect(integrity.single.data.values.first.toString().toLowerCase(), 'ok');
    final bal = await (db.select(db.parties)
          ..where((x) => x.name.equals('DRILL-ORIGINAL')))
        .getSingle();
    expect(bal.balance, 250);
    await db.close();

    expect(looksPlain(dbFile), isFalse);
    expect(await hasPendingRestore(), isFalse);
    expect(File('${dbFile.path}${PendingRestore.preRestoreSuffix}').existsSync(), isFalse,
        reason: 'finalize removed the safety copy after a successful open');
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('BKP-002: schema guard accepts <= app version, rejects a newer backup', () {
    DbInspection i(bool ok, int v) =>
        DbInspection(quickCheckOk: ok, userVersion: v, tableRowCounts: const {});
    expect(PendingRestore.acceptInspection(i(true, kMaxSupportedSchemaVersion)), isTrue);
    expect(PendingRestore.acceptInspection(i(true, 1)), isTrue);
    expect(PendingRestore.acceptInspection(i(true, kMaxSupportedSchemaVersion + 1)), isFalse);
    expect(PendingRestore.acceptInspection(i(false, 1)), isFalse);
  });

  test('kMaxSupportedSchemaVersion equals AppDatabase.schemaVersion', () {
    final db = AppDatabase.forTesting();
    expect(kMaxSupportedSchemaVersion, db.schemaVersion,
        reason: 'bump schema_version_limit.dart together with schemaVersion');
  });
}
