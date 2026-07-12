// ═══════════════════════════════════════════════════════════════════════════
// Spec 149 pre-deploy batch B9 — S-RETURNS-ACCURACY
// ═══════════════════════════════════════════════════════════════════════════
//
// PRET-2 — autoPostPurchaseReturn used to lump the ENTIRE refund
// (returnAmount + vatAmount) onto a SINGLE debit leg chosen only by
// originalPurchase.paymentMethod == 'cash', ignoring how much of the
// invoice was actually paid vs still owed. The callers
// (_processPurchaseReturnBody / api_purchase_handler.postPurchaseReturn)
// already compute the correct AP/cash split on the GROSS refund; this fix
// threads it through as optional apPortion/cashPortion params so the GL
// mirrors exactly what happened to the supplier balance and the safe.
//
// SRET-2 — the standalone sales-return path recomputed output VAT as
// `unitPrice(gross, pre-discount) * returnQty * taxRate`, over-reversing
// VAT whenever the original sale had a discount (the sale charged VAT on
// the DISCOUNTED base, not the gross price). The fix prorates the FROZEN
// original item.taxAmount by the return fraction, matching the sibling
// client-mode path in the same file.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/drift_accounting_repository.dart';
import 'package:ural_erp/data/repositories/purchases_repository_impl.dart';
import 'package:ural_erp/data/repositories/returns_repository_impl.dart';
import 'package:ural_erp/domain/entities/product_entity.dart';
import 'package:ural_erp/domain/repositories/audit_repository_interface.dart';
import 'package:ural_erp/domain/repositories/i_products_repository.dart';
import 'package:ural_erp/domain/repositories/inventory_repository.dart';
import 'package:ural_erp/domain/repositories/parties_repository.dart';
import 'package:ural_erp/domain/repositories/purchases_repository.dart';
import 'package:ural_erp/domain/repositories/settings_repository.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/services/accounting_service.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // PRET-2 — purchase-return refund splits AP (unpaid) vs cash (paid)
  // ─────────────────────────────────────────────────────────────────────────
  group('B9 PRET-2 — autoPostPurchaseReturn splits AP vs cash', () {
    late AppDatabase db;
    late PurchasesRepositoryImpl repo;
    late int warehouseId;
    late int supplierId;
    late int productId;

    setUp(() async {
      db = AppDatabase.forTesting();
      await db.syncDefaultAccounts();

      final accRepo = DriftAccountingRepository(db);
      final svc = AccountingService(
        accRepo,
        _ThrowingPartiesRepo(),
        _ThrowingTreasuryRepo(),
        _ThrowingProductRepo(),
        _ThrowingInventoryRepo(),
        _ThrowingSettingsRepo(),
        _ThrowingAuditRepo(),
      );
      repo = PurchasesRepositoryImpl(db, svc);

      final branchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'main-b9',
              globalId: const Value('gid-br-b9-pret'),
            ),
          );
      warehouseId = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'wh-b9-pret',
              branchId: Value(branchId),
              globalId: const Value('gid-wh-b9-pret'),
            ),
          );
      supplierId = await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'مورد B9',
              isSupplier: const Value(true),
              isCustomer: const Value(false),
              globalId: const Value('gid-supplier-b9'),
            ),
          );
      productId = await db.insertProduct(
        ProductsCompanion.insert(
          code: 'B9-PRET-01',
          name: 'منتج اختبار B9 PRET',
          salePrice: const Value(200.0),
          costPrice: const Value(100.0),
          currentStock: const Value(0),
          trackInventory: const Value(true),
        ),
      );
    });

    tearDown(() async => db.close());

    test(
        'partially-paid credit invoice → full return posts Dr Payables '
        '(unpaid) + Dr Cash (paid), NOT a single lump to payables', () async {
      // total = 10 * 100 = 1000, paid = 400 → oldRemaining = 600.
      final invId = await db.createPurchaseInvoice(
        supplierId: supplierId,
        warehouseId: warehouseId,
        paid: 400.0,
        paymentMethod: 'credit',
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 10,
            unitCost: 100,
            total: 1000,
          ),
        ],
      );
      final invoice = (await db.getPurchaseInvoiceById(invId))!;
      expect(invoice.total, closeTo(1000, 0.001), reason: 'sanity');
      expect(invoice.paid, closeTo(400, 0.001), reason: 'sanity');

      await repo.processPurchaseReturn(
        invoice: invoice,
        returnItems: [
          PurchaseReturnItem(
            itemId: 0,
            productId: productId,
            returnQuantity: 10,
            unitCost: 100,
            taxAmount: 0,
            originalQuantity: 10,
          ),
        ],
      );

      final jes = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('purchase_return')))
          .get();
      expect(jes, hasLength(1),
          reason: 'exactly one purchase-return JE must post');
      final lines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(jes.single.id)))
          .get();

      final debitLines = lines.where((l) => l.debit > 0).toList();
      expect(debitLines, hasLength(2),
          reason: 'the refund must be split into TWO debit legs (AP + '
              'cash), not lumped onto a single 1000 payables leg');

      final payablesLine = debitLines
          .where((l) => l.description == 'تخفيض ذمم الموردين')
          .single;
      final cashLine = debitLines
          .where((l) => l.description == 'استرداد نقدي مرتجع مشتريات')
          .single;
      expect(payablesLine.debit, closeTo(600.0, 0.001),
          reason: 'AP leg = unpaid portion of the gross refund');
      expect(cashLine.debit, closeTo(400.0, 0.001),
          reason: 'cash leg = paid portion of the gross refund');

      final totalDebit = lines.fold<double>(0.0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0.0, (s, l) => s + l.credit);
      expect(totalDebit, closeTo(1000.0, 0.001),
          reason: 'the two legs sum to the full refund (returnAmount + '
              'vatAmount = 1000 + 0)');
      expect(totalDebit, closeTo(totalCredit, 0.001),
          reason: 'the JE must balance — a mis-summed split throws at '
              'createJournalEntry');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // SRET-2 — sales-return output VAT proportional to the discounted base
  // ─────────────────────────────────────────────────────────────────────────
  group('B9 SRET-2 — standalone sales return prorates frozen VAT', () {
    late AppDatabase db;
    late ReturnsRepositoryImpl repo;
    late int warehouseId;
    late int productId;

    setUp(() async {
      db = AppDatabase.forTesting();
      await db.syncDefaultAccounts();

      final accRepo = DriftAccountingRepository(db);
      final svc = AccountingService(
        accRepo,
        _ThrowingPartiesRepo(),
        _ThrowingTreasuryRepo(),
        _ThrowingProductRepo(),
        _ThrowingInventoryRepo(),
        _ThrowingSettingsRepo(),
        _ThrowingAuditRepo(),
      );
      repo = ReturnsRepositoryImpl(db, svc);

      final branchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'main-b9-sret',
              globalId: const Value('gid-br-b9-sret'),
            ),
          );
      warehouseId = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'wh-b9-sret',
              branchId: Value(branchId),
              globalId: const Value('gid-wh-b9-sret'),
            ),
          );
      productId = await db.insertProduct(
        ProductsCompanion.insert(
          code: 'B9-SRET-01',
          name: 'منتج اختبار B9 SRET',
          salePrice: const Value(100.0),
          costPrice: const Value(50.0),
          currentStock: const Value(0),
          trackInventory: const Value(true),
        ),
      );
    });

    tearDown(() async => db.close());

    test(
        'discounted line, full return → reversed output VAT = proportional '
        'frozen tax (120), NOT the gross recompute (150)', () async {
      // unitPrice 100 * qty 10 = 1000 gross, discount 200 → net 800.
      // VAT 15% on the DISCOUNTED net base: 800 * 0.15 = 120.
      // Stored line total (tax-inclusive) = 800 + 120 = 920.
      final invoiceId = await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'INV-B9-SRET-1',
              warehouseId: warehouseId,
              userId: 1, // seeded admin user
              invoiceDate: DateTime.now(),
              subtotal: const Value(800.0),
              tax: const Value(120.0),
              total: const Value(920.0),
              paid: const Value(920.0),
              paymentMethod: const Value('cash'),
              status: const Value('completed'),
            ),
          );
      final itemId = await db.into(db.salesInvoiceItems).insert(
            SalesInvoiceItemsCompanion.insert(
              invoiceId: invoiceId,
              productId: productId,
              quantity: 10,
              unitPrice: 100,
              discount: const Value(200.0),
              total: 920, // net(800) + tax(120), tax-inclusive line total
              costPrice: const Value(50.0),
              taxRate: const Value(15.0),
              taxAmount: const Value(120.0), // frozen at sale time (on 800)
            ),
          );

      final invoice = (await db.getSalesInvoiceById(invoiceId))!;
      final productCache = <int, ProductEntity>{
        productId: ProductEntity(
          id: productId,
          code: 'B9-SRET-01',
          name: 'منتج اختبار B9 SRET',
          salePrice: 100.0,
          costPrice: 50.0,
          currentStock: 0,
          minStock: 0,
        ),
      };

      final ok = await repo.processSalesReturn(
        invoice: invoice,
        returnQuantities: {itemId: 10.0},
        productCache: productCache,
        userId: 1,
        userName: 'B9 Test',
        isFullReturn: true,
      );
      expect(ok, isTrue);

      final jes = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('sales_return')))
          .get();
      expect(jes, hasLength(1),
          reason: 'exactly one sales-return JE must post');
      final lines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(jes.single.id)))
          .get();

      final vatLine =
          lines.where((l) => l.description == 'عكس ضريبة مرتجع').single;
      expect(vatLine.debit, closeTo(120.0, 0.001),
          reason: 'reversed output VAT must be the proportional frozen tax '
              '(item.taxAmount * returnQty/quantity = 120 * 10/10), NOT the '
              'gross recompute (unitPrice(100) * qty(10) * 15% = 150) which '
              'ignores the 200 line discount');

      final revenueLine = lines
          .where((l) => l.description == 'مردودات مبيعات (صافى)')
          .single;
      expect(revenueLine.debit, closeTo(800.0, 0.001),
          reason: 'contra-revenue leg = returnAmount(920) - vatAmount(120) '
              '= the discounted net (800)');

      final totalDebit = lines.fold<double>(0.0, (s, l) => s + l.debit);
      final totalCredit = lines.fold<double>(0.0, (s, l) => s + l.credit);
      expect(totalDebit, closeTo(totalCredit, 0.001),
          reason: 'the JE must balance');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Throwing stubs — only IAccountingRepository is exercised by this suite.
// Neither processPurchaseReturn's standalone path nor processSalesReturn's
// standalone path calls into AccountingService itself.
// ═══════════════════════════════════════════════════════════════════════════

class _ThrowingPartiesRepo implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in B9 returns-accuracy tests');
}

class _ThrowingTreasuryRepo implements ITreasuryRepository {
  @override
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(
          String referenceType, int referenceId) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in B9 returns-accuracy tests');
}

class _ThrowingProductRepo implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in B9 returns-accuracy tests');
}

class _ThrowingInventoryRepo implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in B9 returns-accuracy tests');
}

class _ThrowingSettingsRepo implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in B9 returns-accuracy tests');
}

class _ThrowingAuditRepo implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation inv) => throw UnsupportedError(
      'Stub: ${inv.memberName} not expected in B9 returns-accuracy tests');
}
