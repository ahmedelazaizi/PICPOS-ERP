// ═══════════════════════════════════════════════════════════════════════════
// ProcessSalesReturnUseCase — Happy path + edge case tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Validation paths are covered in process_sales_return_validation_test.dart.
// This file exercises the full execute() flow via real DB to cover
// _processReturn, _calculateTotals, _getUserName, treasury, and accounting.

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/activity_logger.dart';
import 'package:ural_erp/domain/usecases/returns/process_sales_return_usecase.dart';

void main() {
  late AppDatabase db;
  late ActivityLogger logger;
  late ProcessSalesReturnUseCase useCase;
  late int userId;
  late int warehouseId;
  late int productId;
  late int invoiceId;
  late int invoiceItemId;

  setUp(() async {
    db = AppDatabase.forTesting();
    logger = ActivityLogger(db);
    useCase = ProcessSalesReturnUseCase(db, logger);

    // Seed minimal data for return processing
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'ret_user',
      password: 'test',
      displayName: 'Return User',
      roleId: roleId,
    );

    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'RET-P1',
        name: 'منتج للإرجاع',
        salePrice: const Value(100.0),
        costPrice: const Value(60.0),
        currentStock: const Value(50.0),
        trackInventory: const Value(true),
        taxRate: const Value(14.0),
      ),
    );

    // Seed stock
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 50.0,
      type: 'in',
      notes: 'seed',
    );

    // Create original invoice (sell 5 units)
    invoiceId = await db.createSalesInvoice(
      invoiceNumber: 'INV-RET-001',
      warehouseId: warehouseId,
      userId: userId,
      subtotal: 500.0,
      discount: 0.0,
      tax: 70.0,
      total: 570.0,
      paid: 570.0,
      paymentMethod: 'cash',
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 5.0,
          unitPrice: 100.0,
          total: 500.0,
          costPrice: const Value(60.0),
        ),
      ],
    );

    // Get the invoice item id for return reference
    final items = await db.getSalesInvoiceItems(invoiceId);
    invoiceItemId = items.first.id;
  });

  tearDown(() async => db.close());

  // ── Validation extensions ───────────────────────────────────────────────────
  group('execute() — validation extensions', () {
    test('fails when item quantity is zero', () async {
      final request = SalesReturnRequest(
        originalInvoiceId: invoiceId,
        items: [
          ReturnItemInput(
            originalItemId: invoiceItemId,
            productId: productId,
            productName: 'P',
            quantity: 0,
            unitPrice: 100,
          ),
        ],
        returnReason: 'test',
        userId: userId,
      );
      final result = await useCase.execute(request);
      expect(result.isFailure, isTrue);
      expect((result as ReturnFailure).error,
          contains('الكمية المرتجعة'));
    });

    test('fails when item quantity is negative', () async {
      final request = SalesReturnRequest(
        originalInvoiceId: invoiceId,
        items: [
          ReturnItemInput(
            originalItemId: invoiceItemId,
            productId: productId,
            productName: 'P',
            quantity: -2,
            unitPrice: 100,
          ),
        ],
        returnReason: 'test',
        userId: userId,
      );
      final result = await useCase.execute(request);
      expect(result.isFailure, isTrue);
    });

    test('fails when invoice is from delivery app (saleType != default)', () async {
      // Create a delivery-app invoice
      final deliveryInvoiceId = await db.createSalesInvoice(
        invoiceNumber: 'DEL-001',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 100,
        discount: 0,
        tax: 0,
        total: 100,
        paid: 100,
        paymentMethod: 'cash',
        saleType: 'talabat', // delivery app
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1,
            unitPrice: 100,
            total: 100,
          ),
        ],
      );
      final request = SalesReturnRequest(
        originalInvoiceId: deliveryInvoiceId,
        items: [
          ReturnItemInput(
            originalItemId: invoiceItemId,
            productId: productId,
            productName: 'P',
            quantity: 1,
            unitPrice: 100,
          ),
        ],
        returnReason: 'test',
        userId: userId,
      );
      final result = await useCase.execute(request);
      expect(result.isFailure, isTrue);
      expect((result as ReturnFailure).error, contains('شركات التوصيل'));
    });

    test('fails when invoice is already fully returned', () async {
      // Mark the invoice as already returned
      await (db.update(db.salesInvoices)..where((i) => i.id.equals(invoiceId)))
          .write(const SalesInvoicesCompanion(status: Value('returned')));

      final request = SalesReturnRequest(
        originalInvoiceId: invoiceId,
        items: [
          ReturnItemInput(
            originalItemId: invoiceItemId,
            productId: productId,
            productName: 'P',
            quantity: 1,
            unitPrice: 100,
          ),
        ],
        returnReason: 'test',
        userId: userId,
      );
      final result = await useCase.execute(request);
      expect(result.isFailure, isTrue);
      expect((result as ReturnFailure).error, contains('مرتجعة بالكامل'));
    });
  });

  // ── Happy path: cash return ────────────────────────────────────────────────
  group('execute() — happy path', () {
    test('processes cash return successfully and restores stock', () async {
      final stockBefore = (await db.getProductById(productId))!.currentStock;

      final request = SalesReturnRequest(
        originalInvoiceId: invoiceId,
        items: [
          ReturnItemInput(
            originalItemId: invoiceItemId,
            productId: productId,
            productName: 'منتج للإرجاع',
            quantity: 2,
            unitPrice: 100,
          ),
        ],
        returnReason: 'عميل غير راضي',
        refundMethod: 'cash',
        userId: userId,
        isFullReturn: false,
      );

      final result = await useCase.execute(request);

      expect(result.isSuccess, isTrue);
      final s = result as ReturnSuccess;
      expect(s.refundAmount, 200);
      expect(s.itemsReturned, 1);

      // Stock should be restored by 2
      final stockAfter = (await db.getProductById(productId))!.currentStock;
      expect(stockAfter, stockBefore + 2);

      // Invoice status updated to partial_return
      final inv = await db.getSalesInvoiceById(invoiceId);
      expect(inv!.status, 'partial_return');
    });

    test('full return marks invoice as returned', () async {
      final request = SalesReturnRequest(
        originalInvoiceId: invoiceId,
        items: [
          ReturnItemInput(
            originalItemId: invoiceItemId,
            productId: productId,
            productName: 'P',
            quantity: 5,
            unitPrice: 100,
          ),
        ],
        returnReason: 'full',
        userId: userId,
        isFullReturn: true,
      );
      final result = await useCase.execute(request);
      expect(result.isSuccess, isTrue);

      final inv = await db.getSalesInvoiceById(invoiceId);
      expect(inv!.status, 'returned');
    });

    test('processes return for invoice paid by bank/transfer', () async {
      // Create invoice paid by transfer
      final bankInvoiceId = await db.createSalesInvoice(
        invoiceNumber: 'INV-BANK-001',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 300,
        discount: 0,
        tax: 0,
        total: 300,
        paid: 300,
        paymentMethod: 'transfer',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 3,
            unitPrice: 100,
            total: 300,
          ),
        ],
      );
      final bankItems = await db.getSalesInvoiceItems(bankInvoiceId);

      final request = SalesReturnRequest(
        originalInvoiceId: bankInvoiceId,
        items: [
          ReturnItemInput(
            originalItemId: bankItems.first.id,
            productId: productId,
            productName: 'P',
            quantity: 1,
            unitPrice: 100,
          ),
        ],
        returnReason: 'bank refund',
        userId: userId,
      );
      final result = await useCase.execute(request);
      expect(result.isSuccess, isTrue);
    });

    test('processes return with no notes/reason (empty string)', () async {
      final request = SalesReturnRequest(
        originalInvoiceId: invoiceId,
        items: [
          ReturnItemInput(
            originalItemId: invoiceItemId,
            productId: productId,
            productName: 'P',
            quantity: 1,
            unitPrice: 100,
          ),
        ],
        returnReason: '', // empty
        userId: userId,
      );
      final result = await useCase.execute(request);
      expect(result.isSuccess, isTrue);
    });

    test('handles non-existent product in items gracefully (continue)', () async {
      // Use an invalid productId — _processReturn should `continue` past it
      final request = SalesReturnRequest(
        originalInvoiceId: invoiceId,
        items: [
          ReturnItemInput(
            originalItemId: invoiceItemId,
            productId: 999999, // doesn't exist
            productName: 'Ghost',
            quantity: 1,
            unitPrice: 100,
          ),
        ],
        returnReason: 'test',
        userId: userId,
      );
      final result = await useCase.execute(request);
      // The item is skipped via `continue` but the return still completes
      expect(result.isSuccess, isTrue);
    });
  });

  // ── Credit refund (party balance adjustment) ───────────────────────────────
  group('execute() — credit refund path', () {
    test('credit refund adjusts party balance when customerId set', () async {
      // Create a customer party
      final customerId = await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'Test Customer',
              isCustomer: const Value(true),
              balance: const Value(0),
            ),
          );

      // Create invoice with customer
      final custInvoiceId = await db.createSalesInvoice(
        invoiceNumber: 'INV-CREDIT-001',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 200,
        discount: 0,
        tax: 0,
        total: 200,
        paid: 0,
        paymentMethod: 'cash',
        customerId: customerId,
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 2,
            unitPrice: 100,
            total: 200,
          ),
        ],
      );
      final custItems = await db.getSalesInvoiceItems(custInvoiceId);

      final request = SalesReturnRequest(
        originalInvoiceId: custInvoiceId,
        customerId: customerId,
        items: [
          ReturnItemInput(
            originalItemId: custItems.first.id,
            productId: productId,
            productName: 'P',
            quantity: 1,
            unitPrice: 100,
          ),
        ],
        returnReason: 'credit refund',
        refundMethod: 'credit',
        userId: userId,
      );
      final partyBefore = await (db.select(db.parties)
            ..where((p) => p.id.equals(customerId)))
          .getSingle();

      final result = await useCase.execute(request);
      expect(result.isSuccess, isTrue);

      // Customer balance should decrease by refund amount (100)
      final partyAfter = await (db.select(db.parties)
            ..where((p) => p.id.equals(customerId)))
          .getSingle();
      expect(partyAfter.balance, partyBefore.balance - 100);
    });
  });
}
