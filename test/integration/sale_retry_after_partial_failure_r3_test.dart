// R3 — client mode submits the sale to the server BEFORE saving it locally.
// If the local save fails the cashier sees "failed" and re-sells; the retry used
// to mint a NEW globalId, so the server's globalId dedup never fired and the
// invoice (and stock) were doubled. The attempt's globalId is now fixed per cart
// attempt (`CheckoutAttemptId`) and flows through `SaleRequest.globalId`.
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/data/repositories/sales_transaction_orchestrator.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/repositories/audit_repository_interface.dart';
import 'package:picpos_erp/domain/repositories/i_products_repository.dart';
import 'package:picpos_erp/domain/repositories/inventory_repository.dart';
import 'package:picpos_erp/domain/repositories/parties_repository.dart';
import 'package:picpos_erp/domain/repositories/sales_repository.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/presentation/pos/providers/checkout_attempt_id.dart';
import 'package:picpos_erp/services/accounting_service.dart';
import 'package:picpos_erp/services/api/api_sales_handler.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';
import 'package:picpos_erp/services/client_write_interceptor.dart';
import 'package:picpos_erp/domain/models/exchange_sync_payload.dart';

class _ClientInterceptor implements SyncInterceptor {
  @override
  bool get isClientModeImpl => true;
  @override
  bool get isMirrorModeImpl => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

CartItemEntity _item(int productId, {double qty = 2}) => CartItemEntity(
      productId: productId,
      productName: 'صنف',
      productCode: 'R3-1',
      quantity: qty,
      unitPrice: 10,
    );

void main() {
  late AppDatabase db;
  late SalesTransactionOrchestrator orch;
  late int userId;
  late int warehouseId;
  late int productId;

  setUp(() async {
    SyncInterceptor.instance = null;
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    await db.setSetting('zero_cost_policy', 'warn');
    orch = SalesTransactionOrchestrator(
      db,
      AccountingService(
        DriftAccountingRepository(db),
        _StubParties(),
        _StubTreasury(),
        _StubProducts(),
        _StubInventory(),
        _StubSettings(),
        _StubAudit(),
      ),
    );
    final roleId = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)));
    userId = await db.createUser(
      username: 'r3_cashier',
      password: 'pw123456',
      displayName: 'كاشير',
      roleId: roleId,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'R3-1',
      name: 'صنف',
      salePrice: const Value(10),
      costPrice: const Value(5),
      trackInventory: const Value(true),
    ));
    await db.openShift(userId, 0);
    SyncInterceptor.instance = _ClientInterceptor();
  });

  tearDown(() async {
    SyncInterceptor.instance = null;
    await db.close();
  });

  /// Runs one sale attempt in client mode. The exchange collector captures the
  /// payload that would have gone to the server (no network involved).
  Future<(SaleResult, Map<String, dynamic>?)> attempt({String? globalId}) async {
    final collector = ExchangeLegCollector();
    final result = await ClientWriteInterceptor.runWithExchangeCollector(
      collector,
      () => orch.completeSalesTransaction(SaleRequest(
        items: [_item(productId)],
        warehouseId: warehouseId,
        userId: userId,
        paymentMethod: 'cash',
        paidAmount: 20,
        cashAmount: 20,
        taxEnabled: false,
        globalId: globalId,
      )),
    );
    return (result, collector.sale);
  }

  Future<void> breakLocalInsert() => db.customStatement(
      "CREATE TRIGGER r3_fail BEFORE INSERT ON sales_invoices "
      "BEGIN SELECT RAISE(ABORT, 'simulated local save failure'); END");
  Future<void> healLocalInsert() =>
      db.customStatement('DROP TRIGGER r3_fail');

  test('retry after a failed local save re-sends the SAME globalId and the '
      'server keeps ONE invoice', () async {
    final attemptId = CheckoutAttemptId();
    final fp = CheckoutAttemptId.fingerprint(
      items: [_item(productId)],
      customerId: null,
      paymentMethod: 'cash',
      paidAmount: 20,
      asReturn: false,
      warehouseId: warehouseId,
    );

    await breakLocalInsert();
    final gid1 = attemptId.idFor(fp);
    final (r1, payload1) = await attempt(globalId: gid1);
    expect(r1.isSuccess, isFalse,
        reason: 'cashier sees a failure: local save aborted');
    expect(payload1?['globalId'], gid1,
        reason: 'the server submit happened BEFORE the failed local save');
    expect(await db.select(db.salesInvoices).get(), isEmpty);

    await healLocalInsert();
    final gid2 = attemptId.idFor(fp); // same cart → same attempt id
    expect(gid2, gid1);
    final (r2, payload2) = await attempt(globalId: gid2);
    expect(r2.isSuccess, isTrue, reason: r2.errorMessage);
    expect(payload2?['globalId'], gid1);
    final local = await db.select(db.salesInvoices).get();
    expect(local.single.globalId, gid1,
        reason: 'local row carries the id the server already knows');

    // Server side: the real handler dedups by globalId (no new mechanism).
    final server = AppDatabase.forTesting();
    addTearDown(server.close);
    await server.into(server.fiscalYears).insert(FiscalYearsCompanion.insert(
          name: '2026',
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 12, 31),
        ));
    final handler = ApiSalesHandler(server, {});
    Future<Map<String, dynamic>> send(Map<String, dynamic> p) async {
      final res = await handler.postSale(Request(
        'POST',
        Uri.parse('http://localhost/api/sales'),
        body: jsonEncode({
          'globalId': p['globalId'],
          'invoiceNumber': p['invoiceNumber'],
          'subtotal': 20.0,
          'total': 20.0,
          'paid': 20.0,
          'paymentMethod': 'cash',
          'warehouseId': 1,
          'userId': 1,
          'items': [],
        }),
        headers: {'Content-Type': 'application/json'},
        context: {ApiUserCtx.userIdKey: 1},
      ));
      return jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    }

    final first = await send(payload1!);
    final second = await send(payload2!);
    expect(second['duplicate'], isTrue);
    expect(second['serverId'], first['serverId']);
    expect((await server.select(server.salesInvoices).get()).length, 1);
  });

  test('without a pinned id every attempt mints a new one (the old bug)',
      () async {
    final (_, a) = await attempt();
    final (_, b) = await attempt();
    expect(a?['globalId'], isNot(b?['globalId']));
  });

  group('CheckoutAttemptId', () {
    String fp(List<CartItemEntity> items, {double paid = 20}) =>
        CheckoutAttemptId.fingerprint(
          items: items,
          customerId: null,
          paymentMethod: 'cash',
          paidAmount: paid,
          asReturn: false,
          warehouseId: 1,
        );

    test('same cart reuses; changed cart or success gets a fresh id', () {
      final a = CheckoutAttemptId();
      final id1 = a.idFor(fp([_item(1)]));
      expect(a.idFor(fp([_item(1)])), id1);
      final id2 = a.idFor(fp([_item(1, qty: 3)]));
      expect(id2, isNot(id1), reason: 'edited cart is a different sale');
      a.clear();
      expect(a.idFor(fp([_item(1, qty: 3)])), isNot(id2),
          reason: 'after success the identical next cart is a new sale');
    });
  });
}

class _StubParties implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #getPartyById) return Future<Null>.value(null);
    throw UnimplementedError();
  }
}

class _StubTreasury implements ITreasuryRepository {
  @override
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(
          String referenceType, int referenceId) async =>
      [];

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _StubProducts implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _StubInventory implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _StubSettings implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _StubAudit implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}
