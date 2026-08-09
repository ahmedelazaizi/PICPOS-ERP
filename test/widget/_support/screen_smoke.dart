// ═══════════════════════════════════════════════════════════════════════════
// تجهيزةُ فتحِ شاشةٍ كاملة في اختبار — والسببُ الذي جعلها مستحيلةً قبلها.
// ═══════════════════════════════════════════════════════════════════════════
//
// كانت محاولةُ فتح أيّ شاشةِ تقريرٍ تنتهي بمهلةٍ (‏٤٥ ثانية للواحدة، وشاشةٌ
// واحدةٌ معلّقة تُجهض بقيّةَ الملف)، فلم يكن في المستودع اختبارٌ **يفتح** شاشةً.
//
// ── السببُ الجذريّ، بأثرِ إنشاءِ المؤقّت لا بالتخمين ─────────────────────────
// شاشاتُ التقارير تقرأ مزوّداتِ `StreamProvider` مبنيّةً على تدفّقات
// ‏`drift` (`.watch()`). وعند تفكيك `ProviderScope` يُلغى الاشتراك، فينفّذ
// ‏drift داخل `StreamQueryStore.markAsClosed` جدولةَ `Timer(Duration.zero)`:
//
//     #6  StreamQueryStore.markAsClosed  (drift/…/stream_queries.dart:154)
//     #7  QueryStream._onCancelOrPause   (drift/…/stream_queries.dart:305)
//     #24 $StreamProviderElement.dispose (riverpod/…/stream_provider.dart:163)
//     #27 ProviderScopeState.dispose     (flutter_riverpod/…:220)
//     #34 …drawFrame                     (flutter_test/…/binding.dart:2153)
//
// والمؤقّتُ يُنشأ في **منطقة الزمن الوهمي** أثناء الإطار الأخير، فلا يُطلَق
// أبداً إن انتهى الاختبارُ عنده. ومنه ينشأ عطلان:
//
//   ١. `A Timer is still pending even after the widget tree was disposed`.
//   ٢. و`db.close()` ينتظر إغلاقَ مخزنِ التدفّقات المعلَّقِ على ذلك المؤقّت
//      ⇒ **لا يعود أبداً**. وهذا هو أصلُ «التعليق»، لا عطلٌ في الشاشة.
//
// ── ما لا يُصلحه (مُجرَّبٌ ومقيس) ───────────────────────────────────────────
//   • `tester.runAsync(() => db.close())` — يخرج من المنطقة التي فيها
//     المؤقّت، فيزيد الأمرَ سوءاً.
//   • تفكيكُ الشجرة وحدَه ثم الإغلاق.
//   • تأجيلُ الإغلاق إلى `tearDownAll` خارج المنطقة الوهمية.
//
// ── الوصفةُ الصحيحة ────────────────────────────────────────────────────────
//   ١. افتح الشاشة وادفع إطاراً أو إطارين.
//   ٢. **فكّك الشجرة** (`pumpWidget(SizedBox())`) — يُلغي التدفّقات.
//   ٣. **ادفع إطاراً بزمنٍ موجب** — يُطلق مؤقّتَ drift داخل نفس المنطقة.
//   ٤. **لا تُغلق القاعدة.** قاعدةُ الاختبار في الذاكرة وتموت مع العملية،
//      وإغلاقُها هو ما كان يعلّق. (‏٣ شاشاتٍ معلّقة ⇒ ١٢ ثانية بعد الحذف.)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';

/// يفتح [screen] على قاعدةٍ في الذاكرة ويعيد ما سجّله الإطارُ من استثناء
/// (‏`null` = رُسمت نظيفةً). يشمل ذلك `RenderFlex overflow` لأنه يُسجَّل
/// استثناءً أثناء التخطيط.
///
/// والمقاسُ مكتبيٌّ (‏١٩٢٠×١٠٨٠) عن قصد: الافتراضيُّ ٨٠٠×٦٠٠ وخطُّ الاختبار
/// يرسم كلَّ محرفٍ مربّعاً كاملَ العرض، فالنصُّ العربيّ يخرج أعرضَ من الواقع
/// ويولّد فيضاناتٍ وهمية. وهذه الشاشات تعمل على سطح مكتب.
///
/// ⚠️ ومع ذلك يبقى الخطُّ متضخّماً، ففيضانٌ صغير هنا **مشتبهٌ به لا مؤكَّد**.
Future<Object?> pumpScreen(WidgetTester tester, Widget Function() screen) async {
  final db = AppDatabase.forTesting();
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // ⚠️ مندوبو التوطين **ليسوا تجميلاً** هنا: اثنتا عشرة شاشةً تستعمل
  // `DateFormat('…', 'ar')`، والتطبيقُ لا ينادي `initializeDateFormatting`
  // في أيّ موضع — بل `GlobalMaterialLocalizations` هي التي تُهيّئ رموزَ
  // التواريخ عند تحميل اللغة. فـ`MaterialApp` عاريةً ترمي
  // `LocaleDataException` وتبدو عطلاً في الشاشة وهي نقصٌ في التجهيزة.
  // مطابقةً لـ`lib/main.dart:1274`.
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
      home: screen(),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));

  final error = tester.takeException();

  // الخطوتان اللتان تمنعان «المؤقّت المعلّق» — انظر الشرح أعلاه.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));

  return error;
}
