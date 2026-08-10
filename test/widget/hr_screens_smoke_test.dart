// ═══════════════════════════════════════════════════════════════════════════
// تدخينُ شاشة الموارد البشرية — الوحدةُ التي شُحن فيها الأجرُ بالساعة.
// ═══════════════════════════════════════════════════════════════════════════
//
// قبل هذا الملف كانت **كلُّ** شاشات HR بلا تدخين، رغم أن خطةَ الأجر بالساعة
// عدّلت محرّكَها ولمست تبويبَي «الرواتب» و«إضافي». وتبويبٌ يسقط عند فتحه
// عطبٌ يراه العميلُ في أوّل دقيقة، ولا يمسكه أيُّ اختبارِ وحدة.
//
// ولا يكفي فتحُ الشاشة: `TabBarView` **لا يبني** إلا التبويبَ الظاهر، فاختبارٌ
// يفتح الشاشةَ وحدَها يُثبت تبويباً واحداً من ثمانية. لذلك يضغط هذا الاختبارُ
// كلَّ تبويبٍ ويفحص الاستثناءَ بعد كلّ ضغطة.
//
// الوصفةُ (تفكيكٌ ثم إطارٌ موجب ثم **لا** `db.close()`) منسوخةٌ عن
// `_support/screen_smoke.dart` — اقرأ رأسَه للسبب، وإلا علّق الاختبارُ ٤٥ ثانية.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/screens/hr_screen.dart';

/// عناوينُ التبويبات الثمانية بترتيبها في `hr_screen.dart`.
const List<String> _kTabs = [
  'لوحة المعلومات',
  'الموظفين',
  'الحضور',
  'الرواتب',
  'الإجازات',
  'إضافي',
  'الأداء',
  'العقود',
];

void main() {
  testWidgets(
    'HRScreen — التبويباتُ الثمانية تُفتَح بلا استثناء',
    timeout: const Timeout(Duration(seconds: 120)),
    (tester) async {
      final db = AppDatabase.forTesting();
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          locale: Locale('ar'),
          supportedLocales: [Locale('ar'), Locale('en')],
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: HRScreen(),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull,
          reason: 'التبويبُ الافتراضي (${_kTabs.first}) سقط عند الفتح');

      // التبويبُ الأول مبنيٌّ أصلاً، فالبدءُ من الثاني.
      for (var i = 1; i < _kTabs.length; i++) {
        final label = _kTabs[i];
        final tab = find.text(label);

        expect(tab, findsOneWidget, reason: 'تبويبُ «$label» غيرُ موجود');

        // `isScrollable: true` ⇒ تبويبٌ قد يكون خارجَ الشاشة فلا يُضغَط.
        await tester.ensureVisible(tab);
        await tester.pump();
        await tester.tap(tab);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(tester.takeException(), isNull,
            reason: 'تبويبُ «$label» سقط عند فتحه');
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
