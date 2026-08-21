// ═══════════════════════════════════════════════════════════════════════════
// نوع وحدة صنف الميزان — وزن ولا حبة
// ═══════════════════════════════════════════════════════════════════════════
//
// الباج اللي الاختبار ده موجود عشانه: أصناف «ميزان بالحبة» كانت بتترحّل
// للميزان كأنها بالوزن، فالميزان يطبع «كيلو» عليها. والأخطر إن الباركود
// المولَّد كان بياخد بادئة الوزن بدل بادئة السعر، فالسعر بيتحسب غلط على
// البيع السريع.
//
// السبب إن الحساب كان متكرر في أربع أماكن بتلات صيغ. الاختبار ده بيثبّت
// الصيغة الواحدة الصح — وأهم حالة فيه إن `isSoldByWeight = true` **مش**
// كافية لوحدها، لأن شاشة تعديل الصنف بتضبطها `true` لأصناف الحبة كمان.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/label_scale_service.dart';

void main() {
  group('scaleItemIsSoldByWeight', () {
    test('«ميزان» → بالوزن', () {
      expect(
        scaleItemIsSoldByWeight(scaleType: 'weight', isSoldByWeight: true),
        isTrue,
      );
    });

    test('«ميزان بالحبة» → بالحبة، حتى لو isSoldByWeight = true', () {
      // ده جوهر الباج: شاشة تعديل الصنف بتضبط isSoldByWeight = true للنوعين
      // (weight و weightByPiece)، فالاعتماد عليها لوحدها بيحوّل أصناف الحبة
      // لأصناف وزن.
      expect(
        scaleItemIsSoldByWeight(
          scaleType: 'weightByPiece',
          isSoldByWeight: true,
        ),
        isFalse,
      );
    });

    test('«عدد» → مش بالوزن', () {
      expect(
        scaleItemIsSoldByWeight(scaleType: 'count', isSoldByWeight: false),
        isFalse,
      );
    });

    test('«عرض» → مش بالوزن', () {
      expect(
        scaleItemIsSoldByWeight(scaleType: 'display', isSoldByWeight: false),
        isFalse,
      );
    });

    test('صنف قديم بلا scaleType → بيقع على isSoldByWeight', () {
      expect(
        scaleItemIsSoldByWeight(scaleType: null, isSoldByWeight: true),
        isTrue,
      );
      expect(
        scaleItemIsSoldByWeight(scaleType: null, isSoldByWeight: false),
        isFalse,
      );
      expect(
        scaleItemIsSoldByWeight(scaleType: '', isSoldByWeight: true),
        isTrue,
      );
    });

    test('الصيغ التلاتة القديمة الغلط كانت هتفشّل حالة الحبة', () {
      const scaleType = 'weightByPiece';
      const isSoldByWeight = true; // زي ما شاشة الصنف بتحفظها

      // الصيغة اللي كانت في شاشة الترحيل وشاشة اللوحات
      final oldExportFormula = scaleType == 'weight' ||
          scaleType == 'weightByPiece' ||
          isSoldByWeight;
      // الصيغة اللي كانت في مسارَي PLU manager
      const oldPluFormula = isSoldByWeight;

      expect(oldExportFormula, isTrue, reason: 'الصيغة القديمة كانت بتدي وزن');
      expect(oldPluFormula, isTrue, reason: 'الصيغة القديمة كانت بتدي وزن');
      expect(
        scaleItemIsSoldByWeight(
          scaleType: scaleType,
          isSoldByWeight: isSoldByWeight,
        ),
        isFalse,
        reason: 'الصيغة الصح لازم تدي حبة',
      );
    });
  });
}
