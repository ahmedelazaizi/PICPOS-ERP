// A1: "Re-provision this device" - the single entry to change the mode later.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/i18n/locale_provider.dart';
import 'package:picpos_erp/core/theme/app_theme.dart';
import 'package:picpos_erp/presentation/screens/first_run/provisioning_providers.dart';
import 'package:picpos_erp/presentation/settings_picpos/screens/device_reprovision_tile.dart';
import 'package:picpos_erp/services/network_service.dart';

import 'first_run_test_kit.dart';

class _FakeActions implements ProvisioningActions {
  int reprovisioned = 0;
  @override
  Future<void> markSelfCheckPassed() async {}
  @override
  Future<void> reprovision() async => reprovisioned++;
}

Future<_FakeActions> _pump(
  WidgetTester tester, {
  required NetworkMode mode,
  required bool allowed,
  bool offline = false,
  required bool english,
  required bool dark,
  VoidCallback? onRestart,
}) async {
  useLocale(english: english);
  final actions = _FakeActions();
  tester.view.physicalSize = const Size(900, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      userLocaleProvider.overrideWith(FakeLocaleNotifier.new),
      provisioningActionsProvider.overrideWithValue(actions),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: DeviceReprovisionTile(
            mode: mode,
            allowed: allowed,
            offlineBlocked: offline,
            onRestart: onRestart,
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  return actions;
}

void main() {
  setUpAll(loadEnglishCatalog);
  tearDown(() => useLocale(english: false));

  for (final english in [false, true]) {
    for (final dark in [false, true]) {
      final tag = '${english ? 'EN' : 'AR'}/${dark ? 'dark' : 'light'}';

      testWidgets('[$tag] shows the mode and re-provisions after a confirmation',
          (tester) async {
        var restarted = 0;
        final a = await _pump(tester,
            mode: NetworkMode.mirror,
            allowed: true,
            english: english,
            dark: dark,
            onRestart: () => restarted++);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('device_reprovision_mode')), findsOneWidget);
        expect(
            find.textContaining(english ? 'Mirror' : 'مرآة'), findsWidgets);
        await tester.tap(find.byKey(const Key('device_reprovision_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('reprovision_cancel')));
        await tester.pumpAndSettle();
        expect(a.reprovisioned, 0);
        await tester.tap(find.byKey(const Key('device_reprovision_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('reprovision_confirm')));
        await tester.pumpAndSettle();
        expect(a.reprovisioned, 1);
        expect(find.byKey(const Key('device_reprovision_done')), findsOneWidget);
        await tester.tap(find.byKey(const Key('device_reprovision_restart')));
        expect(restarted, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('[$tag] needs settings_edit; a client/mirror must be online',
          (tester) async {
        var a = await _pump(tester,
            mode: NetworkMode.standalone,
            allowed: false,
            english: english,
            dark: dark);
        expect(
            tester
                .widget<OutlinedButton>(find.byKey(const Key('device_reprovision_button')))
                .onPressed,
            isNull);
        expect(find.byKey(const Key('device_reprovision_denied')), findsOneWidget);
        expect(a.reprovisioned, 0);

        a = await _pump(tester,
            mode: NetworkMode.client,
            allowed: true,
            offline: true,
            english: english,
            dark: dark);
        expect(
            tester
                .widget<OutlinedButton>(find.byKey(const Key('device_reprovision_button')))
                .onPressed,
            isNull);
        expect(find.byKey(const Key('device_reprovision_offline')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
