// ═══════════════════════════════════════════════════════════════════════════
// B3 (owner decision) — «معفى من الضريبة» is taxed at 0 % everywhere.
// ═══════════════════════════════════════════════════════════════════════════
//
// Real paths, in-memory SQLite:
//   • POS sale       — product read through DriftProductRepository (raw flag
//                      enrichment) → AddToCartUseCase → cart totals → the
//                      orchestrator; the collected amount is the cart total.
//   • Sales invoice  — the save path builds CartItemEntity from the form map
//                      WITHOUT the flag; the orchestrator must read it from
//                      the DB. Exempt + default + custom 16 % on one invoice.
//   • Sales return   — return of an exempt + custom line reverses only the
//                      custom line's output VAT.
//   • Sync           — server `/api/products` → client ProductSyncStrategy
//                      carries `tax_exempt` both ways (set and cleared).
//   • E-invoice      — exempt line goes out as ETA V003 / JoFotara E.
//
// Output VAT account: `output_vat` → 2121 (accounting_dao_reads).
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/data/repositories/drift_product_repository.dart';
import 'package:picpos_erp/data/repositories/returns_repository_impl.dart';
import 'package:picpos_erp/data/repositories/sales_transaction_orchestrator.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/repositories/audit_repository_interface.dart';
import 'package:picpos_erp/domain/repositories/i_products_repository.dart';
import 'package:picpos_erp/domain/repositories/inventory_repository.dart';
import 'package:picpos_erp/domain/repositories/parties_repository.dart';
import 'package:picpos_erp/domain/repositories/sales_repository.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/domain/repositories/treasury_repository.dart';
import 'package:picpos_erp/domain/usecases/sales/add_to_cart_usecase.dart';
import 'package:picpos_erp/domain/usecases/sales/calculate_invoice_totals_usecase.dart';
import 'package:picpos_erp/services/accounting_service.dart';
import 'package:picpos_erp/services/api/api_handler.dart';
import 'package:picpos_erp/services/e_invoicing/e_invoice_service_wrapper.dart';
import 'package:picpos_erp/services/e_invoicing/eta_service.dart';
import 'package:picpos_erp/services/e_invoicing/jofotara_service.dart';
import 'package:picpos_erp/services/sync/strategies/product_sync_strategy.dart';

const _companyDefault = 14.0;

void main() {
  late AppDatabase db;
  late SalesTransactionOrchestrator orch;
  late ReturnsRepositoryImpl returns;
  late DriftProductRepository productRepo;
  late int userId;
  late int warehouseId;
  late int customerId;
  late int exemptId;
  late int defaultId;
  late int customId;

  Future<int> product(String code, {double taxRate = 0}) async {
    final id = await db.insertProduct(ProductsCompanion.insert(
      code: code,
      name: 'item $code',
      salePrice: const Value(100.0),
      costPrice: const Value(40.0),
      taxRate: Value(taxRate),
      currentStock: const Value(1000),
      trackInventory: const Value(true),
    ));
    await db.adjustStock(
      productId: id,
      warehouseId: warehouseId,
      quantity: 1000,
      type: 'purchase',
      unitCost: 40,
    );
    return id;
  }

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
      username: 'b3_cashier',
      password: 'pw123456',
      displayName: 'B3 cashier',
      roleId: roleId,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;
    customerId = await db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'B3 customer', isCustomer: const Value(true)));

    exemptId = await product('B3-EX');
    await db.setProductTaxExempt(exemptId, true);
    defaultId = await product('B3-DEF');
    customId = await product('B3-16', taxRate: 16);

    await db.openShift(userId, 0);
  });

  tearDown(() async {
    SyncInterceptor.instance = null;
  });

  Future<SalesInvoiceData> invoice(int id) =>
      (db.select(db.salesInvoices)..where((s) => s.id.equals(id))).getSingle();

  Future<Map<int, SalesInvoiceItem>> linesByProduct(int invId) async => {
        for (final l in await db.getSalesInvoiceItems(invId)) l.productId: l,
      };

  Future<double> outputVatNet(String refType, int refId) async {
    final acc = await db.getAccountByCode('2121');
    final entries = await (db.select(db.journalEntries)
          ..where((e) =>
              e.referenceType.equals(refType) & e.referenceId.equals(refId)))
        .get();
    var net = 0.0;
    for (final e in entries) {
      for (final l in await (db.select(db.journalEntryLines)
            ..where((x) => x.entryId.equals(e.id)))
          .get()) {
        if (l.accountId == acc!.id) net += l.debit - l.credit;
      }
    }
    return net;
  }

  CartItemEntity formLine(int productId, double taxRate) => CartItemEntity(
        productId: productId,
        productName: 'item',
        productCode: 'code',
        quantity: 1,
        unitPrice: 100,
        taxRate: taxRate,
      );

  test('repository stamps taxExempt from the raw column', () async {
    expect((await productRepo.getProductById(exemptId))!.taxExempt, isTrue);
    expect((await productRepo.getProductById(defaultId))!.taxExempt, isFalse);
    final many = await productRepo.getProductsByIds([exemptId, customId]);
    expect({for (final p in many) p.id: p.taxExempt},
        {exemptId: true, customId: false});
  });

  test('POS sale of an exempt item: line tax 0, total = net, no output VAT',
      () async {
    final p = (await productRepo.getProductById(exemptId))!;
    final cart = AddToCartUseCase().execute(
      currentCart: const [],
      productId: p.id,
      productName: p.name,
      productCode: p.code,
      unitPrice: p.salePrice,
      customPrice: p.salePrice,
      taxRate: p.taxRate,
      taxExempt: p.taxExempt,
    );
    final shown = CalculateInvoiceTotalsUseCase()
        .execute(items: cart, taxPercent: _companyDefault);
    expect(shown.taxAmount, 0);
    expect(shown.total, closeTo(100, 0.001));

    final r = await orch.completeSalesTransaction(SaleRequest(
      items: cart,
      warehouseId: warehouseId,
      userId: userId,
      paymentMethod: 'cash',
      paidAmount: shown.total,
      cashAmount: shown.total,
      taxEnabled: true,
      taxPercent: _companyDefault,
    ));
    expect(r.isSuccess, isTrue, reason: r.errorMessage);

    final inv = await invoice(r.invoiceId!);
    expect(inv.tax, closeTo(0, 0.001));
    expect(inv.total, closeTo(shown.total, 0.001),
        reason: 'collected (cart) total must equal the saved total');
    final line = (await linesByProduct(inv.id))[exemptId]!;
    expect(line.taxRate, 0);
    expect(line.taxAmount, 0);
    expect(await outputVatNet('sales_invoice', inv.id), closeTo(0, 0.001),
        reason: 'no output VAT on an exempt-only sale');
  });

  test('sales invoice: exempt 0 · default → company 14 · custom 16 unchanged '
      '(flag read from the DB, not the form map)', () async {
    final r = await orch.completeSalesTransaction(SaleRequest(
      items: [
        formLine(exemptId, 0),
        formLine(defaultId, 0),
        formLine(customId, 16),
      ],
      customerId: customerId,
      warehouseId: warehouseId,
      userId: userId,
      paymentMethod: 'credit',
      paidAmount: 0,
      taxEnabled: true,
      taxPercent: _companyDefault,
    ));
    expect(r.isSuccess, isTrue, reason: r.errorMessage);

    final inv = await invoice(r.invoiceId!);
    final lines = await linesByProduct(inv.id);
    expect(lines[exemptId]!.taxAmount, closeTo(0, 0.001));
    expect(lines[exemptId]!.taxRate, 0);
    expect(lines[defaultId]!.taxAmount, closeTo(14, 0.001));
    expect(lines[defaultId]!.taxRate, _companyDefault);
    expect(lines[customId]!.taxAmount, closeTo(16, 0.001));
    expect(lines[customId]!.taxRate, 16);
    expect(inv.tax, closeTo(30, 0.001));
    expect(inv.total, closeTo(330, 0.001));
    expect(await outputVatNet('sales_invoice', inv.id), closeTo(-30, 0.001),
        reason: 'output VAT credit = default 14 + custom 16; exempt adds 0');
  });

  test('regression: without any exempt item the invoice computes as before',
      () async {
    await db.setProductTaxExempt(exemptId, false);
    final r = await orch.completeSalesTransaction(SaleRequest(
      items: [formLine(exemptId, 0), formLine(customId, 16)],
      customerId: customerId,
      warehouseId: warehouseId,
      userId: userId,
      paymentMethod: 'credit',
      paidAmount: 0,
      taxEnabled: true,
      taxPercent: _companyDefault,
    ));
    expect(r.isSuccess, isTrue, reason: r.errorMessage);
    final inv = await invoice(r.invoiceId!);
    // The un-flagged rate-0 item falls back to the company default again.
    expect(inv.tax, closeTo(30, 0.001));
  });

  test('sales return of exempt + custom lines reverses only the custom VAT',
      () async {
    final r = await orch.completeSalesTransaction(SaleRequest(
      items: [formLine(exemptId, 0), formLine(customId, 16)],
      customerId: customerId,
      warehouseId: warehouseId,
      userId: userId,
      paymentMethod: 'credit',
      paidAmount: 0,
      taxEnabled: true,
      taxPercent: _companyDefault,
    ));
    expect(r.isSuccess, isTrue, reason: r.errorMessage);
    final inv = await invoice(r.invoiceId!);
    expect(inv.tax, closeTo(16, 0.001));

    final items = await db.getSalesInvoiceItems(inv.id);
    final ok = await returns.processSalesReturn(
      invoice: inv,
      returnQuantities: {for (final i in items) i.id: i.quantity},
      productCache: {
        for (final p in await productRepo.getProductsByIds(
            [exemptId, customId]))
          p.id: p,
      },
      userId: userId,
      userName: 'B3 cashier',
      isFullReturn: true,
    );
    expect(ok, isTrue);

    final retEntries = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals('sales_return')))
        .get();
    expect(retEntries, isNotEmpty, reason: 'return JE not posted');
    final vat = await db.getAccountByCode('2121');
    var net = 0.0;
    for (final e in retEntries) {
      for (final l in await (db.select(db.journalEntryLines)
            ..where((x) => x.entryId.equals(e.id)))
          .get()) {
        if (l.accountId == vat!.id) net += l.debit - l.credit;
      }
    }
    expect(net, closeTo(16, 0.001),
        reason: 'only the custom line carried VAT; the exempt line had none');
  });

  test('sync round-trip: /api/products carries taxExempt; client applies it',
      () async {
    final response = await ApiHandler(db).buildRouter().call(
        shelf.Request('GET', Uri.parse('http://localhost/api/products')));
    expect(response.statusCode, 200);
    final body =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final rows = (body['products'] as List).cast<Map<String, dynamic>>();
    final byCode = {for (final p in rows) p['code']: p};
    expect(byCode['B3-EX']!['taxExempt'], isTrue);
    expect(byCode['B3-DEF']!['taxExempt'], isFalse);

    final client = AppDatabase.forTesting();
    await ProductSyncStrategy(client).syncFromJson(body);
    final cEx = await (client.select(client.products)
          ..where((p) => p.code.equals('B3-EX')))
        .getSingle();
    final cDef = await (client.select(client.products)
          ..where((p) => p.code.equals('B3-DEF')))
        .getSingle();
    expect(await client.getProductTaxExempt(cEx.id), isTrue);
    expect(await client.getProductTaxExempt(cDef.id), isFalse);

    // Clearing on the server clears on the client.
    await db.setProductTaxExempt(exemptId, false);
    final again = await ApiHandler(db).buildRouter().call(
        shelf.Request('GET', Uri.parse('http://localhost/api/products')));
    await ProductSyncStrategy(client).syncFromJson(
        jsonDecode(await again.readAsString()) as Map<String, dynamic>);
    expect(await client.getProductTaxExempt(cEx.id), isFalse);

    // An older server (no key) leaves the local flag untouched.
    await client.setProductTaxExempt(cEx.id, true);
    final legacy = Map<String, dynamic>.from(byCode['B3-EX']!)
      ..remove('taxExempt');
    await ProductSyncStrategy(client).syncFromJson({
      'products': [legacy],
    });
    expect(await client.getProductTaxExempt(cEx.id), isTrue);
  });

  group('e-invoice', () {
    late int saleId;

    setUp(() async {
      await db.saveEInvoiceConfig(
        platform: 'eta',
        clientId: 'id',
        clientSecret: 'secret',
        registrationNumber: '100-200-300',
        isEnabled: true,
      );
      final r = await orch.completeSalesTransaction(SaleRequest(
        items: [formLine(exemptId, 0), formLine(customId, 16)],
        customerId: customerId,
        warehouseId: warehouseId,
        userId: userId,
        paymentMethod: 'credit',
        paidAmount: 0,
        taxEnabled: true,
        taxPercent: _companyDefault,
      ));
      expect(r.isSuccess, isTrue, reason: r.errorMessage);
      saleId = r.invoiceId!;
    });

    Future<List<Map<String, dynamic>>> unifiedItems() async {
      final payload = await db.buildInvoicePayload(saleId, 'eta');
      return (UnifiedInvoice.fromPayload(payload).toPayload()['items'] as List)
          .cast<Map<String, dynamic>>();
    }

    test('payload: exempt line → V003 + taxExempt; taxed line unchanged',
        () async {
      final items = (await db.buildInvoicePayload(saleId, 'eta'))['items']
          as List;
      final ex = items.cast<Map>().firstWhere((m) => m['taxAmount'] == 0);
      final taxed = items.cast<Map>().firstWhere((m) => m['taxAmount'] != 0);
      expect(ex['taxSubtype'], 'V003');
      expect(ex['taxExempt'], isTrue);
      expect(taxed['taxSubtype'], 'V009');
      expect(taxed.containsKey('taxExempt'), isFalse);
    });

    test('ETA document: exempt line subType V003 (not zero-rated)', () async {
      String? sent;
      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(
              jsonEncode({'access_token': 't', 'expires_in': 3600}), 200);
        }
        sent = req.body;
        return http.Response(
            jsonEncode({
              'submissionId': 'S',
              'acceptedDocuments': [],
              'rejectedDocuments': [],
            }),
            202);
      });
      final payload = await db.buildInvoicePayload(saleId, 'eta');
      final doc = UnifiedInvoice.fromPayload(payload).toPayload();
      await EtaService(
        config: const EtaConfig(
            clientId: 'id', clientSecret: 's', registrationNumber: '1'),
        httpClient: client,
      ).submitInvoice(doc);

      final docs = (jsonDecode(sent!) as Map)['documents'] as List;
      final lines = ((docs.first as Map)['invoiceLines'] as List)
          .cast<Map<String, dynamic>>();
      Map<String, dynamic> firstTax(Map<String, dynamic> l) =>
          ((l['taxableItems'] as List).first as Map).cast<String, dynamic>();
      final subTypes = [for (final l in lines) firstTax(l)['subType']];
      expect(subTypes, containsAll(['V003', 'V009']));
      final exLine = lines.firstWhere((l) => firstTax(l)['subType'] == 'V003');
      expect(firstTax(exLine)['amount'], 0);
    });

    test('JoFotara document: exempt line category E; taxed line has none',
        () async {
      String? sent;
      final client = MockClient((req) async {
        if (req.url.path.contains('/auth/token')) {
          return http.Response(
              jsonEncode({'access_token': 't', 'expires_in': 3600}), 200);
        }
        sent = req.body;
        return http.Response(jsonEncode({'invoiceId': 'J'}), 200);
      });
      await JofotaraService(
        config: const JofotaraConfig(
            clientId: 'id', clientSecret: 's', registrationNumber: '1'),
        httpClient: client,
      ).submitInvoice({
        'issueDate': DateTime(2026, 1, 1).toIso8601String(),
        'items': await unifiedItems(),
      });
      final lines = ((jsonDecode(sent!) as Map)['lineItems'] as List)
          .cast<Map<String, dynamic>>();
      final ex = lines.firstWhere((l) => l['taxAmount'] == 0);
      final taxed = lines.firstWhere((l) => l['taxAmount'] != 0);
      expect(ex['taxCategory'], 'E');
      expect(taxed.containsKey('taxCategory'), isFalse);
    });
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
/// (same as `round_wiring_endtoend_test.dart`).
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
