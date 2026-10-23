// SYNC-001 (audit 2026-10-23): host-side client-schema handshake.
//  * a client that does not announce its schema (v195 and older) is served rows
//    WITHOUT the columns added after v195, so its upsert no longer fails and
//    silently drops the row;
//  * a client announcing >= v196 gets the full row;
//  * a client older than the supported minimum is refused with 426 (and the
//    client keeps its watermark);
//  * /api/health advertises the host schema and the minimum client schema.
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_handler.dart';
import 'package:ural_erp/services/api/api_user_context.dart';
import 'package:ural_erp/services/api/client_schema_gate.dart';

void main() {
  late AppDatabase db;
  late ApiHandler handler;

  setUp(() async {
    db = AppDatabase.forTesting();
    handler = ApiHandler(db);
    final partyId = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'ضيف', isCustomer: const Value(true)));
    final tableId = await db.into(db.restaurantTables).insert(
        RestaurantTablesCompanion.insert(name: 'T1'));
    await db.into(db.tableReservations).insert(
        TableReservationsCompanion.insert(
          tableId: tableId,
          customerName: 'ضيف',
          reservationTime: DateTime(2026, 11, 1, 19),
          partyId: Value(partyId),
        ));
  });

  tearDown(() => db.close());

  Future<shelf.Response> pull(String table, {Map<String, String>? headers}) =>
      Future.value(handler.buildRouter().call(shelf.Request(
        'GET',
        Uri.parse('http://localhost/api/sync/pull?table=$table'),
        headers: headers,
        context: {ApiUserCtx.userIdKey: 1},
      )));

  Future<List<Map<String, dynamic>>> rowsOf(shelf.Response r) async {
    expect(r.statusCode, 200);
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    return (body['rows'] as List).cast<Map<String, dynamic>>();
  }

  test('no announced schema (legacy v195 client): party_id is withheld',
      () async {
    final rows = await rowsOf(await pull('table_reservations'));
    expect(rows, hasLength(1));
    expect(rows.first.containsKey('party_id'), isFalse,
        reason: 'a v195 client has no such column → upsert would fail');
    expect(rows.first['customer_name'], 'ضيف');
  });

  test('client announcing the current schema receives party_id', () async {
    final rows = await rowsOf(await pull('table_reservations', headers: {
      ClientSchemaGate.headerName: '${db.schemaVersion}',
    }));
    expect(rows.first.containsKey('party_id'), isTrue);
  });

  test('client older than the supported minimum is refused with 426',
      () async {
    final r = await pull('table_reservations', headers: {
      ClientSchemaGate.headerName: '${ClientSchemaGate.minSupported - 1}',
    });
    expect(r.statusCode, 426);
    final body = jsonDecode(await r.readAsString()) as Map;
    expect(body['code'], 'client_upgrade_required');
    expect(body['minClientSchema'], ClientSchemaGate.minSupported);
  });

  test('health advertises schemaVersion and minClientSchema', () async {
    final r = await handler.buildRouter().call(
        shelf.Request('GET', Uri.parse('http://localhost/api/health')));
    final body = jsonDecode(await r.readAsString()) as Map;
    expect(body['schemaVersion'], db.schemaVersion);
    expect(body['minClientSchema'], ClientSchemaGate.minSupported);
  });

  test('unparseable header is treated as legacy, never as newest', () {
    expect(ClientSchemaGate.parse('abc'), ClientSchemaGate.legacySchema);
    expect(ClientSchemaGate.parse(null), ClientSchemaGate.legacySchema);
    expect(ClientSchemaGate.parse('196'), 196);
  });
}
