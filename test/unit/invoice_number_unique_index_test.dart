// فهرسا تفرّد رقم الفاتورة — SQLite.
// يغطّي: ينشأ بلا مكررات ويمنع المكرر، يتخطى بأمان مع مكررات قديمة (بلا
// تعديل ولا فشل ولا بيانات حساسة في السجل)، ينشأ تلقائياً بعد التنظيف،
// نطاق الفهرس (محذوف/مرتجع/مورد آخر)، وتخطّي المولِّد للأرقام المحجوزة.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/migrations/invoice_number_unique_index.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;
  late int supA;
  late int supB;
  var seq = 0;

  Future<void> insertSale(String number,
      {String saleType = 'default', bool deleted = false}) {
    seq++;
    return db.customUpdate(
      'INSERT INTO sales_invoices (invoice_number, warehouse_id, user_id, '
      'invoice_date, sale_type, is_deleted, deleted_at, global_id) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      variables: [
        Variable.withString(number),
        Variable.withInt(warehouseId),
        Variable.withInt(userId),
        Variable.withDateTime(DateTime(2026, 1, 1)),
        Variable.withString(saleType),
        Variable.withBool(deleted),
        deleted
            ? Variable.withDateTime(DateTime(2026, 1, 2))
            : const Variable<DateTime>(null),
        Variable.withString('gid-s-$seq'),
      ],
      updates: {db.salesInvoices},
    );
  }

  Future<void> insertPurchase(String number, int supplierId,
      {bool deleted = false}) {
    seq++;
    return db.customUpdate(
      'INSERT INTO purchase_invoices (invoice_number, supplier_id, '
      'warehouse_id, invoice_date, is_deleted, deleted_at, global_id) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      variables: [
        Variable.withString(number),
        Variable.withInt(supplierId),
        Variable.withInt(warehouseId),
        Variable.withDateTime(DateTime(2026, 1, 1)),
        Variable.withBool(deleted),
        deleted
            ? Variable.withDateTime(DateTime(2026, 1, 2))
            : const Variable<DateTime>(null),
        Variable.withString('gid-p-$seq'),
      ],
      updates: {db.purchaseInvoices},
    );
  }

  Future<List<String>> numbers(String table) async => (await db
          .customSelect('SELECT invoice_number AS n FROM $table ORDER BY id')
          .get())
      .map((r) => r.read<String>('n'))
      .toList();

  setUp(() async {
    DiagnosticLogger.enableTestMode();
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    warehouseId = (await db.customSelect('SELECT id FROM warehouses LIMIT 1').getSingle())
        .read<int>('id');
    userId = (await db.customSelect('SELECT id FROM users LIMIT 1').getSingle())
        .read<int>('id');
    supA = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'A', isSupplier: const Value(true), globalId: const Value('g-a')));
    supB = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'B', isSupplier: const Value(true), globalId: const Value('g-b')));
    // The deferred startup phase may already have installed the indexes.
    await db.customStatement(
        'DROP INDEX IF EXISTS $kSalesInvoiceNumberUniqueIndexName');
    await db.customStatement(
        'DROP INDEX IF EXISTS $kPurchaseInvoiceNumberUniqueIndexName');
  });

  tearDown(() async => db.close());

  test('بلا مكررات: ينشأ الفهرسان ويمنعان المكرر الحيّ', () async {
    await insertSale('POS-1');
    await insertPurchase('S-1', supA);

    final r = await ensureInvoiceNumberUniqueIndexes(db);
    expect(r['sales_invoices'], InvoiceNumberIndexOutcome.ready);
    expect(r['purchase_invoices'], InvoiceNumberIndexOutcome.ready);

    await expectLater(insertSale('POS-1'), throwsA(anything));
    await expectLater(insertPurchase('S-1', supA), throwsA(anything));

    // idempotent
    expect((await ensureInvoiceNumberUniqueIndexes(db)).values.toSet(),
        {InvoiceNumberIndexOutcome.ready});
  });

  test('النطاق: المحذوف والمرتجع ومورد آخر مسموحة', () async {
    await ensureInvoiceNumberUniqueIndexes(db);
    await insertSale('POS-1');
    await insertSale('POS-1', deleted: true); // soft-deleted
    await insertSale('POS-1', saleType: 'return'); // other counter
    await insertPurchase('1001', supA);
    await insertPurchase('1001', supB); // per-supplier scope
    await insertPurchase('1001', supA, deleted: true);
    expect((await numbers('sales_invoices')).length, 3);
    expect((await numbers('purchase_invoices')).length, 3);
  });

  test('مكررات قديمة: يتخطى بلا فشل ولا تعديل ويسجّل تحذيراً، ثم ينشأ بعد التنظيف',
      () async {
    await insertSale('POS-7');
    await insertSale('POS-7');
    await insertSale('POS-7');
    await insertSale('POS-8');
    await insertSale('POS-8');
    await insertSale('POS-9');
    await insertPurchase('X-1', supA);
    await insertPurchase('X-1', supA);
    final salesBefore = await numbers('sales_invoices');
    final purBefore = await numbers('purchase_invoices');

    for (var i = 0; i < 2; i++) {
      // every boot retries, never throws
      final r = await ensureInvoiceNumberUniqueIndexes(db);
      expect(r['sales_invoices'], InvoiceNumberIndexOutcome.skippedDuplicates);
      expect(
          r['purchase_invoices'], InvoiceNumberIndexOutcome.skippedDuplicates);
    }

    expect(await numbers('sales_invoices'), salesBefore);
    expect(await numbers('purchase_invoices'), purBefore);

    final warn = DiagnosticLogger.testLog
        .where((l) => l.contains('INVOICE-NUMBER-UNIQUE'))
        .toList();
    expect(warn, isNotEmpty);
    final salesWarn = warn.firstWhere((l) => l.contains('sales_invoices'));
    expect(salesWarn, contains('2 duplicated number group(s)'));
    expect(salesWarn, contains('3 surplus row(s)'));
    expect(salesWarn, contains('POS-7'));
    expect(salesWarn, contains('POS-8'));
    expect(salesWarn, isNot(contains('POS-9')));

    // Owner cleans: soft-delete the surplus rows → next boot installs them.
    await db.customStatement(
        "UPDATE sales_invoices SET is_deleted = 1, deleted_at = 1 "
        "WHERE id IN (SELECT id FROM sales_invoices WHERE invoice_number = 'POS-7' "
        "ORDER BY id LIMIT 2)");
    await db.customStatement(
        "UPDATE sales_invoices SET is_deleted = 1, deleted_at = 1 "
        "WHERE id = (SELECT MAX(id) FROM sales_invoices WHERE invoice_number = 'POS-8')");
    await db.customStatement(
        "UPDATE purchase_invoices SET is_deleted = 1, deleted_at = 1 "
        "WHERE id = (SELECT MAX(id) FROM purchase_invoices)");
    final r = await ensureInvoiceNumberUniqueIndexes(db);
    expect(r.values.toSet(), {InvoiceNumberIndexOutcome.ready});
    await expectLater(insertSale('POS-9'), throwsA(anything));
  });

  test('المولِّد يتخطّى رقماً حيّاً محجوزاً ويقدّم العدّاد', () async {
    await db.customStatement(
        "INSERT INTO document_sequences (prefix, next_value) VALUES ('POS', 1)");
    await insertSale('POS-1');
    await insertSale('POS-2');
    final n = await db.transaction(() => db.generateInvoiceNumber('Receipt'));
    expect(n, 'POS-3');
    expect(await db.peekNumberingCounter('POS'), 4);

    // a soft-deleted holder does not block reuse
    await db.customStatement(
        "UPDATE document_sequences SET next_value = 2 WHERE prefix = 'POS'");
    await db.customStatement(
        "UPDATE sales_invoices SET is_deleted = 1, deleted_at = 1 "
        "WHERE invoice_number = 'POS-2'");
    await db.customStatement(
        "UPDATE sales_invoices SET is_deleted = 1, deleted_at = 1 "
        "WHERE invoice_number = 'POS-3'");
    expect(await db.transaction(() => db.generateInvoiceNumber('Receipt')),
        'POS-2');
  });

  test('خرق الفهرس داخل معاملة يُلتقط ولا يُسقط بقية الدفعة (سلوك السحب)',
      () async {
    await ensureInvoiceNumberUniqueIndexes(db);
    await insertSale('POS-1');
    await db.transaction(() async {
      Object? failure;
      try {
        await insertSale('POS-1');
      } catch (e) {
        failure = e;
      }
      expect(failure, isNotNull);
      await insertSale('POS-2'); // later row of the same chunk still lands
    });
    expect(await numbers('sales_invoices'), ['POS-1', 'POS-2']);
  });
}
