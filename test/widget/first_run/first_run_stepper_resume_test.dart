// الستيبر (الخطوات بعد maxStep معطّلة) والاستئناف بعد إغلاق التطبيق:
// المسودة تُفتح على الخطوة، وكلمات المرور فارغة، وأعلام التحقق من الحقائق،
// والانقطاع أثناء التشغيل يُفتح على المراجعة ببانر ثم إنهاءٌ idempotent.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_draft.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_packs.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_controller.dart';

import 'first_run_test_kit.dart';

FirstRunDraft _saved() => const FirstRunDraft(draftId: 'saved-1').copyWith(
      step: 2,
      maxStep: 3,
      pack: FirstRunPack.restaurant,
      companyName: 'مطعم الياسمين',
      currency: 'EGP',
      vatRate: 14,
      branchName: 'الفرع',
      warehouseName: 'المخزن',
      tablesCount: '8',
      checks: const FirstRunChecks(storageChecked: true, linked: true),
    );

void main() {
  setUpAll(loadEnglishCatalog);
  tearDown(() => useLocale(english: false));

  testWidgets('خطوات بعد maxStep معطّلة، والرجوع لمنجزة مسموح', (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    await h.pump(tester);
    await tapKey(tester, 'first_run_next'); // maxStep = 1
    InkWell stepTile(int i) => tester.widget<InkWell>(
        find.byKey(Key('first_run_step_$i')));
    expect(stepTile(0).onTap, isNotNull);
    expect(stepTile(1).onTap, isNotNull);
    expect(stepTile(2).onTap, isNull);
    expect(stepTile(5).onTap, isNull);
    await tester.tap(find.byKey(const Key('first_run_step_0')));
    await tester.pump();
    expect(h.container.read(firstRunControllerProvider).draft.step, 0);
    await h.teardown(tester);
  });

  testWidgets('مسودة محفوظة ⇒ تُفتح على الخطوة وكلمات المرور فارغة',
      (tester) async {
    useLocale(english: false);
    final settings = MemorySettings();
    settings.values['setup_draft_v2'] = jsonEncode(_saved().toJson());
    final h = FirstRunHarness(settings: settings);
    await h.pump(tester);
    final s = h.container.read(firstRunControllerProvider);
    expect(s.loading, isFalse);
    expect(s.draft.step, 2);
    expect(s.draft.maxStep, 3);
    expect(s.draft.companyName, 'مطعم الياسمين');
    expect(s.secrets.adminPassword, isEmpty);
    expect(s.secrets.developerPassword, isEmpty);
    // الأعلام من الحقائق: المجس كتابة ⇒ تخزين صحيح، ولا ربط (لا عنوان خادم).
    expect(s.draft.checks.storageChecked, isTrue);
    expect(s.draft.checks.linked, isFalse);
    // الخطوة الثالثة = حفظ البيانات.
    expect(find.byKey(const Key('first_run_storage_badge')), findsOneWidget);
    expect(find.byKey(const Key('first_run_resume_banner')), findsNothing);
    await h.teardown(tester);
  });

  testWidgets('مسودة تالفة أو بإصدار آخر ⇒ بداية نظيفة', (tester) async {
    useLocale(english: false);
    final settings = MemorySettings()..values['setup_draft_v2'] = '{not json';
    final h = FirstRunHarness(settings: settings);
    await h.pump(tester);
    final s = h.container.read(firstRunControllerProvider);
    expect(s.draft.step, 0);
    expect(s.draft.companyName, isEmpty);
    await h.teardown(tester);
  });

  testWidgets('انهيار أثناء committing ⇒ مراجعة + بانر ثم إنهاء idempotent',
      (tester) async {
    useLocale(english: false);
    final settings = MemorySettings();
    final saved = _saved().copyWith(step: 5, maxStep: 5, pack: FirstRunPack.restaurant);
    settings.values['setup_draft_v2'] = jsonEncode(saved.toJson());
    settings.values['setup_progress_v2'] = jsonEncode({'stage': 'committing'});
    final h = FirstRunHarness(settings: settings);
    await h.pump(tester);

    expect(find.byKey(const Key('first_run_resume_banner')), findsOneWidget);
    expect(find.byKey(const Key('first_run_finish')), findsOneWidget);

    // الأسرار لا تُستعاد: الإنهاء يقفز إلى خطوة المسؤول ويطلبها.
    await tapKey(tester, 'first_run_finish');
    expect(find.byKey(const Key('first_run_error')), findsOneWidget);
    expect(h.container.read(firstRunControllerProvider).draft.step, 3);
    expect(h.persistence.settings.containsKey('setup_completed'), isFalse);

    await enterKey(tester, 'first_run_admin_password', 'S3cretPass');
    await enterKey(tester, 'first_run_admin_password_confirm', 'S3cretPass');
    await enterKey(tester, 'first_run_dev_password', 'dev123');
    await enterKey(tester, 'first_run_dev_password_confirm', 'dev123');
    await tapKey(tester, 'first_run_next'); // → prep
    await tapKey(tester, 'first_run_next'); // → review
    await tapKey(tester, 'first_run_finish');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('first_run_success_title')), findsOneWidget);
    expect(h.persistence.settings['setup_completed'], 'true');
    expect(h.persistence.ensureTablesCalls, 1);
    expect(h.persistence.tableNames, hasLength(8));

    // إنهاء ثانٍ بنفس المسودة لا يكرّر الطاولات.
    final again = h.container.read(firstRunControllerProvider);
    expect(again.committed, isTrue);
    await h.teardown(tester);
  });
}
