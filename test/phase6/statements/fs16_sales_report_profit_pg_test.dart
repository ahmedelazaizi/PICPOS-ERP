// FS-16 — تكافؤ PostgreSQL/SQLite لقراءة قيد المرتجع في تقرير المبيعات.
//
// يثبت أن `getReturnLedgerAmountsForInvoices` (‏الشكلان: قيدٌ على الأصل
// مباشرةً، وقيدٌ على مستند `sale_type='return'` المربوط بالملاحظة) و
// `getReturnedAmountsForInvoices` بعد نقل SQL الربط إلى
// `_salesReturnDocLinkSql` يعطيان الأرقامَ نفسَها على الخلفيّتين.
//
// تشغيل: Invoke-FlutterTest <الملف> -PgDsn postgres://postgres@127.0.0.1:<58xxx>/postgres
// ignore_for_file: avoid_print
@Tags(['pg'])
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';

import '../../integration_pg/_support/pg_fixture.dart';

typedef _Result = ({
  Map<int, double> refunds,
  Map<int, ({double cogs, double vat})> ledger,
});

/// يبني على [db] بيعتين ومرتجعَين ويعيد خرجَ الدالّتين **بمفاتيحَ نسبية**
/// (0 = الفاتورة الأولى، 1 = الثانية) لأن المعرّفات تختلف بين الخلفيّتين.
Future<_Result> _scenario(AppDatabase db) async {
  await db.syncDefaultAccounts();
  final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'fs16-pg', isSystemRole: const Value(false)));
  final userId = await db.createUser(
      username: 'fs16-pg',
      password: 'pg-test-only',
      displayName: 'FS16 PG',
      roleId: roleId);
  final wh = (await db.getDefaultWarehouse())!.id;
  final safe = (await db.getDefaultSafeByType('cash'))!.id;
  await db.adjustSafeBalance(safe, 1000);
  await db.openShift(userId, 0);
  final p = await db.insertProduct(ProductsCompanion.insert(
      code: 'FS16-PG',
      name: 'FS16 PG',
      salePrice: const Value(100),
      costPrice: const Value(60),
      trackInventory: const Value(true)));
  await db.adjustStock(
      productId: p, warehouseId: wh, quantity: 10, type: 'purchase', unitCost: 60);

  Future<int> sell(double qty) => db.createSalesInvoice(
        warehouseId: wh,
        userId: userId,
        subtotal: qty * 100,
        discount: 0,
        tax: qty * 14,
        total: qty * 114,
        paid: qty * 114,
        paymentMethod: 'cash',
        cashSafeId: safe,
        items: [
          SalesInvoiceItemsCompanion(
            productId: Value(p),
            quantity: Value(qty),
            unitPrice: const Value(100),
            total: Value(qty * 114),
            taxAmount: Value(qty * 14),
            costPrice: const Value(60),
          ),
        ],
      );
  final a = await sell(3);
  final b = await sell(2);

  // الشكلُ ب: مستندُ مرتجعٍ مربوطٌ بـ a عبر الملاحظة (يرحّل قيدَه بنفسه).
  final orig = (await db.getSalesInvoiceById(a))!;
  await db.createSalesInvoice(
    warehouseId: wh,
    userId: userId,
    subtotal: 100,
    discount: 0,
    tax: 14,
    total: 114,
    paid: 114,
    paymentMethod: 'cash',
    cashSafeId: safe,
    saleType: 'return',
    notes: localReturnLinkNote(a, originalGlobalId: orig.globalId),
    items: [
      SalesInvoiceItemsCompanion(
        productId: Value(p),
        quantity: const Value(1),
        unitPrice: const Value(100),
        total: const Value(114),
        taxAmount: const Value(14),
        costPrice: const Value(60),
      ),
    ],
  );

  // الشكلُ أ: قيدُ مرتجعٍ مربوطٌ بـ b مباشرةً (كما يكتبه `autoPostSalesReturn`).
  Future<int> acc(String code) async => (await db.getAccountByCode(code))!.id;
  await db.createJournalEntry(
    description: 'FS16 PG shape A return',
    date: DateTime.now(),
    referenceType: 'sales_return',
    referenceId: b,
    globalId: 'fs16-pg-shape-a',
    lines: [
      JournalLine(accountId: await acc('4211'), debit: 100),
      JournalLine(accountId: await acc('2121'), debit: 14),
      JournalLine(accountId: await acc('1111'), credit: 114),
      JournalLine(accountId: await acc('1136'), debit: 60),
      JournalLine(accountId: await acc('5211'), credit: 60),
    ],
  );

  final refunds = await db.getReturnedAmountsForInvoices([a, b]);
  final ledger = await db.getReturnLedgerAmountsForInvoices([a, b]);
  int rel(int id) => id == a ? 0 : (id == b ? 1 : -1);
  return (
    refunds: {for (final e in refunds.entries) rel(e.key): e.value},
    ledger: {for (final e in ledger.entries) rel(e.key): e.value},
  );
}

void main() {
  test('FS-16 return ledger amounts: PostgreSQL == SQLite',
      skip: 'requires isolated PostgreSQL fixture', () async {
    final lite = AppDatabase.forTesting();
    addTearDown(lite.close);
    final sqlite = await _scenario(lite);

    final fixture = await bootPgTestSchema();
    addTearDown(fixture.tearDown);
    final pg = await _scenario(fixture.db);
    print('FS16-PG sqlite=$sqlite pg=$pg');

    for (final r in [sqlite, pg]) {
      expect(r.refunds.keys, [0], reason: 'مستندُ المرتجع وحدَه يُجمع ردّاً');
      expect(r.refunds[0], closeTo(114, 0.005));
      expect(r.ledger.keys.toSet(), {0, 1});
      expect(r.ledger[0]!.cogs, closeTo(60, 0.005));
      expect(r.ledger[0]!.vat, closeTo(14, 0.005));
      expect(r.ledger[1]!.cogs, closeTo(60, 0.005));
      expect(r.ledger[1]!.vat, closeTo(14, 0.005));
    }
  });
}
