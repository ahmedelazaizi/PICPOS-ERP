// ignore_for_file: avoid_dynamic_calls
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_sales_handler.dart';

void main() {
  group('Idempotency Key Sync Tests', () {
    late AppDatabase db;
    late ApiSalesHandler apiSalesHandler;

    setUp(() async {
      // Use in-memory SQLite for testing
      db = AppDatabase.forTesting();
      
      // Initialize basic schema dependencies if needed
      final roleId = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'admin', isSystemRole: const drift.Value(true)),
      );
      await db.createUser(
        username: 'admin',
        password: 'xx',
        displayName: 'Admin User',
        roleId: roleId,
      );
      await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(
          name: 'Main',
          isActive: const drift.Value(true),
          isDefault: const drift.Value(true),
        )
      );

      // createSalesInvoice calls validateFinancialPeriod — seed a fiscal year
      // covering the current date so the validation doesn't throw.
      await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          name: '2026',
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 12, 31),
        ),
      );

      apiSalesHandler = ApiSalesHandler(db, {});
    });

    tearDown(() async {
      await db.close();
    });

    test('Duplicate postSale requests with same Idempotency-Key return cached response', () async {
      final idempotencyKey = const Uuid().v4();
      final globalId = const Uuid().v4();

      // Get default warehouse and user IDs for a valid payload
      final wh = await db.getDefaultWarehouse();
      final users = await db.select(db.users).get();

      final payload = jsonEncode({
        'invoiceNumber': 'TEST-INV-001',
        'globalId': globalId,
        // subtotal == total == paid with tax:0 so the auto-posted GL entry
        // balances: Dr Cash 100 / Cr Sales 100.
        'subtotal': 100.0,
        'total': 100.0,
        'paid': 100.0,
        'paymentMethod': 'cash',
        'warehouseId': wh?.id ?? 1,
        'userId': users.first.id,
        'items': [],
      });

      // 1. First request
      final request1 = Request(
        'POST',
        Uri.parse('http://localhost/api/sales'),
        body: payload,
        headers: {'X-Idempotency-Key': idempotencyKey, 'Content-Type': 'application/json'},
      );

      final response1 = await apiSalesHandler.postSale(request1);
      expect(response1.statusCode, 200);
      final bodyStr1 = await response1.readAsString();
      final body1 = jsonDecode(bodyStr1);
      expect(body1['success'], true);
      final serverId = body1['serverId'];

      // 2. Simulate network drop (client retries with same idempotency key)
      final request2 = Request(
        'POST',
        Uri.parse('http://localhost/api/sales'),
        body: payload,
        headers: {'X-Idempotency-Key': idempotencyKey, 'Content-Type': 'application/json'},
      );

      final response2 = await apiSalesHandler.postSale(request2);
      expect(response2.statusCode, 200);
      final bodyStr2 = await response2.readAsString();
      final body2 = jsonDecode(bodyStr2);
      
      // The response should be exactly identical, returning the same serverId
      expect(body2['success'], true);
      expect(body2['serverId'], serverId);

      // Verify that only ONE invoice was actually inserted in the database
      final invoices = await db.select(db.salesInvoices).get();
      expect(invoices.length, 1);
      expect(invoices.first.id, serverId);
      expect(invoices.first.invoiceNumber, 'TEST-INV-001');
    });
  });
}