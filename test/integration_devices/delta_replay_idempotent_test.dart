// Integration review 2026-11-04, round 2 — a re-delivered boundary row must
// leave the reader's copy exactly as the server sent it.
//
// The inclusive watermark (INT-05: `>= since`, and on PostgreSQL the
// open-transaction floor) re-sends the rows of the boundary second by design;
// the client upsert is meant to make that harmless. But a byte-identical
// `ON CONFLICT(id) DO UPDATE` is not a no-op on SQLite: it fires the
// `{t}_bump_version` AFTER UPDATE trigger (row_version unchanged ⇒ bump), so
// every duplicate pushed the reader to server+1 with a local stamp. Every
// upgraded SQLite client carries that trigger (v129…v173), and since v198
// every new one does too. For the newerWins tables (parties, shifts) a copy
// that out-versions the server rejects the next genuine server row.
//
// The reader below installs the production v129 trigger itself (IF NOT
// EXISTS) so the file models an upgraded client on any tree.
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/conflict_resolution_service.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';

import '../helpers/lan_host_harness.dart';

Future<void> _installV129Trigger(AppDatabase db, String t) =>
    db.customStatement('''
      CREATE TRIGGER IF NOT EXISTS ${t}_bump_version
      AFTER UPDATE ON $t FOR EACH ROW
      WHEN NEW.row_version = OLD.row_version
      BEGIN
        UPDATE $t SET
          last_modified_at = strftime('%s', 'now'),
          row_version = OLD.row_version + 1
        WHERE id = NEW.id;
      END
    ''');

void main() {
  late LanHost host;
  late LanDevice b;

  setUp(() async {
    host = await LanHost.start();
    await HostFixture.seed(host.db);
    final base = await host.serve();
    final offer = await host.issue(kind: 'mirror');
    b = LanDevice(host.overHttp(base), 'reader', rolesFrom: host.db);
    expect((await b.pair(offer.code)).status, 200);
    expect((await b.login('admin', kHostAdminPw)).status, 200);
  });

  tearDown(() async {
    await b.dispose();
    await host.close();
  });

  Future<Map<String, dynamic>> pulled(String table, String where) async {
    final r = await b.get('/api/sync/pull?table=$table');
    expect(r.status, 200, reason: '$r');
    final rows = (r.json['rows'] as List).cast<Map<String, dynamic>>();
    final id = (await host.db.customSelect('SELECT id FROM $table WHERE $where')
            .getSingle())
        .data['id'];
    return rows.singleWhere((x) => x['id'] == id);
  }

  Future<Map<String, Object?>> local(AppDatabase db, String table, int id) async =>
      (await db.customSelect(
        'SELECT row_version, last_modified_at FROM $table WHERE id = ?',
        variables: [Variable.withInt(id)],
      ).getSingle()).data;

  test('applying the same pulled product twice keeps the server row_version '
      'and stamp on the reader', () async {
    await host.db.customStatement(
      "INSERT INTO products (code, name, last_modified_at, row_version) "
      "VALUES ('DUP-1', 'مكرر', 1700000000, 4)",
    );
    final row = await pulled('products', "code = 'DUP-1'");
    expect(row['row_version'], 4);

    final reader = AppDatabase.forTesting();
    addTearDown(reader.close);
    await _installV129Trigger(reader, 'products');
    DeltaPullService.instance.initialize(reader);
    // Checked after EVERY apply: without the guard the copy alternates
    // (dup ⇒ bump to 5; next dup carries 4 ≠ 5 ⇒ plain write back to 4), so
    // an odd number of deliveries hides the drift.
    for (var i = 1; i <= 3; i++) {
      await DeltaPullService.instance.upsertRowForTest('products', {...row});
      final copy = await local(reader, 'products', row['id'] as int);
      expect(copy['row_version'], 4,
          reason: 'delivery #$i bumped the reader copy');
      expect(copy['last_modified_at'], 1700000000,
          reason: 'delivery #$i restamped the reader copy');
    }
  });

  test('a genuine server change still applies (and only the payload decides)',
      () async {
    await host.db.customStatement(
      "INSERT INTO products (code, name, last_modified_at, row_version) "
      "VALUES ('DUP-2', 'قبل', 1700000000, 1)",
    );
    final first = await pulled('products', "code = 'DUP-2'");
    final reader = AppDatabase.forTesting();
    addTearDown(reader.close);
    await _installV129Trigger(reader, 'products');
    DeltaPullService.instance.initialize(reader);
    await DeltaPullService.instance.upsertRowForTest('products', first);

    final changed = {...first, 'name': 'بعد', 'row_version': 2,
        'last_modified_at': 1700000100};
    await DeltaPullService.instance.upsertRowForTest('products', changed);
    final r = (await reader.customSelect(
      'SELECT name, row_version, last_modified_at FROM products WHERE id = ?',
      variables: [Variable.withInt(first['id'] as int)],
    ).getSingle()).data;
    expect(r['name'], 'بعد');
    expect(r['row_version'], 2);
    expect(r['last_modified_at'], 1700000100);
  });

  test('newerWins (parties): after duplicate deliveries the next genuine '
      'server row is still accepted, not rejected as older', () async {
    await host.db.customStatement(
      "INSERT INTO parties (name, is_customer, global_id, last_modified_at, "
      "row_version) VALUES ('عميل مكرر', 1, 'gid-dup-party', 1700000000, 3)",
    );
    final row = await pulled('parties', "global_id = 'gid-dup-party'");

    final reader = AppDatabase.forTesting();
    addTearDown(reader.close);
    await _installV129Trigger(reader, 'parties');
    DeltaPullService.instance.initialize(reader);
    ConflictResolutionService.instance.initialize(reader);
    for (var i = 0; i < 3; i++) {
      await DeltaPullService.instance.upsertRowForTest('parties', {...row});
    }
    final genuine = {...row, 'name': 'عميل معدّل', 'row_version': 4,
        'last_modified_at': 1700000000 + 7200};
    await DeltaPullService.instance.upsertRowForTest('parties', genuine);
    final r = (await reader.customSelect(
      "SELECT name FROM parties WHERE global_id = 'gid-dup-party'",
    ).getSingle()).data;
    expect(r['name'], 'عميل معدّل',
        reason: 'the reader copy out-versioned the server after duplicates');
  });
}
