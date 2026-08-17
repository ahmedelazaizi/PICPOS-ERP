import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/domain/models/table_order_totals.dart';
import 'package:ural_erp/domain/models/tax_rate_bounds.dart';
import 'package:ural_erp/domain/usecases/sales/calculate_invoice_totals_usecase.dart';

/// ضريبةُ المبيعات على طلبات الطاولات — الطورُ أ.
///
/// `TableOrderTotals` هو المحرّكُ الواحدُ الذي تشترك فيه الخدمةُ والشاشةُ
/// والطباعة. ودلالاتُه ليست جديدةً: هي دلالاتُ
/// `CalculateInvoiceTotalsUseCase` (مواصفة ١٣٧) منقولةً — الضريبةُ على
/// الصافي بعد الخصم، ونسبةُ البند تسبق نسبةَ الطلب، والإطفاءُ يُصفِّرها.
///
/// وآخرُ اختبارٍ هنا هو مقصودُ الملفّ كلِّه: يُثبِّت النموذجَ على المرجع
/// بالمدخلات نفسِها. الافتراقُ بين المحرّكين هو العطلُ الذي يُصلحه هذا
/// الفرع، فلا يُترك بلا حارسٍ يقيسه.
void main() {
  group('TableOrderTotals — الضريبةُ مطفأة', () {
    test('بلا خصمٍ ولا ضريبةٍ: الإجماليُّ هو مجموعُ البنود بحرفه', () {
      final t = TableOrderTotals.compute(
        lines: const [
          TableOrderLine(quantity: 2, unitPrice: 12.5),
          TableOrderLine(quantity: 1, unitPrice: 7.25),
        ],
      );

      expect(t.subtotal, 32.25);
      expect(t.discount, 0.0);
      expect(t.netAfterDiscount, 32.25);
      expect(t.taxAmount, 0.0);
      expect(t.total, 32.25);
    });

    test('بندٌ يحمل نسبتَه والضريبةُ مطفأةٌ ⇐ ضريبةٌ صفرٌ (BUG-C02)', () {
      // الصنفُ ضريبتُه ١٦٪ في بطاقته، لكنّ الكاشير أطفأ الضريبةَ على الطلب.
      // الإطفاءُ يعلو على نسبة البند — وإلّا لَما كان زرّاً.
      final t = TableOrderTotals.compute(
        lines: const [
          TableOrderLine(quantity: 10, unitPrice: 10, taxRate: 16),
        ],
        taxEnabled: false,
        taxPercent: 16,
      );

      expect(t.taxAmount, 0.0);
      expect(t.total, 100.0);
    });

    test('الخصمُ يعمل والضريبةُ مطفأةٌ — مطابقةً لـ`_effectiveTotalOf`', () {
      // هذا هو سلوكُ اليوم بالضبط: `SUM(qty × price)` ناقصاً خصمَ الطلب.
      // فالطاولاتُ القائمةُ (بلا ضريبة) لا يتغيّر حسابُها بهذا النموذج.
      final t = TableOrderTotals.compute(
        lines: const [TableOrderLine(quantity: 4, unitPrice: 25)],
        discountType: 'percent',
        discountValue: 10,
      );

      expect(t.subtotal, 100.0);
      expect(t.discount, 10.0);
      expect(t.taxAmount, 0.0);
      expect(t.total, 90.0);
    });
  });

  group('TableOrderTotals — الضريبةُ مفعَّلة', () {
    test('نسبةُ البند تُستعمَل ولو كانت نسبةُ الطلب صفراً', () {
      final t = TableOrderTotals.compute(
        lines: const [
          TableOrderLine(quantity: 10, unitPrice: 10, taxRate: 16),
        ],
        taxEnabled: true,
      );

      expect(t.subtotal, 100.0);
      expect(t.taxAmount, 16.0);
      expect(t.total, 116.0);
    });

    test('بندٌ بلا نسبةٍ يقع على نسبة الطلب', () {
      final t = TableOrderTotals.compute(
        lines: const [TableOrderLine(quantity: 10, unitPrice: 10)],
        taxEnabled: true,
        taxPercent: 16,
      );

      expect(t.taxAmount, 16.0);
      expect(t.total, 116.0);
    });

    test('نسبةُ البند تسبق نسبةَ الطلب، وكلٌّ يحسب بنسبته', () {
      // بندٌ بـ١٢٪ صراحةً وبندٌ يقع على ١٦٪ الطلب — في طلبٍ واحد.
      final t = TableOrderTotals.compute(
        lines: const [
          TableOrderLine(quantity: 1, unitPrice: 100, taxRate: 12),
          TableOrderLine(quantity: 1, unitPrice: 50),
        ],
        taxEnabled: true,
        taxPercent: 16,
      );

      expect(t.subtotal, 150.0);
      expect(t.taxAmount, 20.0); // ١٢ + ٨
      expect(t.total, 170.0);
    });

    test('لا بنودَ ⇒ أصفارٌ كلُّها', () {
      final t = TableOrderTotals.compute(
        lines: const [],
        taxEnabled: true,
        taxPercent: 16,
      );

      expect(t.subtotal, 0.0);
      expect(t.taxAmount, 0.0);
      expect(t.total, 0.0);
    });
  });

  group('TableOrderTotals — الضريبةُ على الصافي لا على المجمل', () {
    test('بعد خصمٍ نسبيٍّ: ٩٠ لا ١٠٠ (BUG-H01)', () {
      // ١٠ × ١٠٠ = ١٠٠٠، ضريبةُ البند ١٠٪، وخصمُ الطلب ١٠٪.
      // على المجمل لكانت الضريبةُ ١٠٠ والإجماليُّ ١٠٠٠ — أي أن الخصمَ
      // يتبخّر في الضريبة. على الصافي هي ٩٠ والإجماليُّ ٩٩٠.
      final t = TableOrderTotals.compute(
        lines: const [
          TableOrderLine(quantity: 10, unitPrice: 100, taxRate: 10),
        ],
        discountType: 'percent',
        discountValue: 10,
        taxEnabled: true,
      );

      expect(t.subtotal, 1000.0);
      expect(t.discount, 100.0);
      expect(t.netAfterDiscount, 900.0);
      expect(t.taxAmount, 90.0);
      expect(t.taxAmount, lessThan(100.0)); // ١٠٠ = الحسابُ على المجمل
      expect(t.total, 990.0);
    });

    test('بعد خصمٍ بمبلغٍ مقطوع: ١٢ لا ١٥', () {
      // ٤ × ٢٥ = ١٠٠، خصمٌ ٢٠ مبلغاً، ونسبةُ الطلب ١٥٪.
      // على المجمل ١٥، وعلى الصافي (٨٠) اثنا عشر.
      final t = TableOrderTotals.compute(
        lines: const [TableOrderLine(quantity: 4, unitPrice: 25)],
        discountType: 'amount',
        discountValue: 20,
        taxEnabled: true,
        taxPercent: 15,
      );

      expect(t.subtotal, 100.0);
      expect(t.discount, 20.0);
      expect(t.netAfterDiscount, 80.0);
      expect(t.taxAmount, 12.0);
      expect(t.taxAmount, lessThan(15.0)); // ١٥ = الحسابُ على المجمل
      expect(t.total, 92.0);
    });
  });

  group('TableOrderTotals — القاعُ عند الصفر', () {
    test('خصمُ ١٠٠٪ يُنزل الإجماليَّ إلى صفرٍ ولا يُسالبه', () {
      final t = TableOrderTotals.compute(
        lines: const [
          TableOrderLine(quantity: 2, unitPrice: 50, taxRate: 16),
        ],
        discountType: 'percent',
        discountValue: 100,
        taxEnabled: true,
        taxPercent: 16,
      );

      expect(t.discount, 100.0);
      expect(t.netAfterDiscount, 0.0);
      expect(t.taxAmount, 0.0); // لا وعاءَ ⇒ لا ضريبة
      expect(t.total, 0.0);
      expect(t.total, greaterThanOrEqualTo(0.0));
    });

    test('مبلغُ خصمٍ يتجاوز المجموعَ يُقَصُّ عنده', () {
      final t = TableOrderTotals.compute(
        lines: const [TableOrderLine(quantity: 2, unitPrice: 50)],
        discountType: 'amount',
        discountValue: 500,
        taxEnabled: true,
        taxPercent: 16,
      );

      expect(t.discount, 100.0); // لا ٥٠٠
      expect(t.netAfterDiscount, 0.0);
      expect(t.total, 0.0);
      // الثابتُ الذي يحفظه القصّ.
      expect(t.subtotal - t.discount, t.netAfterDiscount);
    });

    test('نوعُ خصمٍ مجهولٌ لا يخصم شيئاً', () {
      final t = TableOrderTotals.compute(
        lines: const [TableOrderLine(quantity: 2, unitPrice: 50)],
        discountType: 'ratio',
        discountValue: 10,
      );

      expect(t.discount, 0.0);
      expect(t.total, 100.0);
    });
  });

  group('TableOrderTotals — حدُّ الوحدات', () {
    test('النسبةُ المخزَّنةُ كسريّةٌ والمحسوبةُ مئويّة', () {
      // `TableOrders.taxRate` لقطةٌ من `pos_default_tax_rate` (0.16)، بينما
      // [compute] تأخذ المئويّةَ مرآةً للمرجع. العبورُ في موضعٍ واحدٍ.
      expect(TableOrderTotals.taxPercentFromRate(0.16), closeTo(16, 1e-9));
      expect(TableOrderTotals.taxPercentFromRate(0), 0.0);

      final t = TableOrderTotals.compute(
        lines: const [TableOrderLine(quantity: 1, unitPrice: 100)],
        taxEnabled: true,
        taxPercent: TableOrderTotals.taxPercentFromRate(0.16),
      );

      expect(t.taxAmount, 16.0);
      expect(t.total, 116.0);
    });
  });

  group('TableOrderTotals — حصصُ البنود', () {
    test('مجموعُ الحصص = المستحقُّ بالضبط، والكسرُ على الأخيرة', () {
      // ثلاثةُ أثلاثٍ من مئةٍ: ٣٣٫٣٣٣ × ٣ = ٩٩٫٩٩٩ لا ١٠٠. الفرقُ يُحمَّل
      // على الأخيرة، وإلّا بقي على الطلب متبقٍّ لا يُسوّيه أحد.
      final t = TableOrderTotals.compute(
        lines: const [
          TableOrderLine(quantity: 1, unitPrice: 33.333),
          TableOrderLine(quantity: 1, unitPrice: 33.333),
          TableOrderLine(quantity: 1, unitPrice: 33.334),
        ],
        taxEnabled: true,
        taxPercent: 16,
      );

      expect(t.lineTotals, hasLength(3));
      final sum = t.lineTotals.fold<double>(0, (s, v) => s + v);
      expect((sum * 1000).round(), (t.total * 1000).round());
    });

    test('الحصّةُ تحمل ضريبةَ بندها هي لا متوسّطاً', () {
      final t = TableOrderTotals.compute(
        lines: const [
          TableOrderLine(quantity: 1, unitPrice: 60),
          TableOrderLine(quantity: 1, unitPrice: 40, taxRate: 5),
        ],
        taxEnabled: true,
        taxPercent: 16,
      );

      expect(t.lineTotals[0], 69.6); // ٦٠ + ١٦٪
      expect(t.lineTotals[1], 42.0); // ٤٠ + ٥٪
      expect(t.total, 111.6);
    });

    test('الخصمُ يُوزَّع على الحصص بنسبته', () {
      final t = TableOrderTotals.compute(
        lines: const [
          TableOrderLine(quantity: 1, unitPrice: 60),
          TableOrderLine(quantity: 1, unitPrice: 40),
        ],
        discountType: 'percent',
        discountValue: 10,
      );

      expect(t.lineTotals[0], 54.0);
      expect(t.lineTotals[1], 36.0);
      expect(t.total, 90.0);
    });

    test('لا بنودَ ⇒ لا حصص', () {
      expect(TableOrderTotals.compute(lines: const []).lineTotals, isEmpty);
    });
  });

  group('TableOrderTotals — التطابقُ مع المرجع', () {
    test('النموذجُ والـ`CalculateInvoiceTotalsUseCase` يخرجان برقمٍ واحد', () {
      // نفسُ المدخلات في المحرّكين: ثلاثةُ بنودٍ بنِسَبٍ مختلفةٍ (وواحدٌ بلا
      // نسبةٍ فيقع على نسبة الطلب)، وخصمُ طلبٍ نسبيٌّ بكسورٍ عشريّةٍ تُظهر
      // أيَّ افتراقٍ في مواضع التقريب.
      //
      // هذا الاختبارُ هو مقصودُ الملفّ: افتراقُ الرقمين هو ما جعل حارسَ
      // `checkTableCharge` يرفض كلَّ تحصيلِ طاولةٍ بضريبة.
      const invoiceDiscountPercent = 7.5;
      const orderTaxPercent = 16.0;

      const items = [
        CartItemEntity(
          productId: 1,
          productName: 'مشويّ',
          productCode: 'P1',
          quantity: 3,
          unitPrice: 19.99,
          taxRate: 16,
        ),
        CartItemEntity(
          productId: 2,
          productName: 'عصير',
          productCode: 'P2',
          quantity: 2,
          unitPrice: 4.5,
          // بلا نسبةٍ — يقع على نسبة الطلب في المحرّكين معاً.
        ),
        CartItemEntity(
          productId: 3,
          productName: 'حلوى',
          productCode: 'P3',
          quantity: 1,
          unitPrice: 100,
          taxRate: 5,
        ),
      ];

      final reference = CalculateInvoiceTotalsUseCase().execute(
        items: items,
        invoiceDiscountPercent: invoiceDiscountPercent,
        taxPercent: orderTaxPercent,
        taxEnabled: true,
      );

      final mine = TableOrderTotals.compute(
        lines: items
            .map((i) => TableOrderLine(
                  quantity: i.quantity,
                  unitPrice: i.unitPrice,
                  taxRate: i.taxRate,
                ))
            .toList(),
        discountType: 'percent',
        discountValue: invoiceDiscountPercent,
        taxEnabled: true,
        taxPercent: orderTaxPercent,
      );

      expect(mine.subtotal, reference.subtotal);
      expect(mine.discount, reference.invoiceDiscount);
      expect(mine.taxAmount, reference.taxAmount);
      expect(mine.total, reference.total);

      // وحارسٌ ضدّ التفاهة: لو صار الرقمان صفرين لَتطابقا بلا معنى.
      expect(mine.taxAmount, greaterThan(0));
      expect(mine.discount, greaterThan(0));
      expect(mine.total, greaterThan(mine.netAfterDiscount));
    });

    test('التطابقُ يصمد والضريبةُ مطفأةٌ كذلك', () {
      const items = [
        CartItemEntity(
          productId: 1,
          productName: 'مشويّ',
          productCode: 'P1',
          quantity: 3,
          unitPrice: 19.99,
          taxRate: 16,
        ),
      ];

      final reference = CalculateInvoiceTotalsUseCase().execute(
        items: items,
        invoiceDiscountPercent: 5,
        taxPercent: 0,
        taxEnabled: false,
      );

      final mine = TableOrderTotals.compute(
        lines: const [TableOrderLine(quantity: 3, unitPrice: 19.99, taxRate: 16)],
        discountType: 'percent',
        discountValue: 5,
      );

      expect(mine.subtotal, reference.subtotal);
      expect(mine.discount, reference.invoiceDiscount);
      expect(mine.taxAmount, reference.taxAmount);
      expect(mine.total, reference.total);
      expect(mine.taxAmount, 0.0);
    });
  });

  group('حارسُ الوحدات يقرأ من TaxRateBounds — لا رقمَين يفترقان', () {
    // `_requirePercent` كان يحمل `1` و`100` عاريَين. صارا يُقرآن من
    // [TaxRateBounds]، فلو شُدّ الحدُّ يوماً في مصدره تحرّك الحارسُ معه بدل أن
    // يبقى يُجيز ما ترفضه الشاشةُ والقيد. وهذا الفوجُ يمسك ذلك الافتراق.

    TableOrderTotals computeAt(double taxPercent) => TableOrderTotals.compute(
          lines: const [TableOrderLine(quantity: 1, unitPrice: 100)],
          taxEnabled: true,
          taxPercent: taxPercent,
        );

    test('الحدُّ الأدنى نفسُه يمرّ بلا إطلاق', () {
      expect(computeAt(TaxRateBounds.minPercent).taxAmount, closeTo(1.0, 1e-9));
    });

    test('ما دون الحدِّ فوق الصفر يُطلق الحارس', () {
      // كسريّةٌ (0.16) قُرئت مئويّةً تسقط هنا، وكذلك نسبةٌ تَعِد ولا تُحصّل.
      expect(() => computeAt(0.16), throwsA(isA<AssertionError>()));
      expect(() => computeAt(0.5), throwsA(isA<AssertionError>()));
    });

    test('الصفرُ يمرّ — «بلا ضريبة» ليست خطأَ وحدات', () {
      expect(computeAt(0).taxAmount, 0.0);
    });

    test('ما فوق المئةِ يُطلق الحارس — مئويّةٌ ضُربت في ١٠٠', () {
      expect(() => computeAt(1600), throwsA(isA<AssertionError>()));
    });

    test('مدى الحارسِ هو مدى TaxRateBounds بعينه', () {
      // لا رقمَ عارياً بقي: المدى المقبولُ هنا يُشتقّ من المصدر لا يُكرَّر.
      expect(TaxRateBounds.isValidPercent(TaxRateBounds.minPercent), isTrue);
      expect(TaxRateBounds.isValidPercent(TaxRateBounds.maxPercent), isTrue);
      expect(computeAt(TaxRateBounds.maxPercent).taxAmount, closeTo(100.0, 1e-9));
    });
  });
}
