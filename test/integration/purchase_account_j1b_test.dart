// ═══════════════════════════════════════════════════════════════════════════
// J1b — «حساب المشتريات» chosen per purchase invoice (mirror of C2).
// ═══════════════════════════════════════════════════════════════════════════
//
// Real paths, in-memory SQLite:
//   • Purchase invoice with a NON-default account → the purchase JE debits it
//     (mapped 'inventory' untouched; VAT / supplier lines unchanged).
//   • NULL (default / legacy) → the mapped 'inventory' debit, as before.
//   • Return of that invoice → credits the SAME account.
//   • An inactive / unsuitable stored account falls back to the mapping.
//   • Edit → repost honours the account (and clearing it returns to mapping).
//   • Sync: `/api/purchases` push stores it, the snapshot carries it, the
//     client PurchaseSyncStrategy stores it.
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_purchase_handler.dart';
import 'package:ural_erp/services/api/api_user_context.dart';
import 'package:ural_erp/services/sync/strategies/purchase_sync_strategy.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int supplierId;
  late int productId;
  late int adminId;
  late int otherAccountId;
  late int mappedInventoryId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    final branchId = await db.into(db.branches).insert(
        BranchesCompanion.insert(name: 'j1b', globalId: const Value('gid-br-j1b')));
    warehouseId = await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        name: 'wh-j1b',
        branchId: Value(branchId),
        globalId: const Value('gid-wh-j1b')));
    supplierId = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'J1b supplier',
        isSupplier: const Value(true),
        isCustomer: const Value(false),
        globalId: const Value('gid-sup-j1b')));
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'J1B-P',
      name: 'J1b item',
      salePrice: const Value(200.0),
      costPrice: const Value(0.0),
      currentStock: const Value(0),
      trackInventory: const Value(true),
    ));
    adminId = (await db
            .customSelect("SELECT id FROM users WHERE username = 'admin' LIMIT 1")
            .getSingle())
        .read<int>('id');
    otherAccountId = await db.into(db.accounts).insert(AccountsCompanion.insert(
          code: '52991',
          name: 'J1b external purchases',
          accountType: 'expense',
          accountNature: const Value('detail'),
          normalBalance: const Value('debit'),
        ));
    mappedInventoryId = (await db.getLeafAccountByPurpose('inventory'))!.id;
    expect(otherAccountId, isNot(mappedInventoryId));
  });

  tearDown(() async => db.close());

  Future<int> buy({int? purchaseAccountId, String gid = 'j1b-purchase'}) {
    return db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0,
      paymentMethod: 'credit',
      globalId: gid,
      purchaseAccountId: purchaseAccountId,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 10,
          unitCost: 10,
          total: 100,
        ),
      ],
    );
  }

  /// Net (debit − credit) per account over the JEs of [refType] / [refId].
  Future<Map<int, double>> net(String refType, int refId) async {
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

  Future<PurchaseInvoiceData> invoice(int id) async =>
      (await db.getPurchaseInvoiceById(id))!;

  Future<Map<int, double>> returnNet(int invoiceId) async {
    final inv = await invoice(invoiceId);
    await db.autoPostPurchaseReturn(
      originalPurchase: inv,
      returnDate: inv.invoiceDate,
      returnAmount: 100,
      apPortion: 100,
      cashPortion: 0,
      returnEventId: 'PRET-J1B-$invoiceId',
    );
    return net('purchase_return', invoiceId);
  }

  test('non-default account: the purchase JE debits it, mapped stays zero',
      () async {
    final id = await buy(purchaseAccountId: otherAccountId);
    expect(await db.getPurchaseInvoicePurchaseAccountId(id), otherAccountId);
    final n = await net('purchase_invoice', id);
    expect(n[otherAccountId], closeTo(100, 0.001));
    expect(n[mappedInventoryId] ?? 0, closeTo(0, 0.001));
    // Whole JE still balances (supplier credit carries the 100).
    expect(n.values.fold<double>(0, (a, b) => a + b), closeTo(0, 0.001));
  });

  test('default (null) keeps the mapped inventory debit', () async {
    final id = await buy();
    expect(await db.getPurchaseInvoicePurchaseAccountId(id), isNull);
    final n = await net('purchase_invoice', id);
    expect(n[mappedInventoryId], closeTo(100, 0.001));
    expect(n[otherAccountId] ?? 0, closeTo(0, 0.001));
  });

  test('return credits the same account as its original invoice', () async {
    final id = await buy(purchaseAccountId: otherAccountId);
    final n = await returnNet(id);
    expect(n[otherAccountId], closeTo(-100, 0.001));
    expect(n[mappedInventoryId] ?? 0, closeTo(0, 0.001));
  });

  test('return of a default invoice credits the mapped account', () async {
    final id = await buy();
    final n = await returnNet(id);
    expect(n[mappedInventoryId], closeTo(-100, 0.001));
  });

  test('inactive stored account falls back to the mapping (post and return)',
      () async {
    final id = await buy(purchaseAccountId: otherAccountId);
    await (db.update(db.accounts)..where((a) => a.id.equals(otherAccountId)))
        .write(const AccountsCompanion(isActive: Value(false)));
    expect(await db.resolvePurchaseAccountOverride(id), isNull);
    final n = await returnNet(id);
    expect(n[mappedInventoryId], closeTo(-100, 0.001));
    expect(n[otherAccountId] ?? 0, closeTo(0, 0.001));

    // A fresh invoice pointing at the (now inactive) account posts to mapping.
    final id2 = await buy(purchaseAccountId: otherAccountId, gid: 'j1b-p2');
    final n2 = await net('purchase_invoice', id2);
    expect(n2[mappedInventoryId], closeTo(100, 0.001));
  });

  test('a revenue account is never accepted as the purchase debit', () async {
    final revenueId = (await db.getLeafAccountByPurpose('sales'))!.id;
    final id = await buy(purchaseAccountId: revenueId);
    expect(await db.resolvePurchaseAccountOverride(id), isNull);
    final n = await net('purchase_invoice', id);
    expect(n[mappedInventoryId], closeTo(100, 0.001));
    final offered = (await db.getActivePurchaseDebitAccounts()).map((a) => a.id);
    expect(offered, contains(otherAccountId));
    expect(offered, contains(mappedInventoryId));
    expect(offered, isNot(contains(revenueId)));
  });

  test('edit repost honours a new account, and clearing returns to mapping',
      () async {
    final id = await buy();
    Future<void> edit({required bool change, int? account}) =>
        db.updatePurchaseInvoice(
          invoiceId: id,
          supplierId: supplierId,
          warehouseId: warehouseId,
          paid: 0,
          paymentMethod: 'credit',
          items: [
            PurchaseInvoiceItemsCompanion.insert(
              invoiceId: id,
              productId: productId,
              quantity: 10,
              unitCost: 10,
              total: 100,
            ),
          ],
          userId: adminId,
          changePurchaseAccount: change,
          purchaseAccountId: account,
        );

    await edit(change: true, account: otherAccountId);
    expect(await db.getPurchaseInvoicePurchaseAccountId(id), otherAccountId);
    var n = await net('purchase', id);
    expect(n[otherAccountId], closeTo(100, 0.001));

    // Untouched when the edit does not carry the choice.
    await edit(change: false);
    expect(await db.getPurchaseInvoicePurchaseAccountId(id), otherAccountId);

    await edit(change: true, account: null);
    expect(await db.getPurchaseInvoicePurchaseAccountId(id), isNull);
    n = await net('purchase', id);
    expect(n[mappedInventoryId], closeTo(100, 0.001));
  });

  test('sync: server push stores it, snapshot carries it, client strategy stores it',
      () async {
    final response = await ApiPurchaseHandler(db, {}).postPurchase(shelf.Request(
      'POST',
      Uri.parse('http://localhost/api/purchases'),
      body: jsonEncode({
        'globalId': 'j1b-api-purchase',
        'supplierId': supplierId,
        'warehouseId': warehouseId,
        'paid': 0.0,
        'paymentMethod': 'credit',
        'purchaseAccountId': otherAccountId,
        'items': [
          {
            'productId': productId,
            'quantity': 10.0,
            'unitCost': 10.0,
            'total': 100.0,
          },
        ],
      }),
      headers: {'Content-Type': 'application/json'},
      context: {ApiUserCtx.userIdKey: adminId},
    ));
    expect(response.statusCode, 200, reason: await response.readAsString());
    final saved = await (db.select(db.purchaseInvoices)
          ..where((p) => p.globalId.equals('j1b-api-purchase')))
        .getSingle();
    expect(await db.getPurchaseInvoicePurchaseAccountId(saved.id), otherAccountId);
    expect((await net('purchase_invoice', saved.id))[otherAccountId],
        closeTo(100, 0.001));

    // The delta pull is `SELECT *`: the raw column is visible to it.
    final raw = await db
        .customSelect('SELECT * FROM purchase_invoices WHERE id = ?',
            variables: [Variable<int>(saved.id)])
        .getSingle();
    expect(raw.data['purchase_account_id'], otherAccountId);

    // Client side: strategy applies the snapshot map (insert, then update).
    final client = AppDatabase.forTesting();
    addTearDown(client.close);
    await client.into(client.parties).insert(PartiesCompanion.insert(
        id: Value(supplierId),
        name: 'J1b supplier',
        isSupplier: const Value(true),
        isCustomer: const Value(false)));
    final map = <String, dynamic>{
      'id': saved.id,
      'invoiceNumber': saved.invoiceNumber,
      'supplierId': supplierId,
      'warehouseId': 1,
      'invoiceDate': saved.invoiceDate.toIso8601String(),
      'subtotal': 100.0,
      'total': 100.0,
      'paid': 0.0,
      'status': 'completed',
      'purchaseAccountId': otherAccountId,
      'items': <Map<String, dynamic>>[],
    };
    await PurchaseSyncStrategy(client).syncFromJson({'purchases': [map]});
    expect(await client.getPurchaseInvoicePurchaseAccountId(saved.id),
        otherAccountId);

    // An older server (no key) leaves the client's value untouched; an explicit
    // null clears it.
    final legacy = Map<String, dynamic>.from(map)..remove('purchaseAccountId');
    await PurchaseSyncStrategy(client).syncFromJson({'purchases': [legacy]});
    expect(await client.getPurchaseInvoicePurchaseAccountId(saved.id),
        otherAccountId);
    await PurchaseSyncStrategy(client)
        .syncFromJson({'purchases': [Map<String, dynamic>.from(map)..['purchaseAccountId'] = null]});
    expect(await client.getPurchaseInvoicePurchaseAccountId(saved.id), isNull);
  });
}
