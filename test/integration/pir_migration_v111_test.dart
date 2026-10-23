import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

/// PIR Integration Test 4: Database Schema & Migration Readiness
/// Verifies schema version and that the database is functional.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() async => db.close());

  group('PIR v111: Schema & Migration', () {
    test('Schema version is at least 111', () {
      expect(db.schemaVersion, greaterThanOrEqualTo(111));
    });

    test('Database creates successfully with all tables', () async {
      // Verify core tables exist and are queryable
      final users = await db.select(db.users).get();
      expect(users, isNotNull);
    });

    test('Journal entries table is queryable', () async {
      final entries = await db.select(db.journalEntries).get();
      expect(entries, isNotNull);
    });

    test('SafeTransactions table is queryable', () async {
      final txns = await db.select(db.safeTransactions).get();
      expect(txns, isNotNull);
    });

    test('PurchaseInvoices table is queryable', () async {
      final invoices = await db.select(db.purchaseInvoices).get();
      expect(invoices, isNotNull);
    });

    test('AllSchemaEntities includes all required tables', () {
      // Verify critical tables are in schema
      final entityNames = db.allSchemaEntities.map((e) => e.entityName).toSet();
      expect(entityNames, contains('sales_invoices'));
      expect(entityNames, contains('purchase_invoices'));
      expect(entityNames, contains('journal_entries'));
      expect(entityNames, contains('journal_entry_lines'));
      expect(entityNames, contains('safe_transactions'));
      expect(entityNames, contains('accounts'));
      expect(entityNames, contains('products'));
    });
  });
}
