// ═══════════════════════════════════════════════════════════════════════════
// Mirror mode must not leave a local row behind when the HQ write failed.
// ═══════════════════════════════════════════════════════════════════════════
//
// Mirror mode has no outbox BY DESIGN (SYNC_ARCHITECTURE §8.3): the operator
// is an HQ admin on a remote laptop, and buffering writes locally would let
// HQ data drift without anyone noticing. `_tryOrQueue` already honours that —
// it throws `MirrorOfflineException` instead of queueing
// (client_write_interceptor.dart).
//
// The defect this file pins down is on the CALLER side: the repositories
// launch the submit with `unawaited(...).catchError(print)` and then write the
// local cache row unconditionally. In client mode that is correct — the outbox
// is the safety net. In mirror mode there IS no safety net, so the user gets a
// row that looks saved forever while HQ never heard about it. The debugPrint
// even claims "queued in outbox", which is a lie in mirror mode.
//
// Test strategy: point the proxy at a closed port so the real HTTP call fails
// immediately with a connection error (no stubbing needed, and no 8s timeout —
// ECONNREFUSED is instant). Then assert the two halves of the contract:
//
//   1. the failure REACHES the caller (MirrorOfflineException propagates), and
//   2. NO local row was written, and
//   3. nothing was queued in the outbox (mirror has no outbox).
//
// Client mode keeps its existing fire-and-forget behaviour — that is asserted
// too, so the fix cannot regress offline-first resilience on cashier devices.

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/data/repositories/purchases_repository_impl.dart';
import 'package:picpos_erp/domain/repositories/audit_repository_interface.dart';
import 'package:picpos_erp/domain/repositories/i_products_repository.dart';
import 'package:picpos_erp/domain/repositories/inventory_repository.dart';
import 'package:picpos_erp/domain/repositories/parties_repository.dart';
import 'package:picpos_erp/domain/repositories/purchases_repository.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/domain/repositories/treasury_repository.dart';
import 'package:picpos_erp/services/accounting_service.dart';
import 'package:picpos_erp/services/client_write_interceptor.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/write_router.dart';

void main() {
  late AppDatabase db;
  late PurchasesRepositoryImpl repo;
  late int supplierId;
  late int warehouseId;
  late int productId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    ClientWriteInterceptor.setup();
    ClientWriteInterceptor.initialize(db);
    // The standalone branch of createInvoice is never reached in these tests
    // (both mirror and client take the interceptor branch), so the collaborator
    // repos are throwing stubs — same pattern as purchase_return_edit_test.
    repo = PurchasesRepositoryImpl(
      db,
      AccountingService(
        DriftAccountingRepository(db),
        _ThrowingPartiesRepo(),
        _ThrowingTreasuryRepo(),
        _ThrowingProductRepo(),
        _ThrowingInventoryRepo(),
        _ThrowingSettingsRepo(),
        _ThrowingAuditRepo(),
      ),
    );

    // Closed port → connection refused on the first attempt, no timeout wait.
    NetworkService.instance.setServerAddress('127.0.0.1', port: 1);

    warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'WH-MIRROR',
            isDefault: const Value(true),
            globalId: const Value('gid-wh-mirror'),
          ),
        );
    await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'Safe-MIRROR',
            safeType: const Value('cash'),
            isDefault: const Value(true),
            globalId: const Value('gid-safe-mirror'),
          ),
        );
    supplierId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'Supplier-MIRROR',
            isSupplier: const Value(true),
            globalId: const Value('gid-supplier-mirror'),
          ),
        );
    productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            code: 'PRD-MIRROR',
            name: 'Product MIRROR',
            trackInventory: const Value(true),
            globalId: const Value('gid-prod-mirror'),
          ),
        );
  });

  tearDown(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    SyncInterceptor.instance = null;
    await db.close();
  });

  void activateMirror() {
    NetworkService.instance.debugSetModeForTests(NetworkMode.mirror);
    MirrorState.instance.debugSetForTests(
      serverDisplayName: '127.0.0.1:1',
      lastHandshakeAt: DateTime.now().toUtc(),
    );
    // Guard the fixture itself — if this ever goes false the test would pass
    // vacuously by taking the standalone branch.
    expect(WriteRouter.isMirrorActive, isTrue,
        reason: 'fixture must actually be in mirror mode');
    expect(SyncInterceptor.isMirrorMode, isTrue);
  }

  CreatePurchaseInvoiceParams buildParams() => CreatePurchaseInvoiceParams(
        supplierId: supplierId,
        warehouseId: warehouseId,
        items: [
          PurchaseItemParams(
            productId: productId,
            quantity: 5,
            unitCost: 10,
            salePrice: 15,
            taxRate: 0,
            taxAmount: 0,
          ),
        ],
        paid: 50,
        paymentMethod: 'cash',
      );

  group('mirror mode — failed HQ write leaves nothing behind', () {
    test('createInvoice throws instead of reporting success', () async {
      activateMirror();
      await expectLater(
        repo.createInvoice(buildParams()),
        throwsA(isA<MirrorOfflineException>()),
      );
    });

    test('createInvoice writes NO local invoice row when HQ is unreachable',
        () async {
      activateMirror();
      try {
        await repo.createInvoice(buildParams());
      } catch (_) {
        // The throw is asserted in the test above; here we only care about
        // what the database looks like afterwards.
      }

      final invoices = await db.select(db.purchaseInvoices).get();
      expect(invoices, isEmpty,
          reason: 'a purchase the HQ never received must not appear in the '
              'mirror cache as a saved invoice');

      final items = await db.select(db.purchaseInvoiceItems).get();
      expect(items, isEmpty, reason: 'no orphan line items either');
    });

    test('nothing is queued in the outbox — mirror has no outbox by design',
        () async {
      activateMirror();
      try {
        await repo.createInvoice(buildParams());
      } catch (_) {}

      final queued = await db.select(db.syncOutbox).get();
      expect(queued, isEmpty,
          reason: 'SYNC_ARCHITECTURE §8.3 — mirror writes are rejected, '
              'never buffered');
    });
  });

  group('mirror mode — the other awaited write paths propagate too', () {
    // These share one root cause with createInvoice, so they share one guard.
    // Each is a path where the submit precedes the local write, which is what
    // makes aborting on failure clean (no half-written row left behind).

    Future<int> seedLocalInvoice() async {
      // Standalone insert so the fixture has an invoice to act on, without
      // going through the mirror path under test.
      NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
      final id = await db.insertPurchaseInvoiceWithoutStock(
        supplierId: supplierId,
        warehouseId: warehouseId,
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 5,
            unitCost: 10,
            total: 50,
          ),
        ],
        paid: 0,
        paymentMethod: 'credit',
        globalId: 'gid-seeded-invoice',
      );
      return id;
    }

    test('recordPayment does not mark the invoice paid when HQ rejected',
        () async {
      final id = await seedLocalInvoice();
      activateMirror();

      await expectLater(
        repo.recordPayment(id, 25, userId: 1),
        throwsA(isA<MirrorOfflineException>()),
      );

      final row = await (db.select(db.purchaseInvoices)
            ..where((i) => i.id.equals(id)))
          .getSingle();
      expect(row.paid, 0,
          reason: 'a payment HQ never accepted must not move the local '
              'paid amount — the supplier balance would diverge silently');
    });

    test('void does not flip the local status when HQ rejected', () async {
      final id = await seedLocalInvoice();
      activateMirror();

      await expectLater(
        repo.voidInvoice(id, reason: 'test'),
        throwsA(isA<MirrorOfflineException>()),
      );

      final row = await (db.select(db.purchaseInvoices)
            ..where((i) => i.id.equals(id)))
          .getSingle();
      expect(row.status, isNot('voided'),
          reason: 'showing an invoice as voided while HQ still has it live '
              'makes the operator stop chasing a live document');
    });
  });

  group('client mode — offline-first behaviour must NOT regress', () {
    test('createInvoice still writes the local cache row and queues the '
        'submit when the server is unreachable', () async {
      NetworkService.instance.debugSetModeForTests(NetworkMode.client);
      expect(SyncInterceptor.isClientMode, isTrue);
      expect(SyncInterceptor.isMirrorMode, isFalse,
          reason: 'client mode has an outbox — it must keep fire-and-forget');

      final id = await repo.createInvoice(buildParams());
      expect(id, greaterThan(0));

      final invoices = await db.select(db.purchaseInvoices).get();
      expect(invoices, hasLength(1),
          reason: 'the cashier device keeps working offline — this is the '
              'behaviour the mirror fix must not break');
    });
  });
}

// ── Collaborator stubs ──────────────────────────────────────────────────────
// createInvoice only touches these on the standalone branch, which these tests
// never take. Throwing loudly is deliberate: if a future refactor makes the
// mirror path fall through to standalone, the test fails instead of passing
// for the wrong reason.

class _ThrowingPartiesRepo implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in mirror-write tests');
}

class _ThrowingTreasuryRepo implements ITreasuryRepository {
  @override
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(
          String referenceType, int referenceId) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in mirror-write tests');
}

class _ThrowingProductRepo implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in mirror-write tests');
}

class _ThrowingInventoryRepo implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in mirror-write tests');
}

class _ThrowingSettingsRepo implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in mirror-write tests');
}

class _ThrowingAuditRepo implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in mirror-write tests');
}
