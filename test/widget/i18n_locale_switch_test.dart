import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/i18n/locale_provider.dart';
import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/presentation/widgets/user_language_selector.dart';

class _LocaleHarness extends ConsumerWidget {
  const _LocaleHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(userLocaleProvider);
    return MaterialApp(
      locale: locale,
      supportedLocales: const [defaultUserLocale, englishUserLocale],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Scaffold(body: _NavHome()),
    );
  }
}

class _NavHome extends ConsumerWidget {
  const _NavHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(userLocaleProvider);
    return Column(
      children: [
        Text(tr('البيع السريع')),
        const UserLanguageSelector(),
      ],
    );
  }
}

void main() {
  testWidgets('switching a user to English renders nav text LTR',
      (tester) async {
    I18nCatalog.setCatalog({'البيع السريع': 'Quick Sale'});
    I18nCatalog.setLocale(defaultUserLocale);
    await tester.pumpWidget(const ProviderScope(child: _LocaleHarness()));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(_LocaleHarness)),
    );
    await container
        .read(userLocaleProvider.notifier)
        .setLocale(englishUserLocale);
    await tester.pump();

    expect(find.text('Quick Sale'), findsOneWidget);
    final directionality = tester.widget<Directionality>(
      find.ancestor(
        of: find.text('Quick Sale'),
        matching: find.byType(Directionality),
      ).first,
    );
    expect(directionality.textDirection, TextDirection.ltr);
  });
}
