// «التوزيع والمواقع» — خطّةُ إعادةِ التسمية قبل أن تُكتَب.
//
// ═══ ما يُقاس هنا ولماذا ═══
//
// 🔴 `FixedAssets.location` **نصٌّ حرّ**، فالموقعُ الواحدُ يُكتَب بصيغٍ
//    فيبدو مواقعَ. والعلاجُ الوحيدُ بلا جدولٍ جديدٍ هو كتابةُ الاسم الجديد
//    على **كلّ أصلٍ** يحمل القديم — وهي كتابةٌ على صفوفٍ متعدّدةٍ لا رجعةَ
//    فيها، فتُخطَّط خالصةً وتُقاس قبل أن تقع.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/asset_location_plan.dart';

/// صفوفٌ مختصرةٌ — ما يلزم التخطيطَ وحدَه.
List<AssetLocationRow> _rows(Map<int, String?> m) =>
    [for (final e in m.entries) (id: e.key, location: e.value)];

void main() {
  group('الوسمُ والتشذيب', () {
    test('الفارغُ والمسافاتُ كلُّها «بلا موقع»', () {
      expect(assetLocationLabel(null), kUnassignedAssetLocation);
      expect(assetLocationLabel(''), kUnassignedAssetLocation);
      expect(assetLocationLabel('   '), kUnassignedAssetLocation);
    });

    test('والمسافاتُ الطرفيّةُ تُشذَّب فلا تصنع موقعاً ثانياً', () {
      expect(assetLocationLabel(' فرع المعادي '), 'فرع المعادي');
      expect(normalizeAssetLocation('  '), isNull);
    });

    // ⚠️ **ولا تطبيعَ للحروف**: «الرئيسي» و«الرئيسى» يبقيان اثنين — لأنّ
    //    أيَّ قاعدةِ تشابهٍ كانت ستدمج «مخزن ١» و«مخزن ٢» أيضاً.
    test('والياءُ المقصورةُ تبقى موقعاً آخرَ — والدمجُ قرارُ مستخدم', () {
      expect(assetLocationLabel('الفرع الرئيسي') ==
          assetLocationLabel('الفرع الرئيسى'), isFalse);
    });
  });

  group('🔴 خطّةُ إعادةِ التسمية', () {
    final rows = _rows({
      1: 'فرع المعادي',
      2: ' فرع المعادي ',
      3: 'فرع مصر الجديدة',
      4: null,
    });

    test('تجمع كلَّ أصلٍ على الاسم القديم — والمشذَّبُ منها', () {
      final p = planAssetLocationRename(
          from: 'فرع المعادي', to: 'فرع المعادي الجديد', rows: rows);
      expect(p.isAllowed, isTrue, reason: p.error);
      expect(p.assetIds, [1, 2],
          reason: 'أصلٌ كُتب بمسافةٍ زائدةٍ يبقى خلف الاسم القديم');
      expect(p.target, 'فرع المعادي الجديد');
      expect(p.isMerge, isFalse);
    });

    test('🔴 والاسمُ القائمُ **دمجٌ** يُقال عددُه قبل وقوعه', () {
      final p = planAssetLocationRename(
          from: 'فرع المعادي', to: 'فرع مصر الجديدة', rows: rows);
      expect(p.isAllowed, isTrue, reason: p.error);
      expect(p.isMerge, isTrue,
          reason: '🔴 دمجٌ صامتٌ لا يُفَكّ: الموقعان يصيران واحداً ولا اسمَ '
              'قديمٌ يبقى في أيّ صفّ');
      expect(p.mergesInto, 1);
      expect(p.assetIds, [1, 2]);
    });

    test('🔴 والاسمُ الفارغُ ممنوعٌ لا يعني «امسح الموقع»', () {
      final p =
          planAssetLocationRename(from: 'فرع المعادي', to: '   ', rows: rows);
      expect(p.isAllowed, isFalse,
          reason: '🔴 حقلٌ تُرك فارغاً بالسهو كان سيُجرّد الأصولَ من مواقعها '
              'بلا رجعة');
      expect(p.assetIds, isEmpty);
      expect(p.target, isNull);
    });

    test('والاسمُ نفسُه لا يكتب شيئاً', () {
      final p = planAssetLocationRename(
          from: 'فرع المعادي', to: ' فرع المعادي ', rows: rows);
      expect(p.isAllowed, isFalse);
      expect(p.assetIds, isEmpty);
    });

    test('وموقعٌ بلا أصولٍ يُمنَع بسببٍ ظاهر', () {
      final p =
          planAssetLocationRename(from: 'فرع طنطا', to: 'فرع دمنهور', rows: rows);
      expect(p.isAllowed, isFalse);
      expect(p.error, contains('فرع طنطا'));
    });

    test('و«بلا موقع» إسنادٌ يشمل كلَّ أصلٍ بعمودٍ فارغ', () {
      final p = planAssetLocationRename(
          from: kUnassignedAssetLocation, to: 'المخزن', rows: rows);
      expect(p.isAllowed, isTrue, reason: p.error);
      expect(p.assetIds, [4]);
    });

    // ⚠️ العمودُ `withLength(max: 100)` — والقصُّ الصامتُ يكتب اسماً غيرَ
    //    الذي رآه المستخدم، فيصير موقعاً ثالثاً بدل أن يوحِّد اثنين.
    test('واسمٌ أطولُ من حدِّ العمود يُمنَع لا يُقَصّ', () {
      final p = planAssetLocationRename(
          from: 'فرع المعادي', to: 'ط' * 101, rows: rows);
      expect(p.isAllowed, isFalse);
      expect(p.target, isNull);
    });
  });
}
