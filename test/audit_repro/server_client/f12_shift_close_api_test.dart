import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_data_handler.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';
import '../../scenarios/scenario_world.dart';

const _skip = 'audit repro — pending owner approval';

void main() {
  test('F12 API close stores snapshot and method; click is not a cash variance input',
      skip: _skip, () async {
    final server = await ScenarioWorld.create();
    final client = await ScenarioWorld.create();
    addTearDown(server.dispose);
    addTearDown(client.dispose);

    Future<int> seedBusiness(ScenarioWorld w, String suffix) async {
      final productId = await w.addProduct('F12-$suffix', price: 60, cost: 30, stock: 10);
      await w.sell([w.line(productId, 2, 60)]);
      final invoice = (await w.db.select(w.db.salesInvoices).get())
          .lastWhere((row) => row.saleType == 'default');
      expect(await w.returnItems(invoice.id, productId, 1), isTrue);

      // Real cashier-safe movements for one operational expense and one
      // supplier/payment voucher, following the production close aggregation.
      final safeId = w.cashSafeId;
      await w.db.createSafeTransaction(SafeTransactionsCompanion.insert(
        voucherNumber: 'F12-$suffix-EXP', safeId: safeId,
        transactionType: 'payment', category: 'expense', amount: 10,
        balanceAfter: 0, userId: Value(w.userId),
      ));
      await w.db.createSafeTransaction(SafeTransactionsCompanion.insert(
        voucherNumber: 'F12-$suffix-VOUCHER', safeId: safeId,
        transactionType: 'payment', category: 'supplier_payment', amount: 15,
        balanceAfter: 0, userId: Value(w.userId),
      ));
      return productId;
    }

    final serverProductId = await seedBusiness(server, 'SRV');
    final clientProductId = await seedBusiness(client, 'CLI');
    await server.grant('pos_shift_close');
    final serverOpen = (await server.db.getCurrentOpenShift(server.userId))!;
    final clientOpen = (await client.db.getCurrentOpenShift(client.userId))!;
    final serverBefore = await server.db.getShiftClosingAggregates(
      userId: server.userId, includeAllUsers: false,
      shiftStart: serverOpen.startTime, openingBalance: serverOpen.openingBalance,
    );
    final clientBefore = await client.db.getShiftClosingAggregates(
      userId: client.userId, includeAllUsers: false,
      shiftStart: clientOpen.startTime, openingBalance: clientOpen.openingBalance,
    );
    // Sale 120 - return 60 - expense 10 - voucher 15 = 35.
    expect(serverBefore.systemCash, 35);
    expect(clientBefore.systemCash, 35);

    const snapshot = '{"actualCash":32,"actualCard":0,"actualClick":7,'
        '"systemCash":35,"systemClick":0,"clickVariance":7}';
    final response = await ApiDataHandler(server.db, {}).postCloseShift(Request(
      'POST', Uri.parse('http://localhost/api/shifts/close'),
      body: jsonEncode({
        'shiftId': serverOpen.id,
        'userId': server.userId,
        'actualCash': 32,
        'actualClick': 7,
        'closingMethod': 'audit-f12',
        'closingSnapshot': snapshot,
      }),
      headers: {'content-type': 'application/json'},
      context: {ApiUserCtx.userIdKey: server.userId},
    ));
    expect(response.statusCode, 200, reason: await response.readAsString());

    final serverAfter = await (server.db.select(server.db.shifts)
          ..where((row) => row.id.equals(serverOpen.id)))
        .getSingle();
    expect(serverAfter.expectedCash, 35);
    expect(serverAfter.variance, -3);
    expect(serverAfter.closingMethod, 'audit-f12');
    expect(serverAfter.closingSnapshot, snapshot);

    await client.db.closeShiftWithAudit(clientOpen.id, 32,
        closingMethod: 'audit-f12', closingSnapshot: snapshot);
    final clientAfter = await (client.db.select(client.db.shifts)
          ..where((row) => row.id.equals(clientOpen.id)))
        .getSingle();
    expect(clientAfter.expectedCash, 35);
    expect(clientAfter.variance, -3);
    expect(clientAfter.closingSnapshot, snapshot);

    final serverMoves = await (server.db.select(server.db.safeTransactions)
          ..where((row) => row.userId.equals(server.userId)))
        .get();
    final clientMoves = await (client.db.select(client.db.safeTransactions)
          ..where((row) => row.userId.equals(client.userId)))
        .get();
    final serverLedger = await server.journalTotals();
    final clientLedger = await client.journalTotals();
    // ignore: avoid_print
    print('[AUDIT-F12] sale=120 return=60 expense=10 voucher=15 '
        'expected server/client=${serverAfter.expectedCash}/${clientAfter.expectedCash} '
        'actualCash=32 snapshot.actualClick=7 variance=${serverAfter.variance}/${clientAfter.variance} '
        'safeTx=${serverMoves.length}/${clientMoves.length} '
        'safeBalance=${await server.safeBalance()}/${await client.safeBalance()} '
        'stock=${await server.stock(serverProductId)}/${await client.stock(clientProductId)} '
        'journalDrCr=${serverLedger.debit}/${serverLedger.credit} '
        'clientJournalDrCr=${clientLedger.debit}/${clientLedger.credit}');
  });
}
