// المسار المستقل من الطرف إلى الطرف على 1366×768: ست خطوات ← إنهاء ← نجاح،
// و`setup_completed` آخرُ كتابة، وفشلُ مرحلةٍ يبقى على المراجعة ولا يكتبه،
// وEnter يُكمل بلوحة المفاتيح.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_controller.dart';

import 'first_run_test_kit.dart';

void main() {
  setUpAll(loadEnglishCatalog);
  tearDown(() => useLocale(english: false));

  testWidgets('ست خطوات ثم نجاح، وsetup_completed آخر كتابة', (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    await h.pump(tester);
    expect(find.byKey(const Key('first_run_step_counter')), findsOneWidget);
    expect(find.text('1 من 6'), findsOneWidget);

    await fillStandaloneUntilReview(tester);
    expect(find.text('6 من 6'), findsOneWidget);
    expect(find.byKey(const Key('first_run_finish')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tapKey(tester, 'first_run_finish');
    await tester.pump(const Duration(milliseconds: 50));

    // صفحة النجاح بعد الكتابة الفعلية.
    expect(find.byKey(const Key('first_run_success_title')), findsOneWidget);
    final p = h.persistence;
    expect(p.settings['setup_completed'], 'true');
    final saves = p.calls.where((c) => c.startsWith('save:')).toList();
    expect(saves.last, 'save:setup_in_progress'); // يُمسح بعد setup_completed
    expect(saves[saves.length - 2], 'save:setup_completed');
    expect(p.calls.indexOf('save:setup_completed'),
        greaterThan(p.calls.indexOf('mode:standalone')));
    expect(p.adminPassword, 'S3cretPass');
    expect(p.developerPassword, 'dev123');
    expect(p.currency, 'JOD');
    expect(p.settings['tax_rate'], '16.0');
    expect(p.settings['company_name'], 'شركة الأمل');
    expect(p.settings['business_profile'], 'lite');
    // المسودة والسجل تُمسحان، والأسرار لا تصل المخزن أبداً.
    expect(h.settings.values['setup_draft_v2'], isEmpty);
    expect(h.settings.values.values.join('|'), isNot(contains('S3cretPass')));
    expect(h.container.read(firstRunControllerProvider).secrets.adminPassword,
        isEmpty);

    await tapKey(tester, 'first_run_start');
    expect(h.started, isTrue);
    await h.teardown(tester);
  });

  testWidgets('فشل مرحلة ⇒ يبقى على المراجعة بلا setup_completed، ثم تنجح الإعادة',
      (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    h.persistence.failOnKey = 'tax_enabled';
    await h.pump(tester);
    await fillStandaloneUntilReview(tester);

    await tapKey(tester, 'first_run_finish');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('first_run_failure')), findsOneWidget);
    expect(find.byKey(const Key('first_run_success_title')), findsNothing);
    expect(h.persistence.settings.containsKey('setup_completed'), isFalse);
    // تقدّمُ التشغيل سُجّل ليُستأنف إن أُغلق التطبيق هنا.
    expect(h.settings.values['setup_progress_v2'], contains('committing'));

    h.persistence.failOnKey = null;
    await tapKey(tester, 'first_run_finish');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('first_run_success_title')), findsOneWidget);
    expect(h.persistence.settings['setup_completed'], 'true');
    expect(h.settings.values['setup_progress_v2'], isEmpty);
    await h.teardown(tester);
  });

  testWidgets('Enter يتقدّم حتى الإنهاء بلوحة المفاتيح فقط', (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    await h.pump(tester);

    Future<void> enter() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 50));
    }

    await enter(); // mode → company
    await enterKey(tester, 'first_run_company_name', 'متجر النور');
    await tapKey(tester, 'first_run_currency_EGP');
    // البؤرة في حقل الاسم (بعد enterText) ⇒ Enter عليه يتقدّم.
    await enter(); // → storage
    expect(find.byKey(const Key('first_run_storage_badge')), findsOneWidget);
    await h.teardown(tester);
  });

  testWidgets('تخطي الخطوة بنقر عمود الخطوات غير المنجزة معطّل', (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    await h.pump(tester);
    await tester.tap(find.byKey(const Key('first_run_step_4')));
    await tester.pump();
    expect(h.container.read(firstRunControllerProvider).draft.step, 0);
    await h.teardown(tester);
  });
}
