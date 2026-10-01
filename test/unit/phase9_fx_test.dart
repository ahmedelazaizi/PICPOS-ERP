import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int currencyId;
  late int userId;
  late int warehouseId;
  late int safeId;
  late int partyAccountId;
  late int supplierId;
  late int customerId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    userId = (await (db.select(db.users)..limit(1)).getSingle()).id;
    warehouseId = (await db.getDefaultWarehouse())!.id;
    final currency = await db.into(db.currencies).insertReturning(
          CurrenciesCompanion.insert(
            code: 'USD',
            name: 'US Dollar',
            symbol: '\$',
            exchangeRate: const Value(50),
            globalId: const Value('phase9-usd'),
          ),
        );
    currencyId = currency.id;
    final detail = await (db.select(db.accounts)
          ..where((a) => a.accountNature.equals('detail'))
          ..limit(1))
        .getSingle();
    partyAccountId = detail.id;
    supplierId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'Phase 9 Supplier',
            isCustomer: const Value(false),
            isSupplier: const Value(true),
            balance: const Value(1000),
            accountId: Value(partyAccountId),
            currencyId: Value(currencyId),
            globalId: const Value('phase9-supplier'),
          ),
        );
    customerId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'Phase 9 Customer',
            balance: const Value(1000),
            accountId: Value(partyAccountId),
            currencyId: Value(currencyId),
            globalId: const Value('phase9-customer'),
          ),
        );
    final cash = await db.accountingDao.getAccountByCode('1111');
    safeId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'Phase 9 Cash',
            balance: const Value(10000),
            isDefault: const Value(true),
            linkedAccountId: Value(cash?.id),
            globalId: const Value('phase9-safe'),
          ),
        );
  });

  tearDown(() => db.close());

  Future<int> purchase({
    required double total,
    required double paid,
    double bookingRate = 50,
    DateTime? date,
    bool foreign = true,
  }) {
    return db.into(db.purchaseInvoices).insert(
          PurchaseInvoicesCompanion.insert(
            invoiceNumber: 'P9-P-${DateTime.now().microsecondsSinceEpoch}',
            supplierId: supplierId,
            warehouseId: warehouseId,
            invoiceDate: date ?? DateTime(2026, 1, 31),
            subtotal: Value(total),
            total: Value(total),
            paid: Value(paid),
            status: Value(paid >= total ? 'paid' : 'pending'),
            currencyId: foreign ? Value(currencyId) : const Value(null),
            exchangeRate: foreign ? Value(bookingRate) : const Value(null),
          ),
        );
  }

  Future<int> sale({
    required double total,
    required double paid,
    double bookingRate = 50,
    DateTime? date,
    bool foreign = true,
  }) {
    return db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: 'P9-S-${DateTime.now().microsecondsSinceEpoch}',
            customerId: Value(customerId),
            warehouseId: warehouseId,
            userId: userId,
            invoiceDate: date ?? DateTime(2026, 1, 31),
            subtotal: Value(total),
            total: Value(total),
            paid: Value(paid),
            paymentMethod: const Value('credit'),
            status: Value(paid >= total ? 'paid' : 'pending'),
            currencyId: foreign ? Value(currencyId) : const Value(null),
            exchangeRate: foreign ? Value(bookingRate) : const Value(null),
          ),
        );
  }

  Future<List<JournalEntryData>> fxEntries() => (db.select(db.journalEntries)
        ..where((e) => e.referenceType.equals('fx_realized_settlement'))
        ..orderBy([(e) => OrderingTerm.asc(e.id)]))
      .get();

  Future<void> expectBalanced() async {
    final entries = await db.select(db.journalEntries).get();
    for (final entry in entries) {
      final lines = await (db.select(db.journalEntryLines)
            ..where((line) => line.entryId.equals(entry.id)))
          .get();
      expect(
        lines.fold<double>(0, (sum, line) => sum + line.debit),
        closeTo(lines.fold<double>(0, (sum, line) => sum + line.credit), 0.001),
        reason: 'JE ${entry.id} must remain balanced',
      );
    }
  }

  test('fresh database exposes schema version 183 for FX, manufacturing, LAN pairing, product tax-exempt and sales revenue-account columns', () async {
    expect(db.schemaVersion, 183);
    final invoiceColumns = await db.customSelect(
      'PRAGMA table_info(sales_invoices)',
    ).get();
    expect(invoiceColumns.any((row) => row.data['name'] == 'currency_id'), isTrue);
    expect(invoiceColumns.any((row) => row.data['name'] == 'revenue_account_id'), isTrue);
    expect(invoiceColumns.any((row) => row.data['name'] == 'exchange_rate'), isTrue);
  });

  test('purchase settlement at a higher rate posts a realized loss and clears AP',
      () async {
    final invoiceId = await purchase(total: 100, paid: 0);
    await db.addPurchasePayment(
      invoiceId: invoiceId,
      amount: 104,
      foreignAmount: 2,
      paymentRate: 52,
      safeId: safeId,
      userId: userId,
      globalId: 'phase9-purchase-payment-1',
    );
    await db.addPurchasePayment(
      invoiceId: invoiceId,
      amount: 104,
      foreignAmount: 2,
      paymentRate: 52,
      safeId: safeId,
      userId: userId,
      globalId: 'phase9-purchase-payment-1',
    );

    final invoice = await db.getPurchaseInvoiceById(invoiceId);
    final supplier = await (db.select(db.parties)
          ..where((p) => p.id.equals(supplierId)))
        .getSingle();
    final fx = await fxEntries();
    final fxLines = await (db.select(db.journalEntryLines)
          ..where((line) => line.entryId.equals(fx.single.id)))
        .get();
    final fxAccount = (await db.accountingDao.getAccountByCode('6313'))!;

    expect(invoice!.paid, 100);
    expect(invoice.status, 'paid');
    expect(supplier.balance, 900);
    expect(fxLines.where((line) => line.accountId == fxAccount.id).single.debit,
        4);
    await expectBalanced();
  });

  test('sale collected below booking rate posts a realized loss and clears AR',
      () async {
    final invoiceId = await sale(total: 100, paid: 0);
    await db.addSalesPayment(
      invoiceId: invoiceId,
      amount: 96,
      foreignAmount: 2,
      paymentRate: 48,
      safeId: safeId,
      userId: userId,
      globalId: 'phase9-sale-payment-1',
    );

    final invoice = await db.getSalesInvoiceById(invoiceId);
    final customer = await (db.select(db.parties)
          ..where((p) => p.id.equals(customerId)))
        .getSingle();
    final fx = await fxEntries();
    final fxLines = await (db.select(db.journalEntryLines)
          ..where((line) => line.entryId.equals(fx.single.id)))
        .get();
    final fxAccount = (await db.accountingDao.getAccountByCode('6313'))!;

    expect(invoice!.paid, 100);
    expect(invoice.status, 'paid');
    expect(customer.balance, 900);
    expect(fxLines.where((line) => line.accountId == fxAccount.id).single.debit,
        4);
    await expectBalanced();
  });

  test('higher sale rate and lower purchase rate post realized gains', () async {
    final saleId = await sale(total: 100, paid: 0);
    await db.addSalesPayment(
      invoiceId: saleId,
      amount: 104,
      foreignAmount: 2,
      paymentRate: 52,
      safeId: safeId,
      userId: userId,
      globalId: 'phase9-sale-gain',
    );
    final purchaseId = await purchase(total: 100, paid: 0);
    await db.addPurchasePayment(
      invoiceId: purchaseId,
      amount: 96,
      foreignAmount: 2,
      paymentRate: 48,
      safeId: safeId,
      userId: userId,
      globalId: 'phase9-purchase-gain',
    );

    final fx = await fxEntries();
    final fxAccount = (await db.accountingDao.getAccountByCode('6313'))!;
    final fxLines = <JournalEntryLine>[];
    for (final entry in fx) {
      fxLines.addAll(await (db.select(db.journalEntryLines)
            ..where((line) => line.entryId.equals(entry.id)))
          .get());
    }
    expect(fxLines.where((line) => line.accountId == fxAccount.id).fold<double>(
        0, (sum, line) => sum + line.credit), 8);
    await expectBalanced();
  });

  test('partial foreign settlement realizes only the settled proportion', () async {
    final invoiceId = await purchase(total: 500, paid: 0);
    await db.addPurchasePayment(
      invoiceId: invoiceId,
      amount: 208,
      foreignAmount: 4,
      paymentRate: 52,
      safeId: safeId,
      userId: userId,
      globalId: 'phase9-purchase-payment-partial',
    );

    final invoice = await db.getPurchaseInvoiceById(invoiceId);
    final supplier = await (db.select(db.parties)
          ..where((p) => p.id.equals(supplierId)))
        .getSingle();
    final fx = await fxEntries();
    final fxLines = await (db.select(db.journalEntryLines)
          ..where((line) => line.entryId.equals(fx.single.id)))
        .get();
    final fxAccount = (await db.accountingDao.getAccountByCode('6313'))!;

    expect(invoice!.paid, 200);
    expect(invoice.status, 'partial');
    expect(supplier.balance, 800);
    expect(fxLines.where((line) => line.accountId == fxAccount.id).single.debit,
        8);
    await expectBalanced();
  });

  test('month-end revaluation previews, reverses next period, and is idempotent',
      () async {
    await purchase(
      total: 100,
      paid: 0,
      date: DateTime(2026, 1, 31),
    );
    final preview = await db.previewOpenForeignBalances(
      asOf: DateTime(2026, 1, 31),
      rates: {currencyId: 52},
      userId: userId,
    );
    expect(preview.periodKey, '2026-01');
    expect(preview.invoiceCount, 1);
    expect(preview.totalAdjustment, 4);
    expect(preview.alreadyPosted, isFalse);

    final result = await db.revalueOpenForeignBalances(
      asOf: DateTime(2026, 1, 31),
      rates: {currencyId: 52},
      userId: userId,
    );
    final entriesAfterFirstRun = await db.select(db.journalEntries).get();
    final reversalLines = await (db.select(db.journalEntryLines)
          ..where((line) => line.entryId.equals(result.reversalJournalEntryId)))
        .get();
    expect(reversalLines.fold<double>(0, (sum, line) => sum + line.debit),
        closeTo(reversalLines.fold<double>(0, (sum, line) => sum + line.credit), 0.001));

    final retry = await db.revalueOpenForeignBalances(
      asOf: DateTime(2026, 1, 31),
      rates: {currencyId: 52},
      userId: userId,
    );
    expect(retry.journalEntryId, result.journalEntryId);
    expect(retry.reversalJournalEntryId, result.reversalJournalEntryId);
    expect((await db.select(db.journalEntries).get()).length,
        entriesAfterFirstRun.length);
    await expectBalanced();
  });

  test('local-currency settlement creates no realized FX entry', () async {
    final invoiceId = await purchase(total: 100, paid: 0, foreign: false);
    await db.addPurchasePayment(
      invoiceId: invoiceId,
      amount: 100,
      safeId: safeId,
      userId: userId,
      globalId: 'phase9-local-payment',
    );
    expect(await fxEntries(), isEmpty);
    await expectBalanced();
  });
}
