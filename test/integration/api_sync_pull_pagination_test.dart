// ═══════════════════════════════════════════════════════════════════════════
// GET /api/sync/pull — bounded pages + keyset cursor
// ═══════════════════════════════════════════════════════════════════════════
//
// The endpoint used to run `SELECT * FROM <table> WHERE last_modified_at > ?`
// with NO LIMIT. A table with a large backlog — or ANY `since=null` first pull
// — materialised the entire table, JSON-encoded it, and shipped it in one
// response, on the same isolate that serves every other client and the
// server's own UI. That is the mechanism behind "one or two clients load the
// whole system while the rest are fine": whichever device had a stale or
// absent watermark pulled everything and every other request queued behind it.
//
// These tests pin the replacement contract:
//   • a response never exceeds `limit` rows, and `hasMore` reports truthfully;
//   • `limit` is clamped, so a client cannot ask for an unbounded result set;
//   • paging with the `(cursorTs, cursorId)` keyset walks the table exactly
//     once — no duplicates, no gaps — INCLUDING when many rows share one
//     `last_modified_at`, which is precisely where an OFFSET or a
//     timestamp-only cursor loses rows.
//
// Harness matches api_p1_8b_sync_scope_test: buildRouter() has no auth
// middleware, so a validated userId is injected straight onto the request
// context. userId 1 is the seeded admin (unrestricted → no branch clamp).
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_handler.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';

void main() {
  late AppDatabase db;
  late ApiHandler handler;

  const adminUserId = 1;

  /// Rows this test inserts. Deliberately not a multiple of the page sizes
  /// used below, so an off-by-one in the trim or the cursor shows up.
  const insertedCategories = 37;

  /// Actual `categories` row count — the seeder creates its own defaults on
  /// top of what this test inserts, so the expected total is read from the DB
  /// rather than assumed.
  late int totalRows;

  setUp(() async {
    db = AppDatabase.forTesting();
    handler = ApiHandler(db);

    // `categories` is a reference table (no branch column) so nothing is
    // clamped away and the row count under test is exactly what we seeded.
    for (var i = 0; i < insertedCategories; i++) {
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              name: 'تصنيف ${i.toString().padLeft(3, '0')}',
              globalId: Value('gid-cat-page-$i'),
            ),
          );
    }
    // Give every row the SAME last_modified_at. This is the adversarial case
    // for pagination: with a timestamp-only cursor the second page would
    // either repeat page one forever or skip the whole tail.
    await db.customStatement(
      'UPDATE categories SET last_modified_at = 1700000000',
    );

    totalRows = (await db
            .customSelect('SELECT COUNT(*) AS c FROM categories')
            .getSingle())
        .read<int>('c');
    expect(totalRows, greaterThanOrEqualTo(insertedCategories));
  });

  tearDown(() => db.close());

  Future<Map<String, dynamic>> pull(
    String table, {
    int? userId = adminUserId,
    int? limit,
    int? cursorTs,
    int? cursorId,
    int? since,
  }) async {
    final q = <String>[
      'table=$table',
      if (limit != null) 'limit=$limit',
      if (cursorTs != null) 'cursorTs=$cursorTs',
      if (cursorId != null) 'cursorId=$cursorId',
      if (since != null) 'since=$since',
    ].join('&');
    final resp = await handler.buildRouter().call(shelf.Request(
          'GET',
          Uri.parse('http://localhost/api/sync/pull?$q'),
          context:
              userId != null ? {ApiUserCtx.userIdKey: userId} : const {},
        ));
    final body = await resp.readAsString();
    expect(resp.statusCode, 200, reason: 'pull $table failed: $body');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> rowsOf(Map<String, dynamic> body) =>
      (body['rows'] as List).cast<Map<String, dynamic>>();

  test('a page never exceeds limit and hasMore reports the remainder',
      () async {
    final page = await pull('categories', limit: 10);

    expect(rowsOf(page).length, 10, reason: 'must be capped at limit');
    expect(page['count'], 10);
    expect(page['hasMore'], isTrue,
        reason: '$totalRows rows seeded, only 10 returned');
    expect(page['limit'], 10);
  });

  test('hasMore is false on the last page', () async {
    final page = await pull('categories', limit: 100);

    expect(rowsOf(page).length, totalRows);
    expect(page['hasMore'], isFalse,
        reason: 'the whole table fits in one page of 100');
  });

  test('limit is clamped — a client cannot request an unbounded set',
      () async {
    // Above the 2000 ceiling.
    final huge = await pull('categories', limit: 999999);
    expect(huge['limit'], 2000, reason: 'clamped down to the max');

    // Below the floor.
    final zero = await pull('categories', limit: 0);
    expect(zero['limit'], 1, reason: 'clamped up to the min');
    expect(rowsOf(zero).length, 1);

    // Garbage falls back to the default rather than becoming unbounded.
    final resp = await handler.buildRouter().call(shelf.Request(
          'GET',
          Uri.parse(
              'http://localhost/api/sync/pull?table=categories&limit=abc'),
          context: const {ApiUserCtx.userIdKey: adminUserId},
        ));
    final body = jsonDecode(await resp.readAsString()) as Map<String, dynamic>;
    expect(body['limit'], 500, reason: 'unparseable limit → default page size');
  });

  test(
      'keyset paging walks every row exactly once when all timestamps are '
      'identical', () async {
    final seen = <int>[];
    int? cursorTs;
    int? cursorId;
    var pages = 0;

    while (true) {
      pages++;
      expect(pages, lessThan(20), reason: 'paging must terminate');

      final page = await pull(
        'categories',
        limit: 7,
        cursorTs: cursorTs,
        cursorId: cursorId,
      );
      final rows = rowsOf(page);
      for (final r in rows) {
        seen.add(r['id'] as int);
      }

      if (page['hasMore'] != true || rows.isEmpty) break;
      cursorTs = (rows.last['last_modified_at'] as num?)?.toInt() ?? 0;
      cursorId = rows.last['id'] as int;
    }

    expect(seen.length, totalRows,
        reason: 'every seeded row must appear — no gaps');
    expect(seen.toSet().length, totalRows,
        reason: 'no row may appear twice — no duplicates');

    // Ordering is (last_modified_at, id) ascending; timestamps are equal here,
    // so ids must come back strictly increasing across the whole walk.
    final sorted = [...seen]..sort();
    expect(seen, sorted, reason: 'rows must arrive in stable cursor order');
  });

  test('paging still walks every row when timestamps differ', () async {
    // Spread the rows across three distinct timestamps, including a NULL
    // bucket, so the COALESCE(last_modified_at, 0) ordering is exercised.
    await db.customStatement(
      'UPDATE categories SET last_modified_at = NULL WHERE id % 3 = 0',
    );
    await db.customStatement(
      'UPDATE categories SET last_modified_at = 1700000500 WHERE id % 3 = 1',
    );

    final seen = <int>[];
    int? cursorTs;
    int? cursorId;

    while (true) {
      final page = await pull(
        'categories',
        limit: 5,
        cursorTs: cursorTs,
        cursorId: cursorId,
      );
      final rows = rowsOf(page);
      for (final r in rows) {
        seen.add(r['id'] as int);
      }
      if (page['hasMore'] != true || rows.isEmpty) break;
      cursorTs = (rows.last['last_modified_at'] as num?)?.toInt() ?? 0;
      cursorId = rows.last['id'] as int;
    }

    expect(seen.length, totalRows);
    expect(seen.toSet().length, totalRows);
  });
}
