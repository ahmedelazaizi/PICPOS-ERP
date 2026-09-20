// test/unit/sidebar_owner_layout_test.dart
//
// عقدُ القائمة الجانبيّة كما طلبه المالك 2026-09-12 — اثنا عشر بنداً
// شكليّاً، كلٌّ منها يُقاس هنا بدل أن يُصدَّق بالنظر إلى الشاشة.
//
// ⚠️ **ولماذا اختبارٌ لا فحصٌ بصريّ**: `kAllNavItemDefs` مصدرُ توصيلٍ
// مستقلٌّ لا يُشتقّ من `ScreenId` ولا من `screenPermissionMap`، فمدخلٌ
// يُنقَل إلى مجموعةٍ لا وجودَ لها يظهر تحت رأسٍ باسم المفتاح الخام
// (`_groupMeta[key] ?? _GroupMeta(groupKey, folder)`) بلا أيّ خطأ.
//
// ⚠️ **والتقاعدُ محكومٌ بالعلامة**: `kAllNavItemDefs` قائمةٌ مشتركةٌ بين
// الفوركَين، وحذفُ المدخل منها يسحب الشاشةَ من الفورك الآخر أيضاً. فالطريقةُ
// هي نفسُ عقدِ `kPicPosFoldedIntoAccountingHub` القائم: إخفاءٌ بالفهرس.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/core/navigation/screen_registry.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';

/// مدخلُ القائمة صاحبُ التسمية — أو فشلٌ واضحٌ إن غاب.
NavItemDef _byLabel(String label) => kAllNavItemDefs.firstWhere(
      (i) => i.label == label,
      orElse: () => throw StateError('لا مدخلَ بالتسمية «$label»'),
    );

NavItemDef _byIndex(int index) => kAllNavItemDefs.firstWhere(
      (i) => i.index == index,
      orElse: () => throw StateError('لا مدخلَ بالفهرس $index'),
    );

/// ترتيبُ المجموعات كما يبنيه الشريطُ الجانبيّ: أوّلُ ظهورٍ لكلّ مفتاح.
List<String> _groupOrder() {
  final seen = <String>[];
  for (final item in kAllNavItemDefs) {
    final g = item.group ?? 'other';
    if (!seen.contains(g)) seen.add(g);
  }
  return seen;
}

void main() {
  group('١ · الشاشاتُ الثلاثُ المتقاعدة', () {
    // «مش محتاجهم يبقوا موجودين فى النظام للعمل بيهم» — أمرُ المالك.
    const retiredLabels = ['الجرد الدوري', 'التكاليف المحملة', 'طلبات الصرف'];

    test('فهارسُها الثلاثةُ مدرجةٌ في سجلّ التقاعد', () {
      for (final label in retiredLabels) {
        expect(kPicPosRetiredNavIndexes, contains(_byLabel(label).index),
            reason: '«$label» ما زالت تظهر في قائمة PicPos');
      }
      expect(kPicPosRetiredNavIndexes, hasLength(3),
          reason: 'التقاعدُ ثلاثُ شاشاتٍ لا أكثرَ ولا أقلّ');
    });

    // ⚠️ **كلُّ النطاقات لا `unified` وحدَها.** أوّلُ صياغةٍ لهذا التوكيد
    // قاست `unified` فقط، فنجت منها طفرةُ `picposRetired.contains(s)` —
    // لأن `unified` تُدرج الشاشةَ باسم `cycleCounting` وهو **عينُ** ما في
    // السجلّ. والفخُّ في الاسم الآخر: `fieldAudit` قيمةٌ أخرى لنفس الفهرس
    // (42)، وهي المدرَجةُ في `restaurant` و`supermarket` و`commercial`
    // و`lite`. فمطابقةُ القيمة تُبقي الجردَ الدوريَّ حيّاً في أربعة نطاقات.
    const scopes = <String, List<ScreenId>>{
      'restaurant': ScreenRegistry.restaurant,
      'supermarket': ScreenRegistry.supermarket,
      'supermarketPro': ScreenRegistry.supermarketPro,
      'commercial': ScreenRegistry.commercial,
      'lite': ScreenRegistry.lite,
      'unified': ScreenRegistry.unified,
    };

    test('ونطاقُ الشاشات يُسقطها فلا تُبلَغ بالفهرس المباشر', () {
      for (final scope in scopes.entries) {
        final kept = ScreenRegistry.withoutPicposRetired(scope.value)
            .map((s) => s.navigationIndex);
        for (final id in const [
          ScreenId.cycleCounting,
          ScreenId.fieldAudit,
          ScreenId.stockRequisitions,
        ]) {
          expect(kept, isNot(contains(id.navigationIndex)),
              reason: '$id باقيةٌ في نطاق «${scope.key}» — '
                  'والترشيحُ بالنطاق يسبق الصلاحية');
        }
      }
    });

    // ═══ 🔴 «التكاليفُ المحمّلة» — الموضعان مفترقان عمداً (المرحلة ٨) ═══
    //
    // قرارُ المالك 2026-09-18: «تُفعَّل وتعيش داخل المشتريات الخارجيّة
    // وحدَها — لا مدخلَ جانبيَّ لها». فهذان توكيدان **متلازمان**، وسقوطُ
    // أحدهما وحدَه عطبٌ مرئيّ:
    //   • لو عادت إلى `picposRetired` ⇒ زرُّ «التكاليف المحمّلة» داخلَ
    //     شاشة الاستيراد يفتح لا شيء (النطاقُ يسبق الصلاحية).
    //   • ولو خرجت من `kPicPosRetiredNavIndexes` ⇒ عاد المدخلُ الجانبيُّ
    //     الذي أسقطه المالك.
    test('و«التكاليف المحمّلة» مبلوغةٌ بالنطاق ومخفيّةٌ من القائمة', () {
      expect(
        ScreenRegistry.withoutPicposRetired(ScreenRegistry.unified)
            .map((s) => s.navigationIndex),
        contains(ScreenId.landedCost.navigationIndex),
        reason: 'أُسقطت من النطاق — فزرُّ التكاليف في شاشة الاستيراد '
            'يفتح لا شيء',
      );
      expect(
        kPicPosRetiredNavIndexes,
        contains(ScreenId.landedCost.navigationIndex),
        reason: 'عاد مدخلُها الجانبيُّ — والمالكُ أسقطه',
      );
      // وشاشةُ الاستيراد هي **المُبلِغُ الوحيد**: لا مدخلَ لها في القائمة.
      expect(
        kAllNavItemDefs
            .where((n) => n.index == ScreenId.landedCost.navigationIndex)
            .map((n) => n.label),
        ['التكاليف المحملة'],
        reason: 'المدخلُ محذوفٌ من القائمة المشتركة — وهو يخصّ الفورك الآخر',
      );
    });

    test('ولا يُسقط الترشيحُ شاشةً أخرى', () {
      // طفرةٌ تُوسّع السجلَّ أو تقارن بما لا ينبغي تُسقط شاشاتٍ سليمة.
      for (final scope in scopes.entries) {
        final before = scope.value.length;
        final after = ScreenRegistry.withoutPicposRetired(scope.value).length;
        final retiredHere = scope.value
            .where((s) => const {38, 42}.contains(s.navigationIndex))
            .length;
        expect(before - after, retiredHere,
            reason: 'نطاق «${scope.key}» فقد شاشاتٍ غيرَ المتقاعدات');
      }
    });

    test('ولا تُسحب من الفورك الآخر — القائمةُ مشتركة', () {
      // الاختبارُ يعمل على العلامة الافتراضيّة (‏ليست PicPos)، فالمداخلُ
      // الثلاثةُ يجب أن تبقى مرئيّةً لها.
      for (final label in retiredLabels) {
        expect(navItemVisibleForBrand(_byLabel(label).index), isTrue,
            reason: '«$label» اختفت من الفورك الآخر — والتقاعدُ لـPicPos وحدَه');
      }
    });
  });

  group('التسمياتُ الأربع', () {
    test('٢ · تحويل مخزني ← سند تحويل اصناف', () {
      expect(_byIndex(ScreenId.stockTransfer.navigationIndex).label,
          'سند تحويل اصناف');
    });

    test('٦ · نقاط الولاء ← نقاط العملاء', () {
      expect(_byIndex(ScreenId.loyalty.navigationIndex).label, 'نقاط العملاء');
    });

    test('٨ · تقارير مخصصة ← اعداد وتصميم التقارير', () {
      expect(_byIndex(ScreenId.reportBuilder.navigationIndex).label,
          'اعداد وتصميم التقارير');
    });

    test('١٢ · الفروع ← الفروع والمخازن', () {
      expect(_byIndex(ScreenId.branches.navigationIndex).label,
          'الفروع والمخازن');
    });
  });

  group('الرؤوسُ الثلاثةُ الجديدة', () {
    test('٣ · «ادارة المطاعم» تحت المبيعات وفيها الطاولات والمطبخ', () {
      final meta = kNavGroupDefs.firstWhere((g) => g.key == 'restaurant',
          orElse: () => throw StateError('لا مجموعةَ باسم restaurant'));
      expect(meta.label, 'ادارة المطاعم');

      expect(_byIndex(ScreenId.tables.navigationIndex).group, 'restaurant');
      expect(_byIndex(ScreenId.kitchen.navigationIndex).group, 'restaurant');

      final order = _groupOrder();
      expect(order.indexOf('restaurant'), order.indexOf('sales') + 1,
          reason: 'الرأسُ الجديدُ يقع مباشرةً تحت المبيعات');
    });

    test('٤ · «ادارة التصنيع» تحت الاصناف والمخزون وفيها التصنيع', () {
      final meta = kNavGroupDefs.firstWhere((g) => g.key == 'manufacturing',
          orElse: () => throw StateError('لا مجموعةَ باسم manufacturing'));
      expect(meta.label, 'ادارة التصنيع');

      expect(_byIndex(ScreenId.manufacturing.navigationIndex).group,
          'manufacturing');

      final order = _groupOrder();
      expect(order.indexOf('manufacturing'), order.indexOf('inventory') + 1);
    });

    test('٥ · «الموارد البشرية» وفيها الموظفين', () {
      final meta = kNavGroupDefs.firstWhere((g) => g.key == 'hr',
          orElse: () => throw StateError('لا مجموعةَ باسم hr'));
      expect(meta.label, 'الموارد البشرية');

      expect(_byIndex(ScreenId.hr.navigationIndex).group, 'hr');
    });
  });

  test('٧ · سجل العمليات ينتقل تحت الإعدادات في مجموعة النظام', () {
    final log = _byIndex(ScreenId.activityLog.navigationIndex);
    expect(log.group, 'system');

    final system = kAllNavItemDefs.where((i) => i.group == 'system').toList();
    final settingsAt =
        system.indexWhere((i) => i.index == ScreenId.settings.navigationIndex);
    final logAt = system
        .indexWhere((i) => i.index == ScreenId.activityLog.navigationIndex);
    expect(settingsAt, greaterThanOrEqualTo(0));
    expect(logAt, greaterThan(settingsAt),
        reason: 'موضعُه **تحت** الإعدادات لا فوقها');
  });

  test('١١ · رأسُ «النظام» ← «اعداد النظام»', () {
    final meta = kNavGroupDefs.firstWhere((g) => g.key == 'system');
    expect(meta.label, 'اعداد النظام');
  });

  group('سلامةُ البنية بعد النقل', () {
    test('كلُّ مفتاحِ مجموعةٍ مستعملٍ له تعريفٌ برأسٍ عربيّ', () {
      final defined = {for (final g in kNavGroupDefs) g.key};
      for (final item in kAllNavItemDefs) {
        expect(defined, contains(item.group),
            reason: '«${item.label}» في مجموعةٍ بلا رأس: ${item.group}');
      }
    });

    test('ولا مجموعةَ معرَّفةً بلا مدخلٍ واحد', () {
      final used = {for (final i in kAllNavItemDefs) i.group};
      for (final g in kNavGroupDefs) {
        expect(used, contains(g.key), reason: 'رأسٌ فارغ: ${g.key}');
      }
    });

    // ⚠️ ولا توكيدَ على `NavItemDef.section`: قِسته فوجدتُه **حقلاً ميّتاً** —
    // يُنسَخ في `userNavItemsProvider` ولا يقرأه راسمٌ واحد، فرؤوسُ المجموعات
    // كلُّها من [kNavGroupDefs]. وتوكيدٌ على ما لا يُرسَم حارسٌ يقيس لا شيء.
  });
}
