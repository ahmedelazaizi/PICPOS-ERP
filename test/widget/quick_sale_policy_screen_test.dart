// شاشةُ سياسة البيع السريع — اختبارُ تركيب.
//
// ═══ لماذا بتجاوز المزوّد لا بقاعدةِ بيانات ═══
//
// الشاشةُ تقرأ `quickSalePolicyProvider` وحدَه في `build`، و`databaseProvider`
// لا يُلمَس إلّا عند الضغط على «حفظ». فتجاوزُ الأوّل يُغني عن قاعدةٍ كاملةً —
// ويُجنّب تعليقَ الاختبار المرصودَ حين تنتظر `db.close()` مؤقّتَ drift في
// المنطقة الوهميّة.
//
// ⚠️ **وعرضان لا عرضٌ واحد**: الشاشةُ ثلاثةُ أعمدةٍ ثابتةِ العرض (٢٥٠ ·
// مرن · ٣٤٠)، وهذا أوّلُ ما ينهار على شاشةٍ ضيّقة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/quick_sale_policy_providers.dart';
import 'package:ural_erp/domain/models/quick_sale_policy.dart';
import 'package:ural_erp/presentation/settings_picpos/screens/quick_sale_policy_screen_picpos.dart';

Future<void> _pump(
  WidgetTester tester, {
  Map<String, String> stored = const {},
  Size size = const Size(1500, 950),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        quickSalePolicyProvider
            .overrideWith((ref) async => QuickSalePolicyValues(stored)),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: QuickSalePolicyScreenPicpos(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('الشاشةُ تُبنى وتعرض خطواتِها', () {
    for (final width in <double>[1500, 1200]) {
      testWidgets('عند عرض ${width.toInt()} — الخطواتُ الخمسُ ظاهرة',
          (tester) async {
        await _pump(tester, size: Size(width, 950));

        for (final step in kQuickSaleSteps) {
          expect(find.text(step.label), findsWidgets,
              reason: 'الخطوةُ «${step.label}» غائبةٌ عن الشريط.');
        }
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('لوحةُ الأثر تتبع الإعدادات', () {
    testWidgets('خطوةُ المسح تعرض أثرَها الافتراضيّ', (tester) async {
      await _pump(tester);

      expect(find.textContaining('وحدة واحدة فوراً'), findsOneWidget,
          reason: 'الافتراضُ أنّ «سؤال الكمية» مطفأ، فالمسحُ يضيف وحدةً.');
    });

    testWidgets('وقلبُ الإعداد يقلب جملةَ الأثر', (tester) async {
      await _pump(tester, stored: {'pos_ask_quantity_before_add': 'true'});

      expect(find.textContaining('لوحة أرقام'), findsWidgets);
      expect(find.textContaining('وحدة واحدة فوراً'), findsNothing);
    });
  });

  group('وسمُ «يُحفَظ ولا يُنفَّذ بعد»', () {
    testWidgets('يظهر لصفٍّ غيرِ موصَّل ولا يظهر لصفٍّ منفَّذ', (tester) async {
      await _pump(tester);

      // خطوةُ المسح فيها أربعةُ صفوفٍ ثلاثةٌ منها غيرُ منفَّذة.
      final notEnforced = kQuickSaleSteps.first.rows
          .where((r) => !r.enforced)
          .length;
      expect(notEnforced, greaterThan(0));

      expect(
        find.text('يُحفَظ ولا يُنفَّذ بعد'),
        findsNWidgets(notEnforced),
        reason: 'كلُّ صفٍّ غيرِ موصَّلٍ يحمل وسمَه — وإخفاؤه يجعل المديرَ '
            'يظنّ أنّ المِزلاجَ غيّر سلوكاً وهو لم يفعل.',
      );
    });
  });

  // لوحةُ «ما يراه الكاشير» — محاكاةٌ تتبع الإعدادات لا صورةٌ ثابتة.
  //
  // ⚠️ **والمحاكاةُ داكنةٌ في الوضعَين معاً عمداً**: هي صورةٌ لشاشةٍ أخرى لا
  // سطحُ واجهةٍ يتبع وضعَ المستخدم — تماماً كمعاينةِ الورق المطبوع.
  group('المعاينةُ تتبع الإعدادات', () {
    Future<void> goToPay(WidgetTester tester) async {
      await tester.tap(find.text('الدفع').first);
      await tester.pumpAndSettle();
    }

    testWidgets('طريقةٌ واحدةٌ ⇒ زرُّ الإتمام الفوريّ في المحاكاة',
        (tester) async {
      await _pump(tester,
          stored: {'pos_enabled_payment_methods': 'cash'});
      await goToPay(tester);

      expect(find.textContaining('إتمام فوري'), findsOneWidget,
          reason: 'المسارُ السريعُ يُلغي حوارَ الدفع، فالمحاكاةُ تعرض زرّاً '
              'واحداً لا شبكةَ طرق.');
    });

    testWidgets('وطريقتان ⇒ شبكةُ الطرق ولوحةُ المبالغ السريعة',
        (tester) async {
      await _pump(tester,
          stored: {'pos_enabled_payment_methods': 'cash,card'});
      await goToPay(tester);

      expect(find.textContaining('إتمام فوري'), findsNothing);
      expect(find.text('٥٠٠'), findsOneWidget,
          reason: 'لوحةُ المبالغ السريعة مضاءةٌ افتراضاً وتظهر مع الحوار.');
    });
  });

  group('الوضعُ الغامق', () {
    testWidgets('تُبنى بلا انهيارٍ ولا استثناء', (tester) async {
      await _pump(tester, brightness: Brightness.dark);

      expect(find.text('مسح الصنف'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
