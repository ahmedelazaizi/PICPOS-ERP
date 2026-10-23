// Audit B DATA-001 — a table reservation made on a LAN client reaches the host:
// idempotent by global id, resolved through global ids, status never regresses.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase host;
  late int tableId;

  setUp(() async {
    host = AppDatabase.forTesting();
    final section = await host.createSection('hall');
    tableId = await host.createTable(name: 'T1', sectionId: section, capacity: 4);
    await (host.update(host.restaurantTables)..where((t) => t.id.equals(tableId)))
        .write(const RestaurantTablesCompanion(globalId: Value('table-gid-1')));
  });
  tearDown(() => host.close());

  Map<String, dynamic> doc({String status = 'pending', String gid = 'res-gid-1', String name = 'Ali'}) => {
        'globalId': gid,
        'tableGlobalId': 'table-gid-1',
        'customerName': name,
        'customerPhone': '0501234567',
        'partyGlobalId': null,
        'reservationTime': DateTime(2030, 1, 1, 20).toIso8601String(),
        'partySize': 4,
        'notes': null,
        'status': status,
      };

  Future<List<TableReservation>> rows() => host.select(host.tableReservations).get();
  Future<String> tableStatus() async =>
      (await (host.select(host.restaurantTables)..where((t) => t.id.equals(tableId))).getSingle()).status;

  test('client reservation lands on the host with the same global id', () async {
    final id = await applyTableReservationSnapshot(host, doc());
    final r = await rows();
    expect(r, hasLength(1));
    expect(r.single.id, id);
    expect(r.single.globalId, 'res-gid-1');
    expect(r.single.customerName, 'Ali');
    expect(r.single.tableId, tableId);
    expect(await tableStatus(), 'reserved');
  });

  test('replaying the same snapshot (offline -> online) is idempotent', () async {
    await applyTableReservationSnapshot(host, doc());
    await applyTableReservationSnapshot(host, doc());
    await applyTableReservationSnapshot(host, doc());
    expect(await rows(), hasLength(1));
  });

  test('cancel frees the table; a stale pending replay does not resurrect it',
      () async {
    await applyTableReservationSnapshot(host, doc());
    await applyTableReservationSnapshot(host, doc(status: 'cancelled'));
    expect((await rows()).single.status, 'cancelled');
    expect(await tableStatus(), 'available');
    await applyTableReservationSnapshot(host, doc(status: 'pending'));
    expect((await rows()).single.status, 'cancelled');
    expect(await tableStatus(), 'available');
  });

  test('unknown table asks the client to retry instead of dropping the write',
      () async {
    final d = doc()..['tableGlobalId'] = 'nope';
    await expectLater(applyTableReservationSnapshot(host, d),
        throwsA(isA<TableReservationDependencyMissing>()));
    expect(await rows(), isEmpty);
  });

  test('invalid document is rejected', () async {
    await expectLater(applyTableReservationSnapshot(host, doc(name: '')),
        throwsA(isA<ArgumentError>()));
  });

  test('client builds the wire document from global ids', () async {
    await host.createReservation(
        tableId: tableId,
        customerName: 'Sara',
        reservationTime: DateTime(2030, 1, 1, 19));
    final r = (await rows()).single;
    final d = buildTableReservationDocument(r,
        globalId: 'g', tableGlobalId: 'table-gid-1');
    expect(d['tableGlobalId'], 'table-gid-1');
    expect(d['customerName'], 'Sara');
    expect(d['status'], 'pending');
    expect(d.containsKey('tableId'), isFalse);
  });
}
