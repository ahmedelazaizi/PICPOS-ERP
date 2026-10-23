// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 · residual #1 — the remaining non-scoped transactional GET endpoints.
//
// P1-8b closed the delta-pull surface (`/api/sync/pull`) and the branch-scoped
// individual GETs (journals/sales/…). But a set of transactional GETs never
// called `_extractBranchId` at all, so they returned ALL-branch rows to any
// caller regardless of identity:
//   /api/payments · /api/payment-allocations · /api/product-batches ·
//   /api/sales-orders · /api/purchase-orders · /api/commercial-papers ·
//   /api/sales/held-items
//
// This suite pins the three-way branch-scope contract on each:
//   • restricted uid (branch A) → own-branch rows only, never branch B
//     (commercial-papers also keeps NULL-safe/head-office rows — the documented
//     `col IN (ids) OR col IS NULL` convention);
//   • no verified identity        → zero rows (omission CLOSED);
//   • admin (userId==1)           → all rows (proves the empty results are a
//     genuine DENY, not an empty table).
//
// held-items has no branch linkage (its parent held_orders has none) → it can
// only close the OMISSION (tokenless → zero); an identified caller still sees
// all rows. That limited contract is asserted explicitly.
//
// Harness modeled on api_p1_8b_sync_scope_test / api_branch_scope_d06_test:
// buildRouter() wires NO ApiAuthMiddleware, so the userId is injected directly
// on the request context. NO userId == "no verified identity" (the omission
// case). userId==1 == admin/full-access.
// ═══════════════════════════════════════════════════════════════════════════

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
  late int branchAId;
  late int branchBId;
  late int whAId;
  late int whBId;
  late int safeAId;
  late int safeBId;
  late int productId;
  late int partyId;
  late int restrictedUserId; // access to branch A only

  // Per-endpoint row ids (A = branch A, B = branch B).
  late int payAId, payBId;
  late int allocAId, allocBId;
  late int batchAId, batchBId;
  late int soAId, soBId;
  late int poAId, poBId;
  late int cpAId, cpBId, cpNullId;
  late int hiAId, hiBId;

  setUp(() async {
    db = AppDatabase.forTesting();
    handler = ApiHandler(db);

    branchAId = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع A', globalId: const Value('gid-br-txn-a')));
    branchBId = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع B', globalId: const Value('gid-br-txn-b')));

    whAId = await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        name: 'مخزن A',
        branchId: Value(branchAId),
        globalId: const Value('gid-wh-txn-a')));
    whBId = await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        name: 'مخزن B',
        branchId: Value(branchBId),
        globalId: const Value('gid-wh-txn-b')));
    safeAId = await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'صندوق A',
        branchId: Value(branchAId),
        globalId: const Value('gid-safe-txn-a')));
    safeBId = await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'صندوق B',
        branchId: Value(branchBId),
        globalId: const Value('gid-safe-txn-b')));

    productId = await db.into(db.products).insert(
        ProductsCompanion.insert(code: 'P-TXN-1', name: 'منتج تجريبي'));
    partyId = await db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'طرف تجريبي'));

    // ── payments (safe→branch) ──────────────────────────────────────────────
    payAId = await db.into(db.payments).insert(PaymentsCompanion.insert(
        paymentNumber: 'PAY-A',
        paymentDate: DateTime(2025, 5, 10),
        amount: 100,
        safeId: safeAId,
        paymentType: 'receipt'));
    payBId = await db.into(db.payments).insert(PaymentsCompanion.insert(
        paymentNumber: 'PAY-B',
        paymentDate: DateTime(2025, 5, 11),
        amount: 200,
        safeId: safeBId,
        paymentType: 'receipt'));

    // ── payment_allocations (payment→safe→branch) ───────────────────────────
    allocAId = await db.into(db.paymentAllocations).insert(
        PaymentAllocationsCompanion.insert(
            paymentId: payAId,
            invoiceType: 'sales',
            invoiceId: 1,
            allocatedAmount: 100));
    allocBId = await db.into(db.paymentAllocations).insert(
        PaymentAllocationsCompanion.insert(
            paymentId: payBId,
            invoiceType: 'sales',
            invoiceId: 2,
            allocatedAmount: 200));

    // ── product_batches (warehouse→branch) ──────────────────────────────────
    batchAId = await db.into(db.productBatches).insert(
        ProductBatchesCompanion.insert(
            productId: productId,
            warehouseId: whAId,
            batchNumber: 'BATCH-A',
            expiryDate: DateTime(2026, 1, 1)));
    batchBId = await db.into(db.productBatches).insert(
        ProductBatchesCompanion.insert(
            productId: productId,
            warehouseId: whBId,
            batchNumber: 'BATCH-B',
            expiryDate: DateTime(2026, 1, 1)));

    // ── sales_orders (warehouse→branch) ─────────────────────────────────────
    soAId = await db.into(db.salesOrders).insert(SalesOrdersCompanion.insert(
        orderNumber: 'SO-A',
        warehouseId: whAId,
        orderDate: DateTime(2025, 5, 10)));
    soBId = await db.into(db.salesOrders).insert(SalesOrdersCompanion.insert(
        orderNumber: 'SO-B',
        warehouseId: whBId,
        orderDate: DateTime(2025, 5, 11)));

    // ── purchase_orders (warehouse→branch) ──────────────────────────────────
    poAId = await db.into(db.purchaseOrders).insert(
        PurchaseOrdersCompanion.insert(
            orderNumber: 'PO-A',
            supplierId: partyId,
            warehouseId: whAId,
            orderDate: DateTime(2025, 5, 10)));
    poBId = await db.into(db.purchaseOrders).insert(
        PurchaseOrdersCompanion.insert(
            orderNumber: 'PO-B',
            supplierId: partyId,
            warehouseId: whBId,
            orderDate: DateTime(2025, 5, 11)));

    // ── commercial_papers (safe→branch, safe NULLABLE) ──────────────────────
    cpAId = await db.into(db.commercialPapers).insert(
        CommercialPapersCompanion.insert(
            paperNumber: 'CP-A',
            type: 'cheque',
            direction: 'received',
            partyId: partyId,
            amount: 100,
            issueDate: DateTime(2025, 5, 10),
            dueDate: DateTime(2025, 6, 10),
            safeId: Value(safeAId)));
    cpBId = await db.into(db.commercialPapers).insert(
        CommercialPapersCompanion.insert(
            paperNumber: 'CP-B',
            type: 'cheque',
            direction: 'received',
            partyId: partyId,
            amount: 200,
            issueDate: DateTime(2025, 5, 11),
            dueDate: DateTime(2025, 6, 11),
            safeId: Value(safeBId)));
    // Undeposited paper — no safe yet → head-office/NULL row, visible to any
    // identified branch user (the `OR safeId IS NULL` convention), but NOT to a
    // tokenless caller.
    cpNullId = await db.into(db.commercialPapers).insert(
        CommercialPapersCompanion.insert(
            paperNumber: 'CP-NULL',
            type: 'cheque',
            direction: 'received',
            partyId: partyId,
            amount: 300,
            issueDate: DateTime(2025, 5, 12),
            dueDate: DateTime(2025, 6, 12)));

    // ── held_order_items (parent held_orders has NO branch linkage) ─────────
    final hoAId = await db.into(db.heldOrders).insert(
        HeldOrdersCompanion.insert(holdNumber: 'HOLD-A'));
    final hoBId = await db.into(db.heldOrders).insert(
        HeldOrdersCompanion.insert(holdNumber: 'HOLD-B'));
    hiAId = await db.into(db.heldOrderItems).insert(
        HeldOrderItemsCompanion.insert(
            heldOrderId: hoAId, productId: productId, quantity: 1, unitPrice: 5));
    hiBId = await db.into(db.heldOrderItems).insert(
        HeldOrderItemsCompanion.insert(
            heldOrderId: hoBId, productId: productId, quantity: 2, unitPrice: 6));

    // Restricted (non-admin) user with a single branch-A access grant.
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
              name: 'كاشير TXN', isSystemRole: const Value(false)),
        );
    restrictedUserId = await db.createUser(
      username: 'txn_cashier',
      password: 'test',
      displayName: 'TXN Cashier',
      roleId: roleId,
    );
    await db.setUserBranchAccess(restrictedUserId, [branchAId]);
  });

  tearDown(() => db.close());

  Future<Map<String, dynamic>> getJson(String path, {int? userId}) async {
    final resp = await handler.buildRouter().call(shelf.Request(
          'GET',
          Uri.parse('http://localhost$path'),
          context: userId != null ? {ApiUserCtx.userIdKey: userId} : const {},
        ));
    final body = await resp.readAsString();
    expect(resp.statusCode, 200, reason: 'GET $path failed: $body');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Set<int> idsOf(Map<String, dynamic> body, String key) => (body[key] as List)
      .map((r) => (r as Map<String, dynamic>)['id'] as int)
      .toSet();

  // ── /api/payments ───────────────────────────────────────────────────────
  group('/api/payments', () {
    test('restricted uid → own safe only, no foreign branch', () async {
      final ids = idsOf(
          await getJson('/api/payments', userId: restrictedUserId), 'payments');
      expect(ids, contains(payAId));
      expect(ids, isNot(contains(payBId)));
    });
    test('no identity → zero rows (omission closed)', () async {
      final body = await getJson('/api/payments');
      expect(body['count'], 0);
      expect(body['payments'], isEmpty);
    });
    test('admin → all rows', () async {
      final ids = idsOf(await getJson('/api/payments', userId: 1), 'payments');
      expect(ids, containsAll({payAId, payBId}));
    });
  });

  // ── /api/payment-allocations ──────────────────────────────────────────────
  group('/api/payment-allocations', () {
    test('restricted uid → own payment only', () async {
      final ids = idsOf(
          await getJson('/api/payment-allocations', userId: restrictedUserId),
          'payment_allocations');
      expect(ids, contains(allocAId));
      expect(ids, isNot(contains(allocBId)));
    });
    test('no identity → zero rows', () async {
      final body = await getJson('/api/payment-allocations');
      expect(body['count'], 0);
      expect(body['payment_allocations'], isEmpty);
    });
    test('admin → all rows', () async {
      final ids = idsOf(await getJson('/api/payment-allocations', userId: 1),
          'payment_allocations');
      expect(ids, containsAll({allocAId, allocBId}));
    });
  });

  // ── /api/product-batches ──────────────────────────────────────────────────
  group('/api/product-batches', () {
    test('restricted uid → own warehouse only', () async {
      final ids = idsOf(
          await getJson('/api/product-batches', userId: restrictedUserId),
          'product_batches');
      expect(ids, contains(batchAId));
      expect(ids, isNot(contains(batchBId)));
    });
    test('no identity → zero rows', () async {
      final body = await getJson('/api/product-batches');
      expect(body['count'], 0);
      expect(body['product_batches'], isEmpty);
    });
    test('admin → all rows', () async {
      final ids = idsOf(
          await getJson('/api/product-batches', userId: 1), 'product_batches');
      expect(ids, containsAll({batchAId, batchBId}));
    });
  });

  // ── /api/sales-orders ─────────────────────────────────────────────────────
  group('/api/sales-orders', () {
    test('restricted uid → own warehouse only', () async {
      final ids = idsOf(
          await getJson('/api/sales-orders', userId: restrictedUserId),
          'sales_orders');
      expect(ids, contains(soAId));
      expect(ids, isNot(contains(soBId)));
    });
    test('no identity → zero rows', () async {
      final body = await getJson('/api/sales-orders');
      expect(body['count'], 0);
      expect(body['sales_orders'], isEmpty);
    });
    test('admin → all rows', () async {
      final ids =
          idsOf(await getJson('/api/sales-orders', userId: 1), 'sales_orders');
      expect(ids, containsAll({soAId, soBId}));
    });
  });

  // ── /api/purchase-orders ──────────────────────────────────────────────────
  group('/api/purchase-orders', () {
    test('restricted uid → own warehouse only', () async {
      final ids = idsOf(
          await getJson('/api/purchase-orders', userId: restrictedUserId),
          'purchase_orders');
      expect(ids, contains(poAId));
      expect(ids, isNot(contains(poBId)));
    });
    test('no identity → zero rows', () async {
      final body = await getJson('/api/purchase-orders');
      expect(body['count'], 0);
      expect(body['purchase_orders'], isEmpty);
    });
    test('admin → all rows', () async {
      final ids = idsOf(
          await getJson('/api/purchase-orders', userId: 1), 'purchase_orders');
      expect(ids, containsAll({poAId, poBId}));
    });
  });

  // ── /api/commercial-papers (nullable safe → NULL rows stay visible) ────────
  group('/api/commercial-papers', () {
    test('restricted uid → own safe + NULL-safe, never foreign branch',
        () async {
      final ids = idsOf(
          await getJson('/api/commercial-papers', userId: restrictedUserId),
          'commercial_papers');
      expect(ids, contains(cpAId), reason: 'own-branch safe paper');
      expect(ids, contains(cpNullId),
          reason: 'undeposited/head-office (NULL safe) stays visible');
      expect(ids, isNot(contains(cpBId)),
          reason: 'the foreign branch-B safe paper must not leak');
    });
    test('no identity → zero rows (NULL rows do NOT leak to tokenless)',
        () async {
      final body = await getJson('/api/commercial-papers');
      expect(body['count'], 0);
      expect(body['commercial_papers'], isEmpty);
    });
    test('admin → all rows incl. NULL', () async {
      final ids = idsOf(
          await getJson('/api/commercial-papers', userId: 1),
          'commercial_papers');
      expect(ids, containsAll({cpAId, cpBId, cpNullId}));
    });
  });

  // ── /api/sales/held-items (no branch linkage → omission-only contract) ─────
  group('/api/sales/held-items', () {
    test('no identity → zero rows (omission closed)', () async {
      final body = await getJson('/api/sales/held-items');
      expect(body['count'], 0);
      expect(body['held_order_items'], isEmpty);
    });
    test('identified caller → rows visible (not branch-scoped, by design)',
        () async {
      final adminIds = idsOf(
          await getJson('/api/sales/held-items', userId: 1),
          'held_order_items');
      expect(adminIds, containsAll({hiAId, hiBId}),
          reason: 'held items have no branch linkage — an identified caller '
              'still sees all (documented gap; only omission is closed here)');
      final restrictedIds = idsOf(
          await getJson('/api/sales/held-items', userId: restrictedUserId),
          'held_order_items');
      expect(restrictedIds, isNotEmpty,
          reason: 'a logged-in restricted user is not blocked (not a deny)');
    });
  });
}
