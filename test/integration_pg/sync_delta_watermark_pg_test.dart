// Integration review 2026-11-04 — INT-03 / INT-04 / INT-05 on PostgreSQL.
//
// The review could only reproduce these on SQLite. Here the same contracts run
// against a real PostgreSQL server: the `fn_bump_row_version` BEFORE INSERT
// trigger stamps new rows (INT-03 is a SQLite-only defect), the inclusive
// `>= since` watermark serves a row stamped in the watermark's own second
// (INT-05), and the KDS category→station mapping saves (INT-04). Round 2:
// a row of a transaction that was open across a pull (stamped with that
// transaction's start, below the wall clock) is served by the next delta.
@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/kitchen_repository_impl.dart';
import 'package:picpos_erp/services/api/api_handler.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';

import '_support/pg_fixture.dart';

void main() {
  late PgTestFixture fx;
  late ApiHandler handler;

  setUpAll(() async {
    fx = await bootPgTestSchema();
    await fx.db.customSelect('SELECT 1').get();
    handler = ApiHandler(fx.db);
  });

  tearDownAll(() async => fx.tearDown());

  /// `/api/sync/pull` as the full-access user (id 1), as the auth middleware
  /// would hand it over after verifying the session token.
  Future<({List<Map<String, dynamic>> rows, int? serverTime})> pull(
    String table,
    int? since,
  ) async {
    final qs = since == null ? '' : '&since=$since';
    final request = shelf.Request(
      'GET',
      Uri.parse('http://localhost/api/sync/pull?table=$table$qs'),
    ).change(context: {ApiUserCtx.userIdKey: 1});
    final response = await handler.buildRouter().call(request);
    expect(response.statusCode, 200);
    final body =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    return (
      rows: (body['rows'] as List).cast<Map<String, dynamic>>(),
      serverTime: body['serverTime'] as int?,
    );
  }

  Future<void> alignToSecondStart() async {
    final ms = DateTime.now().millisecondsSinceEpoch % 1000;
    await Future<void>.delayed(Duration(milliseconds: 1000 - ms + 5));
  }

  test('INT-03 on PostgreSQL: the insert trigger stamps a new product and the '
      'next delta pull serves it', () async {
    final w0 = (await pull('products', null)).serverTime!;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await fx.db.insertProduct(
      ProductsCompanion.insert(code: 'PG-SYNC-1', name: 'صنف'),
    );
    final delta = await pull('products', w0);
    final hit = delta.rows.where((r) => r['code'] == 'PG-SYNC-1').toList();
    expect(hit, hasLength(1));
    expect(hit.single['last_modified_at'], isNotNull);
    expect(hit.single['row_version'], 0);
  });

  test('INT-03 on PostgreSQL: a new kitchen work order reaches a remote KDS '
      'through the delta', () async {
    final w0 = (await pull('work_orders', null)).serverTime!;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final productId = await fx.db.insertProduct(
      ProductsCompanion.insert(code: 'PG-KDS-1', name: 'برجر'),
    );
    final id = await KitchenRepositoryImpl(fx.db).createWorkOrder(
      orderNumber: 'WO-PG-1',
      station: 'grill',
      items: [
        WorkOrderItemData(productId: productId, productName: 'برجر', quantity: 1),
      ],
    );
    final delta = await pull('work_orders', w0);
    expect(delta.rows.where((r) => r['id'] == id), hasLength(1),
        reason: 'rows=${delta.rows}');
  });

  test('INT-05 on PostgreSQL: a row stamped in the watermark second is still '
      'served by the next delta pull', () async {
    await alignToSecondStart();
    final w0 = (await pull('products', null)).serverTime!;
    await fx.db.insertProduct(
      ProductsCompanion.insert(code: 'PG-RACE-1', name: 'سباق'),
    );
    final stamp = (await fx.db.customSelect(
      "SELECT last_modified_at AS t FROM products WHERE code = 'PG-RACE-1'",
    ).getSingle()).data['t'] as int;
    expect(stamp, w0, reason: 'precondition: the trigger stamped the same '
        'second as the watermark');

    final delta = await pull('products', w0);
    expect(delta.rows.where((r) => r['code'] == 'PG-RACE-1'), hasLength(1));
  });

  test('INT-05 on PostgreSQL, long transaction: a row written by a '
      'transaction that started before the pull and commits after it is '
      'served by the next delta', () async {
    final w0 = (await pull('products', null)).serverTime!;
    final writer = openExtraPgConnection();
    addTearDown(writer.close);
    await writer.customSelect('SELECT 1').get();

    final inserted = Completer<void>();
    final release = Completer<void>();
    // Transaction T: NOW() (the stamp) is fixed at its start.
    final tx = writer.transaction(() async {
      await writer.customStatement(
        "INSERT INTO products (code, name) VALUES ('PG-LONG-1', 'طويلة')",
      );
      inserted.complete();
      await release.future;
    });
    await inserted.future;
    // The reader pulls well after T started, while T is still open.
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    final during = await pull('products', w0);
    expect(during.rows.where((r) => r['code'] == 'PG-LONG-1'), isEmpty,
        reason: 'precondition: T is not committed yet');
    final w1 = during.serverTime!;

    release.complete();
    await tx;
    final stamp = (await fx.db.customSelect(
      "SELECT last_modified_at AS t FROM products WHERE code = 'PG-LONG-1'",
    ).getSingle()).data['t'] as int;

    final after = await pull('products', w1);
    expect(after.rows.where((r) => r['code'] == 'PG-LONG-1'), hasLength(1),
        reason: 'stamp=$stamp (start of T) vs next since=$w1');
  });

  test('INT-05 on PostgreSQL: with no open transaction the watermark is the '
      'database clock, not held back', () async {
    final clock = (await fx.db.customSelect(
      'SELECT FLOOR(EXTRACT(EPOCH FROM clock_timestamp()))::bigint AS t',
    ).getSingle()).data['t'] as int;
    final w = (await pull('products', null)).serverTime!;
    expect(w, inInclusiveRange(clock, clock + 2));
  });

  test('INT-04 on PostgreSQL: mapping a category to a KDS station saves and '
      'routes the category', () async {
    final kitchen = KitchenRepositoryImpl(fx.db);
    final stationId = await kitchen.createStation(name: 'الشواية', code: 'grill');
    final categoryId = await fx.db
        .into(fx.db.categories)
        .insert(CategoriesCompanion.insert(name: 'مشويات'));
    await kitchen.setCategoryStationMapping(categoryId, stationId);
    expect(await kitchen.getStationForCategory(categoryId), 'grill');
    await kitchen.removeCategoryStationMapping(categoryId);
    expect(await kitchen.getStationForCategory(categoryId), 'kitchen');
  });
}
