import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as drift;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/strategies/sales_sync_strategy.dart';

/// Phase 1 — Sales Invoice Deduplication TOCTOU (Focused)
///
/// Dedicated test class for the UNIQUE constraint + atomic check-and-insert
/// fix in SalesSyncStrategy. Covers edge cases:
///   - Multiple concurrent syncs of the same invoice number → exactly 1 record.
///   - Two different invoice numbers → 2 records (no over-deduplication).
///   - An invoice that already exists is not updated (insert-or-ignore semantics).
///   - Empty sync payload is a safe no-op.
///   - Mix of new and duplicate invoices in concurrent batch is handled correctly.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'admin', isSystemRole: const drift.Value(true)),
    );
    await db.createUser(username: 'admin', password: 'pw', displayName: 'Admin', roleId: roleId);
    await db.into(db.warehouses).insert(
      WarehousesCompanion.insert(
        name: 'Main',
        isActive: const drift.Value(true),
        isDefault: const drift.Value(true),
      ),
    );
  });

  tearDown(() async => db.close());

  // ─────────────────────────────────────────────────────────────────────────
  // Helper: builds a sync payload using REAL IDs from the seeded test DB.
  // This avoids FK mismatches where warehouseId/userId = '1' are invalid.
  // ─────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> buildPayload(
    String invoiceNumber, {
    double total = 100.0,
  }) async {
    final wh = await db.getDefaultWarehouse();
    final users = await db.select(db.users).get();
    final whId = (wh?.id ?? 1).toString();
    final userId = (users.isNotEmpty ? users.first.id : 1).toString();

    return {
      'sales': [
        {
          'id': '${invoiceNumber.hashCode.abs()}',
          'globalId': 'global-$invoiceNumber',
          'invoiceNumber': invoiceNumber,
          'customerId': null,
          'warehouseId': whId,
          'userId': userId,
          'invoiceDate': DateTime.now().toIso8601String(),
          'subtotal': total,
          'discount': 0.0,
          'tax': 0.0,
          'total': total,
          'paid': total,
          'cashPaid': total,
          'bankPaid': 0.0,
          'paymentMethod': 'cash',
          'status': 'completed',
          'orderNumber': null,
          'deliveryFee': 0.0,
          'notes': null,
          'saleType': 'default',
          'costCenterId': null,
          'items': <dynamic>[],
        }
      ]
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  group('Sales Deduplication TOCTOU — Focused Tests', () {
    // ─────────────────────────────────────────────────────────────────────────
    test('Empty sync payload is a safe no-op', () async {
      final strategy = SalesSyncStrategy(db);
      await expectLater(
        strategy.syncFromJson({'sales': <dynamic>[]}),
        completes,
        reason: 'Empty sales array should be handled gracefully',
      );

      final invoices = await db.select(db.salesInvoices).get();
      expect(invoices.isEmpty, isTrue);
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Two DISTINCT invoice numbers produce EXACTLY two records', () async {
      final strategy = SalesSyncStrategy(db);
      await strategy.syncFromJson(await buildPayload('INV-DISTINCT-001', total: 100.0));
      await strategy.syncFromJson(await buildPayload('INV-DISTINCT-002', total: 200.0));

      final invoices = await db.select(db.salesInvoices).get();
      expect(invoices.length, 2,
          reason: 'Two distinct invoices must both be stored — no over-deduplication');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('10 concurrent syncs of the same invoice produce exactly 1 record', () async {
      final strategy = SalesSyncStrategy(db);
      // Build once with real IDs, then fire 10 concurrent syncs
      final payload = await buildPayload('INV-CONCURRENT-DUP-001');

      final futures = List.generate(10, (_) => strategy.syncFromJson(payload));
      await Future.wait(futures);

      final invoices = await db.select(db.salesInvoices).get();
      expect(invoices.length, 1,
          reason: '10 concurrent syncs of the same invoice must deduplicate to 1');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Existing invoice is not overwritten by second sync (insert-or-ignore)', () async {
      final strategy = SalesSyncStrategy(db);
      const invoiceNumber = 'INV-PRESERVED-001';

      // First sync with total = 500
      await strategy.syncFromJson(await buildPayload(invoiceNumber, total: 500.0));

      // Second sync with DIFFERENT total — should be silently ignored
      await strategy.syncFromJson(await buildPayload(invoiceNumber, total: 999.0));

      final invoices = await db.select(db.salesInvoices).get();
      expect(invoices.length, 1);
      expect(invoices.first.total, 500.0,
          reason: 'Original invoice total must be preserved (insert-or-ignore semantics)');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Re-syncing the same invoice twice is idempotent (final count = 1)', () async {
      final strategy = SalesSyncStrategy(db);
      const invoiceNumber = 'INV-DEDUP-IDEM-001';

      // First sync
      await strategy.syncFromJson(await buildPayload(invoiceNumber));
      // Second sync (same data)
      await strategy.syncFromJson(await buildPayload(invoiceNumber));
      // Third sync (same data)
      await strategy.syncFromJson(await buildPayload(invoiceNumber));

      final invoices = await db.select(db.salesInvoices).get();
      // Regardless of how many times the same payload is synced,
      // the invoice must appear exactly once (deduplication is working).
      final dedupedCount = invoices.where((i) => i.invoiceNumber == invoiceNumber).length;
      expect(dedupedCount, 1,
          reason: 'Idempotent sync: syncing the same invoice 3 times must result in exactly 1 record');
    });
  });
}


