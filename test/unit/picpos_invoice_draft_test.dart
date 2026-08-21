// حسابُ مسوّدةِ فاتورةِ PicPos — الشاشةُ الجديدة «فاتورة جديدة».
//
// يُقاس هنا ما يُفسِد مالاً لو انحرف:
//  ‏١) **مفاتيحُ خريطةِ الحفظ** — المبيعاتُ تقرأ `unitPrice` والمشترياتُ
//     `unitCost`. ومفتاحٌ واحدٌ خاطئٌ يعني بنداً يصل مسارَ الحفظ بسعرِ **صفر**
//     بلا استثناءٍ ولا تحذير: الفاتورةُ تُحفَظ، والرقمُ غلط.
//  ‏٢) **ترتيبُ المعادلة** — الصافي = الفرعي + ضريبة − خصم. وعكسُه (خصمٌ قبل
//     ضريبة) يعطي رقماً مختلفاً على نفس المدخلات.
//  ‏٣) **القسمةُ على صفر** — في Dart تعطي `Infinity` لا استثناءً، فـ
//     «‏+Infinity%» تُطبَع على شاشةٍ ماليّةٍ بلا حارس.
//  ‏٤) **حصرُ المدفوع** — `clamp` على مدىً مقلوبٍ يرمي، وصافٍ سالبٌ ممكن.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/picpos_invoice_draft.dart';

void main() {
  PicPosInvoiceLine line({
    double qty = 1,
    double price = 100,
    double taxRate = 14,
    bool taxOn = false,
  }) =>
      PicPosInvoiceLine(
        productId: 7,
        productName: 'صنف',
        quantity: qty,
        unitPrice: price,
        taxRate: taxRate,
        taxEnabled: taxOn,
      );

  group('حسابُ السطر', () {
    test('الضريبةُ صفرٌ حين تُطفأ الحبّة ولو كانت النسبةُ موجبة', () {
      final l = line(taxRate: 14, taxOn: false);
      expect(l.lineSubtotal, 100);
      expect(l.taxAmount, 0,
          reason: 'حبّةُ الضريبة في التصميم تُنقَر للتبديل — فإطفاؤها يعني '
              'صفراً لا النسبةَ المخزَّنة على الصنف');
      expect(l.lineTotalWithTax, 100);
    });

    test('الضريبةُ تُحسَب على الفرعيِّ حين تُشعَل', () {
      final l = line(qty: 2, price: 50, taxRate: 14, taxOn: true);
      expect(l.lineSubtotal, 100);
      expect(l.taxAmount, 14);
      expect(l.lineTotalWithTax, 114);
    });

    test('نسبةُ صفرٍ تعطي ضريبةَ صفرٍ ولو أُشعلت الحبّة', () {
      expect(line(taxRate: 0, taxOn: true).taxAmount, 0);
    });
  });

  group('خريطةُ الحفظ — المفاتيحُ تختلف بالنمط', () {
    test('المبيعات: `unitPrice` ولا `unitCost`', () {
      final m = line(price: 250).toSaveMap(PicPosInvoiceKind.sales);
      expect(m['unitPrice'], 250);
      expect(m.containsKey('unitCost'), isFalse,
          reason: 'مسارُ حفظ المبيعات يقرأ unitPrice — والمفتاحُ الآخر ضجيج');
      expect(m['productId'], 7);
      expect(m['lineTotal'], 250);
    });

    test('المشتريات: `unitCost` ولا `unitPrice`', () {
      final m = line(price: 250).toSaveMap(PicPosInvoiceKind.purchase);
      expect(m['unitCost'], 250,
          reason: 'purchases_picpos_crud.dart يقرأ item[\'unitCost\'] — '
              'وغيابُه يعني (num) على null');
      expect(m.containsKey('unitPrice'), isFalse);
      expect(m['selectedUnitName'], 'قطعة',
          reason: 'مسارُ المشتريات يقرأ selectedUnitName لا unitName');
      expect(m['taxEnabled'], isFalse);
    });

    test('المفتاحان لا يجتمعان أبداً — وإلّا صار أحدُهما مهمَلاً صامتاً', () {
      for (final k in PicPosInvoiceKind.values) {
        final m = line().toSaveMap(k);
        expect(m.containsKey('unitPrice') && m.containsKey('unitCost'), isFalse);
        expect(m.containsKey('unitPrice') || m.containsKey('unitCost'), isTrue);
      }
    });
  });

  group('إجمالياتُ المستند', () {
    test('الصافي = الفرعي + ضريبة − خصمِ المستند، بهذا الترتيب', () {
      final t = PicPosInvoiceTotals.from(
        [line(qty: 2, price: 50, taxRate: 14, taxOn: true)],
        headerDiscount: 10,
      );
      expect(t.subtotal, 100);
      expect(t.tax, 14);
      // ‏١٠٠ + ١٤ − ١٠ = ١٠٤. ولو خُصم قبل الضريبة: (100−10)*1.14 = 102.6.
      expect(t.net, 104,
          reason: 'نفسُ ترتيب _netAmount في نموذج المشتريات القائم');
    });

    test('العدُّ والكمّيّةُ يُجمعان للتذييل', () {
      final t = PicPosInvoiceTotals.from([line(qty: 2), line(qty: 3)]);
      expect(t.lineCount, 2);
      expect(t.quantityTotal, 5);
    });

    test('بلا سطورٍ ⇒ أصفارٌ لا أخطاء', () {
      final t = PicPosInvoiceTotals.from(const []);
      expect(t.subtotal, 0);
      expect(t.net, 0);
      expect(t.paidPct(0), 0);
    });
  });

  group('المدفوعُ والمتبقي', () {
    final t = PicPosInvoiceTotals.from([line(qty: 1, price: 100)]);

    test('المدفوعُ محصورٌ في [0, net]', () {
      expect(t.clampPaid(-50), 0, reason: 'لا سدادَ سالب');
      expect(t.clampPaid(250), 100, reason: 'لا سدادَ فوق الصافي');
      expect(t.clampPaid(40), 40);
    });

    test('المتبقي يتبع المحصور لا الخام', () {
      expect(t.remainingAfter(250), 0,
          reason: 'دفعةٌ فوق الصافي لا تصنع متبقّياً سالباً');
      expect(t.remainingAfter(40), 60);
    });

    test('صافٍ صفرٌ ⇒ نسبةُ صفرٍ لا Infinity', () {
      final empty = PicPosInvoiceTotals.from(const []);
      expect(empty.paidPct(500), 0,
          reason: 'القسمةُ على صفرٍ في Dart تعطي Infinity لا استثناءً — '
              'فـ«+Infinity%» كانت ستُطبَع على شاشةٍ ماليّة');
      expect(empty.paidPct(500).isFinite, isTrue);
    });

    test('صافٍ سالبٌ (خصمٌ يتجاوز الفرعيَّ) لا يرمي', () {
      // ‏`clamp(0, net)` على مدىً مقلوبٍ يرمي ArgumentError — وهو ما يجعل
      // الحارسَ ضروريّاً لا تجميليّاً.
      final neg = PicPosInvoiceTotals.from(
        [line(qty: 1, price: 10)],
        headerDiscount: 100,
      );
      expect(neg.net, -90);
      expect(() => neg.clampPaid(50), returnsNormally);
      expect(neg.clampPaid(50), 0);
      expect(neg.paidPct(50), 0);
    });
  });

  group('تسمياتُ النمط', () {
    test('المبيعاتُ والمشترياتُ تقلبان النصوصَ السبعة', () {
      const s = PicPosInvoiceKind.sales;
      const p = PicPosInvoiceKind.purchase;
      expect(s.partyLabel, 'العميل');
      expect(p.partyLabel, 'المورد');
      expect(s.priceLabel, 'سعر البيع');
      expect(p.priceLabel, 'سعر الشراء');
      expect(s.paidLabel, 'المحصّل الآن');
      expect(p.paidLabel, 'المسدّد الآن');
      expect(s.netLabel, isNot(p.netLabel));
      expect(s.payTitle, isNot(p.payTitle));
    });
  });
}
