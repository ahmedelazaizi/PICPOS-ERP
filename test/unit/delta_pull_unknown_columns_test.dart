// D-1: a host on a newer schema sends columns this (older) client does not
// have. The inbound upsert must drop the unknown keys (with one SYNC-WARN
// line per table) and still apply the row — not fail with "no such column".
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';

import '../helpers/v195_reservations_db.dart';

void main() {
  late AppDatabase db;
  late int tableId;

  setUp(() async {
    db = AppDatabase.forTesting();
    DeltaPullService.instance.initialize(db);
    tableId = await insertTestTable(db, 'T1');
  });

  tearDown(() => db.close());

  Map<String, dynamic> reservation(int id, String gid, {int? tableId0}) => {
        'id': id,
        'table_id': tableId0 ?? tableId,
        'customer_name': 'Ali',
        'customer_phone': '01001112222',
        'reservation_time': 1900000000,
        'party_size': 2,
        'status': 'pending',
        'created_at': 1700000000,
        'global_id': gid,
        // Columns a newer host has but this client does not:
        'future_column': 'x',
        'another_future_column': 7,
      };

  test('insert path: unknown host column is ignored, row is applied', () async {
    await DeltaPullService.instance
        .upsertRowForTest('table_reservations', reservation(8101, 'tr-d1-a'));

    final row = await rowOf(db, 'table_reservations', 8101);
    expect(row['customer_name'], 'Ali');
    expect(row['customer_phone'], '01001112222');
    expect(row.containsKey('future_column'), isFalse);
  });

  test('in-place update path (local id != server id) also drops unknown keys',
      () async {
    final localId = await insertTestReservation(db, tableId, 'Old', null);
    await db.customStatement(
        'UPDATE table_reservations SET global_id = ? WHERE id = ?',
        ['tr-d1-b', localId]);

    await DeltaPullService.instance
        .upsertRowForTest('table_reservations', reservation(8102, 'tr-d1-b'));

    final row = await rowOf(db, 'table_reservations', localId);
    expect(row['customer_name'], 'Ali',
        reason: 'the local row is updated in place despite the extra keys');
  });

  test('a row with only known columns is applied unchanged', () async {
    final r = reservation(8103, 'tr-d1-c')
      ..remove('future_column')
      ..remove('another_future_column');
    await DeltaPullService.instance.upsertRowForTest('table_reservations', r);
    expect((await rowOf(db, 'table_reservations', 8103))['customer_name'],
        'Ali');
  });

  test('column cache is per session: re-initialize clears it', () async {
    await DeltaPullService.instance
        .upsertRowForTest('table_reservations', reservation(8104, 'tr-d1-d'));
    // A fresh DB (new session) must not reuse the previous table_info.
    final db2 = AppDatabase.forTesting();
    DeltaPullService.instance.initialize(db2);
    final t2 = await insertTestTable(db2, 'T9');
    await DeltaPullService.instance.upsertRowForTest(
        'table_reservations', reservation(8105, 'tr-d1-e', tableId0: t2));
    expect((await rowOf(db2, 'table_reservations', 8105))['customer_name'],
        'Ali');
    DeltaPullService.instance.initialize(db);
  });
}
