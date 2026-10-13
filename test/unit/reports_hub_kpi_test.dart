// مؤشّراتُ صدر مركز التقارير — الرقمُ ونسبتُه.
//
// ═══ العطبُ المحروس ═══
//
// بطاقةُ مؤشّرٍ تكذب بطريقتين، وكلتاهما تُقرأ سليمةً على الشاشة:
//
//   ‏١) **نسبةٌ بلا أساس.** يومُ أمسٍ بلا حركةٍ يجعل القسمةَ على صفر. و«٠٪»
//       تُقرأ «لم يتغيّر» بينما الحقيقةُ «لا مقارنة» — وهي إشارةٌ معاكسةٌ
//       تماماً لصاحب المحلّ الذي فتح أمس ولم يبِع.
//
//   ‏٢) **فترةٌ غير التي يقولها العنوان.** لو قرأ المركزُ مؤشّراتِه من
//       `dashboardKpiProvider` لتبدّلت أرقامُه مع مرشِّح لوحة التحكّم
//       المشترك — فتعرض بطاقةٌ مكتوبٌ عليها «مبيعات اليوم» حصيلةَ شهر.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/library_source.dart';
import 'package:ural_erp/data/providers/reports_hub_kpi_provider.dart';

void main() {
  group('نسبةُ التغيّر', () {
    test('أمسٌ بلا حركةٍ ⇒ لا نسبةَ إطلاقاً — لا صفر', () {
      expect(ReportsHubKpi.deltaPercent((today: 1200, yesterday: 0)), isNull,
          reason: '«٠٪» تُقرأ «لم يتغيّر»، والحقيقةُ أنّه لا أساسَ للمقارنة.');
      expect(ReportsHubKpi.deltaPercent((today: 0, yesterday: 0)), isNull);
    });

    test('والارتفاعُ والانخفاضُ يُحسبان من الأمس', () {
      expect(ReportsHubKpi.deltaPercent((today: 150, yesterday: 100)), 50);
      expect(ReportsHubKpi.deltaPercent((today: 50, yesterday: 100)), -50);
      expect(ReportsHubKpi.deltaPercent((today: 100, yesterday: 100)), 0);
    });

    test('وأساسٌ سالبٌ لا يقلب إشارةَ التغيّر', () {
      // خسارةُ أمسٍ ٥٠ صارت اليومَ خسارةَ ٢٥ ⇒ **تحسّن**. القسمةُ على قيمةٍ
      // سالبةٍ بلا `abs()` كانت تعطي −٥٠٪ فتُقرأ تدهوراً.
      final d = ReportsHubKpi.deltaPercent((today: -25, yesterday: -50));
      expect(d, isNotNull);
      expect(d!, greaterThan(0),
          reason: 'انكماشُ الخسارة تحسّنٌ — والإشارةُ يجب أن تقول ذلك.');
    });
  });

  group('مصدرُ الأرقام', () {
    const provider = 'lib/data/providers/reports_hub_kpi_provider.dart';
    const hub =
        'lib/presentation/reports_picpos/screens/reports_picpos_screen.dart';

    String code(String p) => p == hub
        ? readLibrarySource(p)
        : File(p)
            .readAsStringSync()
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');

    test('المؤشّراتُ محصورةٌ بصلاحية الفروع داخلَ الاستعلام', () {
      final src = code(provider);
      expect(src.contains('branchScopeProvider'), isTrue,
          reason: 'المؤشّرُ لا يحلّ نطاقَ الفروع — فمستخدمٌ محصورٌ بفرعٍ يرى '
              'إجماليَّ الشركة في صدر الشاشة.');
      expect(RegExp(r'allowedBranchIds:\s*allowed').allMatches(src).length, 2,
          reason: 'الحصرُ لا يدخل الاستعلامَين معاً (قائمةُ الدخل وتحليلُ '
              'المبيعات) — فأحدُ الرقمَين غيرُ محصور.');
    });

    test('ومركزُ التقارير لا يقرأ مؤشّراتِ لوحة التحكّم', () {
      expect(code(hub).contains('dashboardKpiProvider'), isFalse,
          reason: 'مؤشّراتُ لوحة التحكّم محصورةٌ بمرشِّحها المشترك — فبطاقةٌ '
              'مكتوبٌ عليها «مبيعات اليوم» قد تعرض حصيلةَ شهر.');
      expect(code(hub).contains('reportsHubKpiProvider'), isTrue);
    });
  });
}
