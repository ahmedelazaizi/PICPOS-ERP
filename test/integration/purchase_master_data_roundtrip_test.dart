// E-SYNC-1 — BEHAVIORAL sync round-trips (same embedded-server harness as
// voucher_discount_roundtrip_test.dart).
//
// M-10: POST /api/purchases must materialize the full purchase on the server —
//       header + lines + stock — atomically (one createPurchaseInvoice
//       transaction). Prior coverage only grep/DAO-tested the forwarding.
//
// M-11: a master record created offline (here a warehouse) must actually reach
//       and persist on the server via POST, not be silently marked "synced"
//       without an insert.
//
// SQLite in-memory; the per-user permission gate is OFF by default, so no auth
// header is needed — identical to a pre-Spec-060 install.

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/core/utils/uuid_v7.dart';
import 'package:ural_erp/services/api/api_handler.dart';
import 'package:ural_erp/services/api/api_user_context.dart';

void main() {
  late AppDatabase db;
  late ApiHandler handler;

  setUp(() {
    db = AppDatabase.forTesting();
    handler = ApiHandler(db);
  });
  tearDown(() async => db.close());

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final request = shelf.Request('POST', Uri.parse('http://localhost$path'),
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'}, context: {ApiUserCtx.userIdKey: 1},);
    final response = await handler.buildRouter().call(request);
    return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
  }

  test('POST /api/purchases materializes header + lines + stock (M-10)',
      () async {
    final whId = (await db.select(db.warehouses).get()).first.id;
    final supplierId = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'مورد تجريبي', isSupplier: const Value(true)));
    final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(code: 'P1', name: 'صنف تجريبي'));

    final resp = await post('/api/purchases', {
      'warehouseId': whId,
      'supplierId': supplierId,
      'paid': 0,
      'paymentMethod': 'cash',
      'globalId': UuidV7.generate(),
      'items': [
        {'productId': productId, 'quantity': 10.0, 'unitCost': 5.0, 'total': 50.0}
      ],
    });

    expect(resp['success'], isTrue, reason: 'server accepted the purchase: $resp');
    final serverId = resp['serverId'] as int;

    // Header persisted.
    final header = await (db.select(db.purchaseInvoices)
          ..where((p) => p.id.equals(serverId)))
        .getSingle();
    expect(header.supplierId, supplierId);

    // Lines persisted.
    final lines = await (db.select(db.purchaseInvoiceItems)
          ..where((i) => i.invoiceId.equals(serverId)))
        .get();
    expect(lines.length, 1);
    expect(lines.first.quantity, 10.0);

    // Stock materialized (the purchase moved stock for the product).
    final movements = await (db.select(db.stockMovements)
          ..where((m) => m.productId.equals(productId)))
        .get();
    expect(movements, isNotEmpty,
        reason: 'purchase must create a stock movement for the product');
  });

  test('POST /api/warehouses persists an offline-created master record (M-11)',
      () async {
    final gid = UuidV7.generate();
    final resp = await post('/api/warehouses', {
      'name': 'مخزن فرع جديد',
      'globalId': gid,
    });

    expect(resp['success'], isTrue, reason: 'server accepted the warehouse: $resp');

    // The record actually exists on the server, keyed by its client globalId.
    final wh = await (db.select(db.warehouses)
          ..where((w) => w.globalId.equals(gid)))
        .getSingleOrNull();
    expect(wh, isNotNull, reason: 'master record must be inserted, not just acked');
    expect(wh!.name, 'مخزن فرع جديد');
  });
}
