// WH-002 through a REAL host and REAL client peers (fleet harness, real HTTP):
// the accountant's receipts inbox on a client desktop reads the MAIN (the phone
// documents are not in the client's own database), converts once with exact
// stock / AP amounts, a user without purchases_create is refused, and a mirror
// console stays outside the warehouse API (route policy unchanged).
@Timeout(Duration(minutes: 5))
library;

import 'dart:io' show HttpOverrides;

import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';


import 'package:picpos_erp/data/database/wh_mobile_docs_schema.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/data/providers/wh_receipts_inbox_provider.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_doc_store.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_http.dart';
import 'package:picpos_erp/services/api/m1_wh/wh_receipts_source.dart';

import '../helpers/fleet_harness.dart';

void main() {
  Fleet.bindEnvironment();
  setUpAll(() => HttpOverrides.global = null);

  late Fleet fleet;
  late int po, productId, supplierId, whId;
  late String receiptGid;
  late String b2Receipt;

  setUp(() async {
    fleet = await Fleet.startMain();
    await fleet.useMain();
    final db = fleet.main.db;
    await Fleet.grantPermissions(db, 'محاسب', ['purchases_create']);
    whId = (await db.select(db.warehouses).get()).first.id;
    await db.into(db.userWarehouseAccess).insert(UserWarehouseAccessCompanion.insert(userId: fleet.userIds['accountant']!, warehouseId: whId));
    supplierId = await db.into(db.parties).insert(PartiesCompanion.insert(name: 'Supp', isSupplier: const Value(true)));
    productId = await db.insertProduct(ProductsCompanion.insert(
        code: 'RICE', name: 'Rice', salePrice: const Value(20.0), costPrice: const Value(10),
        trackInventory: const Value(true)));
    po = await db.createPurchaseOrder(
      supplierId: supplierId,
      warehouseId: whId,
      orderDate: DateTime(2026, 9, 1),
      items: [PurchaseOrderItemsCompanion.insert(orderId: 0, productId: productId, quantity: 12, unitCost: 40, total: 480)],
    );
    await db.updatePurchaseOrderStatus(po, 'confirmed');
    // the phone submitted 6 of 12 (the document lives ONLY on the main)
    await db.ensureWhMobileDocsSchema();
    final store = WhDocStore(db);
    final item = (await db.getPurchaseOrderItems(po)).single;
    final doc = await store.create(
        kind: 'po_receipt', state: 'submitted', warehouseId: whId, createdBy: fleet.userIds['cashier']!,
        deviceId: 'phone-1', refType: 'purchase_order', refId: '$po');
    receiptGid = doc.gid;
    await store.addLine(doc, lineGid: 'line-1', productId: productId, qty: 6, poItemId: item.id);
    await (db.update(db.purchaseOrderItems)..where((i) => i.id.equals(item.id)))
        .write(const PurchaseOrderItemsCompanion(receivedQuantity: Value(6)));
    for (final (d, u, p) in [
      (fleet.accountant, 'accountant', kAcctPw),
      (fleet.cashier, 'cashier', kCashPw),
      (fleet.mirror, 'manager', kManagerFleetPw),
    ]) {
      final r = d.kind == 'mirror' ? await fleet.installMirror(d, u, p) : await fleet.installClient(d, u, p);
      expect(r.ok, isTrue, reason: '$r');
    }
  });
  tearDown(() => fleet.dispose());

  test('the client desktop lists the waiting receipt from the MAIN (its own DB has none), converts it once; '
      'stock and supplier AP are exact', () async {
    await fleet.login(fleet.accountant, 'accountant', kAcctPw);
    final localDocs = await fleet.accountant.db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='wh_mobile_docs'").get();
    expect(localDocs, isEmpty, reason: 'the client has no phone documents of its own');

    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(fleet.accountant.db)]);
    addTearDown(container.dispose);
    final source = container.read(whReceiptsInboxProvider);
    expect(source, isA<WhRemoteReceipts>(), reason: 'client mode reads the main, never the local database');

    final uid = fleet.userIds['accountant']!;
    final waiting = await source.list(uid);
    expect(waiting, hasLength(1));
    expect(waiting.single['globalId'], receiptGid);
    expect(waiting.single['lines'], hasLength(1));
    expect(((waiting.single['lines'] as List).single as Map)['quantity'], '6');

    final out = await source.convert(receiptGid, uid);
    expect(out['invoiceId'], isNotNull);
    final db = fleet.main.db;
    expect(await db.select(db.purchaseInvoices).get(), hasLength(1));
    final bal = await (db.select(db.inventoryBalances)
          ..where((x) => x.productId.equals(productId) & x.warehouseId.equals(whId)))
        .getSingle();
    expect(bal.quantity, 6);
    expect((await (db.select(db.parties)..where((p) => p.id.equals(supplierId))).getSingle()).balance, 240);
    expect((await db.getPurchaseOrderById(po))!.convertedToInvoiceId, isNull, reason: 'only 6 of 12 received: the order stays open');

    expect(await source.list(uid), isEmpty);
    // a lost answer: the SAME key is a replay, not a second invoice
    final again = await source.convert(receiptGid, uid);
    expect(again['replayed'], isTrue);
    // another command on the already converted document is refused
    final peer = await fleet.peer(fleet.accountant);
    expect((await peer.login('accountant', kAcctPw)).status, 200);
    final second = await peer.transport('POST', '/api/m1/wh/desk/receipts/$receiptGid/convert',
        {...peer.headers(), 'x-idempotency-key': 'another-key-0001'}, '{}');
    expect(second.status, 409, reason: '$second');
    expect(second.code ?? second.json['error'], 'invalid_transition');
    expect(await db.select(db.purchaseInvoices).get(), hasLength(1), reason: 'converted once');
  });

  test('a client user without purchases_create is refused by the main (permission_denied / 403)', () async {
    await fleet.login(fleet.cashier, 'cashier', kCashPw);
    await expectLater(WhRemoteReceipts().list(fleet.userIds['cashier']!),
        throwsA(isA<WhError>().having((e) => e.code, 'code', 'permission_denied').having((e) => e.status, 'status', 403)));
    final db = fleet.main.db;
    expect(await db.select(db.purchaseInvoices).get(), isEmpty);
  });

  // ── OWNER DECISION 2026-10-26: the accountant's desk is open to a MIRROR ──
  group('mirror console', () {
    late int managerId;
    setUp(() async {
      managerId = fleet.userIds['manager']!;
      // the owner lets the branch-manager role convert receipts
      await Fleet.grantPermissions(fleet.main.db, 'مدير فروع (fleet)', ['purchases_create']);
    });

    Future<int> receiptInBranch2() async {
      await fleet.useMain(); // writes on the main's own database, not through the mirror's interceptor
      final db = fleet.main.db;
      final wh2 = await db.into(db.warehouses).insert(WarehousesCompanion.insert(name: 'مخزن الفرع الثاني', branchId: Value(fleet.branch2)));
      final po2 = await db.createPurchaseOrder(
        supplierId: supplierId, warehouseId: wh2, orderDate: DateTime(2026, 9, 2),
        items: [PurchaseOrderItemsCompanion.insert(orderId: 0, productId: productId, quantity: 5, unitCost: 40, total: 200)],
      );
      await db.updatePurchaseOrderStatus(po2, 'confirmed');
      final store = WhDocStore(db);
      final item = (await db.getPurchaseOrderItems(po2)).single;
      final doc = await store.create(
          kind: 'po_receipt', state: 'submitted', warehouseId: wh2, createdBy: fleet.userIds['cashier']!,
          deviceId: 'phone-2', refType: 'purchase_order', refId: '$po2');
      await store.addLine(doc, lineGid: 'line-b2', productId: productId, qty: 5, poItemId: item.id);
      b2Receipt = doc.gid;
      return wh2;
    }

    test('the signed-in mirror manager lists and converts through the real host as HIMSELF; exact stock / AP; '
        'a repeat is an idempotent replay', () async {
      expect(await fleet.login(fleet.mirror, 'manager', kManagerFleetPw), isNotNull);
      final source = ProviderContainer(overrides: [databaseProvider.overrideWithValue(fleet.mirror.db)])
          .read(whReceiptsInboxProvider);
      expect(source, isA<WhRemoteReceipts>());
      final waiting = await source.list(managerId);
      expect(waiting.map((r) => r['globalId']), [receiptGid]);

      final out = await source.convert(receiptGid, managerId);
      expect(out['invoiceId'], isNotNull);
      final db = fleet.main.db;
      expect(await db.select(db.purchaseInvoices).get(), hasLength(1));
      final bal = await (db.select(db.inventoryBalances)
            ..where((x) => x.productId.equals(productId) & x.warehouseId.equals(whId)))
          .getSingle();
      expect(bal.quantity, 6);
      expect((await (db.select(db.parties)..where((p) => p.id.equals(supplierId))).getSingle()).balance, 240);
      final doc = await WhDocStore(db).mustGet(receiptGid);
      expect(doc.state, 'posted');
      expect(doc.approvedBy, managerId, reason: 'the acting user is the signed-in mirror user, not the pairing admin');
      final logUsers = await db.customSelect("SELECT DISTINCT user_id FROM activity_logs WHERE entity_type='wh_mobile_doc'").get();
      expect(logUsers.map((r) => r.read<int>('user_id')), [managerId]);

      final again = await source.convert(receiptGid, managerId);
      expect(again['replayed'], isTrue);
      expect(await db.select(db.purchaseInvoices).get(), hasLength(1), reason: 'converted once');
      expect(await source.list(managerId), isEmpty);
    });

    test('a mirror manager without purchases_create, or without mirror_console, is refused and nothing is posted', () async {
      expect(await fleet.login(fleet.mirror, 'manager', kManagerFleetPw), isNotNull);
      final db = fleet.main.db;
      final role = (await db.getAllRoles()).firstWhere((r) => r.name == 'مدير فروع (fleet)');
      final all = await db.getAllPermissions();
      int id(String c) => all.firstWhere((p) => p.code == c).id;
      // 1. no purchases_create
      await db.setRolePermissions(role.id, [id('mirror_console')]);
      await expectLater(WhRemoteReceipts().list(managerId),
          throwsA(isA<WhError>().having((e) => e.code, 'code', 'permission_denied').having((e) => e.status, 'status', 403)));
      await expectLater(WhRemoteReceipts().convert(receiptGid, managerId), throwsA(isA<WhError>().having((e) => e.status, 'status', 403)));
      // 2. purchases_create but the console grant revoked
      await db.setRolePermissions(role.id, [id('purchases_create')]);
      await expectLater(WhRemoteReceipts().list(managerId),
          throwsA(isA<WhError>().having((e) => e.code, 'code', 'mirror_console_denied').having((e) => e.status, 'status', 403)));
      expect(await db.select(db.purchaseInvoices).get(), isEmpty);
      expect((await WhDocStore(db).mustGet(receiptGid)).state, 'submitted');
    });

    test('a user with purchases_create but no mirror_console cannot even sign in on the mirror', () async {
      final mirror = await fleet.peer(fleet.mirror);
      final r = await mirror.login('accountant', kAcctPw);
      expect(r.status, 403, reason: '$r');
      expect(r.code, 'mirror_console_denied');
    });

    test('branch scope: ALL-branch manager sees both branches; narrowed to B1 he sees and converts only B1', () async {
      await receiptInBranch2();
      expect(await fleet.login(fleet.mirror, 'manager', kManagerFleetPw), isNotNull);
      final db = fleet.main.db;
      final all = await WhRemoteReceipts().list(managerId);
      expect(all.map((r) => r['globalId']).toSet(), {receiptGid, b2Receipt});

      // the owner narrows him to branch 1 only
      await db.customStatement(
          'DELETE FROM user_branch_access WHERE user_id = ? AND branch_id = ?', [managerId, fleet.branch2]);
      final only1 = await WhRemoteReceipts().list(managerId);
      expect(only1.map((r) => r['globalId']), [receiptGid], reason: 'the B2 receipt is outside his scope');
      await expectLater(WhRemoteReceipts().convert(b2Receipt, managerId),
          throwsA(isA<WhError>().having((e) => e.code, 'code', 'doc_not_found').having((e) => e.status, 'status', 404)));
      expect(await db.select(db.purchaseInvoices).get(), isEmpty, reason: 'nothing converted outside the scope');
      expect((await WhDocStore(db).mustGet(b2Receipt)).state, 'submitted');
      expect((await WhRemoteReceipts().convert(receiptGid, managerId))['invoiceId'], isNotNull);
    });

    test('offline: the mirror refuses honestly (host_unreachable), posts nothing locally, and works again after reconnect', () async {
      expect(await fleet.login(fleet.mirror, 'manager', kManagerFleetPw), isNotNull);
      await fleet.mainDown();
      for (final call in [() => WhRemoteReceipts().list(managerId), () => WhRemoteReceipts().convert(receiptGid, managerId)]) {
        await expectLater(call(), throwsA(isA<WhError>().having((e) => e.code, 'code', 'host_unreachable').having((e) => e.status, 'status', 503)));
      }
      final mdb = fleet.mirror.db;
      expect(await mdb.select(mdb.purchaseInvoices).get(), isEmpty, reason: 'a mirror never invents a local invoice');
      expect(await mdb.select(mdb.syncOutbox).get(), isEmpty, reason: 'a mirror has no outbox');
      await fleet.mainUp();
      expect(await fleet.login(fleet.mirror, 'manager', kManagerFleetPw), isNotNull);
      expect((await WhRemoteReceipts().convert(receiptGid, managerId))['invoiceId'], isNotNull);
      final db = fleet.main.db;
      expect(await db.select(db.purchaseInvoices).get(), hasLength(1));
    });
  });
}
