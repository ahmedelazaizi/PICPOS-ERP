// عدّاداتُ حالةِ فواتير المشتريات ومرتجعاتُها في `getPurchaseInvoiceSummary`.
//
// شرائحُ الحالة في شريط ترشيح المشتريات تعرض عدّاداً بجانب كلّ حالة، ومصدرُه
// لا بدّ أن يكون تجميعَ SQL على **كلّ** المطابق: `watchAllPurchases` يسقّف
// بـ٥٠٠ صفّ، فالعدُّ من القائمة المحمَّلة يعطي رقماً أقلَّ من الحقيقة بلا ما
// يشي بذلك — وهو أسوأُ من غياب العدّاد لأنه يبدو دقيقاً.
//
// ⚠️ **وهذا الملفُّ ليس نسخةً من توأمِ المبيعات** — يقيس ما تباعد فيه:
//
//  ‏١) **العدُّ على عمود `status` لا على `paid >= total`.** مرشِّحُ الشاشة
//     (`_applyFilters`) يقارن `inv.status` المشتقَّ من العمود عبر
//     `InvoiceEntity._mapStatus`. فلو عُدَّ بالمبلغ — كما في المبيعات —
//     لأعطت الشريحةُ عدداً لا يطابق ما تُظهره حين تُنقَر: عدّادٌ يكذب على
//     مرشِّحه. وهذا هو الاختبارُ الحاسم في هذا الملفّ.
//
//  ‏٢) **«غيرُ المسدَّد» يُعَدُّ بالنفي** — حالةُ الافتراض في `_mapStatus`.
//     فأيُّ `status` مجهولٍ أو فارغٍ يقع فيها، ولا يسقط صفٌّ من العدّ وهو
//     معروضٌ في القائمة.
//
//  ‏٣) **المرتجعاتُ تُنسَب لنافذةِ الفاتورة الأصليّة** لا لتاريخِ المرتجع —
//     لأن `_applyFilters` يجمعها هكذا بالضبط، فلو نُسبت لتاريخِ حدوثها
//     لخالفت البطاقةُ مجموعَ الصفوفِ تحتها.
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    // ‏`forTesting()` يُنفِذ المفاتيح الأجنبية ولا يزرع شيئاً، فالتجهيزةُ
    // تزرع الطرفَين الذين تشير إليهما كلُّ فاتورة.
    await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(name: 'مخزن الاختبار'),
        );
    await db.into(db.parties).insert(
          PartiesCompanion.insert(name: 'مورد الاختبار'),
        );
  });

  // ⚠️ لا `db.close()` في tearDown — يعلّق مؤقّتَ drift في المنطقة الوهميّة
  // فيتجمّد الاختبار (درسٌ موثَّقٌ في المستودع).
  tearDown(() async {});

  final day = DateTime(2026, 8, 10);
  var seq = 0;

  Future<int> seedInvoice({
    required double total,
    required double paid,
    String? status,
    DateTime? on,
  }) async {
    seq++;
    return db.into(db.purchaseInvoices).insert(
          PurchaseInvoicesCompanion.insert(
            invoiceNumber: 'PINV-$seq',
            supplierId: 1,
            warehouseId: 1,
            invoiceDate: on ?? day,
            total: Value(total),
            paid: Value(paid),
            status: status == null ? const Value.absent() : Value(status),
          ),
        );
  }

  Future<PurchaseInvoiceSummary> summarize({
    DateTime? from,
    DateTime? to,
  }) =>
      db.getPurchaseInvoiceSummary(
        from: from ?? DateTime(2026, 8, 1),
        to: to ?? DateTime(2026, 8, 31),
      );

  group('عدّاداتُ الحالة', () {
    test('التقسيمُ الثلاثيُّ لا يتداخل ولا يُسقط صفّاً', () async {
      await seedInvoice(total: 100, paid: 100, status: 'paid');
      await seedInvoice(total: 100, paid: 40, status: 'partial');
      await seedInvoice(total: 100, paid: 0, status: 'pending');

      final s = await summarize();

      expect(s.paidCount, 1);
      expect(s.partialCount, 1);
      expect(s.unpaidCount, 1);
      expect(s.paidCount + s.partialCount + s.unpaidCount, s.invoiceCount,
          reason: 'مجموعُ الحالات = العدُّ الكلّيُّ حين تكون كلُّها من '
              'الثلاثة — التداخلُ يعُدُّ صفّاً مرّتين والفجوةُ تُخفيه');
    });

    test('العدُّ يتبع عمودَ status لا مقدارَ الدفع', () async {
      // ⭐ الاختبارُ الحاسم: فاتورةٌ **مسدَّدةٌ بالكامل مبلغاً** لكنّ عمودَها
      // ما زال `pending` (وهي حالةٌ واقعيّة: دفعةٌ سُجِّلت ولم تُحدَّث الحالة،
      // أو صفٌّ وصل من مزامنةٍ قبل تحديث حالته). المرشِّحُ يضعها في «غير
      // مدفوع» لأنه يقرأ العمود — فليضعها العدّادُ هناك أيضاً.
      //
      // ولو نُسخ شرطُ المبيعات (`paid >= total`) لعُدَّت «مدفوعة»، فتُظهر
      // الشريحةُ «مدفوع 1» ثمّ لا تُخرج شيئاً عند النقر.
      await seedInvoice(total: 100, paid: 100, status: 'pending');

      final s = await summarize();

      expect(s.unpaidCount, 1,
          reason: 'العمودُ `pending` ⇒ الشريحةُ «غير مدفوع» — كما يرشِّح '
              '_applyFilters بالضبط');
      expect(s.paidCount, 0,
          reason: 'المبلغُ مكتملٌ لكنّ الحالةَ ليست `paid` — والعدُّ يتبع '
              'ما يتبعه المرشِّح');
    });

    test('حالةٌ مجهولةٌ تقع في «غير مدفوع» ولا تسقط من العدّ', () async {
      // `_mapStatus` تُرجع `pending` في حالة الافتراض، فالعدُّ بالنفي.
      await seedInvoice(total: 100, paid: 0, status: 'weird_unknown_state');
      await seedInvoice(total: 100, paid: 0, status: '');

      final s = await summarize();

      expect(s.unpaidCount, 2,
          reason: 'العدُّ بالنفي لا بالإثبات — وإلّا سقط صفٌّ من الثلاثة '
              'وهو معروضٌ في القائمة');
      expect(s.invoiceCount, 2);
    });

    test('completed تُعَدُّ مدفوعةً — نفسُ ما تفعله _mapStatus', () async {
      await seedInvoice(total: 100, paid: 100, status: 'completed');

      final s = await summarize();

      expect(s.paidCount, 1);
      expect(s.unpaidCount, 0);
    });

    test('الملغيُّ والمرتجَعُ لا يُعَدّان في أيٍّ من الثلاثة', () async {
      // ولا يُظهرهما أيُّ مرشِّح كذلك — فالمجموعُ هنا **أقلُّ** من الكلّيّ،
      // وذلك صحيحٌ لا نقص.
      await seedInvoice(total: 100, paid: 0, status: 'cancelled');
      await seedInvoice(total: 100, paid: 100, status: 'returned');
      await seedInvoice(total: 100, paid: 50, status: 'partial_return');
      await seedInvoice(total: 100, paid: 0, status: 'draft');

      final s = await summarize();

      expect(s.invoiceCount, 4);
      expect(s.paidCount, 0);
      expect(s.partialCount, 0);
      expect(s.unpaidCount, 0);
      expect(s.paidCount + s.partialCount + s.unpaidCount,
          lessThanOrEqualTo(s.invoiceCount));
    });

    test('لا فواتيرَ ⇒ أصفارٌ لا أخطاء', () async {
      final s = await summarize();
      expect(s.invoiceCount, 0);
      expect(s.totalAmount, 0);
      expect(s.totalReturns, 0);
      expect(s.paidCount, 0);
    });
  });

  group('الإجمالياتُ والمرتجعات', () {
    Future<void> seedReturn(int invoiceId, double qty, double cost) async {
      await db.into(db.products).insert(
            ProductsCompanion.insert(name: 'صنف الاختبار', code: 'T-1'),
          );
      await db.into(db.stockMovements).insert(
            StockMovementsCompanion.insert(
              productId: 1,
              warehouseId: 1,
              movementType: 'return',
              quantity: -qty,
              balanceAfter: 0,
              unitCost: Value(cost),
              referenceType: const Value('purchase_return'),
              referenceId: Value(invoiceId),
            ),
          );
    }

    test('المتبقي = الإجمالي − المسدَّد − المرتجعات', () async {
      final id = await seedInvoice(total: 1000, paid: 400);
      await seedReturn(id, 2, 50); // ‏١٠٠ مرتجعاً

      final s = await summarize();

      expect(s.totalAmount, 1000);
      expect(s.totalPaid, 400);
      expect(s.totalReturns, 100);
      expect(s.totalRemaining, 500,
          reason: 'نفسُ معادلةِ _applyFilters حرفاً بحرف — وإلّا خالفت '
              'البطاقةُ مجموعَ الصفوفِ تحتها');
    });

    test('المرتجعُ يتبع نافذةَ الفاتورة الأصليّة لا تاريخَ حدوثه', () async {
      // فاتورةٌ خارجَ النافذة ومرتجعُها — لا الفاتورةُ ولا مرتجعُها يدخلان،
      // لأن الصفَّ نفسَه لا يُعرَض فلا يُطرَح مرتجعُه.
      final outside =
          await seedInvoice(total: 500, paid: 0, on: DateTime(2026, 7, 5));
      await seedReturn(outside, 1, 200);

      final s = await summarize();

      expect(s.invoiceCount, 0, reason: 'الفاتورةُ خارجَ المدى');
      expect(s.totalReturns, 0,
          reason: 'مرتجعُ فاتورةٍ غيرِ معروضةٍ لا يُخصَم من بطاقةٍ لا تعرضها');
    });
  });
}
