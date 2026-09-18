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
    double discount = 0,
  }) =>
      PicPosInvoiceLine(
        productId: 7,
        productName: 'صنف',
        quantity: qty,
        unitPrice: price,
        taxRate: taxRate,
        taxEnabled: taxOn,
        discount: discount,
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

  // ═══ الخصمُ لكلّ صنف — قرارُ المالك 2026-09-18 ═══════════════════════════
  //
  // كان `PurchaseInvoiceItems.discount` عموداً **بلا كاتبٍ وله قارئ**: طباعةُ
  // المرتجع تقسّطه وتطبعه — صفراً منذ وُجد. ووُصل العمودُ حتى المحرّك عبر
  // `resolvePurchaseLineNets`، وهذه الحزمةُ تحرس شطرَ الواجهة منه.
  group('الخصمُ لكلّ صنف', () {
    test('يخفّض صافيَ السطر ولا يمسّ المجموع', () {
      final l = line(qty: 10, price: 10, discount: 50);
      expect(l.lineSubtotal, 100,
          reason: '«المجموع» في شريط الإجماليّات قبل الخصم — والتصميمُ '
              'يعرض الخصمَ رقماً مستقلاً بجواره');
      expect(l.appliedDiscount, 50);
      expect(l.lineNet, 50);
    });

    test('والضريبةُ على الصافي لا على الإجماليّ', () {
      // ⚠️ الخصمُ التجاريُّ يخفّض وعاءَ الضريبة. واحتسابُها على الإجماليّ
      // يُقرّ ضريبةَ مدخلاتٍ لم تُدفَع — رقمٌ يذهب إلى إقرارٍ ضريبيّ.
      final l = line(qty: 10, price: 10, discount: 50, taxRate: 14, taxOn: true);
      expect(l.taxAmount, 7,
          reason: '١٤٪ من ٥٠ = ٧. وعلى الإجماليِّ كانت ١٤ — ضِعفُ الحقيقة');
      expect(l.lineTotalWithTax, 57);
    });

    test('وبلا خصمٍ لا يتغيّر رقمٌ واحد', () {
      // 🔴 **مرساةُ عدمِ الارتداد.** المبيعاتُ كلُّها وكلُّ فاتورةِ شراءٍ بلا
      // خصمِ أصنافٍ تمرّ من هنا، فأيُّ انزياحٍ هنا يغيّر فواتيرَ قائمة.
      final l = line(qty: 2, price: 50, taxRate: 14, taxOn: true);
      expect(l.appliedDiscount, 0);
      expect(l.lineNet, l.lineSubtotal);
      expect(l.taxAmount, 14);
      expect(l.lineTotalWithTax, 114);
    });

    test('وخصمٌ أكبرُ من قيمة السطر يُحصَر ولا يقلبه سالباً', () {
      // بلا الحصر: صافٍ سالبٌ يدخل حركةَ المخزون ومتوسّطَ التكلفة، ويطرح
      // المستندُ مبلغاً لم يوجد في السطر أصلاً.
      final l = line(qty: 10, price: 10, discount: 500);
      expect(l.appliedDiscount, 100);
      expect(l.lineNet, 0);
      expect(l.lineTotalWithTax, 0);
    });

    test('وسالبٌ يُقرأ صفراً — لا خصماً يزيد القيمة', () {
      expect(line(qty: 1, price: 100, discount: -30).appliedDiscount, 0);
      expect(line(qty: 1, price: 100, discount: -30).lineNet, 100);
    });
  });

  group('الخصمُ يعبر إلى مسار الحفظ — أو لا يُعرَض أصلاً', () {
    test('المشتريات: المفتاحُ موجودٌ ويحمل المحصور', () {
      final m = line(qty: 10, price: 10, discount: 50)
          .toSaveMap(PicPosInvoiceKind.purchase);
      expect(m['discount'], 50);
    });

    test('المبيعات: لا مفتاحَ إطلاقاً — لا صفرٌ ولا رقم', () {
      // 🔴 `createSalesInvoice` لا يعرف خصماً إلّا على المستند. فمفتاحٌ يُكتَب
      // ولا يُقرأ هو الشكلُ الأسوأ: قارئُه يظنّ أنّ القيمةَ وصلت.
      final m = line(qty: 10, price: 10, discount: 50)
          .toSaveMap(PicPosInvoiceKind.sales);
      expect(m.containsKey('discount'), isFalse);
    });

    test('والبوّابةُ نفسُها في النمطَين', () {
      expect(PicPosInvoiceKind.purchase.supportsLineDiscount, isTrue);
      expect(PicPosInvoiceKind.sales.supportsLineDiscount, isFalse);
    });

    test('والمحصورُ هو ما يُحفَظ لا الخام', () {
      final m = line(qty: 10, price: 10, discount: 900)
          .toSaveMap(PicPosInvoiceKind.purchase);
      expect(m['discount'], 100,
          reason: 'المعروضُ محصورٌ والمحفوظُ خامٌ ⇒ ترويسةٌ تطرح ٩٠٠ وسطورٌ '
              'تطرح ١٠٠');
    });
  });

  group('خصمُ السطور يبلغ إجماليَّ المستند', () {
    test('الخصمُ المُمرَّر = حقلُ الترويسة + خصومُ السطور', () {
      // 🔴 **وهذا ما يصل المحرّك.** `resolvePurchaseLineNets` تقرأ خصمَ
      // المستند على أنّه **المجموع** ثمّ تحفر منه الصريحَ. فتمريرُ حقل
      // الترويسة وحدَه كان يجعل الترويسةَ تقول «بلا خصم» وسطورَها مخصومة.
      final t = PicPosInvoiceTotals.from(
        [line(qty: 10, price: 10, discount: 50), line(qty: 10, price: 90)],
        headerDiscount: 20,
      );
      expect(t.subtotal, 1000);
      expect(t.lineDiscount, 50);
      expect(t.headerDiscount, 20);
      expect(t.discountTotal, 70);
      expect(t.net, 930, reason: '١٠٠٠ + ٠ − ٧٠');
    });

    test('وبلا خصومِ سطورٍ يساوي المجموعُ حقلَ الترويسة حرفاً', () {
      final t = PicPosInvoiceTotals.from(
        [line(qty: 2, price: 50, taxRate: 14, taxOn: true)],
        headerDiscount: 10,
      );
      expect(t.lineDiscount, 0);
      expect(t.discountTotal, 10);
      expect(t.net, 104);
    });

    test('ومجموعُ خصومِ السطور محصورٌ سطراً سطراً', () {
      final t = PicPosInvoiceTotals.from(
        [line(qty: 1, price: 100, discount: 500), line(qty: 1, price: 100)],
      );
      expect(t.lineDiscount, 100, reason: 'الحصرُ يقع على السطر لا على المجموع');
      expect(t.net, 100);
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

  // بلاغُ المالك 2026-08-23: فاتورةٌ «نقدي» ظهرت غيرَ مدفوعةٍ ومديونيّةً على
  // العميل. القرارُ استُخرج خالصاً هنا لأنّ عيشَه داخل `onTap` هو ما جعله
  // غيرَ مقيسٍ أصلاً — ونفسُ علاجِ `_allowedPaymentMethods`.
  group('تهيئةُ المحصَّل تتبع طريقةَ الدفع', () {
    test('نقديٌّ يملأ الصافيَ كاملاً', () {
      expect(
        picPosAutoPaid(paymentMethod: 'cash', net: 114, userEdited: false),
        114,
      );
    });

    test('تحويلٌ مالٌ وصل فعلاً ⇒ يتبع الصافيَ كالنقد', () {
      expect(
        picPosAutoPaid(paymentMethod: 'transfer', net: 114, userEdited: false),
        114,
      );
    });

    test('آجلٌ يُصفِّر — الدَّينُ مقصود', () {
      expect(
        picPosAutoPaid(paymentMethod: 'credit', net: 114, userEdited: false),
        0,
      );
    });

    test('رقمُ المستخدمِ يوقف التهيئةَ مهما كانت الطريقة', () {
      expect(
        picPosAutoPaid(paymentMethod: 'cash', net: 114, userEdited: true),
        isNull,
        reason: 'الحقلُ مصدرُ الحقيقة — تهيئةٌ لا إلزام',
      );
      expect(
        picPosAutoPaid(paymentMethod: 'credit', net: 114, userEdited: true),
        isNull,
      );
    });

    test('صافٍ سالبٌ لا يُنتج محصَّلاً سالباً', () {
      // خصمُ مستندٍ يتجاوز الفرعيَّ يعطي صافياً سالباً — و`clampPaid` يحرس
      // الحفظَ، لكنّ التهيئةَ لا يجوز أن تكتب سالباً في الحقل أصلاً.
      expect(
        picPosAutoPaid(paymentMethod: 'cash', net: -30, userEdited: false),
        0,
      );
    });
  });
}
