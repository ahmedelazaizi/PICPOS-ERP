import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/sales_repository.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
  });

  tearDown(() => db.close());

  test('draft journal entry does not change account balances', () async {
    final accounts = await (db.select(db.accounts)
          ..where((account) => account.accountNature.equals('detail')))
        .get();
    final before = {for (final account in accounts) account.id: account.balance};
    await db.createDraftJournalEntry(
      description: 'مسودة اختبار',
      date: DateTime.now(),
      lines: [
        JournalLine(accountId: accounts[0].id, debit: 25),
        JournalLine(accountId: accounts[1].id, credit: 25),
      ],
      createdBy: 1,
    );
    final after = await (db.select(db.accounts)
          ..where((account) => account.accountNature.equals('detail')))
        .get();
    expect({for (final account in after) account.id: account.balance}, before);
  });

  test('double reversal keeps one reversal and carries branch', () async {
    final accounts = await (db.select(db.accounts)
          ..where((account) => account.accountNature.equals('detail')))
        .get();
    // createJournalEntry validates explicit branch ids; make branch 7 a real
    // FK target so this test verifies propagation rather than fallback logic.
    await db.into(db.branches).insert(BranchesCompanion.insert(
      id: const Value(7),
      name: 'فرع اختبار ٧',
      globalId: const Value('phase2-branch-7'),
    ));
    final entryId = await db.createJournalEntry(
      description: 'قيد عكس اختباري',
      date: DateTime.now(),
      lines: [
        JournalLine(accountId: accounts[0].id, debit: 10),
        JournalLine(accountId: accounts[1].id, credit: 10),
      ],
      referenceType: 'phase2_test',
      referenceId: 42,
      branchId: 7,
      globalId: 'phase2-source-42',
      isAutoPosted: true,
    );
    await db.reverseTransaction(
      referenceType: 'phase2_test',
      referenceId: 42,
      descriptionPrefix: 'عكس',
      newReferenceType: 'phase2_reversal',
    );
    await db.reverseTransaction(
      referenceType: 'phase2_test',
      referenceId: 42,
      descriptionPrefix: 'عكس',
      newReferenceType: 'phase2_reversal',
    );
    final reversals = await (db.select(db.journalEntries)
          ..where((entry) => entry.globalId.equals('phase2-source-42-rev')))
        .get();
    expect(reversals, hasLength(1));
    expect(reversals.single.branchId, 7);
    expect(entryId, greaterThan(0));
  });

  Future<int> userWithModifyPermission() async {
    final roleId = await db.into(db.roles).insert(RolesCompanion.insert(
      name: 'دور تعديل الفاتورة',
      isSystemRole: const Value(false),
    ));
    final userId = await db.createUser(
      username: 'phase2-${DateTime.now().microsecondsSinceEpoch}',
      password: 'pw',
      displayName: 'مستخدم تعديل',
      roleId: roleId,
    );
    final permission = await (db.select(db.permissions)
          ..where((p) => p.code.equals(PermissionCodes.modifyLockedInvoice))
          ..limit(1))
        .getSingle();
    await db.addPermissionToRole(roleId, permission.id);
    return userId;
  }

  Future<Map<String, dynamic>> seedPostedSale({
    required String paymentMethod,
    required int userId,
    required double quantity,
  }) async {
    final warehouse = (await db.getDefaultWarehouse())!;
    final productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'PH2-${DateTime.now().microsecondsSinceEpoch}',
      name: 'منتج سلامة دفتر الأستاذ',
      salePrice: const Value(100.0),
      costPrice: const Value(0.0),
      trackInventory: const Value(false),
    ));
    final invoiceId = await db.createSalesInvoice(
      invoiceNumber: 'PH2-${DateTime.now().microsecondsSinceEpoch}',
      warehouseId: warehouse.id,
      userId: userId,
      subtotal: quantity * 100,
      discount: 0,
      tax: 0,
      total: quantity * 100,
      paid: paymentMethod == 'credit' ? 0 : quantity * 100,
      paymentMethod: paymentMethod,
      items: [SalesInvoiceItemsCompanion.insert(
        invoiceId: 0,
        productId: productId,
        quantity: quantity,
        unitPrice: 100,
        total: quantity * 100,
      )],
    );
    final invoice = await db.getSalesInvoiceById(invoiceId);
    if (paymentMethod == 'credit') {
      await db.autoPostCreditSale(invoice!);
    } else {
      await db.autoPostCashSale(invoice!);
    }
    return {
      'id': invoiceId,
      'warehouseId': warehouse.id,
      'productId': productId,
    };
  }

  Future<List<JournalEntryData>> saleEntries(int invoiceId) =>
      (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('sale') &
                e.referenceId.equals(invoiceId) &
                e.isPosted.equals(true) &
                e.isDeleted.equals(false)))
          .get();

  Future<List<JournalEntryData>> activeSaleEntries(int invoiceId) async {
    final entries = await saleEntries(invoiceId);
    final active = <JournalEntryData>[];
    for (final entry in entries) {
      final reversal = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('reversal') &
                e.referenceId.equals(entry.id) &
                e.isPosted.equals(true) &
                e.isDeleted.equals(false))
            ..limit(1))
          .getSingleOrNull();
      if (reversal == null) active.add(entry);
    }
    return active;
  }

  Future<void> expectTrialBalance() async {
    final result = await db.customSelect(
      'SELECT COALESCE(SUM(l.debit), 0) AS debit, '
      'COALESCE(SUM(l.credit), 0) AS credit '
      'FROM journal_entry_lines l JOIN journal_entries e ON e.id = l.entry_id '
      'WHERE e.is_posted = 1 AND e.is_deleted = 0',
      readsFrom: {db.journalEntryLines, db.journalEntries},
    ).getSingle();
    expect((result.data['debit'] as num).toDouble(),
        closeTo((result.data['credit'] as num).toDouble(), 0.01));
  }

  test('editing a locked cash sale preserves revenue through one reversal and repost', () async {
    final userId = await userWithModifyPermission();
    final sale = await seedPostedSale(
      paymentMethod: 'cash', userId: userId, quantity: 2);
    final original = (await saleEntries(sale['id'] as int)).single;
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    final repository = container.read(salesRepositoryProvider);
    await repository.updateFullSalesInvoice(
      invoiceId: sale['id'] as int,
      userId: userId,
      warehouseId: sale['warehouseId'] as int,
      paid: 300,
      paymentMethod: 'cash',
      items: [CartItemEntity(
        productId: sale['productId'] as int,
        productName: 'منتج سلامة دفتر الأستاذ',
        productCode: 'phase2',
        quantity: 3,
        unitPrice: 100,
      )],
    );
    final entries = await saleEntries(sale['id'] as int);
    final reversal = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals('reversal') &
              e.referenceId.equals(original.id) &
              e.isPosted.equals(true) &
              e.isDeleted.equals(false)))
        .get();
    expect(reversal, hasLength(1));
    expect(entries, hasLength(2));
    final activeEntries = await activeSaleEntries(sale['id'] as int);
    expect(activeEntries, hasLength(1));
    final active = activeEntries.single;
    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(active.id)))
        .get();
    expect(lines.fold<double>(0, (sum, l) => sum + l.debit), closeTo(300, 0.01));
    expect(lines.fold<double>(0, (sum, l) => sum + l.credit), closeTo(300, 0.01));
    await expectTrialBalance();
  });

  test('editing a locked sale twice leaves two reversals and one active sale entry', () async {
    final userId = await userWithModifyPermission();
    final sale = await seedPostedSale(
      paymentMethod: 'cash', userId: userId, quantity: 2);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    final repository = container.read(salesRepositoryProvider);
    Future<void> edit(double quantity) => repository.updateFullSalesInvoice(
          invoiceId: sale['id'] as int,
          userId: userId,
          warehouseId: sale['warehouseId'] as int,
          paid: quantity * 100,
          paymentMethod: 'cash',
          items: [CartItemEntity(
            productId: sale['productId'] as int,
            productName: 'منتج سلامة دفتر الأستاذ',
            productCode: 'phase2',
            quantity: quantity,
            unitPrice: 100,
          )],
        );
    await edit(3);
    await edit(4);
    final entries = await saleEntries(sale['id'] as int);
    expect(entries, hasLength(3));
    expect(await activeSaleEntries(sale['id'] as int), hasLength(1));
    final reversals = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals('reversal') &
              e.isPosted.equals(true) &
              e.isDeleted.equals(false)))
        .get();
    expect(reversals, hasLength(2));
    await expectTrialBalance();
  });

  test('payment-method change reverses the old sale and reposts the credit sale', () async {
    final userId = await userWithModifyPermission();
    final sale = await seedPostedSale(
      paymentMethod: 'cash', userId: userId, quantity: 2);
    final original = (await saleEntries(sale['id'] as int)).single;
    await db.updateSalesInvoicePayment(sale['id'] as int, 'credit', null);
    final entries = await saleEntries(sale['id'] as int);
    final reversal = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals('reversal') &
              e.referenceId.equals(original.id) &
              e.isPosted.equals(true) &
              e.isDeleted.equals(false)))
        .get();
    expect(reversal, hasLength(1));
    expect(entries, hasLength(2));
    final activeEntries = await activeSaleEntries(sale['id'] as int);
    expect(activeEntries, hasLength(1));
    final active = activeEntries.single;
    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(active.id)))
        .get();
    expect(lines.fold<double>(0, (sum, l) => sum + l.debit), closeTo(200, 0.01));
    await expectTrialBalance();
  });

  test('editing a locked sale without modifyLockedInvoice leaves the ledger unchanged', () async {
    final restrictedRole = await db.into(db.roles).insert(RolesCompanion.insert(
      name: 'دور بلا تعديل', isSystemRole: const Value(false)));
    final restrictedUser = await db.createUser(
      username: 'phase2-denied-${DateTime.now().microsecondsSinceEpoch}',
      password: 'pw', displayName: 'مستخدم بلا تعديل', roleId: restrictedRole);
    final sale = await seedPostedSale(
      paymentMethod: 'cash', userId: restrictedUser, quantity: 2);
    final before = await db.select(db.journalEntries).get();
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    final repository = container.read(salesRepositoryProvider);
    await expectLater(
      () => repository.updateFullSalesInvoice(
        invoiceId: sale['id'] as int,
        userId: restrictedUser,
        warehouseId: sale['warehouseId'] as int,
        paid: 300,
        paymentMethod: 'cash',
        items: [CartItemEntity(
          productId: sale['productId'] as int,
          productName: 'منتج سلامة دفتر الأستاذ',
          productCode: 'phase2', quantity: 3, unitPrice: 100,
        )],
      ),
      throwsA(isA<PermissionDeniedException>()),
    );
    expect(await db.select(db.journalEntries).get(), hasLength(before.length));
  });

  test('fiscal year is selected from the journal date', () async {
    final now = DateTime.now();
    final prior = DateTime(now.year - 1, 6, 15);
    var fiscalYear = await db.getFiscalYearByDate(prior);
    if (fiscalYear == null) {
      await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(
        name: 'سنة الاختبار السابقة',
        startDate: DateTime(prior.year, 1, 1),
        endDate: DateTime(prior.year, 12, 31, 23, 59, 59),
      ));
      fiscalYear = await db.getFiscalYearByDate(prior);
    }
    expect(fiscalYear, isNotNull);
    final accounts = await (db.select(db.accounts)
          ..where((account) => account.accountNature.equals('detail')))
        .get();
    final entryId = await db.createJournalEntry(
      description: 'قيد مؤرخ سابقاً',
      date: prior,
      lines: [
        JournalLine(accountId: accounts[0].id, debit: 4),
        JournalLine(accountId: accounts[1].id, credit: 4),
      ],
      referenceType: 'phase2_fiscal_year',
    );
    final entry = await (db.select(db.journalEntries)
          ..where((row) => row.id.equals(entryId)))
        .getSingle();
    expect(entry.fiscalYearId, fiscalYear!.id);
  });
}
