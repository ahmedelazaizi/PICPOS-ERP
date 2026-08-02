// استهلاك الخامات في التصنيع كان بيتقيّد على حساب **غير** اللي الشراء دخّل
// عليه.
//
// ── العطل ────────────────────────────────────────────────────────────────────
// `manufacturing_dao.dart:369` بيقرا `raw_materials` = **١١٣١**، بينما
// `purchase_dao.dart:741` بيمدين `inventory` = **١١٣٦** لأي صنف بلا شرط.
//
// فالخامة بتدخل ١١٣٦ وبتخرج من ١١٣١:
//
//   شراء ١٠٠ كجم @ ١٠   →  Dr 1136 = 1000
//   startProduction (٥٠) →  Cr 1131 = -500  ·  Dr 1133 (WIP) = 500
//   completeProduction   →  Dr 1136 = +500  ·  Cr 1133 = -500
//   ────────────────────────────────────────────────────────────
//   1136 = 1500 · 1131 = **-500** (رصيد أصل سالب — مستحيل محاسبياً)
//
// كل أمر إنتاج بيضخّم ١١٣٦ بقيمة الخامات المستهلكة، والرقم بيتراكم بلا سقف.
//
// ── القرار (المالك، 2026-08-02) ─────────────────────────────────────────────
// **الشراء يوجّه حسب نوع الصنف، والتقرير يجمع ١١٣١+١١٣٣+١١٣٦.**
//
// يعني الخامة تدخل ١١٣١ وتخرج منه، والمنتج التام يدخل ١١٣٦ — وحساب المخزون
// الرقابي في التقارير بقى مجموع التلاتة عشان التقييم (اللي بيجمع كل الأصناف
// المتعقَّبة) يساويه.
//
// ── الثابتة اللي الاختبار بيحرسها ───────────────────────────────────────────
// كل نوع صنف له حساب واحد بس، وحسابات المخزون التلاتة **متمايزة** — لو
// اتنين منهم اتساووا، الحركة بين المخزنين بتختفي من الدفاتر.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  group('inventoryAccountPurposeForProduct — التوجيه بنوع الصنف', () {
    test('الخامة بتدخل حساب الخامات', () {
      expect(inventoryAccountPurposeForProduct('raw_material'), 'raw_materials');
    });

    test('المنتج التام بيدخل حساب المخزون', () {
      expect(inventoryAccountPurposeForProduct('finished_goods'), 'inventory');
    });

    test('الصنف العام بيدخل حساب المخزون — سلوك النهاردة للأغلبية', () {
      // معظم أصناف تاجر التجزئة `general`. توجيهها لأي حساب تاني كان هيغيّر
      // دفاتر كل العملاء اللي مالهمش تصنيع أصلاً.
      expect(inventoryAccountPurposeForProduct('general'), 'inventory');
    });

    test('نوع مش معروف بيقع على حساب المخزون مش بيرمي', () {
      expect(inventoryAccountPurposeForProduct('service'), 'inventory');
      expect(inventoryAccountPurposeForProduct(null), 'inventory');
      expect(inventoryAccountPurposeForProduct(''), 'inventory');
    });
  });

  group('kInventoryControlPurposes — نطاق المخزون الرقابي', () {
    test('بيضم التلاتة: خامات + تحت التشغيل + مخزون', () {
      expect(kInventoryControlPurposes,
          containsAll(['raw_materials', 'wip', 'inventory']));
    });

    test('كل غرض بيوجّه له الشراء موجود في النطاق الرقابي', () {
      // لو الشراء وجّه لحساب برّه النطاق، التقييم هيختلف عن الأستاذ بقيمته.
      for (final t in ['raw_material', 'finished_goods', 'general', null]) {
        expect(kInventoryControlPurposes,
            contains(inventoryAccountPurposeForProduct(t)),
            reason: 'نوع «$t» بيتقيّد برّه النطاق الرقابي');
      }
    });
  });

  group('الحسابات متمايزة فعلاً في الدليل', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.forTesting();
      await db.syncDefaultAccounts();
    });
    tearDown(() => db.close());

    test('التلات حسابات موجودة ومختلفة عن بعضها', () async {
      final ids = <int>{};
      for (final purpose in kInventoryControlPurposes) {
        final acc = await db.getAccountByPurpose(purpose);
        expect(acc, isNotNull, reason: 'حساب «$purpose» مش مزروع');
        ids.add(acc!.id);
      }
      expect(ids.length, kInventoryControlPurposes.length,
          reason: 'حسابين على نفس الرقم = الحركة بينهم بتختفي من الدفاتر');
    });
  });
}
