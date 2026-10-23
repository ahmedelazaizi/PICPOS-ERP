// Audit B MIG-001 / MIG-002 / MIG-004 / BKP-002 support.
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

import '../helpers/v195_reservations_db.dart';

class _User extends QueryExecutorUser {
  _User(this.version);
  final int version;
  @override
  int get schemaVersion => version;
  @override
  Future<void> beforeOpen(QueryExecutor e, OpeningDetails d) async {}
}

class _MutUser extends QueryExecutorUser {
  int version = 0;
  @override
  int get schemaVersion => version;
  @override
  Future<void> beforeOpen(QueryExecutor e, OpeningDetails d) async {}
}

/// Reads user_version without letting drift stamp anything (version == stored).
Future<int> _userVersion(File f) async {
  final user = _MutUser();
  var v = -1;
  final e = NativeDatabase(f, setup: (raw) {
    v = (raw.select('PRAGMA user_version;').first.values.first as num).toInt();
    user.version = v;
  });
  await e.ensureOpen(user);
  await e.close();
  return v;
}
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('audit_b_mig_'));
  tearDown(() {
    preMigrationBackupOverride = null;
    liveDatabaseFileExistsOverride = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('MIG-001: a database newer than the app refuses to open and is not re-stamped',
      () async {
    final f = File('${dir.path}/newer.db');
    // Create a plain SQLite file stamped user_version = 999.
    var stamped = -1;
    final seed = NativeDatabase(f, setup: (raw) {
      raw.execute('PRAGMA user_version = 999;');
      stamped = (raw.select('PRAGMA user_version;').first.values.first as num).toInt();
    });
    await seed.ensureOpen(_User(999));
    await seed.close();
    expect(stamped, 999);

    final db = AppDatabase.withExecutor(NativeDatabase(f));
    await expectLater(
      db.customSelect('SELECT 1').get(),
      throwsA(predicate((e) => e.toString().contains('DatabaseTooNewException'))),
    );
    try {
      await db.close();
    } catch (_) {}
    expect(await _userVersion(f), 999, reason: 'user_version must not be re-stamped');
  });

  test('MIG-001: runOnUpgrade(from > to) throws the typed exception first', () async {
    final db = await openV195ReservationsDb();
    await expectLater(db.runOnUpgrade(Migrator(db), 999, 196),
        throwsA(isA<DatabaseTooNewException>()));
    expect(
        (await db.customSelect('PRAGMA table_info(table_reservations)').get())
            .map((r) => r.data['name'])
            .contains('party_id'),
        isFalse,
        reason: 'nothing was migrated');
  });

  test('MIG-004: backup failure on a live database aborts the upgrade untouched',
      () async {
    final db = await openV195ReservationsDb();
    preMigrationBackupOverride = () async => null;
    liveDatabaseFileExistsOverride = () async => true;
    await expectLater(db.runOnUpgrade(Migrator(db), 195, 196),
        throwsA(isA<PreMigrationBackupFailedException>()));
    expect(
        (await db.customSelect('PRAGMA table_info(table_reservations)').get())
            .map((r) => r.data['name'])
            .contains('party_id'),
        isFalse,
        reason: 'the schema must be untouched when the backup could not be taken');
  });

  test('MIG-004: a backup exception is also fatal; success lets the upgrade run',
      () async {
    final db = await openV195ReservationsDb();
    liveDatabaseFileExistsOverride = () async => true;
    preMigrationBackupOverride = () async => throw const FileSystemException('disk full');
    await expectLater(db.runOnUpgrade(Migrator(db), 195, 196),
        throwsA(isA<PreMigrationBackupFailedException>()));
    preMigrationBackupOverride = () async => '${dir.path}/ok.bak';
    await db.runOnUpgrade(Migrator(db), 195, 196);
    expect(
        (await db.customSelect('PRAGMA table_info(table_reservations)').get())
            .map((r) => r.data['name'])
            .contains('party_id'),
        isTrue);
  });

  test('MIG-004: no live database file (tests/web) never blocks the upgrade',
      () async {
    final db = await openV195ReservationsDb();
    preMigrationBackupOverride = () async => null;
    liveDatabaseFileExistsOverride = () async => false;
    await db.runOnUpgrade(Migrator(db), 195, 196);
  });

  test('MIG-002: replaying an interrupted upgrade (user_version still old) is idempotent',
      () async {
    final db = await openV195ReservationsDb();
    final t = await insertTestTable(db, 'T1');
    await insertTestReservation(db, t, 'ليلى', '01001112222', hasPartyColumn: false);
    await insertTestReservation(db, t, 'منى', '01005556666', hasPartyColumn: false);
    Future<List<int>> snapshot() async => [
          for (final q in [
            'SELECT COUNT(*) FROM parties',
            'SELECT COUNT(*) FROM party_dedup_suspects',
            'SELECT COUNT(*) FROM table_reservations WHERE party_id IS NOT NULL',
            'SELECT COUNT(*) FROM accounts',
            'SELECT COUNT(*) FROM sqlite_master',
          ])
            ((await db.customSelect(q).getSingle()).data.values.first as num).toInt()
        ];

    await db.runOnUpgrade(Migrator(db), 195, 196);
    final once = await snapshot();
    // drift re-runs the same upgrade on the next boot when it died before stamping.
    await db.runOnUpgrade(Migrator(db), 195, 196);
    expect(await snapshot(), once);
    expect(once[2], 2, reason: 'both reservations linked');
  });
}
