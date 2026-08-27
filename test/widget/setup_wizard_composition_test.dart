// test/widget/setup_wizard_composition_test.dart
//
// معالجُ البدء — **أوّلُ اختبارِ تركيبٍ له**.
//
// ═══ لماذا ═══
//
// ٣٨٤١ سطراً في ثمانية ملفّات، وصفرُ اختباراتِ تخطيط. وإعادةُ التنسيق
// البصريّةُ التي طلبها المالك تمسّ الترويسةَ والشريطَ الجانبيَّ وجسمَ الخطوة
// الأولى والتذييلَ — أربعةَ مواضعَ في شجرةٍ لم يقسها أحد.
//
// ⚠️ **ويُقاس على عرضَين** (‏١٢٨٠ و١٩٢٠) مع `takeException`: الأعطابُ تتغيّر
// بالعرض، ولوحةُ الشرح الجانبيّةُ تنهار تحت ١٤٠٠px — فالعرضان يمرّان على
// الفرعَين.
//
// ═══ وما يحرسه تحديداً ═══
//
// 🔴 **عطبُ التباين الذي بلّغ عنه المالك**: الخلفيّةُ كانت تتدرّج إلى
//    `Colors.white` مثبَّتاً، فترسم شريطاً أبيضَ عبر وسط الشاشة في الوضع
//    الداكن — والعنوانُ الفرعيُّ عليه يكاد لا يُقرَأ. والفحصُ يقيس **الوضع
//    الداكن** لأنّه موضعُ العطب.
//
// 🔴 **ونوعُ النشاط بطاقاتٌ لا قائمةٌ منسدلة**، **والعملةُ رقاقات** — وهما
//    ما طلبه التصميمُ صراحةً.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/screens/setup_wizard_screen.dart';

Future<void> _pump(
  WidgetTester tester,
  double width, {
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: const SetupWizardScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    group('عرض $w', () {
      testWidgets('الترويسةُ والشريطُ الجانبيُّ يُبنيان بلا انهيار',
          (tester) async {
        await _pump(tester, width);

        expect(find.textContaining('مرحباً بك في'), findsOneWidget);
        expect(find.text('دعنا نُعد نظامك في دقائق معدودة'), findsOneWidget);
        // ثمانِ خطواتٍ في المستقلّ — وهو النمطُ الابتدائيّ.
        //
        // ⚠️ **موضعان لا موضعٌ واحد** عن قصد: العدّادُ في شريط التقدّم أعلى
        //    الشاشة، وشارةٌ في ترويسة الخطوة نفسِها. فالفحصُ `findsNWidgets(2)`
        //    لا `findsOneWidget` — وسقوطُه إلى واحدٍ يعني أنّ أحدَهما سقط.
        expect(find.text('الخطوة 1 من 8'), findsNWidgets(2));

        // 🔴 و«ملف النشاط» في العمود الجانبيّ **غيرُ** «نوع النشاط» في
        //    الجسم — كانا باسمٍ واحدٍ فبدا للمستخدم أنّه يجيب سؤالاً مكرّراً.
        expect(find.text('ملف النشاط'), findsOneWidget);

        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('شريطُ التقدّم يعرض نسبةً — وأوّلُ خطوةٍ صفرٌ لا ١٢٪',
          (tester) async {
        // 🔴 شريطٌ يبدأ ممتلئاً جزئيّاً قبل أن يُكتَب حرفٌ يَعِد بما لم يقع.
        await _pump(tester, width);

        expect(find.text('0٪'), findsOneWidget);
        final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(bar.value, 0);

        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('نوعُ النشاط ستُّ بطاقاتٍ لا قائمةٌ منسدلة', (tester) async {
        await _pump(tester, width);

        expect(find.text('نوع النشاط'), findsOneWidget);
        for (final t in const [
          'تجزئة',
          'مطعم / كافيه',
          'جملة وتوزيع',
          'تصنيع',
          'خدمات',
          'أخرى',
        ]) {
          expect(find.text(t), findsOneWidget, reason: 'البطاقةُ «$t» غائبة');
        }

        // والوصفُ الذي تُخفيه القائمةُ المنسدلةُ ظاهرٌ على البطاقة.
        expect(
          find.text('سوبر ماركت وبقالة — بيعٌ بالباركود والميزان'),
          findsOneWidget,
        );

        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('والعملةُ ستُّ رقاقاتٍ ومعها تحذيرُ «قرار نهائي»',
          (tester) async {
        await _pump(tester, width);

        expect(find.byType(ChoiceChip), findsNWidgets(6));
        expect(find.text('جنيه مصري (EGP)'), findsOneWidget);
        expect(find.text('دولار أمريكي (USD)'), findsOneWidget);

        // ⚠️ التحذيرُ ليس زينة: لا تحويلَ أرصدةٍ بأثرٍ رجعيّ في النظام.
        expect(find.text('العملة قرار نهائي'), findsOneWidget);

        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('واختيارُ نشاطٍ آخرَ يبدّل البطاقةَ المعلَّمة',
          (tester) async {
        await _pump(tester, width);

        await tester.tap(find.text('تصنيع'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('نقاطُ الترقيم في التذييل — ثمانٍ بعدد الخطوات',
          (tester) async {
        await _pump(tester, width);
        // النقاطُ حاويةٌ بارتفاع ٨ — وعددُها عددُ خطوات المسار.
        final dots = find.byWidgetPredicate((w) =>
            w is Container &&
            w.constraints?.maxHeight == 8 &&
            w.constraints?.minHeight == 8);
        expect(dots, findsNWidgets(8));
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('مبدّلُ السمة في ذيل الشريط الجانبيّ', (tester) async {
        await _pump(tester, width);
        expect(find.text('الوضع الداكن'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets(
          '🔴 وفي الوضع الداكن لا خلفيّةَ بيضاءَ مثبَّتةٌ في التدرّج',
          (tester) async {
        // عينُ ما بلّغ عنه المالك: `Colors.white` وسطَ التدرّج يرسم شريطاً
        // أبيضَ عبر الشاشة، والعنوانُ الفرعيُّ عليه يكاد لا يُقرَأ.
        await _pump(tester, width, brightness: Brightness.dark);

        final decorated = tester
            .widgetList<Container>(find.byType(Container))
            .where((c) => c.decoration is BoxDecoration)
            .map((c) => c.decoration! as BoxDecoration)
            .where((d) => d.gradient is LinearGradient);

        expect(decorated, isNotEmpty,
            reason: 'تدرّجُ الخلفيّة غائبٌ فالفحصُ لا يقيس شيئاً');

        for (final d in decorated) {
          final colors = (d.gradient! as LinearGradient).colors;
          expect(
            colors,
            isNot(contains(Colors.white)),
            reason: 'أبيضُ مثبَّتٌ في تدرّج خلفيّةٍ داكنة — عينُ عطب التباين',
          );
        }

        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });
    });
  }
}
