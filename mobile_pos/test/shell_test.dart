import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_pos/app.dart';
import 'package:picpos_pos/l10n/strings.dart';
import 'package:picpos_pos/screens/onboarding_screen.dart';
import 'package:picpos_pos/shell/pos_shell.dart';
import 'package:picpos_ui/picpos_ui.dart';

import 'support.dart';

void main() {
  setUpAll(loadTestFonts);

  group('AR/EN × light/dark × phone/tablet: no overflow', () {
    for (final lang in ['ar', 'en']) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        for (final MapEntry(key: sizeName, value: size) in kSizes.entries) {
          testWidgets('$lang ${mode.name} $sizeName', (tester) async {
            setSurface(tester, size);
            PicPosAppSettings settings() => PicPosAppSettings(locale: Locale(lang), themeMode: mode);

            await tester.pumpWidget(PicPosPosApp(key: const ValueKey('onboarding'), settings: settings()));
            await tester.pumpAndSettle();
            expect(find.byType(OnboardingScreen), findsOneWidget);
            expect(tester.takeException(), isNull);

            for (var i = 0; i < PosShell.destinationCount; i++) {
              await tester.pumpWidget(
                  PicPosPosApp(key: ValueKey(i), settings: settings(), startInShell: true, initialDestination: i));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: 'destination $i');
              final ctx = tester.element(find.byType(PosShell));
              expect(Directionality.of(ctx), lang == 'ar' ? TextDirection.rtl : TextDirection.ltr);
              expect(Theme.of(ctx).brightness, mode == ThemeMode.dark ? Brightness.dark : Brightness.light);
              if (size == kPhone) {
                expect(find.byType(NavigationBar), findsOneWidget);
                expect(find.byType(NavigationDestination), findsNWidgets(5)); // no «More»
              } else {
                expect(find.byType(NavigationRail), findsOneWidget);
              }
            }
          });
        }
      }
    }
  });

  testWidgets('tablet sale screen: items on the start side, cart on the end side (mirrors in LTR)', (tester) async {
    setSurface(tester, kTablet);
    for (final (lang, cart) in [('ar', 'السلة'), ('en', 'Cart')]) {
      await tester.pumpWidget(
          PicPosPosApp(key: ValueKey(lang), settings: PicPosAppSettings(locale: Locale(lang)), startInShell: true));
      await tester.pumpAndSettle();
      final cartX = tester.getCenter(find.text(cart)).dx;
      final itemsX = tester.getCenter(find.byIcon(Icons.grid_view_outlined)).dx;
      expect(lang == 'ar' ? cartX < itemsX : cartX > itemsX, isTrue, reason: lang);
    }
  });

  testWidgets('onboarding → preview → settings: language, theme, back to pairing', (tester) async {
    setSurface(tester, kPhone);
    final settings = PicPosAppSettings();
    await tester.pumpWidget(PicPosPosApp(settings: settings));
    await tester.pumpAndSettle();
    expect(find.text('ربط جهاز الكاشير'), findsWidgets);

    await tester.ensureVisible(find.byKey(const Key('onboarding.preview')));
    await tester.tap(find.byKey(const Key('onboarding.preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الإعدادات'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect((settings.locale, settings.themeMode), (const Locale('en'), ThemeMode.dark));

    await tester.ensureVisible(find.byKey(const Key('settings.openPairing')));
    await tester.tap(find.byKey(const Key('settings.openPairing')));
    await tester.pumpAndSettle();
    expect(find.text('Pair this cashier tablet'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('every string has Arabic and English', () {
    expect(S.table.coverageProblems(), isEmpty);
  });
}
