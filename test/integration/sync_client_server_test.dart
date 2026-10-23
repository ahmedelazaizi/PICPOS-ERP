/// Day-12 Integration Tests — Client-Server Sync Pipeline
///
/// Covers four scenarios that sit at the boundary between the local DB and
/// the server-side sync endpoints:
///
///   1. Mode gate: pushLocalSalesToServer() is a no-op outside client mode.
///   2. globalId is the SOLE dedup key (Feature 054): two DIFFERENT globalIds
///      that share the SAME invoice_number produce TWO distinct rows — the
///      server no longer dedups on invoice_number (that caused lost sales).
///   3. Outbox payload round-trip: JSON serialised into syncOutbox is
///      faithfully recovered on the read path.
///   4. Sale with line-items: postSale() with two items correctly persists
///      both rows in sales_invoice_items.
library;

import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/sync_repository_impl.dart';
import 'package:picpos_erp/services/api/api_sales_handler.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'admin', isSystemRole: const drift.Value(true)),
    );
    userId = await db.createUser(
      username: 'admin',
      password: 'pw',
      displayName: 'Admin',
      roleId: roleId,
    );
    warehouseId = await db.into(db.warehouses).insert(
      WarehousesCompanion.insert(
        name: 'Main',
        isActive: const drift.Value(true),
        isDefault: const drift.Value(true),
      ),
    );

    // validateFinancialPeriod requires a fiscal year covering today.
    await db.into(db.fiscalYears).insert(
      FiscalYearsCompanion.insert(
        name: '2026',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
      ),
    );
  });

  tearDown(() async => db.close());

  // ─────────────────────────────────────────────────────────────────────────
  // Test 1 — Mode gate
  // ─────────────────────────────────────────────────────────────────────────

  test(
    'pushLocalSalesToServer returns error message in non-client mode',
    () async {
      // NetworkService.instance defaults to NetworkMode.standalone in a test
      // environment (no SharedPreferences storage) — not NetworkMode.client.
      final repo = SyncRepositoryImpl(db);
      final result = await repo.pushLocalSalesToServer();

      expect(result.success, false,
          reason: 'non-client mode must return failure');
      expect(result.message, contains('العميل'),
          reason: 'error message must mention client mode');
      expect(result.itemsSynced, 0,
          reason: 'no invoices should have been pushed');
    },
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Test 2 — globalId is the SOLE dedup key (Feature 054)
  //
  // invoice_number-based dedup was DELIBERATELY removed in Feature 054
  // (api_sales_handler.dart — see the "Feature 054 (v134)" comment block;
  // sales_invoices.invoiceNumber carries no UNIQUE constraint). It caused a
  // real lost-sales incident: leftover prefixed numbers from a wiped client
  // session collided with fresh sales that each had a NEW globalId, so 15
  // genuine sales came back as duplicates and were dropped.
  //
  // Current contract: two DIFFERENT globalIds that happen to share the SAME
  // invoice_number are two DISTINCT sales → TWO rows, neither flagged as a
  // duplicate. (The same-globalId / different-number recovery path is pinned
  // by Test 2b below.)
  // ─────────────────────────────────────────────────────────────────────────

  test(
    'ApiSalesHandler treats same invoice_number + different globalId as two distinct sales',
    () async {
      final handler = ApiSalesHandler(db, {});

      // ── First request (novel invoice) ──────────────────────────────────
      final payload1 = jsonEncode({
        'invoiceNumber': 'DUP-SYNC-001',
        'globalId': const Uuid().v4(),
        'subtotal': 80.0,
        'total': 80.0,
        'paid': 80.0,
        'paymentMethod': 'cash',
        'warehouseId': warehouseId,
        'userId': userId,
        'items': [],
      });

      final response1 = await handler.postSale(
        Request(
          'POST',
          Uri.parse('http://localhost/api/sales'),
          body: payload1,
          headers: {'Content-Type': 'application/json'}, context: {ApiUserCtx.userIdKey: 1},
        ),
      );
      expect(response1.statusCode, 200);
      final body1 = jsonDecode(await response1.readAsString()) as Map<String, dynamic>;
      expect(body1['success'], true);
      expect(body1['duplicate'], isNot(true),
          reason: 'first submission must not be flagged as duplicate');
      final serverId1 = body1['serverId'] as int;

      // ── Second request — same invoiceNumber, DIFFERENT globalId ────────
      // Feature 054: invoice_number is NOT a dedup key. A different globalId
      // means a different logical sale, so this must insert a SECOND row and
      // NOT be flagged as a duplicate.
      final payload2 = jsonEncode({
        'invoiceNumber': 'DUP-SYNC-001', // same number
        'globalId': const Uuid().v4(), // different logical identity
        'subtotal': 80.0,
        'total': 80.0,
        'paid': 80.0,
        'paymentMethod': 'cash',
        'warehouseId': warehouseId,
        'userId': userId,
        'items': [],
      });

      final response2 = await handler.postSale(
        Request(
          'POST',
          Uri.parse('http://localhost/api/sales'),
          body: payload2,
          headers: {'Content-Type': 'application/json'}, context: {ApiUserCtx.userIdKey: 1},
        ),
      );
      expect(response2.statusCode, 200);
      final body2 = jsonDecode(await response2.readAsString()) as Map<String, dynamic>;
      expect(body2['success'], true);
      expect(body2['duplicate'], isNot(true),
          reason: 'a different globalId is a different sale — '
              'invoice_number dedup was removed in Feature 054');
      final serverId2 = body2['serverId'] as int;

      // Two distinct server rows were created.
      expect(serverId2, isNot(equals(serverId1)),
          reason: 'each globalId must map to its own row');
      final invoices = await db.select(db.salesInvoices).get();
      expect(invoices.length, 2,
          reason: 'same invoice_number + different globalId must create '
              'TWO rows (globalId is the sole dedup key)');
    },
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Test 2b — Spec 136: re-push with the SAME globalId but a DIFFERENT invoice
  // number must be a no-op. This is the pushLocalSalesToServer duplication bug:
  // the local invoice number (AQ-SINV-1) differs from the server's stored one
  // (AQ-POS-1), and invoice_number dedup was removed in Feature 054 — so the
  // ONLY thing preventing a duplicate is threading the stable globalId. Before
  // the fix the recovery button omitted globalId and re-inserted every sale as
  // a CLTCL- duplicate.
  // ─────────────────────────────────────────────────────────────────────────

  test(
    'Spec 136 — re-push with same globalId but different invoiceNumber is a no-op',
    () async {
      final handler = ApiSalesHandler(db, {});
      final gid = const Uuid().v4();

      Request req(Map<String, dynamic> body) => Request(
            'POST',
            Uri.parse('http://localhost/api/sales'),
            body: jsonEncode(body),
            headers: {'Content-Type': 'application/json'}, context: {ApiUserCtx.userIdKey: 1},
          );

      // Live sale — server stores it (under its own number, e.g. AQ-POS-1).
      final first = await handler.postSale(req({
        'invoiceNumber': 'AQ-POS-1',
        'globalId': gid,
        'subtotal': 50.0,
        'total': 50.0,
        'paid': 50.0,
        'paymentMethod': 'cash',
        'warehouseId': warehouseId,
        'userId': userId,
        'items': [],
      }));
      expect(first.statusCode, 200);
      final b1 = jsonDecode(await first.readAsString()) as Map<String, dynamic>;
      expect(b1['duplicate'], isNot(true));

      // Recovery re-push: SAME globalId, but the LOCAL number differs from the
      // server's stored number. globalId dedup must catch it → no second row.
      final second = await handler.postSale(req({
        'invoiceNumber': 'AQ-SINV-1', // local-side number, different
        'globalId': gid, // same stable identity (the fix threads this)
        'subtotal': 50.0,
        'total': 50.0,
        'paid': 50.0,
        'paymentMethod': 'cash',
        'warehouseId': warehouseId,
        'userId': userId,
        'items': [],
      }));
      expect(second.statusCode, 200);
      final b2 = jsonDecode(await second.readAsString()) as Map<String, dynamic>;
      expect(b2['duplicate'], true,
          reason: 'globalId dedup must recognise the re-push as a duplicate');

      final invoices = await db.select(db.salesInvoices).get();
      expect(invoices.length, 1,
          reason: 're-push with same globalId must NOT create a duplicate row');
    },
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Test 3 — Sync outbox payload round-trip
  // ─────────────────────────────────────────────────────────────────────────

  test(
    'Sync outbox serialises and deserialises complex payload without data loss',
    () async {
      final original = {
        'invoiceNumber': 'SYNC-RT-001',
        'total': 215.50,
        'paymentMethod': 'mixed',
        'cashAmount': 100.0,
        'bankAmount': 115.50,
        'items': [
          {'productId': 7, 'quantity': 3.0, 'unitPrice': 50.0, 'total': 150.0},
          {'productId': 12, 'quantity': 1.0, 'unitPrice': 65.50, 'total': 65.50},
        ],
      };

      final outboxId = await db.addToSyncOutbox(
        tableName: 'sales_invoices',
        recordId: '9999',
        operation: 'insert',
        payload: original,
        idempotencyKey: 'round-trip-day12',
      );
      expect(outboxId, greaterThan(0));

      final pending = await db.getPendingSyncItems();
      expect(pending.length, 1);
      expect(pending.first.status, 'pending');
      expect(pending.first.idempotencyKey, 'round-trip-day12');

      final decoded = jsonDecode(pending.first.payload) as Map<String, dynamic>;
      expect(decoded['invoiceNumber'], 'SYNC-RT-001');
      expect(decoded['total'], 215.50);
      expect(decoded['paymentMethod'], 'mixed');
      expect(decoded['cashAmount'], 100.0);
      expect(decoded['bankAmount'], 115.50);

      final itemsList = decoded['items'] as List;
      expect(itemsList.length, 2);
      expect((itemsList[0] as Map<String, dynamic>)['productId'], 7);
      expect((itemsList[1] as Map<String, dynamic>)['total'], 65.50);
    },
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Test 4 — Sale with line-items persisted
  // ─────────────────────────────────────────────────────────────────────────

  test(
    'ApiSalesHandler persists sale line-items in sales_invoice_items',
    () async {
      // Seed two products with warehouse-level stock (required by the
      // inventory guard inside createSalesInvoice).
      final productId1 = await db.insertProduct(
        ProductsCompanion.insert(
          name: 'Widget A',
          code: 'WGT-A',
          salePrice: const drift.Value(25.0),
          costPrice: const drift.Value(15.0),
          currentStock: const drift.Value(100.0),
        ),
      );
      await db.adjustStock(
        productId: productId1,
        warehouseId: warehouseId,
        quantity: 100.0,
        type: 'adjustment',
      );

      final productId2 = await db.insertProduct(
        ProductsCompanion.insert(
          name: 'Widget B',
          code: 'WGT-B',
          salePrice: const drift.Value(40.0),
          costPrice: const drift.Value(22.0),
          currentStock: const drift.Value(50.0),
        ),
      );
      await db.adjustStock(
        productId: productId2,
        warehouseId: warehouseId,
        quantity: 50.0,
        type: 'adjustment',
      );

      final handler = ApiSalesHandler(db, {});
      final payload = jsonEncode({
        'invoiceNumber': 'ITEMS-TEST-001',
        'globalId': const Uuid().v4(),
        'subtotal': 130.0,
        'total': 130.0,
        'paid': 130.0,
        'paymentMethod': 'cash',
        'warehouseId': warehouseId,
        'userId': userId,
        'items': [
          {
            'productId': productId1,
            'quantity': 2.0,
            'unitPrice': 25.0,
            'total': 50.0,
            'costPrice': 15.0,
          },
          {
            'productId': productId2,
            'quantity': 2.0,
            'unitPrice': 40.0,
            'total': 80.0,
            'costPrice': 22.0,
          },
        ],
      });

      final response = await handler.postSale(
        Request(
          'POST',
          Uri.parse('http://localhost/api/sales'),
          body: payload,
          headers: {'Content-Type': 'application/json'}, context: {ApiUserCtx.userIdKey: 1},
        ),
      );
      // On unexpected 500, surface the body to aid debugging.
      final responseBody = await response.readAsString();
      expect(response.statusCode, 200,
          reason: 'handler must return 200; got body: $responseBody');

      final body = jsonDecode(responseBody) as Map<String, dynamic>;
      expect(body['success'], true);
      expect(body['duplicate'], isNot(true));

      final serverId = body['serverId'] as int;

      // Verify invoice header
      final invoice = await (db.select(db.salesInvoices)
            ..where((si) => si.id.equals(serverId)))
          .getSingleOrNull();
      expect(invoice, isNotNull);
      expect(invoice!.total, 130.0);

      // Verify line-items
      final lineItems = await (db.select(db.salesInvoiceItems)
            ..where((i) => i.invoiceId.equals(serverId)))
          .get();
      expect(lineItems.length, 2,
          reason: 'both line-items must be saved under the invoice');

      final totals = lineItems.map((i) => i.total).toSet();
      expect(totals.contains(50.0), true);
      expect(totals.contains(80.0), true);
    },
  );
}
