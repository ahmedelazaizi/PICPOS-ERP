// Integration review 2026-11-04, round 2 — INT-03 on SQLite at the database
// level (schema v198, lib/data/database/sqlite_sync_triggers.dart).
//
// Round 1 stamped `last_modified_at` inside `AppDatabase.into()` only, so
// `batch.insert` and raw SQL inserts were born NULL, and a database created by
// `onCreate` had no AFTER UPDATE trigger at all (v129 runs in `onUpgrade`
// only): an edit on a freshly installed SQLite server never reached another
// device through the delta. These tests drive every write path — drift insert,
// batch, raw INSERT, drift update, raw UPDATE — on a fresh database, on an
// upgraded one (file at user_version 196), and end to end through
// `GET /api/sync/pull` to a second paired device.
//
// They deliberately reference no symbol introduced by the fix (trigger names
// are matched as strings) so the same file compiles — and fails — on the
// pre-fix tree.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

import '../helpers/lan_host_harness.dart';

int _nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

Future<Map<String, Object?>> _row(AppDatabase db, String table, int id) async =>
    (await db.customSelect(
      'SELECT last_modified_at, row_version FROM $table WHERE id = ?',
      variables: [Variable.withInt(id)],
    ).getSingle()).data;

Future<int> _lastId(AppDatabase db, String table) async =>
    ((await db.customSelect('SELECT MAX(id) AS id FROM $table').getSingle())
            .data['id'] as num)
        .toInt();

Future<Set<String>> _triggers(AppDatabase db) async => (await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'trigger'")
        .get())
    .map((r) => r.data['name'] as String)
    .toSet();

/// Sync tables that exist in [db] with both `id` and `last_modified_at`.
Future<List<String>> _stampableSyncTables(AppDatabase db) async {
  final out = <String>[];
  for (final t in AppDatabase.syncHardenedTablesForTest) {
    final cols = (await db.customSelect('PRAGMA table_info($t)').get())
        .map((r) => r.data['name'] as String)
        .toSet();
    if (cols.contains('id') && cols.contains('last_modified_at')) out.add(t);
  }
  return out;
}

/// The write paths every check below runs, on [db].
Future<void> _expectEveryPathStamps(AppDatabase db) async {
  final before = _nowSec();

  // 1) raw SQL INSERT (the 23 `customStatement('INSERT …')` sites).
  await db.customStatement("INSERT INTO categories (name) VALUES ('raw')");
  final rawId = await _lastId(db, 'categories');
  // 2) batch.insert (field_audit_dao / inventory_transfers_dao).
  await db.batch((b) => b.insert(
        db.categories,
        CategoriesCompanion.insert(name: 'batch'),
      ));
  final batchId = await _lastId(db, 'categories');
  // 3) drift insert through a DAO (into()).
  final daoId = await db.insertProduct(
    ProductsCompanion.insert(code: 'TRG-1', name: 'dao'),
  );
  final after = _nowSec();

  for (final (table, id, path) in [
    ('categories', rawId, 'raw INSERT'),
    ('categories', batchId, 'batch.insert'),
    ('products', daoId, 'DAO insert'),
  ]) {
    final r = await _row(db, table, id);
    expect(r['last_modified_at'], inInclusiveRange(before, after + 1),
        reason: '$path must be stamped (delta pull filters '
            '`last_modified_at IS NOT NULL AND >= since`)');
    expect(r['row_version'], 0,
        reason: '$path: an insert keeps row_version 0, as on PostgreSQL');
  }

  // 4) an explicit stamp (a pulled row applied with the server's stamp) is
  //    kept, on every insert path.
  await db.customStatement(
    "INSERT INTO categories (name, last_modified_at) VALUES ('kept', 1700000000)",
  );
  final keptId = await _lastId(db, 'categories');
  expect((await _row(db, 'categories', keptId))['last_modified_at'], 1700000000);

  // 5) raw UPDATE bumps row_version and refreshes the stamp.
  await db.customStatement(
    "UPDATE categories SET name = 'raw-upd' WHERE id = ?",
    [keptId],
  );
  var r = await _row(db, 'categories', keptId);
  expect(r['row_version'], 1, reason: 'raw UPDATE must bump row_version');
  expect(r['last_modified_at'], greaterThanOrEqualTo(before),
      reason: 'raw UPDATE must refresh last_modified_at');

  // 6) drift update() (the DAO/repository path) bumps too.
  await (db.update(db.categories)..where((c) => c.id.equals(keptId)))
      .write(const CategoriesCompanion(name: Value('dao-upd')));
  r = await _row(db, 'categories', keptId);
  expect(r['row_version'], 2);

  // 7) a writer that advances row_version itself is respected (PG parity:
  //    `NEW.row_version = OLD.row_version` is the only bump condition).
  await db.customStatement(
    'UPDATE categories SET row_version = row_version + 1, '
    'last_modified_at = 1700000005 WHERE id = ?',
    [keptId],
  );
  r = await _row(db, 'categories', keptId);
  expect(r['row_version'], 3);
  expect(r['last_modified_at'], 1700000005);
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    preMigrationBackupOverride = () async => 'test-no-backup';
  });
  tearDownAll(() => preMigrationBackupOverride = null);

  group('fresh SQLite database (onCreate)', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.forTesting();
      await db.customSelect('SELECT 1').get();
    });
    tearDown(() async => db.close());

    test('every sync table that has the columns carries the insert and the '
        'update trigger', () async {
      final tables = await _stampableSyncTables(db);
      expect(tables, isNotEmpty);
      final names = await _triggers(db);
      final missing = [
        for (final t in tables)
          if (!names.contains('${t}_sync_stamp_insert') ||
              !names.contains('${t}_bump_version'))
            t,
      ];
      expect(missing, isEmpty,
          reason: 'sync tables without both triggers: $missing');
    });

    test('insert (raw / batch / DAO) and update (raw / drift) are all stamped',
        () => _expectEveryPathStamps(db));

    test('lazily created sync tables (modifier groups) are stamped as soon as '
        'they are created, not only after the next boot', () async {
      await db.ensureModifierTables();
      final before = _nowSec();
      await db.customStatement(
          "INSERT INTO modifier_groups (name) VALUES ('إضافات')");
      final id = await _lastId(db, 'modifier_groups');
      final r = await _row(db, 'modifier_groups', id);
      expect(r['last_modified_at'], greaterThanOrEqualTo(before));
      expect(r['row_version'], 0);
    });
  });

  group('upgraded SQLite database', () {
    test('runOnUpgrade(197 → 198) installs the triggers on a database that '
        'had none', () async {
      final db = AppDatabase.forTesting();
      addTearDown(db.close);
      for (final n in await _triggers(db)) {
        if (n.endsWith('_sync_stamp_insert') || n.endsWith('_bump_version')) {
          await db.customStatement('DROP TRIGGER $n');
        }
      }
      await db.runOnUpgrade(Migrator(db), 197, 198);
      final tables = await _stampableSyncTables(db);
      final names = await _triggers(db);
      expect(
        [
          for (final t in tables)
            if (!names.contains('${t}_sync_stamp_insert')) t,
        ],
        isEmpty,
      );
      await _expectEveryPathStamps(db);
    });

    test('a v196 database file opened by this build is upgraded and every '
        'write path is stamped; a legacy NULL row is stamped by its next edit',
        () async {
      final dir = await Directory.systemTemp.createTemp('int03_v196_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/picpos_v196.db');

      // Shape it as an install created by an older build: no stamping
      // triggers (onCreate never made any), a legacy unstamped row, and
      // user_version 196.
      final old = AppDatabase.withExecutor(NativeDatabase(file));
      await old.customSelect('SELECT 1').get();
      for (final n in await _triggers(old)) {
        if (n.endsWith('_sync_stamp_insert') || n.endsWith('_bump_version')) {
          await old.customStatement('DROP TRIGGER $n');
        }
      }
      await old.customStatement(
          "INSERT INTO categories (name) VALUES ('legacy-null')");
      final legacyId = await _lastId(old, 'categories');
      expect((await _row(old, 'categories', legacyId))['last_modified_at'],
          isNull,
          reason: 'anchor: the old shape really writes unstamped rows');
      await old.customStatement('PRAGMA user_version = 196');
      await old.close();

      final db = AppDatabase.withExecutor(NativeDatabase(file));
      addTearDown(db.close);
      final v = await db.customSelect('PRAGMA user_version').getSingle();
      expect(v.data.values.first, db.schemaVersion);
      expect(db.schemaVersion, greaterThanOrEqualTo(198));

      await db.customStatement(
        "UPDATE categories SET name = 'legacy-edited' WHERE id = ?",
        [legacyId],
      );
      final legacy = await _row(db, 'categories', legacyId);
      expect(legacy['last_modified_at'], isNotNull,
          reason: 'an edit of a pre-v198 row must reach the delta');
      expect(legacy['row_version'], 1);

      await _expectEveryPathStamps(db);
    });
  });

  group('end to end on a SQLite host: device B sees device-A-side writes in '
      'its next delta pull', () {
    late LanHost host;
    late String base;
    final devices = <LanDevice>[];

    setUp(() async {
      host = await LanHost.start();
      await HostFixture.seed(host.db);
      base = await host.serve();
    });
    tearDown(() async {
      for (final d in devices) {
        await d.dispose();
      }
      devices.clear();
      await host.close();
    });

    Future<LanDevice> reader() async {
      final offer = await host.issue(kind: 'mirror');
      final d = LanDevice(host.overHttp(base), 'reader-B', rolesFrom: host.db);
      devices.add(d);
      expect((await d.pair(offer.code)).status, 200);
      expect((await d.login('admin', kHostAdminPw)).status, 200);
      return d;
    }

    Future<({Set<String> names, int serverTime})> pull(
        LanDevice d, int? since) async {
      final r = await d.get(
          '/api/sync/pull?table=categories${since == null ? '' : '&since=$since'}');
      expect(r.status, 200, reason: '$r');
      return (
        names: (r.json['rows'] as List)
            .map((e) => (e as Map)['name'] as String)
            .toSet(),
        serverTime: r.json['serverTime'] as int,
      );
    }

    test('raw INSERT, batch.insert, raw UPDATE and drift update all arrive',
        () async {
      // A row that predates the watermark, with an old explicit stamp.
      await host.db.customStatement(
        "INSERT INTO categories (name, last_modified_at) "
        "VALUES ('old-a', 1700000000), ('old-b', 1700000000)",
      );
      final b = await reader();
      final w0 = (await pull(b, null)).serverTime;
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      await host.db.customStatement(
          "INSERT INTO categories (name) VALUES ('new-raw')");
      await host.db.batch((x) => x.insert(
            host.db.categories,
            CategoriesCompanion.insert(name: 'new-batch'),
          ));
      final d1 = await pull(b, w0);
      expect(d1.names, containsAll(['new-raw', 'new-batch']));
      expect(d1.names, isNot(contains('old-a')),
          reason: 'anchor: the delta is a delta, not a full dump');

      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await host.db.customStatement(
          "UPDATE categories SET description = 'x' WHERE name = 'old-a'");
      await (host.db.update(host.db.categories)
            ..where((c) => c.name.equals('old-b')))
          .write(const CategoriesCompanion(description: Value('y')));
      final d2 = await pull(b, d1.serverTime);
      expect(d2.names, containsAll(['old-a', 'old-b']),
          reason: 'an edit on a freshly created SQLite host must reach the '
              'other device through the delta (v129 trigger was upgrade-only)');
    });
  });
}
