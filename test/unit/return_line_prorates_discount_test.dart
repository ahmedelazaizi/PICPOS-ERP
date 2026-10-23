// مرتجعٌ جزئيٌّ يقسّط خصمَ السطر وضريبتَه — لا ينقلهما كاملَين.
//
// ── العطبُ الذي يمنعه ──────────────────────────────────────────────────────
// حقولُ `discount` و`tax` أُضيفت إلى [InvoiceItem] كي يطبعها عمودا الجدول
// بدل الأصفار. والقيمتان المخزَّنتان على سطر الفاتورة تخصّان السطرَ
// **كاملاً** — فمرتجعُ صنفَين من عشرةٍ ينقلهما حرفيّاً فيطبع خصماً أكبرَ من
// قيمةِ المرتجَع نفسِه. رقمٌ خاطئٌ على مستندٍ ماليّ، لا تشويهٌ تجميليّ.
//
// والتقسيطُ هو عينُ ما يفعله الكودُ القائمُ بالسعر (`netUnitPrice`)، فهذا
// اتّساقٌ مع قاعدةٍ مستقرّةٍ لا اختراعُ قاعدة.
//
// ⚠️ **والمقيسُ هنا الحسابُ لا الطباعة**: أربعةُ مواضعَ تُقسّط بالدارت
// (`returns_repository_impl` · توأما `purchase_returns`)، وموضعان بـSQL في
// `getPurchaseReturnItemDetails`. هذا الملفُّ يثبّت القاعدةَ التي يشتركون
// فيها، وحارسُ SQL يقع في اختبارات الـDAO.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/generators/base_generator.dart';

/// نسبةُ المرتجَع كما يحسبها كلُّ موضعٍ — محروسةٌ من القسمة على صفر.
double _ratio(double returnQty, double lineQty) =>
    lineQty > 0 ? returnQty / lineQty : 0.0;

void main() {
  group('نسبةُ المرتجَع', () {
    test('جزئيٌّ — عشرةٌ يُرتجع منها اثنان', () {
      expect(_ratio(2, 10), 0.2);
    });

    test('كاملٌ — النسبةُ واحدٌ فلا يتغيّر شيء', () {
      expect(_ratio(10, 10), 1.0);
    });

    test('سطرٌ بكمّيّةٍ صفريّةٍ لا يقسم على صفر', () {
      // بلا الحارس تعطي `NaN`، وهي تُطبع «NaN» على الورق لا صفراً.
      expect(_ratio(3, 0), 0.0);
      expect(_ratio(3, 0).isNaN, isFalse);
    });
  });

  group('السطرُ المطبوعُ يحمل المقسَّطَ لا المخزَّن', () {
    test('خصمُ ١٠ على عشرة أصناف يصير ٢ عند إرجاع اثنين', () {
      const lineQty = 10.0;
      const lineDiscount = 10.0;
      const lineTax = 14.0;
      const returnQty = 2.0;

      final r = _ratio(returnQty, lineQty);
      final item = InvoiceItem(
        name: 'صنف',
        quantity: returnQty,
        price: 5,
        total: returnQty * 5,
        discount: lineDiscount * r,
        tax: lineTax * r,
      );

      // القيمةُ المحسوبةُ مثبَّتةٌ صراحةً — لا «أصغرُ من المخزَّن».
      // شرطٌ فضفاضٌ يبارك أيَّ رقمٍ أقلّ، ومنها الصفرُ الذي كان العطبَ الأصليّ.
      expect(item.discount, 2.0);
      // ‏١٤ × ٠٫٢ = 2.8000000000000003 بالعشريّة الثنائيّة — فالمقارنةُ
      // بهامشٍ، والقيمةُ التي تصل الورقةَ هي المنسَّقةُ بمنزلتين.
      expect(item.tax, closeTo(2.8, 1e-9));
      expect(item.tax.toStringAsFixed(2), '2.80');
    });

    test('مرتجعٌ كاملٌ ينقلهما كما هما', () {
      final r = _ratio(10, 10);
      expect(10.0 * r, 10.0);
      expect(14.0 * r, 14.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // الاستعلامان المعدَّلان — يُنفَّذان فعلاً لا يُقرآن
  // ═══════════════════════════════════════════════════════════════════════
  //
  // ⚠️ **عمودٌ زائدٌ في SQL لا يمسكه `analyze`**: النصُّ سلسلةٌ عاديّة، فخطأُ
  // اسمِ عمودٍ أو قوسٍ ناقصٍ يظهر **عند التشغيل** على شاشة المستخدم. وقبل هذا
  // الملفّ لم يكن في المستودع اختبارٌ واحدٌ ينادي `getPurchaseReturnItemDetails`.
  group('استعلامُ تفاصيل مرتجع المشتريات يُنفَّذ ويحمل الأعمدةَ الجديدة', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting());
    tearDown(() => db.close());

    Future<(int invoiceId, int productId)> seed() async {
      final productId = await db.insertProduct(
        ProductsCompanion.insert(
          code: 'SKU-RT-1',
          name: 'صنفُ فحص',
          barcode: const Value('6221999'),
          salePrice: const Value(12),
          costPrice: const Value(10),
          currentStock: const Value(0),
        ),
      );
      final invoiceId = await db.createPurchaseInvoice(
        supplierId: 1,
        warehouseId: 1,
        paid: 0,
        items: [
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 10,
            unitCost: 10,
            total: 100,
            discount: const Value(10),
            taxAmount: const Value(14),
            unitName: const Value('كرتونة'),
          ),
        ],
      );
      return (invoiceId, productId);
    }

    test('المسارُ الجزئيُّ — يقسّط بـSQL بنسبة المرتجَع', () async {
      final (invoiceId, productId) = await seed();

      // حركةُ مرتجعٍ بصنفَين من عشرة ⇒ النسبةُ ٠٫٢.
      await db.adjustStock(
        productId: productId,
        warehouseId: 1,
        quantity: -2,
        type: 'purchase_return',
        // ⚠️ الاستعلامُ يُرشِّح بـ`reference_type` لا بـ`type` — وهما عمودان
        //    مختلفان. تمريرُ الأوّلِ وحدَه يُرجع صفرَ صفوفٍ بلا خطأ.
        referenceType: 'purchase_return',
        referenceId: invoiceId,
      );

      final rows = await db.getPurchaseReturnItemDetails(invoiceId);
      expect(rows, hasLength(1), reason: 'الاستعلامُ الأوّلُ لم يُرجع شيئاً');

      final r = rows.single;
      expect(r['product_code'], 'SKU-RT-1');
      expect(r['product_barcode'], '6221999');
      expect(r['unit_name'], 'كرتونة');
      // ‏١٠ × (٢ ÷ ١٠) = ٢ · و١٤ × ٠٫٢ = ٢٫٨ — قيمتان محسوبتان لا «> صفر».
      expect((r['line_discount'] as num).toDouble(), closeTo(2.0, 1e-9));
      expect((r['line_tax'] as num).toDouble(), closeTo(2.8, 1e-9));
    });

    test('المسارُ الاحتياطيُّ — مرتجعٌ كاملٌ بلا تقسيط', () async {
      final (invoiceId, _) = await seed();
      // بلا حركةِ مخزونٍ ⇒ يسقط إلى الاستعلام الثاني، وهو مشروطٌ بالحالة.
      await db.updatePurchaseInvoiceStatus(invoiceId, 'returned');

      final rows = await db.getPurchaseReturnItemDetails(invoiceId);
      expect(rows, hasLength(1), reason: 'الاستعلامُ الثاني لم يُرجع شيئاً');

      final r = rows.single;
      expect(r['product_code'], 'SKU-RT-1');
      expect((r['line_discount'] as num).toDouble(), 10.0);
      expect((r['line_tax'] as num).toDouble(), 14.0);
    });
  });

  group('المُهيَّآتُ تُبقي المسارات غيرَ المملوءة على سلوكها', () {
    test('بندٌ بلا الحقول الجديدة يعطي أصفاراً وفراغاتٍ لا انهياراً', () {
      final item = InvoiceItem(name: 'صنف', quantity: 1, price: 5, total: 5);
      expect(item.discount, 0);
      expect(item.tax, 0);
      expect(item.code, isNull);
      expect(item.unit, isNull);
      expect(item.barcode, isNull);
    });
  });
}
