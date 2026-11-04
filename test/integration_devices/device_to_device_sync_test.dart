// Integration review 2026-11-04: a change written by one paired device reaches
// another paired device through the host API (write endpoint -> host SQLite ->
// GET /api/sync/pull watermark delta), over a real loopback socket.
//
// The pull is driven the way DeltaPullService drives it
// (lib/services/delta_pull_service.dart:655-773): the next `since` is the
// `serverTime` (epoch seconds) of the previous successful pull.
import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/kitchen_repository_impl.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';

import '../helpers/lan_host_harness.dart';

void main() {
  late LanHost host;
  late HostFixture fx;
  late String base;
  final devices = <LanDevice>[];

  setUp(() async {
    host = await LanHost.start();
    fx = await HostFixture.seed(host.db);
    base = await host.serve();
  });

  tearDown(() async {
    for (final d in devices) {
      await d.dispose();
    }
    devices.clear();
    await host.close();
  });

  Future<LanDevice> signedInClient(String id) async {
    final offer = await host.issue(kind: 'client', branchId: fx.branch1);
    final d = LanDevice(host.overHttp(base), id, rolesFrom: host.db);
    devices.add(d);
    expect((await d.pair(offer.code)).status, 200);
    expect((await d.login('admin', kHostAdminPw)).status, 200);
    return d;
  }

  Future<({List<Map<String, dynamic>> rows, int? serverTime})> pull(
    LanDevice d,
    String table,
    int? since,
  ) async {
    final r = await d.get(
      '/api/sync/pull?table=$table${since == null ? '' : '&since=$since'}',
    );
    expect(r.status, 200, reason: '$r');
    return (
      rows: (r.json['rows'] as List).cast<Map<String, dynamic>>(),
      serverTime: r.json['serverTime'] as int?,
    );
  }

  /// Waits until the wall clock is just past a second boundary so the steps
  /// that follow land inside one epoch second.
  Future<void> alignToSecondStart() async {
    final ms = DateTime.now().millisecondsSinceEpoch % 1000;
    await Future<void>.delayed(Duration(milliseconds: 1000 - ms + 5));
  }

  test('a product created on device A is stored once on the host and served to '
      'device B, with A\'s globalId, by a first (full) pull', () async {
    final a = await signedInClient('desk-A');
    final b = await signedInClient('desk-B');
    final body = {
      'code': 'SYNC-A-1',
      'name': 'صنف من الجهاز أ',
      'salePrice': 7.5,
      'globalId': 'f3b0c4a2-0000-4000-8000-00000000a001',
    };
    final created = await a.post('/api/products', body);
    expect(created.status, 200, reason: '$created');
    // A retry of the same write (offline outbox replay) is idempotent.
    final replay = await a.post('/api/products', body);
    expect(replay.json['serverId'], created.json['serverId']);

    final full = await pull(b, 'products', null);
    final hit = full.rows.where((r) => r['code'] == 'SYNC-A-1').toList();
    expect(hit, hasLength(1));
    expect(hit.single['sale_price'], 7.5);
    expect(hit.single['global_id'], 'f3b0c4a2-0000-4000-8000-00000000a001');
  });

  test(
    'a product created on device A arrives in device B\'s next delta pull',
    () async {
      final a = await signedInClient('desk-A');
      final b = await signedInClient('desk-B');
      final w0 = (await pull(b, 'products', null)).serverTime!;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(
        (await a.post('/api/products', {
          'code': 'SYNC-A-2',
          'name': 'ب',
        })).status,
        200,
      );

      final stamped = (await pull(
        b,
        'products',
        null,
      )).rows.singleWhere((r) => r['code'] == 'SYNC-A-2')['last_modified_at'];
      // Fixed INT-03 (was `last_modified_at = null` on the SQLite host).
      final delta = await pull(b, 'products', w0);
      expect(
        delta.rows.where((r) => r['code'] == 'SYNC-A-2'),
        hasLength(1),
        reason: 'last_modified_at on the host = $stamped',
      );
    },
  );

  test(
    'a row stamped in the same second as the reader\'s watermark is still '
    'delivered by the next delta pull',
    () async {
      final a = await signedInClient('desk-A');
      final b = await signedInClient('desk-B');
      await alignToSecondStart();
      final w0 = (await pull(b, 'products', null)).serverTime!;
      expect(
        (await a.post('/api/products', {
          'code': 'SYNC-RACE-1',
          'name': 'ج',
        })).status,
        200,
      );
      // Stamp exactly as the PostgreSQL BEFORE INSERT trigger does (epoch
      // seconds of "now"; database_pg_sync_infra.dart:289-294).
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(nowSec, w0, reason: 'precondition: same second as the watermark');
      await host.db.customStatement(
        'UPDATE products SET last_modified_at = ? WHERE code = ?',
        [nowSec, 'SYNC-RACE-1'],
      );

      // Fixed INT-05 (the filter is now `>= since`).
      final delta = await pull(b, 'products', w0);
      expect(delta.rows.where((r) => r['code'] == 'SYNC-RACE-1'), hasLength(1));
    },
  );

  test('INT-03 contract on SQLite: an insert through the DAOs stamps '
      'last_modified_at with "now" and leaves row_version at 0 (as the '
      'PostgreSQL trigger does); a value the row already carries is kept', () async {
    final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final id = await host.db.insertProduct(
      ProductsCompanion.insert(code: 'STAMP-1', name: 'ختم'),
    );
    final after = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final row = (await host.db.customSelect(
      'SELECT last_modified_at, row_version FROM products WHERE id = ?',
      variables: [Variable.withInt(id)],
    ).getSingle()).data;
    expect(row['last_modified_at'], inInclusiveRange(before, after));
    expect(row['row_version'], 0);

    final pulledStamp = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);
    final kept = await host.db.into(host.db.categories).insert(
      CategoriesCompanion.insert(
        name: 'مسحوب',
        lastModifiedAt: Value(pulledStamp),
      ),
    );
    final keptRow = (await host.db.customSelect(
      'SELECT last_modified_at FROM categories WHERE id = ?',
      variables: [Variable.withInt(kept)],
    ).getSingle()).data;
    expect(keptRow['last_modified_at'], 1700000000);
  });

  test('INT-05 inclusive watermark: the boundary row is served again by a '
      'repeated pull and applying it twice on the reader is idempotent',
      () async {
    final a = await signedInClient('desk-A');
    final b = await signedInClient('desk-B');
    expect(
      (await a.post('/api/products', {'code': 'SYNC-TWICE', 'name': 'د'}))
          .status,
      200,
    );
    final stamp = (await pull(b, 'products', null))
        .rows
        .singleWhere((r) => r['code'] == 'SYNC-TWICE')['last_modified_at']
        as int;
    final first = await pull(b, 'products', stamp);
    final second = await pull(b, 'products', stamp);
    final row = first.rows.singleWhere((r) => r['code'] == 'SYNC-TWICE');
    expect(second.rows.where((r) => r['code'] == 'SYNC-TWICE'), hasLength(1));

    final reader = AppDatabase.forTesting();
    addTearDown(reader.close);
    DeltaPullService.instance.initialize(reader);
    await DeltaPullService.instance.upsertRowForTest('products', row);
    await DeltaPullService.instance.upsertRowForTest('products', row);
    final copies = await reader.customSelect(
      "SELECT COUNT(*) AS c FROM products WHERE code = 'SYNC-TWICE'",
    ).getSingle();
    expect(copies.data['c'], 1);
  });

  group('kitchen work orders (KDS) reach a remote device', () {
    Future<int> sendToKitchen() async {
      final productId = await host.db.insertProduct(
        ProductsCompanion.insert(code: 'KDS-1', name: 'برجر'),
      );
      return KitchenRepositoryImpl(host.db).createWorkOrder(
        orderNumber: 'WO04-001',
        items: [
          WorkOrderItemData(
            productId: productId,
            productName: 'برجر',
            quantity: 2,
          ),
        ],
        station: 'grill',
        customerName: 'طاولة 4',
      );
    }

    test('a first (full) pull of work_orders carries a new order to another '
        'signed-in device', () async {
      final kds = await signedInClient('kds-1');
      final id = await sendToKitchen();

      final orders = await pull(kds, 'work_orders', null);
      final order = orders.rows.singleWhere((r) => r['id'] == id);
      expect(order['status'], 'pending');
      expect(order['station'], 'grill');
      final items = await pull(kds, 'work_order_items', null);
      expect(items.rows.where((r) => r['work_order_id'] == id), hasLength(1));
    });

    test(
      'a new order reaches the remote device through the watermark delta',
      () async {
        final kds = await signedInClient('kds-1');
        final w0 = (await pull(kds, 'work_orders', null)).serverTime!;
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        final id = await sendToKitchen();

        // Fixed INT-03: createWorkOrder's insert is stamped on SQLite too.
        final delta = await pull(kds, 'work_orders', w0);
        expect(
          delta.rows.where((r) => r['id'] == id),
          hasLength(1),
          reason: 'rows=${delta.rows}',
        );
      },
    );
  });
}
