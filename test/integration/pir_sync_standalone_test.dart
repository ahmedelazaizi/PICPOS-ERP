/// PIR Integration Test: Sync & Standalone Mode Verification
///
/// Tests that:
/// 1. Sync outbox correctly queues, processes, and handles failures
/// 2. Sync strategies correctly map JSON → DB records
/// 3. Standalone mode: all core operations (sale, purchase, accounting, stock) work without network
/// 4. Idempotency keys prevent duplicate processing
/// 5. Dead letter handling after max retries
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/strategies/category_sync_strategy.dart';
import 'package:ural_erp/services/sync/strategies/product_sync_strategy.dart';
import 'package:ural_erp/services/sync/strategies/party_sync_strategy.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;
  late int roleId;

  setUp(() async {
    db = AppDatabase.forTesting();
    roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'Admin', isSystemRole: const Value(true)),
    );
    userId = await db.createUser(
      username: 'admin',
      password: 'admin123',
      displayName: 'Admin',
      roleId: roleId,
    );
    warehouseId = await db.into(db.warehouses).insert(
      WarehousesCompanion.insert(name: 'Main Warehouse'),
    );
  });

  tearDown(() async {
    await db.close();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 1: Sync Outbox Operations
  // ═══════════════════════════════════════════════════════════════════════════

  group('Sync Outbox — Queue & Lifecycle', () {
    test('addToSyncOutbox creates pending entry', () async {
      final id = await db.addToSyncOutbox(
        tableName: 'products',
        recordId: '42',
        operation: 'insert',
        payload: {'name': 'Test Product', 'code': 'TST-001'},
        idempotencyKey: 'idem-key-001',
      );

      expect(id, greaterThan(0));

      final items = await db.getPendingSyncItems();
      expect(items.length, 1);
      expect(items.first.targetTable, 'products');
      expect(items.first.recordId, '42');
      expect(items.first.operation, 'insert');
      expect(items.first.status, 'pending');
      expect(items.first.idempotencyKey, 'idem-key-001');

      final payload = jsonDecode(items.first.payload) as Map<String, dynamic>;
      expect(payload['name'], 'Test Product');
    });

    test('markAsSyncSuccess changes status to synced', () async {
      final id = await db.addToSyncOutbox(
        tableName: 'categories',
        recordId: '1',
        operation: 'insert',
        payload: {'name': 'Electronics'},
      );

      await db.markAsSyncSuccess(id, remoteId: 'server-uuid-123');

      final all = await db.getAllSyncItems();
      final item = all.firstWhere((i) => i.id == id);
      expect(item.status, 'synced');
      expect(item.remoteId, 'server-uuid-123');
    });

    test('markAsSyncFailed increments attempts and keeps pending', () async {
      final id = await db.addToSyncOutbox(
        tableName: 'sales',
        recordId: '10',
        operation: 'insert',
        payload: {'total': 100.0},
      );

      await db.markAsSyncFailed(id, 'Connection refused');
      var items = await db.getAllSyncItems();
      var item = items.firstWhere((i) => i.id == id);
      expect(item.status, 'pending');
      expect(item.attempts, 1);
      expect(item.lastError, 'Connection refused');

      await db.markAsSyncFailed(id, 'Timeout');
      items = await db.getAllSyncItems();
      item = items.firstWhere((i) => i.id == id);
      expect(item.attempts, 2);
      expect(item.lastError, 'Timeout');
    });

    test('markAsSyncDeadLetter permanently excludes from retry', () async {
      final id = await db.addToSyncOutbox(
        tableName: 'journals',
        recordId: '5',
        operation: 'insert',
        payload: {'amount': 500.0},
      );

      await db.markAsSyncDeadLetter(id, 'Server rejected: duplicate globalId');

      final items = await db.getAllSyncItems();
      final item = items.firstWhere((i) => i.id == id);
      expect(item.status, 'dead_letter');
      expect(item.lastError, contains('DEAD_LETTER'));

      // resetFailedSyncItems should NOT touch dead_letter items
      final resetCount = await db.resetFailedSyncItems();
      expect(resetCount, 0);

      final afterReset = await db.getAllSyncItems();
      final stillDead = afterReset.firstWhere((i) => i.id == id);
      expect(stillDead.status, 'dead_letter');
    });

    test('resetFailedSyncItems resets only failed, not dead_letter', () async {
      // Create a failed item
      final failedId = await db.addToSyncOutbox(
        tableName: 'products',
        recordId: '1',
        operation: 'update',
        payload: {'name': 'Updated'},
      );
      await db.markAsSyncError(failedId, 'Server error 500');

      // Create a dead_letter item
      final deadId = await db.addToSyncOutbox(
        tableName: 'products',
        recordId: '2',
        operation: 'insert',
        payload: {'name': 'Duplicate'},
      );
      await db.markAsSyncDeadLetter(deadId, 'Duplicate key');

      final resetCount = await db.resetFailedSyncItems();
      expect(resetCount, 1);

      final items = await db.getAllSyncItems();
      final failedItem = items.firstWhere((i) => i.id == failedId);
      final deadItem = items.firstWhere((i) => i.id == deadId);

      expect(failedItem.status, 'pending');
      expect(failedItem.attempts, 0);
      expect(deadItem.status, 'dead_letter');
    });

    test('getPendingSyncItems respects limit parameter', () async {
      for (int i = 0; i < 10; i++) {
        await db.addToSyncOutbox(
          tableName: 'products',
          recordId: '$i',
          operation: 'insert',
          payload: {'name': 'Product $i'},
        );
      }

      final limited = await db.getPendingSyncItems(limit: 3);
      expect(limited.length, 3);

      final all = await db.getPendingSyncItems(limit: 50);
      expect(all.length, 10);
    });

    test('watchSyncPendingCount emits accurate count', () async {
      // Initial count should be 0
      final stream = db.watchSyncPendingCount();

      await db.addToSyncOutbox(
        tableName: 'products',
        recordId: '1',
        operation: 'insert',
        payload: {'name': 'P1'},
      );
      final id2 = await db.addToSyncOutbox(
        tableName: 'products',
        recordId: '2',
        operation: 'insert',
        payload: {'name': 'P2'},
      );

      // After marking one as synced, pending count should decrease
      await db.markAsSyncSuccess(id2);

      final count = await stream.first;
      expect(count, 1); // Only one pending
    });

    test('dead letter count tracking', () async {
      final id1 = await db.addToSyncOutbox(
        tableName: 'sales',
        recordId: '1',
        operation: 'insert',
        payload: {},
      );
      final id2 = await db.addToSyncOutbox(
        tableName: 'sales',
        recordId: '2',
        operation: 'insert',
        payload: {},
      );

      await db.markAsSyncDeadLetter(id1, 'Bad data');
      await db.markAsSyncDeadLetter(id2, 'Duplicate');

      final deadCount = await db.getDeadLetterCount();
      expect(deadCount, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 2: Sync Strategy — JSON → DB Mapping
  // ═══════════════════════════════════════════════════════════════════════════

  group('Sync Strategy — Category JSON Mapping', () {
    test('syncFromJson inserts categories from server payload', () async {
      final strategy = CategorySyncStrategy(db);

      await strategy.syncFromJson({
        'categories': [
          {
            'id': 100,
            'name': 'Electronics',
            'color': '#FF0000',
            'sortOrder': 1,
            'isActive': true,
            'isGlobal': true,
            'isLocked': false,
            'isExcluded': false,
            'showInPos': true,
          },
          {
            'id': 101,
            'name': 'Food',
            'color': '#00FF00',
            'sortOrder': 2,
            'isActive': true,
            'isGlobal': true,
            'isLocked': false,
            'isExcluded': false,
            'showInPos': true,
          },
        ],
      });

      final cats = await db.select(db.categories).get();
      // Note: beforeOpen seeds some default categories, so filter by our IDs
      final synced = cats.where((c) => c.id == 100 || c.id == 101).toList();
      expect(synced.length, 2);
      expect(synced.firstWhere((c) => c.id == 100).name, 'Electronics');
      expect(synced.firstWhere((c) => c.id == 101).name, 'Food');
    });

    test('syncFromJson updates existing categories (upsert)', () async {
      final strategy = CategorySyncStrategy(db);

      // First sync
      await strategy.syncFromJson({
        'categories': [
          {'id': 200, 'name': 'Old Name', 'color': '#000', 'sortOrder': 0, 'isActive': true, 'isGlobal': true, 'isLocked': false, 'isExcluded': false, 'showInPos': true},
        ],
      });

      // Second sync with updated data
      await strategy.syncFromJson({
        'categories': [
          {'id': 200, 'name': 'New Name', 'color': '#FFF', 'sortOrder': 5, 'isActive': true, 'isGlobal': true, 'isLocked': false, 'isExcluded': false, 'showInPos': true},
        ],
      });

      final cat = await (db.select(db.categories)..where((c) => c.id.equals(200))).getSingleOrNull();
      expect(cat, isNotNull);
      expect(cat!.name, 'New Name');
      expect(cat.color, '#FFF');
      expect(cat.sortOrder, 5);
    });
  });

  group('Sync Strategy — Party JSON Mapping', () {
    test('syncFromJson inserts parties from server', () async {
      final strategy = PartySyncStrategy(db);

      await strategy.syncFromJson({
        'parties': [
          {
            'id': 300,
            'name': 'Customer A',
            'isCustomer': true,
            'isSupplier': false,
            'phone': '01234567890',
            'balance': 0.0,
            'isActive': true,
          },
        ],
      });

      final party = await (db.select(db.parties)..where((p) => p.id.equals(300))).getSingleOrNull();
      expect(party, isNotNull);
      expect(party!.name, 'Customer A');
      expect(party.isCustomer, true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 3: Standalone Mode — Full Operation Without Network
  // ═══════════════════════════════════════════════════════════════════════════

  group('Standalone Mode — Core Operations', () {
    test('Products CRUD works without network', () async {
      // Insert
      final productId = await db.insertProduct(
        ProductsCompanion.insert(
          name: 'Standalone Product',
          code: 'STND-001',
          salePrice: const Value(50.0),
          costPrice: const Value(30.0),
          barcode: const Value('9999999999'),
        ),
      );
      expect(productId, greaterThan(0));

      // Read
      final product = await db.getProductById(productId);
      expect(product, isNotNull);
      expect(product!.name, 'Standalone Product');
      expect(product.salePrice, 50.0);

      // Update — invalidate cache first
      db.invalidateProductCache(productId);
      await (db.update(db.products)..where((p) => p.id.equals(productId))).write(
        const ProductsCompanion(salePrice: Value(55.0)),
      );
      db.invalidateProductCache(productId);
      final updated = await db.getProductById(productId);
      expect(updated!.salePrice, 55.0);
    });

    test('Sales invoice creation works offline', () async {
      // Create a product first
      final productId = await db.insertProduct(
        ProductsCompanion.insert(
          name: 'Offline Sale Item',
          code: 'OFF-001',
          salePrice: const Value(100.0),
          costPrice: const Value(60.0),
          currentStock: const Value(50.0),
        ),
      );

      // Seed warehouse-level stock (required by inventory guard)
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 50.0,
        type: 'adjustment',
      );

      // Create sales invoice
      final invoiceId = await db.createSalesInvoice(
        invoiceNumber: 'STND-INV-001',
        total: 100.0,
        subtotal: 100.0,
        discount: 0.0,
        tax: 0.0,
        paid: 100.0,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 2.0,
            unitPrice: 50.0,
            total: 100.0,
          ),
        ],
        warehouseId: warehouseId,
        userId: userId,
      );

      expect(invoiceId, greaterThan(0));

      // Verify invoice was created
      final invoice = await (db.select(db.salesInvoices)
            ..where((si) => si.id.equals(invoiceId)))
          .getSingleOrNull();
      expect(invoice, isNotNull);
      expect(invoice!.total, 100.0);
      expect(invoice.invoiceNumber, 'STND-INV-001');
    });

    test('Stock movements work without network', () async {
      final productId = await db.insertProduct(
        ProductsCompanion.insert(
          name: 'Stock Test',
          code: 'STK-001',
          salePrice: const Value(10.0),
          costPrice: const Value(5.0),
          currentStock: const Value(100.0),
        ),
      );

      // Record stock adjustment
      await db.into(db.stockMovements).insert(
        StockMovementsCompanion.insert(
          productId: productId,
          warehouseId: warehouseId,
          quantity: -10.0,
          movementType: 'adjustment',
          balanceAfter: 90.0,
          userId: Value(userId),
        ),
      );

      final movements = await (db.select(db.stockMovements)
            ..where((sm) => sm.productId.equals(productId)))
          .get();
      // At least one stock movement from the insert + our adjustment
      expect(movements.isNotEmpty, true);

      final adjustment = movements.where((m) => m.movementType == 'adjustment').toList();
      expect(adjustment.length, greaterThanOrEqualTo(1));
      expect(adjustment.last.quantity, -10.0);
    });

    test('Journal entries work without network (double-entry)', () async {
      // Create accounts first
      final cashAccountId = await db.into(db.accounts).insert(
        AccountsCompanion.insert(
          code: '1001',
          name: 'Cash Standalone',
          accountType: 'asset',
        ),
      );
      final revenueAccountId = await db.into(db.accounts).insert(
        AccountsCompanion.insert(
          code: '4001',
          name: 'Revenue Standalone',
          accountType: 'revenue',
        ),
      );

      // Create journal entry
      final jeId = await db.into(db.journalEntries).insert(
        JournalEntriesCompanion.insert(
          entryNumber: 'JE-STND-001',
          entryDate: DateTime.now(),
          description: const Value('Standalone sale'),
          isPosted: const Value(true),
        ),
      );

      // Add lines (debit cash, credit revenue)
      await db.into(db.journalEntryLines).insert(
        JournalEntryLinesCompanion.insert(
          entryId: jeId,
          accountId: cashAccountId,
          debit: const Value(100.0),
          credit: const Value(0.0),
        ),
      );
      await db.into(db.journalEntryLines).insert(
        JournalEntryLinesCompanion.insert(
          entryId: jeId,
          accountId: revenueAccountId,
          debit: const Value(0.0),
          credit: const Value(100.0),
        ),
      );

      // Verify trial balance sums to zero
      final trialBalance = await db.customSelect(
        'SELECT SUM(debit) as total_debit, SUM(credit) as total_credit FROM journal_entry_lines WHERE entry_id = ?',
        variables: [Variable<int>(jeId)],
      ).getSingleOrNull();

      expect(trialBalance, isNotNull);
      final totalDebit = trialBalance!.read<double>('total_debit');
      final totalCredit = trialBalance.read<double>('total_credit');
      expect(totalDebit, totalCredit);
      expect(totalDebit, 100.0);
    });

    test('Category and product search work offline', () async {
      // Create category
      final catId = await db.into(db.categories).insert(
        CategoriesCompanion.insert(
          name: 'Offline Cat',
          color: const Value('#123456'),
        ),
      );

      // Create products
      await db.insertProduct(
        ProductsCompanion.insert(
          name: 'Pepsi Cola',
          code: 'PEP-001',
          categoryId: Value(catId),
          salePrice: const Value(5.0),
          barcode: const Value('6281234567890'),
        ),
      );

      // Search by barcode (direct SQL, same as POS barcode scan path)
      final barcodeResults = await db.customSelect(
        'SELECT * FROM products WHERE barcode = ?',
        variables: [const Variable<String>('6281234567890')],
      ).get();
      expect(barcodeResults.isNotEmpty, true);

      // Get all categories
      final cats = await db.getAllCategories();
      expect(cats.isNotEmpty, true);
      expect(cats.any((c) => c.name == 'Offline Cat'), true);
    });

    test('User authentication works without network', () async {
      // authenticateByPasswordOrCard should work on local DB
      final result = await db.authenticateByPasswordOrCard('admin123');
      expect(result, isNotNull);
      expect(result!.user.username, 'admin');
    });

    test('Shift open/close works offline', () async {
      // Open shift
      final shiftId = await db.openShift(userId, 0.0);
      expect(shiftId, greaterThan(0));

      // Close shift (positional: shiftId, actualCash)
      await db.closeShiftWithAudit(shiftId, 0.0);

      // Verify shift is closed
      final closedShift = await (db.select(db.shifts)
            ..where((s) => s.id.equals(shiftId)))
          .getSingleOrNull();
      expect(closedShift, isNotNull);
      expect(closedShift!.endTime, isNotNull);
    });

    test('Purchase invoice works without network', () async {
      // Create supplier party
      final supplierId = await db.into(db.parties).insert(
        PartiesCompanion.insert(
          name: 'Offline Supplier',
          isSupplier: const Value(true),
          isCustomer: const Value(false),
        ),
      );

      // Create product
      final productId = await db.insertProduct(
        ProductsCompanion.insert(
          name: 'Purchase Item',
          code: 'PUR-001',
          costPrice: const Value(20.0),
        ),
      );

      // Create purchase invoice
      final purchaseId = await db.createPurchaseInvoice(
        supplierId: supplierId,
        paid: 200.0,
        paymentMethod: 'cash',
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 10.0,
            unitCost: 20.0,
            total: 200.0,
          ),
        ],
        warehouseId: warehouseId,
      );

      expect(purchaseId, greaterThan(0));

      final pi = await (db.select(db.purchaseInvoices)
            ..where((p) => p.id.equals(purchaseId)))
          .getSingleOrNull();
      expect(pi, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 4: Idempotency Key — Exactly-Once Processing
  // ═══════════════════════════════════════════════════════════════════════════

  group('Idempotency Key — Exactly-Once Semantics', () {
    test('Processed message prevents duplicate processing', () async {
      const key = 'idem-unique-001';
      const response = '{"success": true, "id": 42}';

      // Store processed message
      await db.into(db.processedMessages).insert(
        ProcessedMessagesCompanion.insert(
          idempotencyKey: key,
          responsePayload: response,
          actionType: const Value('postSale'),
        ),
      );

      // Try to find it
      final existing = await (db.select(db.processedMessages)
            ..where((pm) => pm.idempotencyKey.equals(key)))
          .getSingleOrNull();

      expect(existing, isNotNull);
      expect(existing!.responsePayload, response);
      expect(existing.actionType, 'postSale');
    });

    test('Different idempotency keys are independent', () async {
      await db.into(db.processedMessages).insert(
        ProcessedMessagesCompanion.insert(
          idempotencyKey: 'key-A',
          responsePayload: '{"id": 1}',
        ),
      );
      await db.into(db.processedMessages).insert(
        ProcessedMessagesCompanion.insert(
          idempotencyKey: 'key-B',
          responsePayload: '{"id": 2}',
        ),
      );

      final a = await (db.select(db.processedMessages)
            ..where((pm) => pm.idempotencyKey.equals('key-A')))
          .getSingleOrNull();
      final b = await (db.select(db.processedMessages)
            ..where((pm) => pm.idempotencyKey.equals('key-B')))
          .getSingleOrNull();

      expect(a!.responsePayload, '{"id": 1}');
      expect(b!.responsePayload, '{"id": 2}');
    });

    test('Duplicate idempotency key insert fails (PK constraint)', () async {
      await db.into(db.processedMessages).insert(
        ProcessedMessagesCompanion.insert(
          idempotencyKey: 'dupe-key',
          responsePayload: '{"id": 1}',
        ),
      );

      // Second insert with same key should fail
      expect(
        () => db.into(db.processedMessages).insert(
          ProcessedMessagesCompanion.insert(
            idempotencyKey: 'dupe-key',
            responsePayload: '{"id": 2}',
          ),
        ),
        throwsA(anything),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 5: Conflict Log — Audit Trail
  // ═══════════════════════════════════════════════════════════════════════════

  group('Sync Conflict Log — Audit Trail', () {
    test('Conflict log records resolution details', () async {
      await db.into(db.syncConflictLog).insert(
        SyncConflictLogCompanion.insert(
          conflictTable: 'products',
          recordId: '42',
          resolution: 'server_wins',
          clientPayload: '{"name": "Client Version", "price": 10.0}',
          serverPayload: const Value('{"name": "Server Version", "price": 12.0}'),
          reason: const Value('Server data is more recent'),
          clientId: const Value('branch-01'),
        ),
      );

      final logs = await db.select(db.syncConflictLog).get();
      expect(logs.length, 1);
      expect(logs.first.conflictTable, 'products');
      expect(logs.first.resolution, 'server_wins');
      expect(logs.first.clientId, 'branch-01');

      final clientData = jsonDecode(logs.first.clientPayload) as Map<String, dynamic>;
      expect(clientData['name'], 'Client Version');
    });

    test('Multiple conflicts for same record create separate entries', () async {
      for (int i = 0; i < 3; i++) {
        await db.into(db.syncConflictLog).insert(
          SyncConflictLogCompanion.insert(
            conflictTable: 'parties',
            recordId: '10',
            resolution: i == 2 ? 'client_wins' : 'server_wins',
            clientPayload: '{"attempt": $i}',
          ),
        );
      }

      final logs = await (db.select(db.syncConflictLog)
            ..where((l) => l.recordId.equals('10')))
          .get();
      expect(logs.length, 3);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP 6: Outbox Ordering & FIFO
  // ═══════════════════════════════════════════════════════════════════════════

  group('Sync Outbox — FIFO Ordering', () {
    test('getPendingSyncItems returns items in FIFO order', () async {
      // Insert items in sequence
      await db.addToSyncOutbox(
        tableName: 'categories',
        recordId: 'first',
        operation: 'insert',
        payload: {'order': 1},
      );
      // Small delay to ensure different timestamps
      await Future.delayed(const Duration(milliseconds: 10));
      await db.addToSyncOutbox(
        tableName: 'products',
        recordId: 'second',
        operation: 'insert',
        payload: {'order': 2},
      );
      await Future.delayed(const Duration(milliseconds: 10));
      await db.addToSyncOutbox(
        tableName: 'sales',
        recordId: 'third',
        operation: 'insert',
        payload: {'order': 3},
      );

      final items = await db.getPendingSyncItems();
      expect(items.length, 3);
      expect(items[0].recordId, 'first');
      expect(items[1].recordId, 'second');
      expect(items[2].recordId, 'third');
    });
  });
}
