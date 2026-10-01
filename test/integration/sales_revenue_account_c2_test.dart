// ═══════════════════════════════════════════════════════════════════════════
// C2 (owner item 3) — «حساب المبيعات» chosen per sales invoice.
// ═══════════════════════════════════════════════════════════════════════════
//
// Real paths, in-memory SQLite:
//   • Sales invoice with a NON-default revenue account → the sales JE credits
//     that account (standalone orchestrator → JournalEntryFactory), and the
//     mapped default is untouched.
//   • Return of that invoice → the sales-return JE debits the SAME account.
//   • NULL (every legacy invoice / POS quick sale) → mapped 'sales' credit and
//     mapped 'sales_return' debit, exactly as before.
//   • Server/DAO path (`createSalesInvoice` + Phase-8 autopost, which is what
//     `api_sales_handler.postSale` runs) honours the stored account too.
//   • Sync: `/api/sales` snapshot carries `revenueAccountId`, the client
//     SalesSyncStrategy stores it, and the generic delta pull (`SELECT *`)
//     sees the raw column.
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/sync_interceptor.dart';
import 'package:ural_erp/data/repositories/drift_accounting_repository.dart';
import 'package:ural_erp/data/repositories/drift_product_repository.dart';
import 'package:ural_erp/data/repositories/returns_repository_impl.dart';
import 'package:ural_erp/data/repositories/sales_transaction_orchestrator.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/domain/repositories/audit_repository_interface.dart';
import 'package:ural_erp/domain/repositories/i_products_repository.dart';
import 'package:ural_erp/domain/repositories/inventory_repository.dart';
import 'package:ural_erp/domain/repositories/parties_repository.dart';
import 'package:ural_erp/domain/repositories/sales_repository.dart';
import 'package:ural_erp/domain/repositories/settings_repository.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/services/accounting_service.dart';
import 'package:ural_erp/services/api/api_handler.dart';
import 'package:ural_erp/services/api/api_sales_handler.dart';
import 'package:ural_erp/services/api/api_user_context.dart';
import 'package:ural_erp/services/sync/strategies/sales_sync_strategy.dart';

void main() {
  late AppDatabase db;
  late SalesTransactionOrchestrator orch;
  late ReturnsRepositoryImpl returns;
  late DriftProductRepository productRepo;
  late int userId;
  late int warehouseId;
  late int customerId;
  late int productId;
  late int otherRevenueId;
  late int defaultSalesId;
  late int defaultReturnId;

  setUp(() async {
    SyncInterceptor.instance = null;
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    final svc = AccountingService(
      DriftAccountingRepository(db),
      _StubParties(),
      _RealisticTreasury(db),
      _StubProducts(),
      _StubInventory(),
      _StubSettings(),
      _StubAudit(),
    );
    orch = SalesTransactionOrchestrator(db, svc);
    returns = ReturnsRepositoryImpl(db, svc);
    productRepo = DriftProductRepository(db);

    final roleId = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'cashier', isSystemRole: const Value(false)));
    userId = await db.createUser(
      username: 'c2_cashier',
      password: 'pw123456',
      displayName: 'C2 cashier',
      roleId: roleId,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;
    customerId = await db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'C2 customer', isCustomer: const Value(true)));
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'C2-P',
      name: 'C2 item',
      salePrice: const Value(100.0),
      costPrice: const Value(40.0),
      currentStock: const Value(1000),
      trackInventory: const Value(true),
    ));
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 1000,
      type: 'purchase',
      unitCost: 40,
    );

    otherRevenueId = await db.into(db.accounts).insert(AccountsCompanion.insert(
      code: '41991',
      name: 'C2 export sales',
      accountType: 'revenue',
      accountNature: const Value('detail'),
      normalBalance: const Value('credit'),
    ));
    defaultSalesId = (await db.getLeafAccountByPurpose('sales'))!.id;
    defaultReturnId = (await db.getLeafAccountByPurpose('sales_return'))!.id;
    expect(otherRevenueId, isNot(defaultSalesId));

    await db.openShift(userId, 0);
  });

  tearDown(() async {
    SyncInterceptor.instance = null;
  });

  /// Net (debit − credit) per account across every JE of [refType]/[refId].
  Future<Map<int, double>> netByAccount(String refType, int refId) async {
    final entries = await (db.select(db.journalEntries)
          ..where((e) =>
              e.referenceType.equals(refType) & e.referenceId.equals(refId)))
        .get();
    final out = <int, double>{};
    for (final e in entries) {
      for (final l in await (db.select(db.journalEntryLines)
            ..where((x) => x.entryId.equals(e.id)))
          .get()) {
        out[l.accountId] = (out[l.accountId] ?? 0) + l.debit - l.credit;
      }
    }
    return out;
  }

  Future<SalesInvoiceData> invoice(int id) =>
      (db.select(db.salesInvoices)..where((s) => s.id.equals(id))).getSingle();

  Future<int> sell({int? revenueAccountId}) async {
    final r = await orch.completeSalesTransaction(SaleRequest(
      items: [
        CartItemEntity(
          productId: productId,
          productName: 'C2 item',
          productCode: 'C2-P',
          quantity: 1,
          unitPrice: 100,
          taxRate: 0,
        ),
      ],
      customerId: customerId,
      warehouseId: warehouseId,
      userId: userId,
      paymentMethod: 'credit',
      paidAmount: 0,
      taxEnabled: false,
      revenueAccountId: revenueAccountId,
    ));
    expect(r.isSuccess, isTrue, reason: r.errorMessage);
    return r.invoiceId!;
  }

  Future<void> returnAll(int invoiceId) async {
    final inv = await invoice(invoiceId);
    final items = await db.getSalesInvoiceItems(inv.id);
    final ok = await returns.processSalesReturn(
      invoice: inv,
      returnQuantities: {for (final i in items) i.id: i.quantity},
      productCache: {
        for (final p in await productRepo.getProductsByIds([productId]))
          p.id: p,
      },
      userId: userId,
      userName: 'C2 cashier',
      isFullReturn: true,
    );
    expect(ok, isTrue);
  }

  test('v183 column exists and the revenue-account list is detail revenue only',
      () async {
    final cols = await db.customSelect('PRAGMA table_info(sales_invoices)').get();
    expect(cols.any((c) => c.data['name'] == 'revenue_account_id'), isTrue);
    // Idempotent ensure.
    await db.ensureSalesInvoiceRevenueAccountSchema();

    final list = await db.getActiveRevenueDetailAccounts();
    expect(list.map((a) => a.id), contains(otherRevenueId));
    expect(list.map((a) => a.id), contains(defaultSalesId));
    expect(list.every((a) => a.accountType == 'revenue'), isTrue);
    expect(list.every((a) => a.accountNature == 'detail' && a.isActive), isTrue);
  });

  test('non-default revenue account → sales JE credits it, not the mapping',
      () async {
    final id = await sell(revenueAccountId: otherRevenueId);
    expect(await db.getSalesInvoiceRevenueAccountId(id), otherRevenueId);

    final net = await netByAccount('sales_invoice', id);
    expect(net[otherRevenueId], closeTo(-100, 0.001),
        reason: 'the chosen revenue account must carry the sales credit');
    expect(net[defaultSalesId] ?? 0, closeTo(0, 0.001),
        reason: 'the mapped default must not be touched');
  });

  test('return of that invoice debits the SAME revenue account', () async {
    final id = await sell(revenueAccountId: otherRevenueId);
    await returnAll(id);

    final net = await netByAccount('sales_return', id);
    expect(net[otherRevenueId], closeTo(100, 0.001),
        reason: 'return must reverse the account the sale credited');
    expect(net[defaultReturnId] ?? 0, closeTo(0, 0.001));
  });

  test('NULL → mapped default credit; return → mapped sales_return debit',
      () async {
    final id = await sell();
    expect(await db.getSalesInvoiceRevenueAccountId(id), isNull);

    final sale = await netByAccount('sales_invoice', id);
    expect(sale[defaultSalesId], closeTo(-100, 0.001));
    expect(sale[otherRevenueId] ?? 0, closeTo(0, 0.001));

    await returnAll(id);
    final ret = await netByAccount('sales_return', id);
    expect(ret[defaultReturnId], closeTo(100, 0.001));
    expect(ret[otherRevenueId] ?? 0, closeTo(0, 0.001));
  });

  test('an inactive stored account falls back to the mapped default', () async {
    await (db.update(db.accounts)..where((a) => a.id.equals(otherRevenueId)))
        .write(const AccountsCompanion(isActive: Value(false)));
    final id = await sell(revenueAccountId: otherRevenueId);
    final net = await netByAccount('sales_invoice', id);
    expect(net[defaultSalesId], closeTo(-100, 0.001));
    expect(net[otherRevenueId] ?? 0, closeTo(0, 0.001));
  });

  test('server/DAO path (Phase-8 autopost) honours the stored account',
      () async {
    final id = await db.createSalesInvoice(
      customerId: customerId,
      warehouseId: warehouseId,
      userId: userId,
      subtotal: 100,
      discount: 0,
      tax: 0,
      total: 100,
      paid: 0,
      paymentMethod: 'credit',
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 1,
          unitPrice: 100,
          total: 100,
        ),
      ],
      revenueAccountId: otherRevenueId,
    );
    final entries = await (db.select(db.journalEntries)
          ..where((e) => e.referenceId.equals(id)))
        .get();
    expect(entries, isNotEmpty, reason: 'Phase-8 autopost did not run');
    var other = 0.0;
    var mapped = 0.0;
    for (final e in entries) {
      for (final l in await (db.select(db.journalEntryLines)
            ..where((x) => x.entryId.equals(e.id)))
          .get()) {
        if (l.accountId == otherRevenueId) other += l.debit - l.credit;
        if (l.accountId == defaultSalesId) mapped += l.debit - l.credit;
      }
    }
    expect(other, lessThan(0), reason: 'chosen account must be credited');
    expect(mapped, closeTo(0, 0.001));
  });

  test('sync: /api/sales snapshot + SalesSyncStrategy + SELECT * delta row',
      () async {
    final id = await sell(revenueAccountId: otherRevenueId);

    final rows = await db
        .customSelect('SELECT * FROM sales_invoices WHERE id = ?',
            variables: [Variable<int>(id)])
        .get();
    expect(rows.single.data['revenue_account_id'], otherRevenueId,
        reason: 'the generic delta pull (SELECT *) must see the column');

    // Admin identity (id 1): a tokenless call is fail-closed to zero rows.
    final response = await ApiHandler(db).buildRouter().call(shelf.Request(
        'GET', Uri.parse('http://localhost/api/sales'),
        context: {ApiUserCtx.userIdKey: 1}));
    expect(response.statusCode, 200);
    final body =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final sale = (body['sales'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((s) => s['id'] == id);
    expect(sale['revenueAccountId'], otherRevenueId);

    final client = AppDatabase.forTesting();
    // The fresh client has neither this customer nor the cashier; party/user
    // resolution is not what this test measures.
    sale
      ..['customerId'] = null
      ..['userId'] = 1
      ..['items'] = <Map<String, dynamic>>[];
    await SalesSyncStrategy(client).syncFromJson({
      'sales': [sale],
    });
    expect(await client.getSalesInvoiceRevenueAccountId(id), otherRevenueId);

    // An older server (no key) leaves the client's value untouched.
    final legacy = Map<String, dynamic>.from(sale)..remove('revenueAccountId');
    await SalesSyncStrategy(client).syncFromJson({
      'sales': [legacy],
    });
    expect(await client.getSalesInvoiceRevenueAccountId(id), otherRevenueId);
  });

  test('client push: server postSale stores revenueAccountId and credits it',
      () async {
    final response = await ApiSalesHandler(db, {}).postSale(shelf.Request(
      'POST',
      Uri.parse('http://localhost/api/sales'),
      body: jsonEncode({
        'invoiceNumber': 'C2-API-1',
        'globalId': 'c2-api-sale-1',
        'subtotal': 100.0,
        'discount': 0.0,
        'tax': 0.0,
        'total': 100.0,
        'paid': 0.0,
        'paymentMethod': 'credit',
        'customerId': customerId,
        'warehouseId': warehouseId,
        'userId': userId,
        'revenueAccountId': otherRevenueId,
        'items': [
          {
            'productId': productId,
            'quantity': 1.0,
            'unitPrice': 100.0,
            'total': 100.0,
            'costPrice': 40.0,
          },
        ],
      }),
      headers: {'Content-Type': 'application/json'},
      context: {ApiUserCtx.userIdKey: 1},
    ));
    expect(response.statusCode, 200, reason: await response.readAsString());
    final saleId = (await (db.select(db.salesInvoices)
              ..where((s) => s.globalId.equals('c2-api-sale-1')))
            .getSingle())
        .id;
    expect(await db.getSalesInvoiceRevenueAccountId(saleId), otherRevenueId);
    final entries = await (db.select(db.journalEntries)
          ..where((e) => e.referenceId.equals(saleId)))
        .get();
    var other = 0.0;
    var mapped = 0.0;
    for (final e in entries) {
      for (final l in await (db.select(db.journalEntryLines)
            ..where((x) => x.entryId.equals(e.id)))
          .get()) {
        if (l.accountId == otherRevenueId) other += l.debit - l.credit;
        if (l.accountId == defaultSalesId) mapped += l.debit - l.credit;
      }
    }
    expect(other, lessThan(0));
    expect(mapped, closeTo(0, 0.001));
  });
}

class _StubParties implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation inv) {
    if (inv.memberName == #getPartyById) return Future<Null>.value(null);
    throw UnsupportedError('parties repo not used here');
  }
}

/// Behavioural copy of `TreasuryRepositoryImpl.getSafeAccountsForReference`
/// (same as `tax_exempt_item_b3_test.dart`).
class _RealisticTreasury implements ITreasuryRepository {
  final AppDatabase db;
  _RealisticTreasury(this.db);

  @override
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(
      String referenceType, int referenceId) async {
    final rows = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.referenceType.equals(referenceType) &
              t.referenceId.equals(referenceId) &
              t.transactionType.equals('receipt')))
        .get();
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      final safe =
          await (db.select(db.safes)..where((s) => s.id.equals(r.safeId)))
              .getSingle();
      var accountId = safe.linkedAccountId;
      accountId ??= (await db.getAccountByCode(
              safe.safeType == 'bank' ? '1112' : '1111'))
          ?.id;
      if (accountId != null) {
        out.add({
          'accountId': accountId,
          'amount': r.amount,
          'safeName': safe.name,
        });
      }
    }
    return out;
  }

  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('treasury repo: ${inv.memberName}');
}

class _StubProducts implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('product repo not used here');
}

class _StubInventory implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('inventory repo not used here');
}

class _StubSettings implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('settings repo not used here');
}

class _StubAudit implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('audit repo not used here');
}
