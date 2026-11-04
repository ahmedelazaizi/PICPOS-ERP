// R9 + R4 (docs/plans/2026-10-30-review-stability-sustainability.md).
//
// R9: the first number for a new prefix was seeded from COUNT(*)+1, so with
//     gaps an existing number was re-issued. Now MAX(numeric tail)+1.
// R4: the server prefixes client numbers with the BRANCH code only, so two
//     terminals in one branch that both issue `POS-1` land as the same server
//     number. Fixed on receipt by lib/services/api/server_invoice_number.dart
//     (next free MAX+1 in the same prefix; same globalId stays a duplicate).
import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_sales_handler.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';

void main() {
  group('R9 — seed from MAX not COUNT', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting());
    tearDown(() => db.close());

    Future<void> seedInvoice(String number) =>
        db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
              invoiceNumber: number,
              warehouseId: 1,
              userId: 1,
              invoiceDate: DateTime(2026, 3, 5),
            ));

    test('gaps 1,2,5 then 2 deleted → next is POS-6 (not POS-3)', () async {
      await seedInvoice('POS-1');
      await seedInvoice('POS-2');
      await seedInvoice('POS-5');
      await (db.delete(db.salesInvoices)
            ..where((s) => s.invoiceNumber.equals('POS-2')))
          .go();

      final n = await db.transaction(() => db.generateInvoiceNumber('POS'));
      expect(n, 'POS-6');
      // and it keeps advancing sequentially afterwards
      expect(await db.transaction(() => db.generateInvoiceNumber('POS')),
          'POS-7');
    });

    test('a longer prefix (POSX-9) and non-numeric tails do not pollute POS',
        () async {
      await seedInvoice('POS-3');
      await seedInvoice('POSX-9');
      await seedInvoice('POS-abc');
      final n = await db.transaction(() => db.generateInvoiceNumber('POS'));
      expect(n, 'POS-4');
    });

    test('legacy alias rows (Receipt-7) are honoured for the POS counter',
        () async {
      await seedInvoice('Receipt-7');
      final n = await db.transaction(() => db.generateInvoiceNumber('Receipt'));
      expect(n, 'POS-8');
    });

    test('empty table still starts at 1', () async {
      expect(await db.transaction(() => db.generateInvoiceNumber('POS')),
          'POS-1');
    });
  });

  group('R4 — two terminals in one branch (server side)', () {
    late AppDatabase db;
    late ApiSalesHandler handler;

    setUp(() async {
      db = AppDatabase.forTesting();
      await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(
            name: '2026',
            startDate: DateTime(2026, 1, 1),
            endDate: DateTime(2026, 12, 31),
          ));
      await (db.update(db.branches)..where((b) => b.id.equals(1)))
          .write(const BranchesCompanion(code: drift.Value('BR')));
      handler = ApiSalesHandler(db, {});
    });
    tearDown(() => db.close());

    Future<Response> post(String gid, String number) {
      return handler.postSale(Request(
        'POST',
        Uri.parse('http://localhost/api/sales'),
        body: jsonEncode({
          'globalId': gid,
          'invoiceNumber': number, // each terminal's own local counter value
          'clientIpSuffix': 'CL',
          'branchId': 1,
          'subtotal': 10.0,
          'total': 10.0,
          'paid': 10.0,
          'paymentMethod': 'cash',
          'warehouseId': 1,
          'userId': 1,
          'items': [],
        }),
        headers: {'Content-Type': 'application/json'},
        context: {ApiUserCtx.userIdKey: 1},
      ));
    }

    Future<Map<String, dynamic>> body(Response r) async =>
        jsonDecode(await r.readAsString()) as Map<String, dynamic>;

    test(
        'R4 fixed: terminals A and B both sending POS-1 get two distinct '
        'consecutive server numbers; resend of the same globalId is a '
        'duplicate with no new number', () async {
      final a = await post('gid-terminal-A-0001', 'POS-1');
      final b = await post('gid-terminal-B-0001', 'POS-1');
      expect(a.statusCode, 200);
      expect(b.statusCode, 200);
      final ja = await body(a);
      final jb = await body(b);
      expect(ja['invoiceNumber'], 'BR-POS-1');
      expect(jb['invoiceNumber'], 'BR-POS-2',
          reason: 'returned so the client can update its local number');

      // Resend B (its client number is still POS-1) and A.
      final bAgain = await body(await post('gid-terminal-B-0001', 'POS-1'));
      final aAgain = await body(await post('gid-terminal-A-0001', 'POS-1'));
      expect(bAgain['duplicate'], true);
      expect(bAgain['invoiceNumber'], 'BR-POS-2');
      expect(bAgain['serverId'], jb['serverId']);
      expect(aAgain['duplicate'], true);
      expect(aAgain['invoiceNumber'], 'BR-POS-1');

      final rows = await db.select(db.salesInvoices).get();
      expect(rows.length, 2, reason: 'no third invoice from the resends');
      expect(rows.map((r) => r.invoiceNumber).toSet(),
          {'BR-POS-1', 'BR-POS-2'});
    });

    test('a third collision continues from MAX+1', () async {
      await post('gid-A', 'POS-1');
      await post('gid-B', 'POS-1');
      final c = await body(await post('gid-C', 'POS-1'));
      expect(c['invoiceNumber'], 'BR-POS-3');
    });
  });
}
