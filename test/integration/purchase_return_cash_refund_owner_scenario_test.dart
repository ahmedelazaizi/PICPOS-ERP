// 🔴 Owner bug report — PicPos «مرتجع مشتريات جديد» did nothing on confirm.
//
// Scenario (real in-memory DB, real repository): cash supplier «نقدي», purchase
// invoice #1 worth 93000.00 fully paid in cash, four tax-exempt lines at cost
// 3/4/5/6, returned 100/50/10/70 ⇒ net 970.00, settled 100 % as a cash refund.
//
//   • with an open shift the return persists: stock decreases per line, one
//     balanced JE Dr cash 970 / Cr inventory 970 with no VAT and no AP leg,
//     a 970 receipt lands in the cash safe, and the `purchase_returns` row is
//     listed by the records screen query for TODAY's range;
//   • without an open shift the repository refuses with
//     `ShiftRequiredException` and writes nothing — this is the failure the
//     UI used to swallow silently (see picpos_purchase_return_save_feedback_test).
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/errors/app_exceptions.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/data/repositories/purchases_repository_impl.dart';
import 'package:picpos_erp/domain/models/document_record.dart';
import 'package:picpos_erp/domain/repositories/audit_repository_interface.dart';
import 'package:picpos_erp/domain/repositories/i_products_repository.dart';
import 'package:picpos_erp/domain/repositories/inventory_repository.dart';
import 'package:picpos_erp/domain/repositories/parties_repository.dart';
import 'package:picpos_erp/domain/repositories/purchases_repository.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/domain/repositories/treasury_repository.dart';
import 'package:picpos_erp/services/accounting_service.dart';

/// (purchased qty, unit cost, returned qty) — 93000 bought, 970 returned.
const _lines = [
  (5000.0, 3.0, 100.0),
  (6000.0, 4.0, 50.0),
  (6000.0, 5.0, 10.0),
  (4000.0, 6.0, 70.0),
];

void main() {
  late AppDatabase db;
  late PurchasesRepositoryImpl repo;
  late int warehouseId;
  late int supplierId;
  late List<int> productIds;
  late PurchaseInvoiceData invoice;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    repo = PurchasesRepositoryImpl(
      db,
      AccountingService(
        DriftAccountingRepository(db),
        _UnusedParties(),
        _UnusedTreasury(),
        _UnusedProducts(),
        _UnusedInventory(),
        _UnusedSettings(),
        _UnusedAudit(),
      ),
    );

    final branchId = await db.into(db.branches).insert(BranchesCompanion.insert(
          name: 'الفرع الرئيسي',
          globalId: const Value('gid-br-owner-pret'),
        ));
    warehouseId = await db.into(db.warehouses).insert(WarehousesCompanion.insert(
          name: 'المخزن الرئيسي',
          branchId: Value(branchId),
          globalId: const Value('gid-wh-owner-pret'),
        ));
    supplierId = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'نقدي',
          isSupplier: const Value(true),
          isCustomer: const Value(false),
          globalId: const Value('gid-sup-owner-pret'),
        ));

    productIds = [];
    for (var i = 0; i < _lines.length; i++) {
      productIds.add(await db.insertProduct(ProductsCompanion.insert(
        code: 'OWN-PRET-$i',
        name: 'صنف معفى $i',
        costPrice: Value(_lines[i].$2),
        currentStock: const Value(0),
        trackInventory: const Value(true),
        taxRate: const Value(0),
      )));
    }

    final invoiceId =
        await db.into(db.purchaseInvoices).insert(PurchaseInvoicesCompanion.insert(
              invoiceNumber: '1',
              supplierId: supplierId,
              warehouseId: warehouseId,
              invoiceDate: DateTime.now(),
              subtotal: const Value(93000),
              tax: const Value(0),
              total: const Value(93000),
              paid: const Value(93000),
              paymentMethod: const Value('cash'),
              status: const Value('paid'),
            ));
    for (var i = 0; i < _lines.length; i++) {
      final (qty, cost, _) = _lines[i];
      await db.into(db.purchaseInvoiceItems).insert(
            PurchaseInvoiceItemsCompanion.insert(
              invoiceId: invoiceId,
              productId: productIds[i],
              quantity: qty,
              unitCost: cost,
              total: qty * cost,
            ),
          );
      await db.adjustStock(
        productId: productIds[i],
        warehouseId: warehouseId,
        quantity: qty,
        type: 'purchase',
        referenceType: 'purchase_invoice',
        referenceId: invoiceId,
        unitCost: cost,
      );
    }
    invoice = (await db.getPurchaseInvoiceById(invoiceId))!;
    expect(invoice.total, 93000, reason: 'sanity');
  });

  tearDown(() async => db.close());

  Future<double> processOwnerReturn() async {
    final items = await db.getPurchaseInvoiceItemsWithProduct(invoice.id);
    return repo.processPurchaseReturn(
      invoice: invoice,
      reason: 'فائض',
      returnItems: [
        for (final it in items)
          PurchaseReturnItem(
            itemId: it.item.id,
            productId: it.item.productId,
            returnQuantity:
                _lines[productIds.indexOf(it.item.productId)].$3,
            unitCost: it.item.unitCost,
            taxAmount: it.item.taxAmount,
            originalQuantity: it.item.quantity,
            quantityInBase: it.item.quantityInBase,
          ),
      ],
    );
  }

  Future<List<PurchaseReturnRecord>> todaysRecords() {
    final now = DateTime.now();
    // Same bounds the records screen builds for a one-day range.
    return db
        .watchPurchaseReturnRecords(
          from: DateTime(now.year, now.month, now.day),
          to: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
        )
        .first;
  }

  test(
      'open shift ⇒ return persisted: stock, JE (Dr cash / Cr inventory, no '
      'VAT), cash refund into the safe, and listed for today', () async {
    await db.openShift(1, 0);
    final cashTxBefore = await (db.select(db.safeTransactions)
          ..where((t) => t.category.equals('purchase_return')))
        .get();
    expect(cashTxBefore, isEmpty);

    final total = await processOwnerReturn();
    expect(total, closeTo(970, 0.001));

    // Stock: bought − returned, per line.
    for (var i = 0; i < _lines.length; i++) {
      final p = (await db.getProductById(productIds[i]))!;
      expect(p.currentStock, closeTo(_lines[i].$1 - _lines[i].$3, 0.001),
          reason: 'product $i stock must drop by the returned qty');
    }

    // JE: one balanced entry, cash debit 970, inventory credit 970, no VAT/AP.
    final jes = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals('purchase_return')))
        .get();
    expect(jes, hasLength(1));
    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(jes.single.id)))
        .get();
    final debits = lines.where((l) => l.debit > 0).toList();
    final credits = lines.where((l) => l.credit > 0).toList();
    expect(debits, hasLength(1), reason: 'paid invoice ⇒ cash leg only');
    expect(debits.single.description, 'استرداد نقدي مرتجع مشتريات');
    expect(debits.single.debit, closeTo(970, 0.001));
    expect(credits, hasLength(1), reason: 'tax-exempt ⇒ no input-VAT leg');
    expect(credits.single.description, 'مرتجع مشتريات — تخفيض مخزون');
    expect(credits.single.credit, closeTo(970, 0.001));

    // Cash refund: one 970 receipt into a cash safe.
    final cashTx = await (db.select(db.safeTransactions)
          ..where((t) => t.category.equals('purchase_return')))
        .get();
    expect(cashTx, hasLength(1));
    expect(cashTx.single.transactionType, 'receipt');
    expect(cashTx.single.amount, closeTo(970, 0.001));
    final safe = (await db.getSafeById(cashTx.single.safeId))!;
    expect(safe.safeType, 'cash');
    expect(safe.balance, closeTo(cashTx.single.balanceAfter, 0.001));

    // No AP memo: nothing was owed on a fully paid invoice.
    final memos = await (db.select(db.safeTransactions)
          ..where((t) => t.category.equals('purchase_return_balance')))
        .get();
    expect(memos, isEmpty);

    // Records list for today's range shows it.
    final records = await todaysRecords();
    expect(records, hasLength(1),
        reason: 'the saved return must appear in the records list');
    final r = records.single;
    expect(r.originalInvoiceNumber, '1');
    expect(r.supplierName, 'نقدي');
    expect(r.reason, 'فائض');
    expect(r.total, closeTo(970, 0.001));
    expect(r.tax, 0);

    final inv = (await db.getPurchaseInvoiceById(invoice.id))!;
    expect(inv.status, 'partial_return');
  });

  test(
      'no open shift ⇒ ShiftRequiredException and nothing is written '
      '(the failure the UI used to hide)', () async {
    await expectLater(processOwnerReturn(),
        throwsA(isA<ShiftRequiredException>()));

    for (var i = 0; i < _lines.length; i++) {
      final p = (await db.getProductById(productIds[i]))!;
      expect(p.currentStock, closeTo(_lines[i].$1, 0.001),
          reason: 'no stock may leave on a refused return');
    }
    final jes = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals('purchase_return')))
        .get();
    expect(jes, isEmpty);
    expect(await todaysRecords(), isEmpty);
  });
}

mixin _Unused {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnsupportedError('${i.memberName} not expected');
}

class _UnusedParties with _Unused implements IPartiesRepository {}

class _UnusedProducts with _Unused implements IProductRepository {}

class _UnusedInventory with _Unused implements InventoryRepository {}

class _UnusedSettings with _Unused implements ISettingsRepository {}

class _UnusedAudit with _Unused implements IAuditRepository {}

class _UnusedTreasury implements ITreasuryRepository {
  @override
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(
          String referenceType, int referenceId) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnsupportedError('${i.memberName} not expected');
}
