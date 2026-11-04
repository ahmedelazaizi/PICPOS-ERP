// Integration review 2026-11-04: a kitchen order sent from the tables POS is
// received by the kitchen display (KDS) on the SAME database.
//
// KitchenDisplayScreen renders `watchPendingOrders()` / `watchOrdersByStation`
// (kitchen_display_screen.dart:119-120); `_sendToKitchen` routes each item by
// `getStationForCategory` (table_pos_operations.dart:491-541). This test drives
// those repository calls on SQLite and observes the streams the screen uses.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/kitchen_repository_impl.dart';

void main() {
  late AppDatabase db;
  late KitchenRepositoryImpl kitchen;
  late int burgerId;
  late int grillCategoryId;

  setUp(() async {
    db = AppDatabase.forTesting();
    kitchen = KitchenRepositoryImpl(db);
    grillCategoryId = await db
        .into(db.categories)
        .insert(CategoriesCompanion.insert(name: 'مشويات'));
    burgerId = await db.insertProduct(
      ProductsCompanion.insert(code: 'BRG', name: 'برجر'),
    );
  });

  tearDown(() => db.close());

  /// The next emission of [stream] that satisfies [test].
  Future<T> nextWhere<T>(Stream<T> stream, bool Function(T) test) =>
      stream.firstWhere(test).timeout(const Duration(seconds: 5));

  test('an order routed to the grill station appears on the grill KDS and the '
      'all-stations KDS, not on another station', () async {
    await kitchen.createStation(name: 'الشواية', code: 'grill');
    // An unmapped category falls back to the default station.
    expect(await kitchen.getStationForCategory(grillCategoryId), 'kitchen');
    const station = 'grill';

    final grillScreen = kitchen.watchOrdersByStation('grill');
    final orderNumber = await kitchen.generateWorkOrderNumber();
    expect(orderNumber, matches(RegExp(r'^WO\d{2}-001$')));
    final id = await kitchen.createWorkOrder(
      orderNumber: orderNumber,
      station: station,
      items: [
        WorkOrderItemData(
          productId: burgerId,
          productName: 'برجر',
          quantity: 2,
          notes: 'بدون بصل',
        ),
      ],
    );

    final onGrill = await nextWhere(grillScreen, (l) => l.isNotEmpty);
    expect(onGrill.single.id, id);
    expect(onGrill.single.status, 'pending');
    final all = await kitchen.watchPendingOrders().first;
    expect(all.map((o) => o.id), [id]);
    expect(await kitchen.watchOrdersByStation('kitchen').first, isEmpty);

    final items = await kitchen.watchOrderItems(id).first;
    expect(items.single.quantity, 2);
    expect(items.single.notes, 'بدون بصل');
    expect(await kitchen.generateWorkOrderNumber(), endsWith('-002'));
  });

  test('urgent orders are listed first; ready orders leave the KDS queue and '
      'reach the POS ready list', () async {
    final normal = await kitchen.createWorkOrder(
      orderNumber: 'WO-N',
      items: [
        WorkOrderItemData(
          productId: burgerId,
          productName: 'برجر',
          quantity: 1,
        ),
      ],
    );
    final urgent = await kitchen.createWorkOrder(
      orderNumber: 'WO-U',
      priority: 'urgent',
      items: [
        WorkOrderItemData(
          productId: burgerId,
          productName: 'برجر',
          quantity: 1,
        ),
      ],
    );
    expect((await kitchen.watchPendingOrders().first).map((o) => o.id), [
      urgent,
      normal,
    ]);

    await kitchen.updateWorkOrderStatus(normal, 'preparing');
    expect(
      (await kitchen.watchPendingOrders().first).map((o) => o.id),
      containsAll([urgent, normal]),
    );

    final itemId = (await kitchen.watchOrderItems(normal).first).single.id;
    await kitchen.markItemReady(itemId);
    expect(await kitchen.areAllItemsReady(normal), isTrue);
    await kitchen.updateWorkOrderStatus(normal, 'ready');

    expect((await kitchen.watchPendingOrders().first).map((o) => o.id), [
      urgent,
    ]);
    final ready = await kitchen.watchReadyOrders().first;
    expect(ready.single.id, normal);
    expect(ready.single.preparedAt, isNotNull);
  });

  test(
    'mapping a category to a station in KDS settings routes that category',
    () async {
      final stationId = await kitchen.createStation(
        name: 'الشواية',
        code: 'grill',
      );
      await kitchen.setCategoryStationMapping(grillCategoryId, stationId);
      expect(await kitchen.getStationForCategory(grillCategoryId), 'grill');
      // Fixed INT-04 (customStatement now receives raw ints): a re-map
      // replaces the previous station instead of adding a second row.
      final bar = await kitchen.createStation(name: 'البار', code: 'bar');
      await kitchen.setCategoryStationMapping(grillCategoryId, bar);
      expect(await kitchen.getStationForCategory(grillCategoryId), 'bar');
      expect(await kitchen.getAllCategoryStationMappings(), hasLength(1));
      await kitchen.removeCategoryStationMapping(grillCategoryId);
      expect(await kitchen.getStationForCategory(grillCategoryId), 'kitchen');
    },
  );
}
