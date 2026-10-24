// UX-001/UX-004: الشرائحُ JOD وEGP فقط (= CurrencyInfo.all)، بلا اختيار مسبق،
// و«التالي» معطّل حتى الاختيار، والاشتقاقُ (16%/JoFotara · 14%/ETA)،
// وما يصل الإعداداتِ عملةٌ معتمدة.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/constants/app_constants.dart' show CurrencyInfo;
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_currency.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_controller.dart';

import 'first_run_test_kit.dart';

FilledButton _next(WidgetTester t) =>
    t.widget<FilledButton>(find.byKey(const Key('first_run_next')));

void main() {
  setUpAll(loadEnglishCatalog);
  tearDown(() => useLocale(english: false));

  for (final english in [false, true]) {
    testWidgets('الشرائح JOD/EGP فقط وبلا اختيار مسبق (${english ? 'EN' : 'AR'})',
        (tester) async {
      useLocale(english: english);
      final h = FirstRunHarness();
      await h.pump(tester);
      await tapKey(tester, 'first_run_next');
      await enterKey(tester, 'first_run_company_name', 'شركة');

      final chips = find.byWidgetPredicate((w) =>
          w is ChoiceChip &&
          (w.key as ValueKey<String>?)?.value.startsWith('first_run_currency_') ==
              true);
      expect(chips, findsNWidgets(CurrencyInfo.all.length));
      expect(CurrencyInfo.all.map((c) => c.code), kFirstRunCurrencies);
      for (final code in kFirstRunCurrencies) {
        expect(find.byKey(Key('first_run_currency_$code')), findsOneWidget);
      }
      for (final bad in ['SAR', 'AED', 'KWD', 'USD']) {
        expect(find.byKey(Key('first_run_currency_$bad')), findsNothing);
      }
      // لا اختيار مسبق: لا شريحةَ محدّدة، والتالي معطّل.
      expect(
        tester.widgetList<ChoiceChip>(chips).where((c) => c.selected),
        isEmpty,
      );
      expect(h.container.read(firstRunControllerProvider).draft.currency, '');
      expect(_next(tester).onPressed, isNull);
      expect(find.byKey(const Key('first_run_blocked_hint')), findsOneWidget);

      await tapKey(tester, 'first_run_currency_JOD');
      expect(_next(tester).onPressed, isNotNull);
      final d = h.container.read(firstRunControllerProvider).draft;
      expect(d.currency, 'JOD');
      expect(d.vatRate, 16);
      expect(d.eInvoice, FirstRunEInvoice.jordan);
      expect(find.byKey(const Key('first_run_currency_decimals')), findsOneWidget);

      await tapKey(tester, 'first_run_currency_EGP');
      final e = h.container.read(firstRunControllerProvider).draft;
      expect((e.currency, e.vatRate, e.eInvoice),
          ('EGP', 14, FirstRunEInvoice.egypt));
      if (english) {
        expect(I18nCatalog.missingKeys, isEmpty);
      }
      await h.teardown(tester);
    });
  }

  testWidgets('system_currency المكتوب ∈ {JOD, EGP} وتأكيد العملة في المراجعة',
      (tester) async {
    useLocale(english: false);
    final h = FirstRunHarness();
    await h.pump(tester);
    await fillStandaloneUntilReview(tester, currency: 'EGP');
    expect(find.byKey(const Key('first_run_currency_confirm')), findsOneWidget);
    await tapKey(tester, 'first_run_finish');
    await tester.pump(const Duration(milliseconds: 50));
    expect(h.persistence.currency, 'EGP');
    expect(kFirstRunCurrencies, contains(h.persistence.currency));
    expect(h.persistence.settings['tax_rate'], '14.0');
    expect(h.persistence.settings['show_eta_einvoice'], 'true');
    expect(h.persistence.settings['show_jofotara_einvoice'], 'false');
    await h.teardown(tester);
  });
}
