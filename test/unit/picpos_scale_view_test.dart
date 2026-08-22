// أهليّةُ صنفِ الميزان وعدّاداتُه.
//
// ما يُقاس: أن الشرطَ يشمل الأنواعَ الأربعةَ كلَّها — وتحديداً
// `weightByPiece` الذي **يُعدّ صنفَ ميزانٍ** وإن كان لا يُباع بالوزن في
// حساب الباركود. خلطُ المفهومَين كان يُسقط نوعاً كاملاً من التصدير.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/entities/product_entity.dart';
import 'package:ural_erp/domain/models/picpos_scale_view.dart';

ProductEntity _p({
  int id = 1,
  String? scaleType,
  bool isSoldByWeight = false,
  int? scalePluNumber,
}) =>
    ProductEntity(
      id: id,
      code: 'P$id',
      name: 'صنف $id',
      salePrice: 10,
      costPrice: 5,
      currentStock: 0,
      minStock: 0,
      scaleType: scaleType,
      isSoldByWeight: isSoldByWeight,
      scalePluNumber: scalePluNumber,
    );

void main() {
  group('picposIsScaleItem', () {
    test('الأنواعُ الثلاثةُ الصريحةُ أصنافُ ميزان', () {
      expect(picposIsScaleItem(_p(scaleType: 'weight')), isTrue);
      expect(picposIsScaleItem(_p(scaleType: 'display')), isTrue);
    });

    // ⚠️ الحارسُ المقصود: `weightByPiece` صنفُ ميزانٍ للتصدير، وإن كان
    // `scaleItemIsSoldByWeight` تعامله على أنه **ليس** مبيعاً بالوزن لأجل
    // بادئة الباركود. المفهومان مختلفان ولا يُخلطان.
    test('weightByPiece صنفُ ميزانٍ رغم أنه ليس بيعاً بالوزن', () {
      expect(picposIsScaleItem(_p(scaleType: 'weightByPiece')), isTrue);
    });

    test('البيعُ بالوزن وحدَه يكفي ولو بلا scaleType', () {
      expect(picposIsScaleItem(_p(isSoldByWeight: true)), isTrue);
    });

    test('صنفٌ عاديٌّ ليس صنفَ ميزان', () {
      expect(picposIsScaleItem(_p()), isFalse);
      expect(picposIsScaleItem(_p(scaleType: 'none')), isFalse);
    });
  });

  group('PicPosScaleStats', () {
    test('قائمةٌ فارغةٌ تعطي أصفاراً', () {
      final s = PicPosScaleStats.from(
        products: const [],
        selectedForExport: 0,
        definedScales: 0,
      );
      expect(s.scaleItems, 0);
      expect(s.missingPlu, 0);
    });

    test('تعدُّ أصنافَ الميزان وحدَها لا كلَّ الأصناف', () {
      final s = PicPosScaleStats.from(
        products: [
          _p(id: 1, scaleType: 'weight'),
          _p(id: 2, isSoldByWeight: true),
          _p(id: 3), // عاديّ
          _p(id: 4), // عاديّ
        ],
        selectedForExport: 0,
        definedScales: 0,
      );
      expect(s.scaleItems, 2);
    });

    test('«بلا PLU» تُحسب داخل أصناف الميزان فقط', () {
      final s = PicPosScaleStats.from(
        products: [
          _p(id: 1, scaleType: 'weight', scalePluNumber: 100),
          _p(id: 2, scaleType: 'weight'), // بلا PLU
          _p(id: 3), // عاديٌّ بلا PLU — لا يُعدّ
        ],
        selectedForExport: 0,
        definedScales: 0,
      );
      expect(s.scaleItems, 2);
      expect(s.missingPlu, 1);
    });

    test('المحدَّدُ والموازينُ يُمرَّران كما هما', () {
      final s = PicPosScaleStats.from(
        products: const [],
        selectedForExport: 7,
        definedScales: 2,
      );
      expect(s.selectedForExport, 7);
      expect(s.definedScales, 2);
    });
  });
}
