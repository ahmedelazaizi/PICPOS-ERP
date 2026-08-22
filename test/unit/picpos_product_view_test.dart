// حسابُ عمودَي «الهامش» و«الوحدة» في تصميم الأصناف.
//
// الهامشُ حسابٌ ماليٌّ يسهل قلبُه: القسمةُ على التكلفة بدل البيع تعطي رقماً
// **أكبرَ دائماً** ويبدو معقولاً — فلا يُكتشف بالنظر. ولذلك يُقاس صراحةً.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/picpos_product_view.dart';

void main() {
  group('picposMarginPercent — البسطُ والمقام', () {
    // ⚠️ الحارسُ الأهمّ: ‏١٠ ← ٢٠ هامشُه ٥٠٪ على البيع و١٠٠٪ على التكلفة.
    // لو انقلب المقامُ لصار الرقمُ ضِعفَه ولبقي «معقولاً» بالنظر.
    test('يُقسَم على سعر البيع لا على التكلفة', () {
      expect(picposMarginPercent(salePrice: 20, costPrice: 10), closeTo(50, 1e-9));
      expect(picposMarginPercent(salePrice: 100, costPrice: 60), closeTo(40, 1e-9));
    });

    test('بيعٌ يساوي التكلفةَ ⇒ صفر', () {
      expect(picposMarginPercent(salePrice: 10, costPrice: 10), closeTo(0, 1e-9));
    });

    test('بيعٌ دون التكلفة ⇒ هامشٌ سالبٌ يُعرَض ولا يُخفى', () {
      expect(picposMarginPercent(salePrice: 10, costPrice: 15),
          closeTo(-50, 1e-9));
    });

    // القسمةُ على صفرٍ في Dart تعطي Infinity لا استثناءً — فبلا الحارس
    // كانت «∞%» ستُطبع في خانةٍ ماليّة.
    test('سعرُ بيعٍ صفرٌ أو سالبٌ ⇒ null لا Infinity', () {
      expect(picposMarginPercent(salePrice: 0, costPrice: 10), isNull);
      expect(picposMarginPercent(salePrice: -5, costPrice: 10), isNull);
    });

    test('تكلفةٌ صفرٌ ⇒ null لا ١٠٠٪', () {
      expect(picposMarginPercent(salePrice: 20, costPrice: 0), isNull);
      expect(picposMarginPercent(salePrice: 20, costPrice: -1), isNull);
    });
  });

  group('picposMarginLabel', () {
    test('نسبةٌ بلا كسورٍ ولاحقةُ ٪', () {
      expect(picposMarginLabel(salePrice: 20, costPrice: 10), '50%');
      expect(picposMarginLabel(salePrice: 10, costPrice: 15), '-50%');
    });

    test('المجهولُ شرطةٌ لا صفرٌ ولا فراغ', () {
      expect(picposMarginLabel(salePrice: 20, costPrice: 0), '—');
      expect(picposMarginLabel(salePrice: 0, costPrice: 5), '—');
    });
  });

  group('picposMarginBand', () {
    test('يصنّف المجهولَ والسالبَ والمنخفضَ والسليم', () {
      expect(picposMarginBand(salePrice: 20, costPrice: 0),
          PicPosMarginBand.unknown);
      expect(picposMarginBand(salePrice: 10, costPrice: 15),
          PicPosMarginBand.negative);
      expect(picposMarginBand(salePrice: 100, costPrice: 90),
          PicPosMarginBand.low);
      expect(picposMarginBand(salePrice: 100, costPrice: 50),
          PicPosMarginBand.healthy);
    });

    test('الصفرُ منخفضٌ لا سالب', () {
      expect(picposMarginBand(salePrice: 10, costPrice: 10),
          PicPosMarginBand.low);
    });
  });

  group('picposSaleUnitLabel', () {
    test('الوزنُ كجم وغيرُه قطعة', () {
      expect(picposSaleUnitLabel(isSoldByWeight: true), 'كجم');
      expect(picposSaleUnitLabel(isSoldByWeight: false), 'قطعة');
    });
  });

  group('PicPosProductKpis', () {
    ({
      double salePrice,
      double costPrice,
      double currentStock,
      double minStock,
      bool trackInventory,
      bool isActive,
    }) row({
      double salePrice = 20,
      double costPrice = 10,
      double currentStock = 100,
      double minStock = 0,
      bool trackInventory = true,
      bool isActive = true,
    }) =>
        (
          salePrice: salePrice,
          costPrice: costPrice,
          currentStock: currentStock,
          minStock: minStock,
          trackInventory: trackInventory,
          isActive: isActive,
        );

    test('قائمةٌ فارغةٌ تعطي أصفاراً', () {
      final k = PicPosProductKpis.from(const []);
      expect(k.loaded, 0);
      expect(k.active, 0);
      expect(k.belowMinStock, 0);
      expect(k.missingCost, 0);
    });

    test('يعدُّ المحمَّلَ والنشط', () {
      final k = PicPosProductKpis.from([
        row(),
        row(isActive: false),
        row(),
      ]);
      expect(k.loaded, 3);
      expect(k.active, 2);
    });

    // ⚠️ نفسُ منطق حدّ الائتمان: `minStock == 0` يعني «لا حدَّ مضبوطاً».
    // بدونه كان كلُّ صنفٍ رصيدُه صفرٌ سيُعدّ «تحت الحدّ» بلا أن يضبطه أحد.
    test('حدٌّ أدنى صفريٌّ لا يُعدّ تحت الحدّ', () {
      final k = PicPosProductKpis.from([
        row(currentStock: 0, minStock: 0),
        row(currentStock: 0, minStock: 5),
      ]);
      expect(k.belowMinStock, 1);
    });

    test('صنفٌ لا يُتابَع مخزونُه لا يُعدّ تحت الحدّ', () {
      final k = PicPosProductKpis.from([
        row(currentStock: 0, minStock: 5, trackInventory: false),
      ]);
      expect(k.belowMinStock, 0);
    });

    test('الرصيدُ عند الحدِّ ليس تحته', () {
      final k = PicPosProductKpis.from([row(currentStock: 5, minStock: 5)]);
      expect(k.belowMinStock, 0);
    });

    test('يعدُّ الأصنافَ بلا تكلفةٍ مسجَّلة', () {
      final k = PicPosProductKpis.from([
        row(costPrice: 0),
        row(costPrice: 10),
        row(costPrice: -1),
      ]);
      expect(k.missingCost, 2);
    });
  });

  group('picposStockFillRatio — شريطُ المخزون', () {
    test('النسبةُ إلى الحدّ الأدنى لا إلى سعةٍ مخترَعة', () {
      expect(picposStockFillRatio(currentStock: 5, minStock: 10),
          closeTo(0.5, 1e-9));
      expect(picposStockFillRatio(currentStock: 10, minStock: 10),
          closeTo(1.0, 1e-9));
    });

    // بلا القصّ كان رصيدٌ أضعافَ الحدِّ يمدُّ الشريطَ خارجَ إطاره.
    test('يُقَصُّ عند ١ فوق الحدِّ وعند صفرٍ تحت السالب', () {
      expect(picposStockFillRatio(currentStock: 500, minStock: 10),
          closeTo(1.0, 1e-9));
      expect(picposStockFillRatio(currentStock: -8, minStock: 10),
          closeTo(0.0, 1e-9));
    });

    // ⚠️ نفسُ منطقِ حدّ الائتمان: العمودُ افتراضُه صفرٌ لمن لا حدَّ له.
    // فبلا هذا الحارس كان كلُّ صنفٍ يُرسم له شريطٌ يدّعي قياساً لا مرجعَ له.
    test('حدٌّ أدنى صفريٌّ ⇒ null فلا شريطَ أصلاً', () {
      expect(picposStockFillRatio(currentStock: 5, minStock: 0), isNull);
      expect(picposStockFillRatio(currentStock: 5, minStock: -1), isNull);
    });

    test('صنفٌ لا يُتابَع مخزونُه ⇒ null', () {
      expect(
        picposStockFillRatio(
            currentStock: 5, minStock: 10, trackInventory: false),
        isNull,
      );
    });
  });

  group('picposStockBand', () {
    test('النفادُ يُقاس قبل الحدِّ — صفرٌ نفادٌ ولو بلا حدٍّ مضبوط', () {
      expect(picposStockBand(currentStock: 0, minStock: 0),
          PicPosStockBand.out);
      expect(picposStockBand(currentStock: -3, minStock: 10),
          PicPosStockBand.out);
    });

    test('دون الحدِّ منخفضٌ، وعنده فأعلى سليم', () {
      expect(picposStockBand(currentStock: 4, minStock: 10),
          PicPosStockBand.low);
      expect(picposStockBand(currentStock: 10, minStock: 10),
          PicPosStockBand.ok);
      expect(picposStockBand(currentStock: 99, minStock: 10),
          PicPosStockBand.ok);
    });

    test('بلا حدٍّ مضبوطٍ ورصيدٌ موجبٌ ⇒ سليم لا منخفض', () {
      expect(picposStockBand(currentStock: 1, minStock: 0),
          PicPosStockBand.ok);
    });

    test('غيرُ المتابَع صنفُه بندٌ مستقلٌّ لا «نفاد»', () {
      expect(
        picposStockBand(currentStock: 0, minStock: 0, trackInventory: false),
        PicPosStockBand.untracked,
      );
    });
  });
}
