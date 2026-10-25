// F2 - DATA FLOW across the fleet: the cashier sells (invoice + a later
// payment) through the real write interceptor -> the main receives it; the
// accountant sees it after a sync; the mirror reads ALL branches while a branch
// device only sees its own.
@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io' show HttpOverrides;

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' show Request;

import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/api/api_sales_handler.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';
import 'package:picpos_erp/services/client_write_interceptor.dart';

import '../helpers/fleet_harness.dart';

/// delta rows are column-keyed (snake_case); tolerate either spelling
Object? _number(Map r) => r['invoice_number'] ?? r['invoiceNumber'];

void main() {
  Fleet.bindEnvironment();
  setUpAll(() => HttpOverrides.global = null);

  late Fleet fleet;
  setUp(() async => fleet = await Fleet.build());
  tearDown(() => fleet.dispose());

  Future<List<SalesInvoiceData>> hostInvoices() =>
      fleet.main.db.select(fleet.main.db.salesInvoices).get();

  test('F2.1 the cashier sells: the main stores the invoice once, authored by '
      "the cashier, with the device's global id; the accountant collects the rest "
      '(additive, deduped)', () async {
    expect(await fleet.login(fleet.cashier, 'cashier', kCashPw), isNotNull);
    final serverId = await fleet.sell(fleet.cashier,
        invoiceNo: 'F2-1',
        globalId: 'gid-f2-1',
        total: 50,
        paid: 20,
        onCredit: true,
        username: 'cashier');
    expect(serverId, isNotNull, reason: 'online: answered by the main, not queued');

    var rows = await hostInvoices();
    expect(rows.length, 1);
    expect(rows.single.globalId, 'gid-f2-1');
    expect(rows.single.invoiceNumber, 'F2-1');
    expect(rows.single.userId, fleet.userIds['cashier']);
    expect(rows.single.paid, 20.0);
    final outbox = await fleet.cashier.db.select(fleet.cashier.db.syncOutbox).get();
    expect(outbox.where((o) => o.status == 'pending'), isEmpty,
        reason: 'nothing left pending after an online sale');

    // the accountant (sales_edit) collects the remaining 30 on his own device
    await fleet.login(fleet.accountant, 'accountant', kAcctPw);
    Future<bool> collect() => ClientWriteInterceptor.submitSalesPayment(
        salesId: serverId!,
        salesGlobalId: 'gid-f2-1',
        invoiceNumber: 'F2-1',
        amount: 30,
        globalId: 'gid-f2-pay-1',
        userId: fleet.userIds['accountant']);
    expect(await collect(), isTrue);
    rows = await hostInvoices();
    expect(rows.single.paid, 50.0, reason: '20 + 30 collected');
    expect(await collect(), isTrue, reason: 'lost answer: the same payment again');
    rows = await hostInvoices();
    expect(rows.single.paid, 50.0, reason: 'deduped on its global id');
    expect(rows.length, 1);
  });

  test('F2.2 the accountant (same branch) sees the cashier\'s invoice after '
      'a sync, with the payment applied', () async {
    await fleet.login(fleet.cashier, 'cashier', kCashPw);
    final id = await fleet.sell(fleet.cashier,
        invoiceNo: 'F2-2', globalId: 'gid-f2-2', total: 80, paid: 30, onCredit: true, username: 'cashier');
    await fleet.login(fleet.accountant, 'accountant', kAcctPw);
    expect(
        await ClientWriteInterceptor.submitSalesPayment(
            salesId: id!,
            salesGlobalId: 'gid-f2-2',
            invoiceNumber: 'F2-2',
            amount: 50,
            globalId: 'gid-f2-pay-2',
            userId: fleet.userIds['accountant']),
        isTrue);

    expect(await fleet.accountant.db.select(fleet.accountant.db.salesInvoices).get(),
        isEmpty,
        reason: 'nothing before the sync');
    await fleet.deltaPull(fleet.accountant, ['sales_invoices']);
    final seen = await fleet.accountant.db.select(fleet.accountant.db.salesInvoices).get();
    final inv = seen.firstWhere((i) => i.invoiceNumber == 'F2-2');
    expect(inv.paid, 80.0);
    expect(inv.globalId, 'gid-f2-2');
  });
  test('F2.3 the mirror reads ALL branches; a branch device only its own',
      () async {
    // an invoice of branch 2 exists on the main (written there)
    final db = fleet.main.db;
    final wh2 = await db.createWarehouseForBranch(
        name: 'مخزن ب2', branchId: fleet.branch2, isDefault: true);
    await fleet.login(fleet.cashier, 'cashier', kCashPw);
    await fleet.sell(fleet.cashier,
        invoiceNo: 'B1-100', globalId: 'gid-b1-100', total: 10, username: 'cashier');

    final posted = await ApiSalesHandler(db, {}).postSale(Request(
      'POST',
      Uri.parse('http://localhost/api/sales'),
      body: jsonEncode({
        'invoiceNumber': 'B2-200',
        'globalId': 'gid-b2-200',
        'subtotal': 25.0,
        'total': 25.0,
        'paid': 25.0,
        'paymentMethod': 'cash',
        'warehouseId': wh2,
        'branchId': fleet.branch2,
        'userId': fleet.userIds['b2emp'],
        'items': <Object>[],
      }),
      headers: {'content-type': 'application/json'},
      context: {ApiUserCtx.userIdKey: fleet.userIds['b2emp']!},
    ));
    expect(posted.statusCode, 200, reason: await posted.readAsString());

    final mirror = await fleet.peer(fleet.mirror);
    expect((await mirror.login('manager', kManagerFleetPw)).status, 200);    // the mirror's read path is the delta pull (it sends no branch_id): the
    // multi-branch manager receives the rows of EVERY branch he may access
    final pulled = await mirror.get('/api/sync/pull?table=sales_invoices');
    expect(pulled.status, 200, reason: '$pulled');
    final mirrorNumbers = [
      for (final s in (pulled.json['rows'] as List)) _number(s as Map)
    ];
    expect(mirrorNumbers, containsAll(['B1-100', 'B2-200']),
        reason: 'the mirror (multi-branch manager) reads both branches');

    final acct = await fleet.peer(fleet.accountant);
    expect((await acct.login('accountant', kAcctPw)).status, 200);
    final own = await acct.get('/api/sync/pull?table=sales_invoices&branch_id=${fleet.branch1}');
    final acctNumbers = [
      for (final s in (own.json['rows'] as List)) _number(s as Map)
    ];
    expect(acctNumbers, contains('B1-100'));
    expect(acctNumbers, isNot(contains('B2-200')),
        reason: 'a B1 device never reads branch 2 transactions');
    final foreign = await acct.get('/api/sync/pull?table=sales_invoices&branch_id=${fleet.branch2}');
    final foreignNumbers = [
      for (final s in (foreign.json['rows'] as List)) _number(s as Map)
    ];
    expect(foreignNumbers, isNot(contains('B2-200')),
        reason: 'asking for a foreign branch is clamped to the device\'s own');  });
}
