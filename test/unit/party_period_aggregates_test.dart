// تجميعُ فترةٍ لكلّ طرف — `getCustomerPeriodAggregates` / `getSupplierPeriodAggregates`.
//
// ═══ ما يحمي هذا الملفّ ═══
//
// ثلاثةُ تقاريرَ تقوم على هذين الاستعلامَين: «تحليل سلوك العملاء» و«تقسيم
// العملاء (RFM)» و«تحليل سلوك الموردين». وثلاثةُ أعطابٍ تمرّ صامتةً لو لم
// تُقَس:
//
//  ‏١) **التاريخُ ثوانٍ لا مِلّي.** `dateVar` يخزّن ثوانيَ الحِقبة، فقراءةُ
//     `MAX(invoice_date)` بـ`fromMillisecondsSinceEpoch` مباشرةً تُوقع كلَّ
//     تاريخٍ في يناير ١٩٧٠. والتقريرُ لا ينهار — يعرض «آخرُ تعاملٍ منذ
//     ٢٠٦٠٠ يوم» ويبدو رقماً. وهذا **جوهرُ RFM**: الحداثةُ هي الـR.
//  ‏٢) **المرتجعُ يُحتسَب بيعاً.** بلا `_saleReturnExclusion` يُعَدُّ المرتجعُ
//     فاتورةً في التكرار وتُضاف قيمتُه إلى المجموع — فيتصدّر عميلٌ يُرجع
//     أكثرَ ممّا يشتري.
//  ‏٣) **البيعُ النقديُّ العابرُ يصنع عميلاً وهميّاً.** الضمُّ داخليٌّ عمداً؛
//     لو صار خارجيّاً لتجمّعت كلُّ الفواتير بلا عميلٍ في صفٍّ واحدٍ يتصدّر
//     كلَّ تقرير.
//
// والمدى يُختبَر أيضاً: فاتورةٌ خارجَه لا تُحتسَب.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;
  late int aliceId;
  late int bobId;
  late int supplierId;

  // المدى المقيس: أغسطس ٢٠٢٦ كلُّه.
  final from = DateTime(2026, 8, 1);
  final to = DateTime(2026, 8, 31, 23, 59, 59);

  setUp(() async {
    db = AppDatabase.forTesting();
    warehouseId = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'المخزن الرئيسي'));
    userId = await db.into(db.users).insert(
          UsersCompanion.insert(
            username: 'cashier',
            passwordHash: 'x',
            displayName: 'كاشير',
          ),
        );
    aliceId = await db
        .into(db.parties)
        .insert(PartiesCompanion.insert(name: 'مطعم النيل'));
    bobId = await db
        .into(db.parties)
        .insert(PartiesCompanion.insert(name: 'بقالة الحرية'));
    supplierId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'مورّد الألبان',
            isSupplier: const Value(true),
          ),
        );
  });

  tearDown(() => db.close());

  Future<void> sale({
    int? customerId,
    required DateTime at,
    required double total,
    double paid = 0,
    String? saleType,
    required String number,
  }) async {
    await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: number,
            warehouseId: warehouseId,
            userId: userId,
            invoiceDate: at,
            customerId: Value(customerId),
            subtotal: Value(total),
            total: Value(total),
            paid: Value(paid),
            saleType: Value.absentIfNull(saleType),
          ),
        );
  }

  Future<void> purchase({
    required DateTime at,
    required double total,
    double paid = 0,
    required String number,
  }) async {
    await db.into(db.purchaseInvoices).insert(
          PurchaseInvoicesCompanion.insert(
            invoiceNumber: number,
            supplierId: supplierId,
            warehouseId: warehouseId,
            invoiceDate: at,
            subtotal: Value(total),
            total: Value(total),
            paid: Value(paid),
          ),
        );
  }

  group('العملاء', () {
    test('يجمع لكلّ عميلٍ عدَّه ومجموعَه ومدفوعَه', () async {
      await sale(
          customerId: aliceId,
          at: DateTime(2026, 8, 5),
          total: 100,
          paid: 100,
          number: 'S1');
      await sale(
          customerId: aliceId,
          at: DateTime(2026, 8, 20),
          total: 300,
          paid: 100,
          number: 'S2');
      await sale(
          customerId: bobId,
          at: DateTime(2026, 8, 9),
          total: 50,
          paid: 50,
          number: 'S3');

      final rows =
          await db.getCustomerPeriodAggregates(from: from, to: to);

      expect(rows, hasLength(2));
      // مرتَّبةٌ بالقيمة تنازليّاً.
      final alice = rows.first;
      expect(alice.partyName, 'مطعم النيل');
      expect(alice.invoiceCount, 2);
      expect(alice.totalValue, 400);
      expect(alice.paidValue, 200);
      expect(alice.unpaidValue, 200);
      expect(alice.averageValue, 200);

      expect(rows[1].partyName, 'بقالة الحرية');
      expect(rows[1].invoiceCount, 1);
    });

    test('آخرُ تعاملٍ وأوّلُه بتاريخٍ حقيقيٍّ لا يناير ١٩٧٠', () async {
      await sale(
          customerId: aliceId,
          at: DateTime(2026, 8, 5),
          total: 100,
          number: 'S1');
      await sale(
          customerId: aliceId,
          at: DateTime(2026, 8, 20),
          total: 300,
          number: 'S2');

      final rows =
          await db.getCustomerPeriodAggregates(from: from, to: to);
      final alice = rows.single;

      expect(alice.firstInvoiceDate, isNotNull);
      expect(alice.lastInvoiceDate, isNotNull);
      // ⚠️ الفحصُ الحاسم: السنةُ ٢٠٢٦ لا ١٩٧٠. الضربُ في ألفٍ هو الفرق.
      expect(alice.lastInvoiceDate!.year, 2026);
      expect(alice.lastInvoiceDate!.month, 8);
      expect(alice.lastInvoiceDate!.day, 20);
      expect(alice.firstInvoiceDate!.day, 5);
    });

    test('المرتجعُ لا يُحتسَب فاتورةَ بيع', () async {
      await sale(
          customerId: aliceId,
          at: DateTime(2026, 8, 5),
          total: 100,
          number: 'S1');
      await sale(
          customerId: aliceId,
          at: DateTime(2026, 8, 6),
          total: 40,
          saleType: 'return',
          number: 'R1');

      final alice =
          (await db.getCustomerPeriodAggregates(from: from, to: to)).single;
      expect(alice.invoiceCount, 1, reason: 'المرتجعُ عُدَّ فاتورةَ بيع');
      expect(alice.totalValue, 100, reason: 'قيمةُ المرتجع دخلت المجموع');
    });

    test('البيعُ بلا عميلٍ لا يصنع صفّاً', () async {
      await sale(at: DateTime(2026, 8, 5), total: 900, number: 'S1');
      await sale(
          customerId: bobId,
          at: DateTime(2026, 8, 5),
          total: 50,
          number: 'S2');

      final rows =
          await db.getCustomerPeriodAggregates(from: from, to: to);
      expect(rows, hasLength(1));
      expect(rows.single.partyName, 'بقالة الحرية');
      expect(rows.single.totalValue, 50,
          reason: 'البيعُ العابرُ تسرّب إلى عميلٍ مسجَّل');
    });

    test('ما خارجَ المدى لا يُحتسَب', () async {
      await sale(
          customerId: aliceId,
          at: DateTime(2026, 7, 20),
          total: 500,
          number: 'S0');
      await sale(
          customerId: aliceId,
          at: DateTime(2026, 8, 5),
          total: 100,
          number: 'S1');

      final alice =
          (await db.getCustomerPeriodAggregates(from: from, to: to)).single;
      expect(alice.invoiceCount, 1);
      expect(alice.totalValue, 100);
      expect(alice.firstInvoiceDate!.month, 8);
    });

    test('مدىً بلا فواتيرَ يعود فارغاً لا صفراً كاذباً', () async {
      final rows = await db.getCustomerPeriodAggregates(
          from: DateTime(2026, 1, 1), to: DateTime(2026, 1, 31));
      expect(rows, isEmpty);
    });
  });

  group('الموردون', () {
    test('يجمع لكلّ مورّدٍ عدَّه ومجموعَه وتواريخَه', () async {
      await purchase(at: DateTime(2026, 8, 3), total: 700, paid: 300, number: 'P1');
      await purchase(at: DateTime(2026, 8, 18), total: 300, paid: 300, number: 'P2');

      final row =
          (await db.getSupplierPeriodAggregates(from: from, to: to)).single;
      expect(row.partyName, 'مورّد الألبان');
      expect(row.invoiceCount, 2);
      expect(row.totalValue, 1000);
      expect(row.paidValue, 600);
      expect(row.unpaidValue, 400);
      expect(row.averageValue, 500);
      // نفسُ مصيدة الثواني.
      expect(row.lastInvoiceDate!.year, 2026);
      expect(row.lastInvoiceDate!.day, 18);
      expect(row.firstInvoiceDate!.day, 3);
    });

    test('ما خارجَ المدى لا يُحتسَب', () async {
      await purchase(at: DateTime(2026, 6, 1), total: 900, number: 'P0');
      final rows = await db.getSupplierPeriodAggregates(from: from, to: to);
      expect(rows, isEmpty);
    });
  });
}
