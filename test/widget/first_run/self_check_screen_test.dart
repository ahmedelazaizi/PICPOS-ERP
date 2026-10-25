// A1: the one-time self-check screen (AR/EN, light/dark) and its actions.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/i18n/locale_provider.dart';
import 'package:picpos_erp/core/theme/app_theme.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_self_check_screen.dart';
import 'package:picpos_erp/presentation/screens/first_run/provisioning_providers.dart';
import 'package:picpos_erp/services/deployment/self_check.dart';

import 'first_run_test_kit.dart';

class _FakeRunner implements SelfCheckRunner {
  _FakeRunner(this.report);
  SelfCheckReport report;
  int runs = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<SelfCheckReport> run() async {
    runs++;
    return report;
  }
}

class _FakeActions implements ProvisioningActions {
  int passed = 0;
  int reprovisioned = 0;
  @override
  Future<void> markSelfCheckPassed() async => passed++;
  @override
  Future<void> reprovision() async => reprovisioned++;
}

SelfCheckReport _healthy() => const SelfCheckReport([
      SelfCheckItem(SelfCheckId.record, SelfCheckStatus.pass),
      SelfCheckItem(SelfCheckId.mode, SelfCheckStatus.pass, blocking: true),
      SelfCheckItem(SelfCheckId.pairing, SelfCheckStatus.pass, blocking: true),
      SelfCheckItem(SelfCheckId.server, SelfCheckStatus.pass),
      SelfCheckItem(SelfCheckId.firstSync, SelfCheckStatus.pass, blocking: true),
      SelfCheckItem(SelfCheckId.noDefaultAdmin, SelfCheckStatus.pass),
      SelfCheckItem(SelfCheckId.users, SelfCheckStatus.skip),
    ]);

SelfCheckReport _tokenLost() => const SelfCheckReport([
      SelfCheckItem(SelfCheckId.record, SelfCheckStatus.pass),
      SelfCheckItem(SelfCheckId.mode, SelfCheckStatus.pass, blocking: true),
      SelfCheckItem(SelfCheckId.pairing, SelfCheckStatus.fail,
          blocking: true, detail: 'device token lost'),
    ]);

Future<_FakeActions> _pump(
  WidgetTester tester,
  _FakeRunner runner, {
  required bool english,
  required bool dark,
  VoidCallback? onPassed,
  VoidCallback? onRestart,
}) async {
  useLocale(english: english);
  final actions = _FakeActions();
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      userLocaleProvider.overrideWith(FakeLocaleNotifier.new),
      selfCheckRunnerProvider.overrideWithValue(runner),
      provisioningActionsProvider.overrideWithValue(actions),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: FirstRunSelfCheckScreen(
        onPassed: onPassed ?? () {},
        onRestart: onRestart,
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return actions;
}

void main() {
  setUpAll(loadEnglishCatalog);
  tearDown(() => useLocale(english: false));

  for (final english in [false, true]) {
    for (final dark in [false, true]) {
      final tag = '${english ? 'EN' : 'AR'}/${dark ? 'dark' : 'light'}';

      testWidgets('[$tag] healthy: every row, continue enabled, no overflow',
          (tester) async {
        var passed = 0;
        final runner = _FakeRunner(_healthy());
        final actions = await _pump(tester, runner,
            english: english, dark: dark, onPassed: () => passed++);
        expect(tester.takeException(), isNull);
        expect(find.text(english ? 'Setup verification' : 'فحص اعتماد الإعداد'),
            findsOneWidget);
        for (final id in SelfCheckId.values) {
          if (id == SelfCheckId.users || id == SelfCheckId.server ||
              id == SelfCheckId.pairing || id == SelfCheckId.firstSync ||
              id == SelfCheckId.mode || id == SelfCheckId.record ||
              id == SelfCheckId.noDefaultAdmin) {
            expect(find.byKey(Key('self_check_row_${id.name}')), findsOneWidget,
                reason: id.name);
          }
        }
        final cont = tester.widget<FilledButton>(
            find.byKey(const Key('self_check_continue')));
        expect(cont.onPressed, isNotNull);
        await tester.tap(find.byKey(const Key('self_check_continue')));
        await tester.pump();
        expect(actions.passed, 1, reason: 'the check is marked as passed (shown once)');
        expect(passed, 1);
      });

      testWidgets('[$tag] lost pairing: login blocked, re-pair prompt, '
          're-provision asks to restart', (tester) async {
        var restarted = 0;
        final runner = _FakeRunner(_tokenLost());
        final actions = await _pump(tester, runner,
            english: english, dark: dark, onRestart: () => restarted++);
        expect(tester.takeException(), isNull);
        expect(
            tester
                .widget<FilledButton>(find.byKey(const Key('self_check_continue')))
                .onPressed,
            isNull);
        expect(find.byKey(const Key('self_check_repair_prompt')), findsOneWidget);

        // retry runs the check again
        await tester.tap(find.byKey(const Key('self_check_retry')));
        await tester.pump();
        expect(runner.runs, 2);

        // re-provision: confirm dialog -> action -> restart prompt
        await tester.ensureVisible(find.byKey(const Key('self_check_reprovision')));
        await tester.tap(find.byKey(const Key('self_check_reprovision')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('reprovision_confirm_dialog')), findsOneWidget);
        await tester.tap(find.byKey(const Key('reprovision_cancel')));
        await tester.pumpAndSettle();
        expect(actions.reprovisioned, 0, reason: 'cancel changes nothing');
        await tester.tap(find.byKey(const Key('self_check_reprovision')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('reprovision_confirm')));
        await tester.pumpAndSettle();
        expect(actions.reprovisioned, 1);
        expect(find.byKey(const Key('self_check_reprovisioned')), findsOneWidget);
        await tester.tap(find.byKey(const Key('self_check_restart')));
        expect(restarted, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
