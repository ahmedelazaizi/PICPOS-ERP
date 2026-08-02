// سند «رصيد أول المدة» كان بيتقيّد **إيراد** بدل رأس مال.
//
// ── العطل ────────────────────────────────────────────────────────────────────
// `createAddingBond` بيثبّت `type: const Value('in')` على كل سند، و
// `createOpeningBalanceBond` مجرد wrapper بينادي نفس الدالة. والقرار المحاسبي
// تحته بيقرا **نفس الحقل**:
//
//   final purpose = (bond.type == 'opening') ? 'capital' : 'inventory_surplus';
//
// يعني الشرط **مستحيل يتحقق** وفرع `capital` كود ميت من يوم ما اتكتب.
//
// و`'opening'` هو **الاختيار الافتراضي** في الشاشتين
// (`inventory_bonds_picpos_screen.dart:59` و`inventory_bonds_screen.dart:25`).
//
// ── الأثر بالأرقام ──────────────────────────────────────────────────────────
// عميل جديد بيدخل رصيد افتتاحي ٢٥٠,٠٠٠ بضاعة:
//
//   المفروض:   مدين 1136 مخزون 250,000 / دائن 311 رأس المال 250,000
//   اللي بيحصل: مدين 1136 مخزون 250,000 / دائن 4317 فائض مخزون 250,000
//
// و4317 نوعه **revenue**. يعني ٢٥٠ ألف ربح وهمي في قائمة الدخل من أول يوم،
// وحقوق ملكية ناقصة ٢٥٠ ألف، وضريبة دخل محسوبة على ربح مش موجود.
//
// ── ليه اختبار على دالة نقية ────────────────────────────────────────────────
// `createAddingBond` بيلمس المخزون والتكلفة والقيد في ترانزاكشن واحدة على
// قاعدة بيانات. اللي انكسر هو **قرار الغرض المحاسبي** من نوع السند — فده
// اللي اتفصل واتغطّى.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/inventory_service.dart';

void main() {
  group('inventoryBondAccountPurpose — نوع السند بيحدد الحساب المقابل', () {
    test('سند رصيد أول المدة بيدائن رأس المال مش الإيراد', () {
      expect(
        inventoryBondAccountPurpose(bondType: 'opening', totalValue: 250000),
        'capital',
      );
    });

    test('سند إضافة عادي بقيمة موجبة = فائض مخزون', () {
      expect(
        inventoryBondAccountPurpose(bondType: 'in', totalValue: 5000),
        'inventory_surplus',
      );
    });

    test('قيمة سالبة = عجز مخزون', () {
      expect(
        inventoryBondAccountPurpose(bondType: 'in', totalValue: -300),
        'inventory_shrinkage',
      );
    });

    test('نوع السند بيغلب على إشارة القيمة — رصيد افتتاحي بيفضل رأس مال', () {
      // رصيد افتتاحي بقيمة سالبة (تسوية على تركيبة قايمة) لسه حركة حقوق
      // ملكية مش عجز تشغيلي.
      expect(
        inventoryBondAccountPurpose(bondType: 'opening', totalValue: -1000),
        'capital',
      );
    });

    test('نوع مش معروف بيتعامل زي سند الإضافة مش بيرمي', () {
      // سندات قديمة اتسجّلت بأنواع تانية لازم تفضل شغّالة.
      expect(
        inventoryBondAccountPurpose(bondType: 'adjustment', totalValue: 100),
        'inventory_surplus',
      );
      expect(
        inventoryBondAccountPurpose(bondType: null, totalValue: 100),
        'inventory_surplus',
      );
    });
  });
}
