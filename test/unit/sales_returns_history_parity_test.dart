// ═══════════════════════════════════════════════════════════════════════════
// سجل مرتجع المبيعات — parity with سجل مرتجع المشتريات
//
// Bug (client report 2026-07-26): the "سجل المرتجعات" dialog on the sales
// returns screen lists nothing, while the same dialog on the purchase returns
// screen lists every return.
//
// Root cause: a sales return is persisted in TWO mutually exclusive shapes
// (documented on `getReturnedAmountsForInvoices` in sales_dao.dart):
//
//   A. STANDALONE / server-local path (`processSalesReturn`, the shape the
//      sales-returns SCREEN itself produces): flips the ORIGINAL invoice to
//      status 'returned' / 'partial_return' and writes
//      safe_transactions(reference_type='sales_return', reference_id=<original>).
//      It creates NO `sale_type='return'` invoice row.
//
//   B. Server-API / client-mirror / POS path: writes a separate
//      `sale_type='return'` invoice row linked to its original via
//      `notes = 'Return for invoice #<id>[|gid:<uuid>]'`.
//
// `getSalesReturns` only matches shape B (`sale_type='return' OR total < 0`),
// so on a standalone/server install the history dialog is ALWAYS empty.
// `getPurchaseReturnHistory` matches the ORIGINAL invoice's status — which is
// why the purchases dialog works. This test pins the sales side to the same
// behaviour, with dedup so a shape-B return doesn't list twice (once as the
// return doc, once as its flipped original).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int wId;
  late int uId;
  late int safeId;
  final from = DateTime(2026, 1, 1);
  final to = DateTime(2026, 12, 31);
  final day = DateTime(2026, 6, 1);

  setUp(() async {
    db = AppDatabase.forTesting();
    wId = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'W1'));
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'مدير', isSystemRole: const Value(true)),
        );
    uId = await db.createUser(
      username: 'user1',
      password: 'pass123',
      displayName: 'U1',
      roleId: roleId,
    );
    safeId = await db.into(db.safes).insert(
          SafesCompanion.insert(name: 'الخزنة', balance: const Value(10000)),
        );
  });

  tearDown(() => db.close());

  Future<int> seedInvoice({
    required String number,
    required double total,
    String saleType = 'default',
    String status = 'completed',
    String? notes,
    String? globalId,
  }) =>
      db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: number,
              warehouseId: wId,
              userId: uId,
              invoiceDate: day,
              subtotal: Value(total),
              total: Value(total),
              saleType: Value(saleType),
              status: Value(status),
              notes: Value(notes),
              globalId: Value(globalId),
            ),
          );

  /// The shape-A footprint: the refund row the standalone return flow writes.
  Future<void> seedStandaloneRefund(int originalId, double amount) =>
      db.into(db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: 'SRET-$originalId',
              safeId: safeId,
              transactionType: 'payment',
              category: 'sales_return',
              amount: amount,
              balanceAfter: 0,
              referenceType: const Value('sales_return'),
              referenceId: Value(originalId),
              userId: Value(uId),
            ),
          );

  test('shape A (standalone) — flipped original appears in the history',
      () async {
    final orig = await seedInvoice(
      number: 'INV-1',
      total: 570,
      status: 'partial_return',
    );
    await seedStandaloneRefund(orig, 120);

    final rows = await db.getSalesReturnHistoryEntries(from, to);

    expect(rows, hasLength(1));
    expect(rows.single.originalInvoiceId, orig);
    expect(rows.single.invoice.invoiceNumber, 'INV-1');
    // The ACTUAL refund, not the original invoice's 570.
    expect(rows.single.returnAmount, closeTo(120, 0.001));
    expect(rows.single.isReturnDocument, isFalse);
    expect(rows.single.isFullReturn, isFalse);
  });

  test('shape B (server/mirror/POS) — the return document appears once',
      () async {
    final orig = await seedInvoice(
      number: 'INV-2',
      total: 800,
      status: 'returned',
      globalId: 'gid-orig-2',
    );
    await seedInvoice(
      number: 'SRET-2',
      total: 300,
      saleType: 'return',
      notes: localReturnLinkNote(orig, originalGlobalId: 'gid-orig-2'),
    );

    final rows = await db.getSalesReturnHistoryEntries(from, to);

    // Exactly one entry: the return document. Its flipped original must NOT
    // be listed a second time.
    expect(rows, hasLength(1));
    expect(rows.single.isReturnDocument, isTrue);
    expect(rows.single.invoice.invoiceNumber, 'SRET-2');
    expect(rows.single.originalInvoiceId, orig);
    expect(rows.single.originalInvoiceNumber, 'INV-2');
    expect(rows.single.returnAmount, closeTo(300, 0.001));
  });

  test('legacy negative-total return document still appears', () async {
    await seedInvoice(number: 'RET-LEGACY', total: -250, saleType: 'default');

    final rows = await db.getSalesReturnHistoryEntries(from, to);

    expect(rows, hasLength(1));
    expect(rows.single.isReturnDocument, isTrue);
    expect(rows.single.returnAmount, closeTo(250, 0.001));
  });

  test('plain completed sales and deleted rows are excluded', () async {
    await seedInvoice(number: 'INV-OK', total: 400);
    final del = await seedInvoice(
      number: 'INV-DEL',
      total: 400,
      status: 'returned',
    );
    await (db.update(db.salesInvoices)..where((s) => s.id.equals(del)))
        .write(const SalesInvoicesCompanion(isDeleted: Value(true)));

    final rows = await db.getSalesReturnHistoryEntries(from, to);

    expect(rows, isEmpty);
  });

  test('branch scope cap is honoured', () async {
    final b1 = await db
        .into(db.branches)
        .insert(BranchesCompanion.insert(name: 'B1', code: const Value('B1')));
    final b2 = await db
        .into(db.branches)
        .insert(BranchesCompanion.insert(name: 'B2', code: const Value('B2')));

    final i1 = await seedInvoice(
      number: 'INV-B1',
      total: 100,
      status: 'returned',
    );
    final i2 = await seedInvoice(
      number: 'INV-B2',
      total: 100,
      status: 'returned',
    );
    await (db.update(db.salesInvoices)..where((s) => s.id.equals(i1)))
        .write(SalesInvoicesCompanion(branchId: Value(b1)));
    await (db.update(db.salesInvoices)..where((s) => s.id.equals(i2)))
        .write(SalesInvoicesCompanion(branchId: Value(b2)));

    final scoped = await db.getSalesReturnHistoryEntries(
      from,
      to,
      allowedBranchIds: {b1},
    );
    expect(scoped.map((e) => e.invoice.invoiceNumber), ['INV-B1']);

    final unscoped = await db.getSalesReturnHistoryEntries(from, to);
    expect(unscoped, hasLength(2));

    final failClosed = await db.getSalesReturnHistoryEntries(
      from,
      to,
      allowedBranchIds: const <int>{},
    );
    expect(failClosed, isEmpty);
  });
}
