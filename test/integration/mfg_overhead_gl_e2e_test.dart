import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:picpos_erp/data/database/database.dart';

/// E2E — S-MFG-GL (Spec 146): manufacturing overhead reaches a balanced GL,
/// and reversing an in-progress order restores stock + unwinds the WIP entry.
///
/// US1: completing an order with indirect cost posts Dr WIP / Cr 5138 so the
///      order's net WIP movement is 0 and the overhead has a credit party.
/// US2: reverseManufacturingOrder restores consumed raw at frozen cost and
///      reverses the start WIP entry (draft no-op; completed/cancelled reject).
void main() {
  late AppDatabase db;
  late int warehouseId;
  late int rawId;
  late int finishedId;

  const rawCost = 10.0; // consumed unit cost
  const rawOnHand = 100.0;

  setUp(() async {
    db = AppDatabase.forTesting();
    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;

    rawId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'MFG-RAW',
        name: 'مادة خام',
        salePrice: const Value(0.0),
        costPrice: const Value(rawCost),
        trackInventory: const Value(true),
      ),
    );
    finishedId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'MFG-FIN',
        name: 'منتج تام',
        salePrice: const Value(500.0),
        costPrice: const Value(0.0),
        trackInventory: const Value(true),
      ),
    );
    // Seed raw stock so startProduction can consume it.
    await db.adjustStock(
      productId: rawId,
      warehouseId: warehouseId,
      quantity: rawOnHand,
      type: 'opening',
      unitCost: rawCost,
    );
  });

  tearDown(() async => db.close());

  // BOM: 1 finished unit consumes 1 raw unit. Order of 10 → consumes 10 raw
  // @ 10 = 100 material cost.
  Future<int> makeOrderAndStart({double orderedQty = 10}) async {
    final bomId = await db.createBOM(
      finishedProductId: finishedId,
      bomCode: 'BOM-1',
      expectedQuantity: 1,
      components: [
        {
          'rawMaterialId': rawId,
          'quantity': 1.0,
          'unit': 'قطعة',
          'quantityInBase': 1.0,
          'wastagePercent': 0.0,
        },
      ],
    );
    final orderId = await db.createManufacturingOrder(
      bomId: bomId,
      orderedQty: orderedQty,
      warehouseId: warehouseId,
      startDate: DateTime(2026, 7, 6),
    );
    await db.startProduction(orderId);
    return orderId;
  }

  Future<int> accountIdFor(String purposeKey, String defaultCode) async {
    final code =
        await db.accountingDao.getMappedAccountCode(purposeKey, defaultCode);
    final acct = await db.accountingDao.getAccountByCode(code);
    return acct!.id;
  }

  /// Net (debit − credit) posted to [accountId] across this order's mfg entries.
  Future<double> mfgNet(int orderId, int accountId) async {
    final r = await db.customSelect(
      '''SELECT COALESCE(SUM(l.debit),0) AS d, COALESCE(SUM(l.credit),0) AS c
         FROM journal_entry_lines l
         JOIN journal_entries e ON e.id = l.entry_id
         WHERE e.reference_id = ?
           AND e.reference_type IN
             ('manufacturing_order','manufacturing_overhead',
              'manufacturing_complete','manufacturing_reverse')
           AND l.account_id = ?''',
      variables: [Variable(orderId), Variable(accountId)],
    ).getSingle();
    return (r.data['d'] as num).toDouble() - (r.data['c'] as num).toDouble();
  }

  Future<String?> gidFor(int orderId, String referenceType) async {
    final rows = await (db.select(db.journalEntries)
          ..where((e) =>
              e.referenceId.equals(orderId) &
              e.referenceType.equals(referenceType)))
        .get();
    return rows.isEmpty ? null : rows.first.globalId;
  }

  Future<String> orderStatus(int orderId) async {
    final o = await (db.select(db.manufacturingOrders)
          ..where((x) => x.id.equals(orderId)))
        .getSingle();
    return o.status;
  }

  group('US1 — overhead credit party + balanced WIP', () {
    test('a) complete with overhead → WIP nets 0 and 5138 credited', () async {
      final orderId = await makeOrderAndStart(); // consumes 100 raw
      await db.addMfgOrderCost(
        orderId: orderId,
        costType: 'labor',
        description: 'عمالة',
        amount: 40.0,
      );
      await db.completeProduction(orderId);

      final wipId = await accountIdFor('wip', '1133');
      final appliedId = await accountIdFor('applied_overhead', '5138');

      // WIP: Dr 100 (start) + Dr 40 (overhead) − Cr 140 (complete) = 0.
      expect(await mfgNet(orderId, wipId), closeTo(0.0, 0.001));
      // 5138: credited exactly the overhead (net = −40).
      expect(await mfgNet(orderId, appliedId), closeTo(-40.0, 0.001));
      expect(await orderStatus(orderId), 'completed');
    });

    test('b) zero-overhead complete → no overhead entry, WIP nets 0', () async {
      final orderId = await makeOrderAndStart();
      await db.completeProduction(orderId);

      // No manufacturing_overhead entry was posted.
      expect(await gidFor(orderId, 'manufacturing_overhead'), isNull);
      final wipId = await accountIdFor('wip', '1133');
      // Dr 100 (start) − Cr 100 (complete) = 0.
      expect(await mfgNet(orderId, wipId), closeTo(0.0, 0.001));
    });

    test('c) mfg JEs carry deterministic gids (FR-006)', () async {
      final orderId = await makeOrderAndStart();
      await db.addMfgOrderCost(
        orderId: orderId,
        costType: 'overhead',
        description: 'إهلاك',
        amount: 25.0,
      );
      await db.completeProduction(orderId);

      expect(await gidFor(orderId, 'manufacturing_overhead'),
          'je-mfg-order$orderId-overhead');
      // start ('manufacturing_order') and complete ('manufacturing_complete')
      // now carry distinct referenceTypes + distinct deterministic gids.
      expect(await gidFor(orderId, 'manufacturing_order'),
          'je-mfg-order$orderId-start');
      expect(await gidFor(orderId, 'manufacturing_complete'),
          'je-mfg-order$orderId-complete');
    });

    test('d) missing 5138 with overhead>0 → throws and rolls back', () async {
      final orderId = await makeOrderAndStart();
      await db.addMfgOrderCost(
        orderId: orderId,
        costType: 'labor',
        description: 'عمالة',
        amount: 40.0,
      );
      // Simulate an install where the applied-overhead account is absent. FK is
      // enforced in tests now — force the deletion with FK momentarily off; the
      // code under test still runs with FK ON.
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await (db.delete(db.accounts)..where((a) => a.code.equals('5138'))).go();
      await db.customStatement('PRAGMA foreign_keys = ON');

      await expectLater(
        db.completeProduction(orderId),
        throwsA(isA<Exception>()),
      );
      // Rolled back: order still in_progress, no finished-goods movement.
      expect(await orderStatus(orderId), 'in_progress');
      final inMovements = await db.customSelect(
        '''SELECT COUNT(*) AS n FROM stock_movements
           WHERE reference_type='manufacturing_order' AND reference_id=?
             AND movement_type='manufacturing_in' ''',
        variables: [Variable(orderId)],
      ).getSingle();
      expect((inMovements.data['n'] as num).toInt(), 0);
    });
  });

  group('US2 — reverse restores stock + unwinds WIP', () {
    test('a) reverse draft → cancelled, no stock/GL', () async {
      final bomId = await db.createBOM(
        finishedProductId: finishedId,
        bomCode: 'BOM-D',
        expectedQuantity: 1,
        components: [
          {
            'rawMaterialId': rawId,
            'quantity': 1.0,
            'unit': 'قطعة',
            'quantityInBase': 1.0,
            'wastagePercent': 0.0,
          },
        ],
      );
      final orderId = await db.createManufacturingOrder(
        bomId: bomId,
        orderedQty: 10,
        warehouseId: warehouseId,
        startDate: DateTime(2026, 7, 6),
      );

      await db.reverseManufacturingOrder(orderId);

      expect(await orderStatus(orderId), 'cancelled');
      // Raw untouched (nothing consumed for a draft).
      final raw = await db.getProductById(rawId);
      expect(raw!.currentStock, closeTo(rawOnHand, 0.001));
      // No mfg JE at all.
      expect(await gidFor(orderId, 'manufacturing_reverse'), isNull);
      expect(await gidFor(orderId, 'manufacturing_order'), isNull);
    });

    test('b) reverse in_progress → raw restored + WIP nets 0', () async {
      final orderId = await makeOrderAndStart(); // consumes 10 raw units
      final afterStart = await db.getProductById(rawId);
      expect(afterStart!.currentStock, closeTo(rawOnHand - 10, 0.001));

      await db.reverseManufacturingOrder(orderId);

      // Raw restored to pre-start level.
      final afterReverse = await db.getProductById(rawId);
      expect(afterReverse!.currentStock, closeTo(rawOnHand, 0.001));
      // WIP: Dr 100 (start) − Cr 100 (reverse) = 0.
      final wipId = await accountIdFor('wip', '1133');
      expect(await mfgNet(orderId, wipId), closeTo(0.0, 0.001));
      // Raw account: Cr 100 (start) + Dr 100 (reverse) = 0.
      final rawAcctId = await accountIdFor('raw_materials', '1131');
      expect(await mfgNet(orderId, rawAcctId), closeTo(0.0, 0.001));
      expect(await gidFor(orderId, 'manufacturing_reverse'),
          'je-mfg-order$orderId-revstart');
      expect(await orderStatus(orderId), 'cancelled');
    });

    test('c) reverse completed → rejected, no side effects', () async {
      final orderId = await makeOrderAndStart();
      await db.completeProduction(orderId);

      await expectLater(
        db.reverseManufacturingOrder(orderId),
        throwsA(isA<Exception>()),
      );
      expect(await orderStatus(orderId), 'completed');
    });

    test('d) reverse already-cancelled → rejected (retry safety)', () async {
      final orderId = await makeOrderAndStart();
      await db.reverseManufacturingOrder(orderId); // in_progress → cancelled
      expect(await orderStatus(orderId), 'cancelled');

      await expectLater(
        db.reverseManufacturingOrder(orderId),
        throwsA(isA<Exception>()),
      );
    });
  });
}
