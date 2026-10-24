// حالة القبول 1 (مستقل + مطاعم فقط): ملف النشاط restaurant + قسم + N طاولات +
// overrides للطاولات والتوصيل — كلها قبل setup_completed، والإعادة لا تكرّر.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'first_run_test_kit.dart';

void main() {
  setUpAll(loadEnglishCatalog);
  tearDown(() => useLocale(english: false));

  testWidgets('باقة مطاعم ⇒ profile + طاولات + overrides قبل setup_completed',
      (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    await h.pump(tester);
    await tapKey(tester, 'first_run_next');
    await tapKey(tester, 'first_run_pack_restaurant');
    await enterKey(tester, 'first_run_company_name', 'مطعم الياسمين');
    await tapKey(tester, 'first_run_currency_JOD');
    await tapKey(tester, 'first_run_next'); // storage
    await tapKey(tester, 'first_run_next'); // users
    await enterKey(tester, 'first_run_admin_password', 'Rest@urant1');
    await enterKey(tester, 'first_run_admin_password_confirm', 'Rest@urant1');
    await enterKey(tester, 'first_run_dev_password', 'dev123');
    await enterKey(tester, 'first_run_dev_password_confirm', 'dev123');
    await tapKey(tester, 'first_run_next'); // prep
    expect(find.byKey(const Key('first_run_tables_count')), findsOneWidget);
    await tapKey(tester, 'first_run_service_all');
    await enterKey(tester, 'first_run_tables_count', '12');
    await tapKey(tester, 'first_run_next'); // review
    await tapKey(tester, 'first_run_finish');
    await tester.pump(const Duration(milliseconds: 50));

    final p = h.persistence;
    expect(p.settings['business_profile'], 'restaurant');
    expect(p.settings['business_type'], 'restaurant');
    expect(p.settings['feature.pos.tables'], 'true');
    expect(p.settings['feature.pos.delivery'], 'true');
    expect(p.tableNames, hasLength(12));
    expect(p.ensureTablesCalls, 1);
    // الإضافات قبل setup_completed.
    expect(p.calls.indexOf('tables:12'),
        lessThan(p.calls.indexOf('save:setup_completed')));
    expect(p.calls.indexOf('cached:feature.pos.tables'),
        lessThan(p.calls.indexOf('save:setup_completed')));
    expect(find.byKey(const Key('first_run_success_title')), findsOneWidget);
    await h.teardown(tester);
  });

  testWidgets('سفري وتوصيل فقط ⇒ لا طاولات، و override tables=false', (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    await h.pump(tester);
    await tapKey(tester, 'first_run_next');
    await tapKey(tester, 'first_run_pack_restaurant');
    await enterKey(tester, 'first_run_company_name', 'مطعم');
    await tapKey(tester, 'first_run_currency_JOD');
    await tapKey(tester, 'first_run_next');
    await tapKey(tester, 'first_run_next');
    await enterKey(tester, 'first_run_admin_password', 'Rest@urant1');
    await enterKey(tester, 'first_run_admin_password_confirm', 'Rest@urant1');
    await enterKey(tester, 'first_run_dev_password', 'dev123');
    await enterKey(tester, 'first_run_dev_password_confirm', 'dev123');
    await tapKey(tester, 'first_run_next');
    await tapKey(tester, 'first_run_service_takeawayDelivery');
    expect(find.byKey(const Key('first_run_tables_count')), findsNothing);
    await tapKey(tester, 'first_run_next');
    await tapKey(tester, 'first_run_finish');
    await tester.pump(const Duration(milliseconds: 50));
    expect(h.persistence.settings['feature.pos.tables'], 'false');
    expect(h.persistence.settings['feature.pos.delivery'], 'true');
    expect(h.persistence.ensureTablesCalls, 0);
    await h.teardown(tester);
  });

  testWidgets('باقة نقطة بيع فقط لا تكتب أي override للطاولات', (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    await h.pump(tester);
    await fillStandaloneUntilReview(tester);
    await tapKey(tester, 'first_run_finish');
    await tester.pump(const Duration(milliseconds: 50));
    expect(h.persistence.settings.containsKey('feature.pos.tables'), isFalse);
    expect(h.persistence.ensureTablesCalls, 0);
    await h.teardown(tester);
  });
}
