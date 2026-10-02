// شاشةُ أوامر الشراء — زرُّ الرجوع، ومحاذاةُ الترويسة بعده.
//
// ═══ ما يحمي هذا الملفّ ═══
//
// بلاغُ المالك 2026-08-26: «تقرير أوامر الشراء ليس به زر رجوع». والشاشةُ
// تُفتَح من **أربعة** مواضع، ثلاثةٌ منها `Navigator.push` وواحدٌ من الشريط
// الجانبيّ. فكانت الثلاثةُ تقع في شاشةٍ لا مخرجَ منها.
//
// وفحصان لا واحد، لأنّ الإصلاحَ الساذجَ يكسر الرابع:
//
//  ‏١) **مدفوعةً** ⇒ الزرُّ ظاهر.
//  ‏٢) **من الشريط الجانبيّ** (`canPop == false`) ⇒ الزرُّ **غائب**. زرُّ
//     رجوعٍ هناك إمّا لا يفعل شيئاً أو يخرج من التطبيق.
//
// ⚠️ **وفحصُ الفيض ليس زينة**: الزرُّ يأكل ~٥٨ بكسلاً من ترويسةٍ عمودُ
// عنوانها بلا `Flexible`. وهو عينُ العطب الذي كلّف `PicPosPageHeader` فيضاً
// قدرُه ٤٧٥ بكسلاً — ودجتٌ عاشت به منذ كُتبت ولم يظهر حتى ضاقت الترويسة.
//
// ⚠️ ولا `db.close()` ولا `pumpAndSettle`: تدفّقاتُ drift تعلّق كليهما في
// المنطقة الوهميّة. الوصفةُ الكاملةُ في `_support/screen_smoke.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/screens/purchase_orders_screen.dart';

void main() {
  /// يفتح الشاشة — مدفوعةً أو جذراً — ويعيد ما سجّله الإطارُ من استثناء.
  Future<Object?> open(
    WidgetTester tester, {
    required bool pushed,
    required Size size,
  }) async {
    final db = AppDatabase.forTesting();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // مندوبو التوطين ليسوا تجميلاً — بدونهم ترمي `DateFormat('…','ar')`.
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: pushed
            ? Scaffold(
                body: Builder(
                  builder: (ctx) => Center(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PurchaseOrdersScreen(),
                        ),
                      ),
                      child: const Text('افتح'),
                    ),
                  ),
                ),
              )
            : const PurchaseOrdersScreen(),
      ),
    ));
    await tester.pump();

    if (pushed) {
      await tester.tap(find.text('افتح'));
      // ‏`pump` مرّتين لا `pumpAndSettle`: انتقالُ الراوت مؤقّتٌ، وتدفّقُ
      // drift لا يستقرّ في المنطقة الوهميّة فتنفد المهلة.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    } else {
      await tester.pump(const Duration(seconds: 1));
    }

    // ⚠️ **لا تفكيكَ هنا**: الفحوصُ تقع بعد `open`، ولو فُكّت الشجرةُ قبل
    // العودة لبحثت كلُّ `find` في `SizedBox` فارغةٍ ومرّت أو سقطت بسببٍ
    // كاذب — أمسك ذلك المرساةُ في الفحص الثاني.
    return tester.takeException();
  }

  /// يُفكّك الشجرةَ ويُطلق مؤقّتَ drift **داخلَ جسم الاختبار**.
  ///
  /// ⚠️ ولا يصلح `addTearDown` لهذا: يعمل **بعد** فحصِ إطارِ الاختبار
  /// للمؤقّتات المعلّقة، فيسقط الاختبارُ بـ«A Timer is still pending» رغم
  /// صحّة كلّ توقّعاته. مقيسٌ هنا.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  // في RTL «رجوع» سهمٌ إلى اليمين — نفسُ عقد `PicPosPageHeader`:
  // `arrow_back` بـ`matchTextDirection` يُرسَم → في RTL و← في LTR.
  final backButton = find.widgetWithIcon(IconButton, Icons.arrow_back);

  testWidgets('مدفوعةً ⇒ زرُّ الرجوع ظاهر', (tester) async {
    final err = await open(tester, pushed: true, size: const Size(1920, 1080));
    expect(err, isNull, reason: 'الشاشةُ رمت أثناء الرسم');
    expect(backButton, findsOneWidget,
        reason: 'شاشةٌ مدفوعةٌ بلا مخرج — عينُ بلاغ المالك');
    await dispose(tester);
  });

  testWidgets('من الشريط الجانبيّ ⇒ لا زرَّ رجوع', (tester) async {
    final err = await open(tester, pushed: false, size: const Size(1920, 1080));
    expect(err, isNull);
    // مرساة: الشاشةُ فُتحت فعلاً — وإلّا مرّ الفحصُ على شجرةٍ فارغة.
    expect(find.text('أوامر الشراء'), findsWidgets,
        reason: 'الشاشةُ لم تُرسَم — الفحصُ أعمى');
    expect(backButton, findsNothing,
        reason: 'زرُّ رجوعٍ في أعلى المكدّس يخرج من التطبيق');
    await dispose(tester);
  });

  testWidgets('الترويسةُ لا تفيض بعد إضافة الزرّ — عرضٌ ضيّق',
      (tester) async {
    // الزرُّ يأكل ~٥٨ بكسلاً. لوحُ كاشيرٍ ضيّقٌ هو ما يكشف ذلك لا ١٩٢٠.
    final err = await open(tester, pushed: true, size: const Size(1024, 768));
    expect(err, isNull,
        reason: 'الترويسةُ فاضت بعد إضافة الزرّ — عمودُ العنوان يحتاج Flexible');
    expect(backButton, findsOneWidget);
    await dispose(tester);
  });
}
