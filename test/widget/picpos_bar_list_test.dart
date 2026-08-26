// `PicPosBarList` — اللبنةُ السابعةُ في `picpos_shell` (كتلةُ `kind:'bars'`).
//
// ═══ ما يُقاس ═══
//
// ‏١) **النسبةُ محسوبةٌ لا مكتوبة**: التصميمُ يكتب `pct:'62%'` بجانب
//    `value:'12,040'` لأنّه صورة. وهنا العرضُ يُقسَم على أكبرِ قيمة، فأكبرُ
//    شريطٍ يملأ المسار وما دونَه بنسبته. ورقمان لنفس السؤال ينحرفان بأوّل
//    يومِ بيع.
//
// ‏٢) **لا قسمةَ على صفر**: كلُّ القيم أصفاراً حالةٌ واقعيّة (طرفٌ بلا ذمّةٍ
//    قائمة) لا استثنائيّة. تُرسم الأشرطةُ فارغةً ويبقى الصفُّ مقروءاً بدل
//    `NaN` تُسقط الإطار.
//
// ‏٣) **النصُّ داخلَ الشريط يخرج منه إن ضاق**: التصميمُ عرضُه ١٩٢٠ فالفيضُ لا
//    يقع عنده، وشاشةُ المشغّل أضيق. ونصٌّ مقصوصٌ إلى حرفٍ واحدٍ بيانةٌ ضائعة.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_bar_list.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    List<PicPosBarItem> items, {
    double width = 900,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: PicPosBarList(
                title: 'توزيع الرصيد',
                subtitle: 'اختبار',
                items: items,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('الرأسُ والصفوفُ تُرسَم', (tester) async {
    await mount(tester, const [
      PicPosBarItem(
        label: 'لم يحن',
        sub: 'فاتورتان',
        value: 19560,
        display: '19,560',
        caption: '44٪',
        icon: Icons.check,
      ),
      PicPosBarItem(
        label: 'متأخر',
        value: 12040,
        display: '12,040',
        caption: '27٪',
      ),
    ]);
    expect(tester.takeException(), isNull);
    expect(find.text('توزيع الرصيد'), findsOneWidget);
    expect(find.text('لم يحن'), findsOneWidget);
    expect(find.text('19,560'), findsOneWidget);
    expect(find.text('44٪'), findsOneWidget);
    await teardownTree(tester);
  });

  testWidgets('عرضُ الشريط نسبةٌ من الأكبر لا من نصٍّ مكتوب', (tester) async {
    await mount(tester, const [
      PicPosBarItem(label: 'الأكبر', value: 100, display: '100'),
      PicPosBarItem(label: 'النصف', value: 50, display: '50'),
      PicPosBarItem(label: 'الربع', value: 25, display: '25'),
    ]);
    expect(tester.takeException(), isNull);

    // الحاوياتُ المصبوغةُ داخلَ المسار: عرضُها هو الجزءُ الممتلئ.
    double fillOf(String label) {
      final row = find.ancestor(
        of: find.text(label),
        matching: find.byType(Row),
      );
      final stack = find.descendant(
        of: row.last,
        matching: find.byType(Stack),
      );
      final fill = find.descendant(
        of: stack.first,
        matching: find.byType(Container),
      );
      return tester.getSize(fill.first).width;
    }

    final big = fillOf('الأكبر');
    final half = fillOf('النصف');
    final quarter = fillOf('الربع');

    expect(big, greaterThan(0));
    // نسبةٌ محسوبةٌ ⇒ النصفُ نصفُ الأكبر والربعُ ربعُه، بهامشٍ لتقريب البكسل.
    expect(half / big, closeTo(0.5, 0.02),
        reason: 'الشريطُ لا يتبع القيمةَ — النسبةُ مكتوبةٌ لا محسوبة');
    expect(quarter / big, closeTo(0.25, 0.02));
    await teardownTree(tester);
  });

  testWidgets('كلُّ القيم أصفاراً — لا NaN ولا انهيار', (tester) async {
    await mount(tester, const [
      PicPosBarItem(label: 'أ', value: 0, display: '0', caption: '0٪'),
      PicPosBarItem(label: 'ب', value: 0, display: '0', caption: '0٪'),
    ]);
    expect(tester.takeException(), isNull,
        reason: 'قسمةٌ على صفرٍ أسقطت الإطار');
    expect(find.text('أ'), findsOneWidget);
    expect(find.text('ب'), findsOneWidget);
    await teardownTree(tester);
  });

  testWidgets('نصُّ الشريط يبقى كاملاً حتى على شريطٍ ضيّقٍ جدّاً',
      (tester) async {
    // شريطٌ نسبتُه ٢٪ من الأكبر: لا يسع نصَّه، فيجب أن يخرج بعدَه لا يُقصّ.
    await mount(
      tester,
      const [
        PicPosBarItem(label: 'الأكبر', value: 1000, display: '1000'),
        PicPosBarItem(
          label: 'الضئيل',
          value: 20,
          display: '20',
          caption: 'نصٌّ طويلٌ نسبيّاً',
        ),
      ],
      width: 700,
    );
    expect(tester.takeException(), isNull);
    final caption = find.text('نصٌّ طويلٌ نسبيّاً');
    expect(caption, findsOneWidget,
        reason: 'النصُّ اختفى بدل أن يخرج من الشريط');
    // ويُقرأ فعلاً: عرضُه أكبرُ من صفرٍ ولم يُقصَّ إلى لا شيء.
    expect(tester.getSize(caption).width, greaterThan(20));
    await teardownTree(tester);
  });

  testWidgets('قائمةٌ فارغةٌ تقول ذلك ولا تُرسَم بطاقةً بلا جسم',
      (tester) async {
    await mount(tester, const []);
    expect(tester.takeException(), isNull);
    expect(find.text('لا بيانات في هذه الفترة'), findsOneWidget);
    await teardownTree(tester);
  });
}
