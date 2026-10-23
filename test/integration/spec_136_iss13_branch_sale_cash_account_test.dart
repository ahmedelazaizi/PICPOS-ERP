import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';

/// Spec 136 ISS-13 — a branch cash sale must autopost its cash debit to the
/// account linked to the safe the cash actually went into, NOT the admin cash
/// account.
///
/// Field incident: Aqaba branch sale `AQ-POS-10` (branch=2, cash_safe=6) posted
/// its cash leg to `111-00001 صندوق نقد الادارة` (admin) instead of the Aqaba
/// cash safe's account. Root cause: the autopost resolved the cash account from
/// the branch's *default* safe (whose link was NULL) and gave up to the global
/// admin account, even though the safe the cash physically landed in IS linked.
///
/// This test reproduces the exact shape: a branch with a DEFAULT cash safe that
/// has NO linked account plus the ACTUAL cash safe (linked to a branch account).
/// Before the fix the cash debit lands on the admin account; after the fix it
/// lands on the branch account.
void main() {
  late AppDatabase db;
  late int branchId;
  late int warehouseId;
  late int userId;
  late int productId;
  late int adminCashAccountId;
  late int branchCashAccountId;
  // ignore: unused_local_variable
  late int defaultUnlinkedSafeId;
  late int actualBranchSafeId;

  setUp(() async {
    db = AppDatabase.forTesting();

    // Role + user
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير ISS13', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'iss13_test',
      password: 'test123',
      displayName: 'ISS-13 Tester',
      roleId: roleId,
    );

    // The seeded default ('admin') cash account that the global fallback uses.
    adminCashAccountId = (await db.accountingDao
            .getAccountByCode(await db.accountingDao
                .getMappedAccountCode('cash', AccountingDao.accountPurposes['cash']!)))!
        .id;

    // A distinct branch cash account (e.g. 111-00003 صندوق نقد العقبة).
    branchCashAccountId = await db.into(db.accounts).insert(
          AccountsCompanion.insert(
            code: '111-00003',
            name: 'صندوق نقد العقبة',
            accountType: 'asset',
            accountNature: const Value('detail'),
            normalBalance: const Value('debit'),
          ),
        );

    // Branch + warehouse in that branch.
    branchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(name: 'فرع العقبة'),
        );
    warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'مخزن العقبة',
            branchId: Value(branchId),
          ),
        );

    // The branch's DEFAULT cash safe — deliberately UNLINKED (linkedAccountId
    // NULL). This is the safe the old branch-default resolver picked.
    defaultUnlinkedSafeId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'صندوق العقبة الافتراضي',
            safeType: const Value('cash'),
            branchId: Value(branchId),
            isDefault: const Value(true),
            isActive: const Value(true),
          ),
        );

    // The ACTUAL cash safe the operator collected into — linked to the branch
    // account. Not the default, so the old resolver never reached it.
    actualBranchSafeId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'صندوق نقد العقبة',
            safeType: const Value('cash'),
            branchId: Value(branchId),
            linkedAccountId: Value(branchCashAccountId),
            isDefault: const Value(false),
            isActive: const Value(true),
          ),
        );

    // Product with cost so COGS posts too.
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'ISS13-01',
        name: 'منتج ISS-13',
        salePrice: const Value(100.0),
        costPrice: const Value(40.0),
        trackInventory: const Value(true),
      ),
    );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 100.0,
      type: 'adjustment',
    );
  });

  tearDown(() async => db.close());

  test('branch cash sale debits the branch cash account, not admin cash',
      () async {
    // Sale of 1 unit @ 100, cash, collected into the ACTUAL branch safe.
    final invoiceId = await db.createSalesInvoice(
      invoiceNumber: 'AQ-POS-ISS13',
      warehouseId: warehouseId,
      userId: userId,
      branchId: branchId,
      subtotal: 100.0,
      discount: 0.0,
      tax: 0.0,
      total: 100.0,
      paid: 100.0,
      paymentMethod: 'cash',
      cashSafeId: actualBranchSafeId,
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 1.0,
          unitPrice: 100.0,
          total: 100.0,
          costPrice: const Value(40.0),
        ),
      ],
    );
    expect(invoiceId, isPositive);

    // The receipt landed in the actual branch safe (sanity).
    final receipt = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.referenceType.equals('sales_invoice') &
              t.referenceId.equals(invoiceId) &
              t.transactionType.equals('receipt')))
        .getSingle();
    expect(receipt.safeId, actualBranchSafeId);

    // The autoposted sale JE.
    final je = await (db.select(db.journalEntries)
          ..where((e) =>
              e.referenceType.equals('sale') & e.referenceId.equals(invoiceId)))
        .getSingle();
    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(je.id)))
        .get();

    // The single debit line of 100 is the cash leg.
    final cashLine = lines.firstWhere((l) => l.debit == 100.0);
    expect(cashLine.accountId, branchCashAccountId,
        reason: 'cash debit must hit the branch cash account (linked safe), '
            'not the admin cash account');
    expect(cashLine.accountId, isNot(adminCashAccountId),
        reason: 'regression guard: must not fall back to admin cash');
  });
}
