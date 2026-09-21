// أزرارُ ترويسة PicPos تتّسع بسعة الشاشة — بلاغٌ ميدانيٌّ 2026-09-21.
//
// ═══ ما بُلِّغ ═══
//
// «زرُّ إضافة طاولةٍ جديدةٍ في شاشة الطاولات… متآكلٌ نصُّه» — يظهر منه
// «ة طاولة» والباقي مقصوصٌ عند الحافّة، على نافذةٍ عرضُها ١٧٠٩ بكسلاً
// وفيها متّسعٌ واسع.
//
// ═══ والسببُ: سقفٌ «متجاوبٌ» ميّتٌ منذ كُتب ═══
//
// مجموعةُ الذيل في `PicPosPageHeader` تعيش في `SingleChildScrollView`
// أفقيٍّ مثبَّتٍ من آخره (`reverse: true`) — فإذا ضاقت انزلق **أوّلُ** زرٍّ
// خارجَ النافذة. وسقفُها كان:
//
//     maxWidth: c.maxWidth.isFinite ? c.maxWidth * 0.72 : 720
//
// و`LayoutBuilder` هناك طفلٌ **غيرُ مرنٍ** في `Row`، و`Row` يعطي أطفالَه
// غيرَ المرنين قيداً أفقيّاً **لا نهائيّاً**. فـ`isFinite` كاذبةٌ دائماً،
// والسقفُ يقع على الاحتياط `720` **مهما اتّسعت الشاشة** — والنيّةُ المكتوبةُ
// فوقَه («٧٢٪ للأزرار و٢٨٪ للعنوان») لم تُنفَّذ قطّ.
//
// ═══ ولماذا يُقاس العرضُ لا الرسم ═══
//
// ⚠️ `RenderFlex overflowed` **لا يرمي** هنا أصلاً: المجموعةُ تتمرّر ولا
//    تفيض، فلا خطأَ ولا تحذير — الزرُّ يختفي بصمتٍ تامّ. ولذلك المقياسُ
//    **عرضُ النافذة** لا وقوعُ استثناء.
//
// ⚠️ **وبعرضَين لا عرضٍ واحد** — عرفُ هذا المستودع في التخطيط: فيضانٌ عند
//    ١٢٨٠ يمرّ خضراءَ عند ١٩٢٠، وهنا العكسُ يلزم: سقفٌ ثابتٌ يبدو سليماً
//    عند العرض الضيّق ويكشف نفسَه عند الواسع.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:ural_erp/presentation/picpos_shell/picpos_screen_scaffold.dart';

/// حملُ شاشة «إدارة الطاولات» بنصوصه — وهي أثقلُ ترويسةٍ في المستودع.
List<Widget> _tablesActions() => [
      OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(PhosphorIconsBold.plus, size: 18),
        label: const Text('إضافة طاولة'),
      ),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(PhosphorIconsBold.mapPinArea, size: 18),
        label: const Text('إدارة الأقسام'),
      ),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(PhosphorIconsBold.mapTrifold, size: 18),
        label: const Text('عرض الخريطة'),
      ),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(PhosphorIconsBold.squaresFour, size: 18),
        label: const Text('مصمم القاعة'),
      ),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(PhosphorIconsBold.mapPin, size: 18),
        label: const Text('كل المناطق'),
      ),
      const SizedBox(width: 8),
      IconButton(onPressed: () {}, icon: const Icon(PhosphorIconsBold.dotsThree)),
    ];

Future<void> _pump(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar'), Locale('en')],
      locale: const Locale('ar'),
      home: PicPosScreenScaffold(
        title: 'إدارة الطاولات',
        subtitle: 'كل المناطق',
        icon: PhosphorIconsBold.circlesThree,
        headerActions: _tablesActions(),
        body: const SizedBox.shrink(),
      ),
    ),
  );
  await tester.pump();
}

/// نافذةُ تمرير مجموعةِ الذيل — الوحيدةُ في الترويسة.
Rect _viewport(WidgetTester tester) =>
    tester.getRect(find.byType(SingleChildScrollView).first);

void main() {
  testWidgets('مرساةٌ — الترويسةُ تُرسَم وفيها نافذةُ تمريرٍ واحدة',
      (tester) async {
    await _pump(tester, 1920);
    expect(find.byType(SingleChildScrollView), findsOneWidget,
        reason: 'تغيّر تركيبُ الترويسة — وما تحته يقيس شيئاً آخر');
    expect(find.text('إدارة الطاولات'), findsOneWidget);
  });

  testWidgets('🔴 وسعةُ الأزرار تنمو بنمو الشاشة — لا سقفَ ثابت',
      (tester) async {
    await _pump(tester, 1280);
    final narrow = _viewport(tester).width;

    await _pump(tester, 1920);
    final wide = _viewport(tester).width;

    expect(narrow, greaterThan(0), reason: 'لم تُرسَم المجموعةُ أصلاً');
    expect(wide, greaterThan(narrow + 100),
        reason: '🔴 السقفُ ثابتٌ لا متجاوب: المجموعةُ نالت $narrow عند ١٢٨٠ '
            'و$wide عند ١٩٢٠. و`LayoutBuilder` طفلٌ غيرُ مرنٍ في `Row` '
            'فقيدُه لا نهائيٌّ دوماً، والسقفُ يسقط على الاحتياط ٧٢٠ — '
            'فتُقَصُّ الأزرارُ على شاشةٍ فيها متّسعٌ واسع');
  });

  testWidgets('🔴 وأوّلُ زرٍّ ظاهرٌ كاملاً على شاشةٍ واسعة', (tester) async {
    // 🔴 هو «إضافة طاولة» في البلاغ: `reverse: true` يثبّت المجموعةَ من
    //    آخرها، فالمقصوصُ دائماً **أوّلُها**.
    await _pump(tester, 1920);

    final vp = _viewport(tester);
    final btn = tester.getRect(
      find.ancestor(
        of: find.text('إضافة طاولة'),
        matching: find.byType(OutlinedButton),
      ),
    );

    expect(btn.left, greaterThanOrEqualTo(vp.left - 0.5),
        reason: '🔴 «إضافة طاولة» مقصوصٌ من أوّله — وهو عينُ البلاغ');
    expect(btn.right, lessThanOrEqualTo(vp.right + 0.5),
        reason: '🔴 «إضافة طاولة» يتجاوز نافذةَ العرض');
  });

  testWidgets('✅ ومرساةٌ معاكسة — عند الضيق الحقيقيّ تبقى قابلةً للتمرير',
      (tester) async {
    // بلا هذه يبدو الإصلاحُ وكأنّه «وسِّع السقفَ حتى يختفي التمرير»، فيُحذَف
    // غداً ويعود الفيضانُ على الشاشات الصغيرة. التمريرُ آليّةٌ مقصودةٌ
    // تبقى — المعطوبُ كان السقفَ الثابتَ لا وجودُ التمرير.
    await _pump(tester, 700);
    final vp = _viewport(tester);
    final content = tester.getRect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Row),
      ).first,
    );
    expect(content.width, greaterThan(vp.width),
        reason: 'عند ٧٠٠ يجب أن يتجاوز المحتوى النافذةَ فيتمرّر');
  });
}
