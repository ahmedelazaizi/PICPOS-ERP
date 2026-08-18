// ═══════════════════════════════════════════════════════════════════════════
// Spec 151 — E-01 · standalone sales line tax reconciles with the header
// ═══════════════════════════════════════════════════════════════════════════
//
// Root cause: in STANDALONE / server mode (SyncInterceptor.isClientMode ==
// false) SalesTransactionOrchestrator.completeSalesTransaction computed the
// header tax correctly (net-base, two-pass, gated by taxEnabled) but then
// persisted the invoice LINES from the raw, pre-discount, ungated,
// merge-stale `CartItemEntity.taxAmount`. So the saved sales_invoice_items
// carried phantom VAT that the header never posted. Every sales RETURN reads
// that saved line tax to reverse output-VAT → it reversed VAT the sale never
// booked → orphan negative output-VAT in the GL on every return.
//
// The fix threads the SAME net-base per-line VAT the client/mirror path
// already uses (perLineBeforeTax / perLineTax / perLineRate) into the
// standalone line build, via the shared buildSalesLineCompanion helper.
//
// Invariants locked here:
//   1. taxEnabled == false  ⇒ every saved line.taxAmount == 0 AND
//      SUM(line.total) == header.total (no phantom VAT on a non-taxed sale).
//   2. taxEnabled == true + invoice-level discount ⇒
//      SUM(line.taxAmount) == header.tax (net-base, within 0.01).
//   3. The shared helper stores net values verbatim and only stamps costPrice
//      when the client/mirror path supplies it.
//
// Standalone path runs by default: SyncInterceptor.instance is null in tests,
// so SyncInterceptor.isClientMode == false.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/drift_accounting_repository.dart';
import 'package:ural_erp/data/repositories/sales_transaction_orchestrator.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/domain/repositories/audit_repository_interface.dart';
import 'package:ural_erp/domain/repositories/i_products_repository.dart';
import 'package:ural_erp/domain/repositories/inventory_repository.dart';
import 'package:ural_erp/domain/repositories/kitchen_repository.dart';
import 'package:ural_erp/domain/repositories/parties_repository.dart';
import 'package:ural_erp/domain/repositories/printers_repository.dart';
import 'package:ural_erp/domain/repositories/sales_repository.dart';
import 'package:ural_erp/domain/repositories/settings_repository.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/services/accounting_service.dart';
import 'package:ural_erp/services/kitchen_service.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // Full standalone path — completeSalesTransaction → sales_invoice_items rows
  // ─────────────────────────────────────────────────────────────────────────
  group('E-01 — standalone lines reconcile with the header (net-base VAT)', () {
    late AppDatabase db;
    late SalesTransactionOrchestrator orch;
    late int warehouseId;
    late int userId;
    late int customerId;
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
      // Kitchen work-order generation is non-fatal (wrapped in try/catch by the
      // orchestrator), so throwing stubs are fine — the sale still completes.
      // لا `KitchenService` هنا: المنسّقُ ما عاد يولّد أوامرَ تحضير —
      // الطاولاتُ وحدَها تُحضَّر (2026-08-18).
      orch = SalesTransactionOrchestrator(db, svc);

      final roleId = await db.into(db.roles).insert(
            RolesCompanion.insert(
              name: 'كاشير E01',
              isSystemRole: const Value(false),
            ),
          );
      userId = await db.createUser(
        username: 'e01_cashier',
        password: 'pw',
        displayName: 'E01 Cashier',
        roleId: roleId,
      );

      warehouseId = (await db.getDefaultWarehouse())!.id;

      // Taxable product (taxRate 14) with a known cost so COGS posts cleanly.
      productId = await db.insertProduct(
        ProductsCompanion.insert(
          code: 'E01-01',
          name: 'منتج E01',
          salePrice: const Value(100.0),
          costPrice: const Value(60.0),
          taxRate: const Value(14.0),
          currentStock: const Value(1000),
          trackInventory: const Value(true),
        ),
      );
      await db.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: 1000.0,
        type: 'adjustment',
      );

      // Credit customer (creditLimit 0 ⇒ no limit gate) so we can pay 0 and
      // avoid coupling the request to the exact computed total.
      customerId = await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'عميل E01',
              isCustomer: const Value(true),
            ),
          );
    });

    tearDown(() async => db.close());

    test(
        'taxEnabled=false, product taxRate=14, price 100 qty 1 → '
        'every saved line.taxAmount == 0 AND SUM(line.total) == header.total',
        () async {
      final result = await orch.completeSalesTransaction(SaleRequest(
        items: [
          CartItemEntity(
            productId: productId,
            productName: 'منتج E01',
            productCode: 'E01-01',
            quantity: 1,
            unitPrice: 100,
            taxRate: 14,
            // Simulate the stale GROSS AddToCartUseCase value
            // (qty*price*rate/100) that the old standalone path persisted
            // verbatim. The fix must NOT use it when taxEnabled=false.
            taxAmount: 14,
          ),
        ],
        customerId: customerId,
        warehouseId: warehouseId,
        userId: userId,
        paymentMethod: 'credit',
        paidAmount: 0,
        taxEnabled: false,
      ));

      expect(result.isSuccess, isTrue,
          reason: 'standalone credit sale must persist: ${result.errorMessage}');
      final invId = result.invoiceId!;

      final invoice = await (db.select(db.salesInvoices)
            ..where((s) => s.id.equals(invId)))
          .getSingle();
      final lines = await (db.select(db.salesInvoiceItems)
            ..where((i) => i.invoiceId.equals(invId)))
          .get();

      expect(lines, isNotEmpty);
      // Header posts no tax when taxEnabled=false.
      expect(invoice.tax, closeTo(0.0, 0.001));
      // Every line must carry ZERO tax — not the stale gross 14.
      for (final l in lines) {
        expect(l.taxAmount, closeTo(0.0, 0.001),
            reason: 'taxEnabled=false ⇒ line.taxAmount must be 0, not the '
                'gross CartItemEntity.taxAmount (14)');
      }
      final sumLineTax = lines.fold<double>(0, (s, l) => s + l.taxAmount);
      final sumLineTotal = lines.fold<double>(0, (s, l) => s + l.total);
      expect(sumLineTax, closeTo(0.0, 0.001));
      expect(sumLineTotal, closeTo(invoice.total, 0.01),
          reason: 'SUM(line.total) must equal header.total (100), not 114');
    });

    test(
        'taxEnabled=true + invoice discount 10% + tax 14% → '
        'SUM(line.taxAmount) == header.tax (net-base, within 0.01)', () async {
      final result = await orch.completeSalesTransaction(SaleRequest(
        items: [
          CartItemEntity(
            productId: productId,
            productName: 'منتج E01',
            productCode: 'E01-01',
            quantity: 1,
            unitPrice: 100,
            taxRate: 14,
            taxAmount: 14, // gross pre-discount — must NOT be persisted verbatim
          ),
        ],
        customerId: customerId,
        warehouseId: warehouseId,
        userId: userId,
        paymentMethod: 'credit',
        paidAmount: 0,
        taxEnabled: true,
        discountPercent: 10,
      ));

      expect(result.isSuccess, isTrue,
          reason: 'standalone credit sale must persist: ${result.errorMessage}');
      final invId = result.invoiceId!;

      final invoice = await (db.select(db.salesInvoices)
            ..where((s) => s.id.equals(invId)))
          .getSingle();
      final lines = await (db.select(db.salesInvoiceItems)
            ..where((i) => i.invoiceId.equals(invId)))
          .get();

      // net = (100 − 0 line-disc) × 0.9 invoice-disc = 90; tax = 90 × 14% = 12.6
      expect(invoice.tax, closeTo(12.6, 0.01),
          reason: 'header tax is net-base: (100×0.9)×0.14');
      final sumLineTax = lines.fold<double>(0, (s, l) => s + l.taxAmount);
      expect(sumLineTax, closeTo(invoice.tax, 0.01),
          reason: 'SUM(line.taxAmount) must reconcile with header.tax — the '
              'gross 14 would NOT (it ignores the 10% invoice discount)');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Pure unit guard for the shared line builder (fast, DB-free)
  // ─────────────────────────────────────────────────────────────────────────
  group('E-01 — buildSalesLineCompanion stores net values verbatim', () {
    const item = CartItemEntity(
      productId: 7,
      productName: 'p',
      productCode: 'c',
      quantity: 1,
      unitPrice: 100,
      taxRate: 14,
      taxAmount: 14, // gross — the helper must ignore this
    );

    test('netTax=0 / netRate=0 → line tax 0, total = netBeforeTax, cost absent',
        () {
      final c = SalesTransactionOrchestrator.buildSalesLineCompanion(
        item: item,
        netBeforeTax: 100,
        netTax: 0,
        netRate: 0,
      );
      expect(c.taxAmount.value, closeTo(0.0, 1e-9));
      expect(c.taxRate.value, closeTo(0.0, 1e-9));
      expect(c.total.value, closeTo(100.0, 1e-9));
      expect(c.costPrice.present, isFalse,
          reason: 'standalone path leaves costPrice for the DAO WAC stamp');
    });

    test('taxable net line → net tax/rate/total persisted; cost stamped', () {
      final c = SalesTransactionOrchestrator.buildSalesLineCompanion(
        item: item,
        netBeforeTax: 90,
        netTax: 12.6,
        netRate: 14,
        costPrice: 50,
      );
      expect(c.taxAmount.value, closeTo(12.6, 1e-9));
      expect(c.taxRate.value, closeTo(14.0, 1e-9));
      expect(c.total.value, closeTo(102.6, 1e-9));
      expect(c.costPrice.present, isTrue);
      expect(c.costPrice.value, closeTo(50.0, 1e-9));
    });
  });
}

// Throwing stubs: AccountingService.generateSalesAccountingEntry only touches
// the accounting repo (proven by accounting_double_entry_test), so every other
// collaborator can throw on use. noSuchMethod catches all interface methods.
class _ThrowingPartiesRepo implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation inv) {
    // A credit sale resolves the AR account via getPartyById; returning null
    // lets _partyAccount fall back to the seeded 'receivables' account so the
    // sale posts. The E-01 line-tax invariant is independent of the party.
    if (inv.memberName == #getPartyById) return Future<Null>.value(null);
    throw UnsupportedError('parties repo not used in this test');
  }
}

class _ThrowingTreasuryRepo implements ITreasuryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('treasury repo not used in this test');
}

class _ThrowingProductRepo implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('product repo not used in this test');
}

class _ThrowingInventoryRepo implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('inventory repo not used in this test');
}

class _ThrowingSettingsRepo implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('settings repo not used in this test');
}

class _ThrowingAuditRepo implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('audit repo not used in this test');
}

class _ThrowingKitchenRepo implements KitchenRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('kitchen repo not used in this test');
}

class _ThrowingPrintersRepo implements IPrintersRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('printers repo not used in this test');
}
