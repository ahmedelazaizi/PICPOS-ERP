import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_admin/app.dart';
import 'package:picpos_admin/l10n/strings.dart';
import 'package:picpos_admin/screens/onboarding_screen.dart';
import 'package:picpos_admin/shell/admin_shell.dart';
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

            await tester.pumpWidget(PicPosAdminApp(key: const ValueKey('onboarding'), settings: settings()));
            await tester.pumpAndSettle();
            expect(find.byType(OnboardingScreen), findsOneWidget);
            expect(tester.takeException(), isNull);

            for (var i = 0; i < AdminShell.destinationCount; i++) {
              await tester.pumpWidget(
                  PicPosAdminApp(key: ValueKey(i), settings: settings(), startInShell: true, initialDestination: i));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: 'destination $i');
              final ctx = tester.element(find.byType(AdminShell));
              expect(Directionality.of(ctx), lang == 'ar' ? TextDirection.rtl : TextDirection.ltr);
              expect(Theme.of(ctx).brightness, mode == ThemeMode.dark ? Brightness.dark : Brightness.light);
              if (size == kPhone) {
                expect(find.byType(NavigationBar), findsOneWidget);
              } else {
                expect(find.byType(NavigationRail), findsOneWidget);
              }
            }
          });
        }
      }
    }
  });

  testWidgets('onboarding → preview → settings toggles language and theme → back to pairing', (tester) async {
    setSurface(tester, kPhone);
    final settings = PicPosAppSettings();
    await tester.pumpWidget(PicPosAdminApp(settings: settings));
    await tester.pumpAndSettle();
    expect(find.text('ربط هذا الجوال'), findsWidgets);

    await tester.ensureVisible(find.byKey(const Key('onboarding.preview')));
    await tester.tap(find.byKey(const Key('onboarding.preview')));
    await tester.pumpAndSettle();
    expect(find.byType(AdminShell), findsOneWidget);
    expect(find.text('الرئيسية'), findsWidgets);

    // Settings sits under «المزيد» on phones.
    await tester.tap(find.text('المزيد'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الإعدادات').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(settings.locale, const Locale('en'));
    expect(find.text('Settings'), findsWidgets);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(settings.themeMode, ThemeMode.dark);
    expect(Theme.of(tester.element(find.byType(AdminShell))).brightness, Brightness.dark);

    await tester.tap(find.byKey(const Key('settings.openPairing')));
    await tester.pumpAndSettle();
    expect(find.text('Pair this phone'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet rail shows all six destinations', (tester) async {
    setSurface(tester, kTablet);
    await tester.pumpWidget(PicPosAdminApp(settings: PicPosAppSettings(locale: const Locale('en')), startInShell: true));
    await tester.pumpAndSettle();
    for (final l in ['Dashboard', 'Approvals', 'Reports', 'Operations', 'Notifications', 'Settings']) {
      expect(find.descendant(of: find.byType(NavigationRail), matching: find.text(l)), findsOneWidget, reason: l);
    }
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(find.text('Financial statements and ledgers'), findsOneWidget);
  });

  test('every string has Arabic and English', () {
    expect(S.table.coverageProblems(), isEmpty);
  });
}
