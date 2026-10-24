// UX-005: اسمٌ عربي يصل الإعداداتِ كما كُتب، ويصحّ تعديلُه من المراجعة ثم يصل
// الاسمُ الأحدث — لا اسمَ قديم ولا فقدَ حروف.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'first_run_test_kit.dart';

void main() {
  setUpAll(loadEnglishCatalog);
  tearDown(() => useLocale(english: false));

  testWidgets('اسم الشركة العربي ثم تعديله يصل إلى الإعدادات', (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    await h.pump(tester);
    await fillStandaloneUntilReview(tester, company: 'مؤسسة النور للتجارة');
    expect(find.text('مؤسسة النور للتجارة'), findsOneWidget);

    // «تعديل» من المراجعة ⇒ خطوة الشركة، نغيّر الاسم، ونعود.
    await tapKey(tester, 'first_run_edit_company');
    await enterKey(tester, 'first_run_company_name', 'مؤسسة الأمل الحديثة');
    for (var i = 0; i < 4; i++) {
      await tapKey(tester, 'first_run_next');
    }
    expect(find.byKey(const Key('first_run_finish')), findsOneWidget);
    expect(find.text('مؤسسة الأمل الحديثة'), findsOneWidget);

    await tapKey(tester, 'first_run_finish');
    await tester.pump(const Duration(milliseconds: 50));
    expect(h.persistence.settings['company_name'], 'مؤسسة الأمل الحديثة');
    await h.teardown(tester);
  });
}
