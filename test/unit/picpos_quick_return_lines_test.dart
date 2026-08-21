// وضعُ المرتجع — دوالُّ القرار الخالصة وراء سطح اختيار الأسطر
// (`_QuickReturnLinesEditorDialog`)، جولةُ إصلاح ١ على المهمّة ٧.
//
// ── ما يقيسه هذا الملفّ ──────────────────────────────────────────────────
// `computeIsFullReturn` — الرايةُ الممرَّرة لـ`processSalesReturn.
// isFullReturn`. كانت مثبَّتةً `true` دوماً (I2 المراجعة)، وهذا خطرٌ فعليّ:
// `processSalesReturn` تختم الفاتورةَ `'returned'` حين `isFullReturn`،
// و`getInvoicesForReturn` تستبعد الفواتيرَ `'returned'` **أبداً** — فمرتجعٌ
// جزئيٌّ مُعلَّمٌ خطأً «كامل» يُفقِد بقيّةَ الفاتورة من كلّ شاشات المرتجعات.
//
// `findReturnableLineForProduct` — نقطةُ القرار وراء حقل الباركود/البحث في
// المحرِّر: هل الصنفُ المقروء جزءٌ من الفاتورة، وأيُّ سطرٍ منها لسه له مكان.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/returnable_line.dart';
import 'package:ural_erp/presentation/pos_picpos/screens/picpos_pos_screen.dart'
    as picpos;
import 'package:ural_erp/presentation/pos_picpos/state/pos_return_mode.dart';

void main() {
  const lineA = ReturnableLine(
    invoiceItemId: 1, productId: 10, productName: 'لوز',
    soldQty: 5, alreadyReturnedQty: 0, unitPrice: 20,
  );
  const lineB = ReturnableLine(
    invoiceItemId: 2, productId: 20, productName: 'كاجو',
    soldQty: 3, alreadyReturnedQty: 1, unitPrice: 15,
  );
  // متاحٌ صفرٌ (استُنفد سلفاً) — يبقى موجوداً في السطور، لا يظهر في المتاح.
  const lineExhausted = ReturnableLine(
    invoiceItemId: 3, productId: 30, productName: 'فستق',
    soldQty: 2, alreadyReturnedQty: 2, unitPrice: 30,
  );

  group('computeIsFullReturn', () {
    test('يرجع true حين كلُّ سطرٍ بلغ متاحه الحاليّ بالضبط', () {
      final mode = PosReturnMode.fromLines(
        invoiceId: 1,
        lines: [lineA, lineB],
      );
      mode.setQty(lineA.invoiceItemId, lineA.availableQty); // 5
      mode.setQty(lineB.invoiceItemId, lineB.availableQty); // 2

      expect(picpos.computeIsFullReturn(mode), isTrue);
    });

    test('يرجع false حين سطرٌ واحدٌ لم يُطلَب كاملاً — مرتجعٌ جزئيّ', () {
      final mode = PosReturnMode.fromLines(
        invoiceId: 1,
        lines: [lineA, lineB],
      );
      mode.setQty(lineA.invoiceItemId, lineA.availableQty); // 5 — كامل
      mode.setQty(lineB.invoiceItemId, 1); // متاحه 2، طلب 1 — جزئيّ

      expect(picpos.computeIsFullReturn(mode), isFalse);
    });

    test('سطرٌ مستنفَدٌ سلفاً (متاحه صفر) لا يمنع الوصفَ «كامل»', () {
      final mode = PosReturnMode.fromLines(
        invoiceId: 1,
        lines: [lineA, lineExhausted],
      );
      mode.setQty(lineA.invoiceItemId, lineA.availableQty); // 5
      // lineExhausted لم يُطلَب منه شيء — availableQty=0 أصلاً فـ(0-0)=0.

      expect(picpos.computeIsFullReturn(mode), isTrue);
    });

    test('لا تسقط تحت المقارنة الساذجة «كلّ الكميات > صفر»: سطرٌ جزئيّ '
        'موجب لكنه غير كامل', () {
      // مقارنةٌ ساذجةٌ بديلة: `requestedQty.values.every((q) => q > 0)`.
      // هنا كلُّ الكميّات المطلوبة موجبة (5 و1)، فالساذجةُ تقول «كامل».
      // الصحيحةُ تقارن كلَّ سطرٍ بمتاحه فتكتشف أن lineB (متاحه 2) طُلِب منه
      // 1 فقط — جزئيّ.
      final mode = PosReturnMode.fromLines(
        invoiceId: 1,
        lines: [lineA, lineB],
      );
      mode.setQty(lineA.invoiceItemId, lineA.availableQty); // 5 (كامل)
      mode.setQty(lineB.invoiceItemId, 1); // متاحه 2 — جزئيّ

      final naiveIsFull = mode.requestedQty.values.every((q) => q > 0);
      expect(naiveIsFull, isTrue,
          reason: 'تأكيدٌ أن السيناريو فعلاً يخدع المقارنة الساذجة');
      expect(picpos.computeIsFullReturn(mode), isFalse);
    });

    test(
        'صنفٌ على سطرين (مفتاحُ alreadyReturnedQty مزدوج) — لا تُختم '
        '«كاملاً» أبداً ولو طُلِب كلُّ المتاح الظاهر', () {
      // إعادةُ إنتاج قياس المراجع بالحرف: صنفٌ واحدٌ على سطرين (٥ و٤)،
      // ومرتجعٌ سابقٌ حقيقيٌّ ٣ بمفتاح productId (لا بمفتاح أيّ سطرٍ بعينه) —
      // فـ`_showQuickReturn` تنسبه لكلّ سطرٍ مستقلاً (راجع تعليقها):
      //   سطر١: sold=5, alreadyReturned=3 (مكرَّر) ⇒ available=2
      //   سطر٢: sold=4, alreadyReturned=3 (مكرَّر) ⇒ available=1
      // «تحديد الكلّ» تطلب مجموع المتاح الظاهر=3 (2+1)، بينما الباقي
      // الحقيقيّ = (5+4)-3 = 6. ختمُ هذه الحالة `true` كان يفقد 3 وحداتٍ
      // حقيقيّةً للأبد (`processSalesReturn` تختم 'returned' نهائياً).
      const splitLine1 = ReturnableLine(
        invoiceItemId: 11, productId: 99, productName: 'سكر',
        soldQty: 5, alreadyReturnedQty: 3, unitPrice: 10,
      );
      const splitLine2 = ReturnableLine(
        invoiceItemId: 12, productId: 99 /* نفسُ الصنف */,
        productName: 'سكر', soldQty: 4, alreadyReturnedQty: 3,
        unitPrice: 10,
      );
      final mode = PosReturnMode.fromLines(
        invoiceId: 1,
        lines: [splitLine1, splitLine2],
      );
      // «تحديد الكلّ»: كلُّ سطرٍ يطلب متاحه الظاهر بالضبط.
      mode.setQty(splitLine1.invoiceItemId, splitLine1.availableQty); // 2
      mode.setQty(splitLine2.invoiceItemId, splitLine2.availableQty); // 1

      final requestedTotal = mode.requestedQty.values
          .fold<double>(0, (sum, q) => sum + q);
      expect(requestedTotal, 3.0,
          reason: 'تأكيدُ أرقام قياس المراجع بالحرف قبل فحص السلوك');

      expect(picpos.computeIsFullReturn(mode), isFalse,
          reason: 'صنفٌ مكرَّرٌ على سطرين ⇒ alreadyReturnedQty غيرُ موثوقة '
              '⇒ لا يجوز الختمُ true إطلاقاً، حتى لو بلغ كلُّ سطرٍ متاحه '
              'الظاهر');
    });
  });

  group('findReturnableLineForProduct', () {
    test('يرجع null لصنفٍ خارج الفاتورة أصلاً', () {
      final mode = PosReturnMode.fromLines(invoiceId: 1, lines: [lineA]);
      expect(picpos.findReturnableLineForProduct(mode, 999), isNull);
    });

    test('يرجع السطرَ حين الصنف داخل الفاتورة وله متاحٌ', () {
      final mode = PosReturnMode.fromLines(invoiceId: 1, lines: [lineA]);
      final found = picpos.findReturnableLineForProduct(mode, lineA.productId);
      expect(found?.invoiceItemId, lineA.invoiceItemId);
    });

    test('يرجع null حين طُلِب المتاحُ كاملاً لصنفٍ بسطرٍ واحد', () {
      final mode = PosReturnMode.fromLines(invoiceId: 1, lines: [lineA]);
      mode.setQty(lineA.invoiceItemId, lineA.availableQty);
      expect(
          picpos.findReturnableLineForProduct(mode, lineA.productId), isNull);
    });

    test('نفسُ الصنف على سطرين: يرجع الثاني بعد استنفاد الأوّل', () {
      const lineA2 = ReturnableLine(
        invoiceItemId: 4, productId: 10 /* نفسُ productId لِـlineA */,
        productName: 'لوز', soldQty: 4, alreadyReturnedQty: 0, unitPrice: 20,
      );
      final mode = PosReturnMode.fromLines(
        invoiceId: 1,
        lines: [lineA, lineA2],
      );
      mode.setQty(lineA.invoiceItemId, lineA.availableQty); // استنفدَ الأوّل

      final found =
          picpos.findReturnableLineForProduct(mode, lineA.productId);
      expect(found?.invoiceItemId, lineA2.invoiceItemId);
    });
  });

  group('nextIncrementedQty', () {
    test('يزيد بمقدار خطوةٍ واحدة عادةً حين يوجد متسّع', () {
      // متاحُ lineA = 5. عند current=3 توقّعُ الخطوةِ التالية 4 لا القفزُ
      // للمتاح مباشرةً.
      expect(picpos.nextIncrementedQty(lineA, 3), 4.0);
    });

    test('يقصّ الخطوةَ الأخيرة على المتاح الكسريّ بدل تجاوزه — محكُّ '
        'المتطلَّب ٥', () {
      const weighedLine = ReturnableLine(
        invoiceItemId: 5, productId: 50, productName: 'موز',
        soldQty: 2.5, alreadyReturnedQty: 0, unitPrice: 8,
      );
      // متاحٌ 2.5؛ عند current=2 الخطوةُ الساذجةُ (current+1=3) تتجاوز
      // المتاح — الصحيحةُ تقصّها إلى 2.5 بالضبط.
      expect(picpos.nextIncrementedQty(weighedLine, 2), 2.5);
    });

    test('يرجع null حين الكميةُ الحاليّةُ بلغت المتاحَ أصلاً', () {
      expect(picpos.nextIncrementedQty(lineA, lineA.availableQty), isNull);
    });

    test('يرجع null لسطرٍ مستنفَدٍ سلفاً (متاحه صفر)', () {
      expect(picpos.nextIncrementedQty(lineExhausted, 0), isNull);
    });
  });

  group('blocksCartMutation', () {
    test('لا تمنع شيئاً خارجَ وضع المرتجع (mode=null)', () {
      expect(picpos.blocksCartMutation(null), isFalse);
    });

    test('تمنع أثناء وضع المرتجع — نفسُ الشرط وراء الحرّاس الثلاثة', () {
      final mode = PosReturnMode.fromLines(invoiceId: 1, lines: [lineA]);
      expect(picpos.blocksCartMutation(mode), isTrue);
    });
  });
}
