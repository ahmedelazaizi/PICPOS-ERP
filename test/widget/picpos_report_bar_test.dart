// شريطُ مرشِّحات التقارير على هويّة PicPos.
//
// ═══ لماذا حارسٌ لهذا الشريط بعينه ═══
//
// ثلاثَ عشرةَ شاشةَ تقريرٍ تمرّ من `ReportFilterBar`، فأيُّ عطبٍ هنا عطبٌ في
// ثلاثَ عشرةَ شاشةً دفعةً. وأخطرُ ما فيه ليس الشكل: **الفتراتُ الجاهزةُ هي
// حدودُ الاستعلام**، فلو حسبها الشريطُ بنفسه لأمكن أن يعني «الشهر» في شريطٍ
// شيئاً وفي آخرَ شيئاً — وهي أرقامٌ خاطئةٌ لا اختلافُ شكل.
//
// والعطبُ الثاني فيضٌ: هذا الشريطُ وُجد أصلاً (‏Spec 076) لأنّ صفّاً واحداً
// بسبعة مرشِّحاتٍ تجاوز عرضَ ١٩٢٠. فيُقاس عرضان لا واحد.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_report_bar.dart';
import 'package:picpos_erp/presentation/widgets/report_components.dart'
    show DateRangeFilter;

void main() {
  DateTimeRange today() => DateRangeFilter.presets()[0].range;

  Future<void> pump(
    WidgetTester tester, {
    required DateTimeRange range,
    void Function(DateTime, DateTime)? onChanged,
    List<Widget> trailing = const [],
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PicPosReportFilterBar(
          selectedRange: range,
          onRangeChanged: onChanged ?? (_, _) {},
          trailing: trailing,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('الفتراتُ الجاهزة', () {
    test('مصدرٌ واحدٌ: أربعُ فتراتٍ بحدودٍ مسوّاةٍ ليومٍ كامل', () {
      final ps = DateRangeFilter.presets();
      expect(ps.map((p) => p.label).toList(),
          ['اليوم', 'أمس', 'الشهر', 'السنة']);
      for (final p in ps) {
        expect(p.range.start.hour, 0);
        expect(p.range.start.minute, 0);
        expect(p.range.end.hour, 23);
        expect(p.range.end.minute, 59,
            reason: 'حدُّ «${p.label}» غيرُ مسوًّى ليومٍ كامل — واليومُ '
                'الأخيرُ يسقط من التقرير بلا أن يظهر ذلك للمستخدم.');
      }
    });

    test('وانتقاءُ الفترة يُقاس باليوم لا باللحظة', () {
      final ps = DateRangeFilter.presets();
      for (final p in ps) {
        expect(DateRangeFilter.isPresetSelected(p.range, p.range), isTrue);
      }
      expect(DateRangeFilter.isPresetSelected(ps[0].range, ps[1].range),
          isFalse);
    });
  });

  group('شريطُ PicPos', () {
    testWidgets('يرسم الفتراتِ الأربعَ وزرَّ المدى', (tester) async {
      await pump(tester, range: today());
      for (final p in DateRangeFilter.presets()) {
        expect(find.text(p.label), findsOneWidget);
      }
      expect(find.byIcon(PhosphorIconsBold.calendarBlank), findsOneWidget);
    });

    // ⚠️ **الفتراتُ ليست متنافيةً بالضرورة.** في **أوّلِ كلِّ شهر** يكون مدى
    //    «الشهر» (‏من أوّل الشهر إلى اليوم) هو **عينُ** مدى «اليوم»، وكذلك
    //    «السنة» في أوّلِ يناير. فإبرازُ الاثنين سلوكٌ صادق: كلتاهما تصف المدى
    //    المعروضَ فعلاً، وترجيحُ إحداهما كان سيحتاج قاعدةَ تعادلٍ مخترَعة.
    //
    //    وكان الفحصُ يفترض التنافيَ فيسقط في أوّلِ كلِّ شهر — وقد سقط فعلاً
    //    يوم 2026-09-01. فالمقارنةُ الآن على **المدى** لا على الترتيب.
    testWidgets('والمنتقاةُ هي التي تطابق المدى المعروض', (tester) async {
      final ps = DateRangeFilter.presets();
      final selected = ps[2].range;
      await pump(tester, range: selected);

      Text label(String s) => tester.widget<Text>(find.text(s));

      expect(label(ps[2].label).style?.fontWeight, FontWeight.w800,
          reason: 'الفترةُ المطابقةُ للمدى ليست هي المُبرَزة.');

      // مرساة: ثمّة فترةٌ واحدةٌ على الأقلّ **تختلف** فعلاً، وإلّا كانت الحلقةُ
      // أدناه فارغةً ومرَّ الفحصُ بلا أن يقيس شيئاً.
      final differing = [ps[0], ps[1], ps[3]]
          .where((p) => !DateRangeFilter.isPresetSelected(selected, p.range))
          .toList();
      expect(differing, isNotEmpty,
          reason: 'مرساة: يجب أن تبقى فترةٌ غيرُ مطابقةٍ ليُقاس عليها');

      for (final other in differing) {
        expect(label(other.label).style?.fontWeight, FontWeight.w700,
            reason: 'فترةٌ مداها مختلفٌ يجب ألّا تُبرَز: «${other.label}»');
      }
    });

    testWidgets('واللمسُ يبثّ مدى تلك الفترة نفسِه', (tester) async {
      DateTime? gotStart;
      DateTime? gotEnd;
      final ps = DateRangeFilter.presets();
      await pump(
        tester,
        range: ps[0].range,
        onChanged: (s, e) {
          gotStart = s;
          gotEnd = e;
        },
      );
      await tester.tap(find.text(ps[3].label));
      await tester.pump();
      expect(gotStart, ps[3].range.start);
      expect(gotEnd, ps[3].range.end,
          reason: 'الشريطُ بثّ مدىً غيرَ مدى الفترة الملموسة — والتقريرُ '
              'يُحسَب من المبثوث.');
    });

    testWidgets('ومرشِّحاتُ الشاشة تُعرض كما هي', (tester) async {
      await pump(
        tester,
        range: today(),
        trailing: const [Text('مرشِّحُ الفرع'), Text('مرشِّحُ المخزن')],
      );
      expect(find.text('مرشِّحُ الفرع'), findsOneWidget);
      expect(find.text('مرشِّحُ المخزن'), findsOneWidget);
    });

    testWidgets('ولا يفيض بسبعة مرشِّحاتٍ عند ١٢٨٠ ولا عند ١٩٢٠',
        (tester) async {
      final trailing = [
        for (var i = 0; i < 7; i++)
          SizedBox(width: 180, height: 44, child: Text('مرشِّح $i')),
      ];
      for (final w in [1280.0, 1920.0]) {
        await pump(
          tester,
          range: today(),
          trailing: trailing,
          size: Size(w, 900),
        );
        expect(tester.takeException(), isNull,
            reason: 'الشريطُ فاض عند عرض $w — وهو عينُ العطب الذي بُني هذا '
                'الشريطُ ليمنعه (Spec 076).');
      }
    });
  });

  // ═══════════ الرافعةُ نفسُها ═══════════
  //
  // قيمةُ هذا الشريط ليست في شكله بل في أنّه **واحد**. فالمحروسُ هنا موضعُ
  // الفرع، وبقاءُ فرع UralCash، وعددُ الشاشات التي ما زالت تمرّ منه.
  group('موضعُ الفرع', () {
    String code(String p) => File(p)
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('`ReportFilterBar` تتفرّع إلى شريط PicPos ويبقى فرعُ UralCash', () {
      final src = code('lib/presentation/widgets/report_filter_bar.dart');
      expect(src.contains('Brand.isPicPos'), isTrue,
          reason: 'الفرعُ سقط — فثلاثَ عشرةَ شاشةَ تقريرٍ تعود إلى شريط '
              'UralCash دفعةً واحدة.');
      expect(src.contains('PicPosReportFilterBar('), isTrue);
      expect(src.contains('DateRangeFilter('), isTrue,
          reason: 'شريطُ UralCash حُذف — والنقلُ مشروطٌ بأنّ الفرعَ الآخرَ '
              'لا يتبدّل فيه بايت.');
    });

    test('وشريطُ PicPos لا يحسب مدىً بنفسه', () {
      final src = code('lib/presentation/picpos_shell/picpos_report_bar.dart');
      expect(src.contains('DateRangeFilter.presets()'), isTrue);
      expect(RegExp(r'DateTime\.now\(\)').hasMatch(src), isFalse,
          reason: 'الشريطُ صار يحسب تواريخَه — فقد تنحرف حدودُ «الشهر» عن '
              'الشريط الآخر، والتقريرُ يُحسَب من الحدود لا من العنوان.');
    });

    test('و`reportScaffold` تتفرّع وتُبقي `AppBar` لـUralCash', () {
      final src = code('lib/presentation/screens/reports/report_scaffold.dart');
      expect(src.contains('Brand.isPicPos'), isTrue);
      expect(src.contains('PicPosScreenScaffold('), isTrue);
      expect(src.contains('appBar: AppBar('), isTrue,
          reason: 'فرعُ UralCash فقد `AppBar` — وهو ما كانت تبنيه الشاشاتُ '
              'حرفاً بحرف قبل النقل.');
    });

    test('والشاشاتُ المنقولةُ لا تبني ترويستَها بيدها', () {
      const moved = [
        'sales_report_screen',
        'inventory_report_screen',
        'shifts_report_screen',
        'treasury_report_screen',
        'purchases_report_screen',
        'tables_report_screen',
        'sales_by_classification_report',
      ];
      for (final f in moved) {
        final src = code('lib/presentation/screens/reports/$f.dart');
        expect(src.contains('reportScaffold('), isTrue,
            reason: '$f: لا تمرّ من الإطار المشترك.');
        expect(src.contains('appBar: AppBar('), isFalse,
            reason: '$f: عادت تبني `AppBar` بيدها — فأيُّ تعديلٍ في الهويّة '
                'يفوتها.');
      }
    });

    test('ولا تُضاف ترويسةٌ مرسومةٌ بيدٍ إلى شاشةِ تقريرٍ جديدة', () {
      // عدّادُ تقدّمٍ لا حكمٌ نهائيّ: الباقياتُ أربعَ عشرةَ شاشةً تنتظر
      // النقلَ في دفعاتٍ تالية. والحارسُ يمنع أن يزيد العددُ لا أن يبقى.
      final raw = Directory('lib/presentation/screens/reports')
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.dart') &&
              // الإطارُ المشترك نفسُه يبني `AppBar` لفرع UralCash — وهو
              // المكانُ الذي يُفترَض أن تُبنى فيه، فلا يُعَدُّ مخالفة.
              !f.path.endsWith('report_scaffold.dart') &&
              f.readAsStringSync().contains('appBar: AppBar('))
          .length;
      expect(raw, lessThanOrEqualTo(11),
          reason: 'عددُ شاشات التقارير التي ترسم ترويستَها بيدها ارتفع إلى '
              '$raw — استعمل `reportScaffold` بدل `Scaffold(appBar: …)`.');
    });

    test('وشاشاتُ التقارير ما زالت تمرّ من الشريط المشترك', () {
      final n = Directory('lib/presentation/screens/reports')
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.dart') &&
              f.readAsStringSync().contains('ReportFilterBar'))
          .length;
      expect(n, greaterThanOrEqualTo(13),
          reason: 'عددُ شاشات التقارير التي تمرّ من الشريط المشترك نزل إلى '
              '$n — وكلُّ شاشةٍ تخرج منه تحتاج تنسيقاً بيدها، وهو عينُ ما '
              'بُني الشريطُ ليمنعه.');
    });
  });
}
