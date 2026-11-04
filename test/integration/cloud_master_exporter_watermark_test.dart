// Integration review 2026-11-04, round 2 — the cloud master export compares
// its watermark INCLUSIVELY (same defect class as INT-05 in /api/sync/pull).
//
// `last_modified_at` is stored in whole epoch seconds. A row stamped in the
// watermark's own second has `last_modified_at == floor(since)`; the strict
// `> ?` (route customers), `isBiggerThanValue` (products) and `isAfter`
// (price lists) skipped it until the next full push. Re-sending a boundary
// row is harmless — `/desktop/master` upserts every entity by `global_id`
// (server/lib/src/service/desktop_service.dart `_write`), which the second
// test models by exporting the same window twice.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/cloud_sync/cloud_master_exporter.dart';

void main() {
  late AppDatabase db;
  // A whole second, as every stamp in the database is.
  const s = 1790000000;
  final since = DateTime.fromMillisecondsSinceEpoch(s * 1000);

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.forTesting();
  });
  tearDown(() async => db.close());

  Future<int> product(String code, int stamp) async {
    final id = await db.insertProduct(
        ProductsCompanion.insert(code: code, name: code));
    // `row_version + 1` so the update trigger keeps the explicit stamp.
    await db.customStatement(
      'UPDATE products SET last_modified_at = ?, row_version = row_version + 1 '
      'WHERE id = ?',
      [stamp, id],
    );
    return id;
  }

  Future<void> routeCustomerEndedLongAgo(int stamp) async {
    final rep = await db.into(db.employees)
        .insert(EmployeesCompanion.insert(name: 'Rep W'));
    final customer = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'Cust W', isCustomer: const Value(true)));
    final route = await db.saveDistributionRoute(
        name: 'Route W', repEmployeeId: rep, visitDays: const [1]);
    await db.assignCustomerToRoute(
        customerId: customer, routeId: route, at: DateTime(2020));
    // Ended in 2021: only the "changed since" arm can select it.
    await db.customStatement(
      'UPDATE route_customers SET effective_to = ?, last_modified_at = ?, '
      'row_version = row_version + 1 WHERE customer_id = ?',
      [DateTime(2021).millisecondsSinceEpoch ~/ 1000, stamp, customer],
    );
  }

  Future<void> priceListWithItemAt(int stamp) async {
    final listId = await db.into(db.priceLists).insert(
          PriceListsCompanion.insert(
            name: 'قائمة الحد',
            code: 'PL-W',
            lastModifiedAt: Value(DateTime.fromMillisecondsSinceEpoch(
                (s - 100) * 1000)),
          ),
        );
    final p = await product('PL-ITEM', s - 100);
    await db.into(db.priceListItems).insert(PriceListItemsCompanion.insert(
          priceListId: listId,
          productId: p,
          price: 9,
          lastModifiedAt:
              Value(DateTime.fromMillisecondsSinceEpoch(stamp * 1000)),
        ));
  }

  List<String> names(Map<String, Object?> batch, String key) =>
      [for (final m in (batch[key] as List).cast<Map>()) m['name'] as String];

  test('a product, a route customer and a price-list item stamped in the '
      "watermark's own second are exported", () async {
    await product('AT-BOUNDARY', s);
    await product('BEFORE', s - 1);
    await routeCustomerEndedLongAgo(s);
    await priceListWithItemAt(s);

    final batch = await CloudMasterExporter(db).build(since: since);

    expect(names(batch, 'products'), isNot(contains('BEFORE')),
        reason: 'anchor: it is still an incremental export');
    // All three arms reported together, so a failure names every one.
    expect({
      'products': names(batch, 'products').contains('AT-BOUNDARY'),
      'routeCustomers': (batch['routeCustomers'] as List).length == 1,
      'priceLists': names(batch, 'priceLists').contains('قائمة الحد'),
    }, {'products': true, 'routeCustomers': true, 'priceLists': true});
  });

  test('the same boundary window exported twice yields the same global ids '
      '(the cloud upsert by global_id makes the repeat a no-op)', () async {
    await product('AT-BOUNDARY', s);
    Set<String> gids(Map<String, Object?> b) => {
          for (final m in (b['products'] as List).cast<Map>())
            m['globalId'] as String,
        };
    final first = await CloudMasterExporter(db).build(since: since);
    final second = await CloudMasterExporter(db).build(since: since);
    expect(gids(first), isNotEmpty);
    expect(gids(second), gids(first));
  });
}
