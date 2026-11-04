// فهرسا تفرّد رقم الفاتورة على PostgreSQL (نفس عقد نسخة SQLite):
// ينشأ بلا مكررات ويمنع الحيّ المكرر، يتخطى بلا تعديل مع مكررات قديمة،
// ينشأ بعد التنظيف، والنطاق (محذوف/مرتجع/مورد آخر)، وتخطّي المولِّد، وأن
// خرق الفهرس داخل savepoint يُلتقط دون إجهاض المعاملة الأم (سلوك السحب).
@Tags(['pg'])
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/migrations/invoice_number_unique_index.dart';

import '_support/pg_fixture.dart';

void main() {
  group('uniqueness of invoice_number on PostgreSQL', () {
    late PgTestFixture fx;
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

    Future<void> resetState() async {
      await db.customStatement(
          'DROP INDEX IF EXISTS $kSalesInvoiceNumberUniqueIndexName');
      await db.customStatement(
          'DROP INDEX IF EXISTS $kPurchaseInvoiceNumberUniqueIndexName');
      await db.customStatement('DELETE FROM purchase_invoices');
      await db.customStatement('DELETE FROM sales_invoices');
      await db.customStatement('DELETE FROM document_sequences');
      DiagnosticLogger.enableTestMode();
    }

    setUpAll(() async {
      fx = await bootPgTestSchema();
      db = fx.db;
      await db.customSelect('SELECT 1').get();
      warehouseId =
          (await db.customSelect('SELECT id FROM warehouses LIMIT 1').getSingle())
              .read<int>('id');
      userId = (await db.customSelect('SELECT id FROM users LIMIT 1').getSingle())
          .read<int>('id');
      supA = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'A',
          isSupplier: const Value(true),
          globalId: const Value('g-a')));
      supB = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'B',
          isSupplier: const Value(true),
          globalId: const Value('g-b')));
    });

    tearDownAll(() async => fx.tearDown());
    setUp(resetState);

    test('no duplicates: both indexes are created, partial, and block live dups',
        () async {
      await insertSale('POS-1');
      await insertPurchase('S-1', supA);

      final r = await ensureInvoiceNumberUniqueIndexes(db);
      expect(r['sales_invoices'], InvoiceNumberIndexOutcome.ready);
      expect(r['purchase_invoices'], InvoiceNumberIndexOutcome.ready);

      final defs = await db.customSelect(
          "SELECT indexname, indexdef FROM pg_indexes "
          "WHERE indexname IN ('$kSalesInvoiceNumberUniqueIndexName', "
          "'$kPurchaseInvoiceNumberUniqueIndexName')").get();
      expect(defs.length, 2);
      for (final d in defs) {
        expect(d.read<String>('indexdef'), contains('UNIQUE'));
        expect(d.read<String>('indexdef'), contains('WHERE'));
      }

      await expectLater(insertSale('POS-1'), throwsA(anything));
      await expectLater(insertPurchase('S-1', supA), throwsA(anything));
      expect((await ensureInvoiceNumberUniqueIndexes(db)).values.toSet(),
          {InvoiceNumberIndexOutcome.ready});
    });

    test('scope: soft-deleted, return and other-supplier rows are allowed',
        () async {
      await ensureInvoiceNumberUniqueIndexes(db);
      await insertSale('POS-1');
      await insertSale('POS-1', deleted: true);
      await insertSale('POS-1', saleType: 'return');
      await insertPurchase('1001', supA);
      await insertPurchase('1001', supB);
      await insertPurchase('1001', supA, deleted: true);
      expect((await numbers('sales_invoices')).length, 3);
      expect((await numbers('purchase_invoices')).length, 3);
    });

    test('legacy duplicates: skipped without failure/change, then created after cleanup',
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
        final r = await ensureInvoiceNumberUniqueIndexes(db);
        expect(r['sales_invoices'], InvoiceNumberIndexOutcome.skippedDuplicates);
        expect(r['purchase_invoices'],
            InvoiceNumberIndexOutcome.skippedDuplicates);
      }
      expect(await numbers('sales_invoices'), salesBefore);
      expect(await numbers('purchase_invoices'), purBefore);

      final warn = DiagnosticLogger.testLog
          .firstWhere((l) => l.contains('uq_sales_invoices_number_live'));
      expect(warn, contains('2 duplicated number group(s)'));
      expect(warn, contains('3 surplus row(s)'));
      expect(warn, contains('POS-7'));
      expect(warn, isNot(contains('POS-9')));

      await db.customStatement(
          "UPDATE sales_invoices SET is_deleted = TRUE, deleted_at = 1 "
          "WHERE id IN (SELECT id FROM sales_invoices "
          "WHERE invoice_number = 'POS-7' ORDER BY id LIMIT 2)");
      await db.customStatement(
          "UPDATE sales_invoices SET is_deleted = TRUE, deleted_at = 1 "
          "WHERE id = (SELECT MAX(id) FROM sales_invoices "
          "WHERE invoice_number = 'POS-8')");
      await db.customStatement(
          "UPDATE purchase_invoices SET is_deleted = TRUE, deleted_at = 1 "
          "WHERE id = (SELECT MAX(id) FROM purchase_invoices)");
      final r = await ensureInvoiceNumberUniqueIndexes(db);
      expect(r.values.toSet(), {InvoiceNumberIndexOutcome.ready});
      await expectLater(insertSale('POS-9'), throwsA(anything));
    });

    test('generator skips a live number and advances the counter', () async {
      await db.customStatement(
          "INSERT INTO document_sequences (prefix, next_value) VALUES ('POS', 1)");
      await insertSale('POS-1');
      await insertSale('POS-2');
      final n = await db.transaction(() => db.generateInvoiceNumber('Receipt'));
      expect(n, 'POS-3');
      expect(await db.peekNumberingCounter('POS'), 4);
    });

    test('a unique violation inside a nested savepoint does not abort the parent',
        () async {
      await ensureInvoiceNumberUniqueIndexes(db);
      await insertSale('POS-1');
      await db.transaction(() async {
        Object? failure;
        try {
          await db.transaction(() => insertSale('POS-1'));
        } catch (e) {
          failure = e;
        }
        expect(failure, isNotNull);
        await insertSale('POS-2'); // parent txn is still usable
      });
      expect(await numbers('sales_invoices'), ['POS-1', 'POS-2']);
    });
  });
}
