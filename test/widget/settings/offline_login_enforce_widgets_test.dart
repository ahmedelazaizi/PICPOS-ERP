// Login leftover #1 (UI): the shadow/enforce settings tile with its summary and
// PicPos confirmation, and the "N days left" / "expired" banner - AR/EN, light
// and dark, plus the providers behind them on a real in-memory database.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/core/i18n/locale_provider.dart';
import 'package:picpos_erp/core/logging/diagnostic_logger.dart';
import 'package:picpos_erp/core/theme/app_theme.dart';
import 'package:picpos_erp/data/providers/offline_login_providers.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_dialog.dart';
import 'package:picpos_erp/presentation/settings_picpos/screens/offline_login_mode_tile.dart';
import 'package:picpos_erp/presentation/widgets/offline_login_expiry_banner.dart';
import 'package:picpos_erp/presentation/widgets/shell_banners.dart';
import 'package:picpos_erp/services/auth/offline_login_policy.dart';
import 'package:picpos_erp/services/auth/offline_login_standing.dart';
import 'package:picpos_erp/services/auth/shadow_login_log.dart';

import '../first_run/first_run_test_kit.dart';

Widget _app(Widget child, {required bool dark, List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        userLocaleProvider.overrideWith(FakeLocaleNotifier.new),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void _size(WidgetTester t) {
  t.view.physicalSize = const Size(900, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

const _dirty = ShadowLoginSummary(
  windowDays: 30,
  total: 5,
  accounts: 2,
  byDecision: {
    OfflineLoginDecision.notProvisioned: 3,
    OfflineLoginDecision.credentialChanged: 2,
  },
);

void main() {
  setUpAll(loadEnglishCatalog);
  tearDown(() => useLocale(english: false));

  for (final english in [false, true]) {
    for (final dark in [false, true]) {
      final tag = '${english ? 'EN' : 'AR'}/${dark ? 'dark' : 'light'}';

      group('[$tag] settings tile', () {
        testWidgets('shadow: explains, summarises what would be refused and '
            'enforces only after the PicPos confirmation', (tester) async {
          useLocale(english: english);
          _size(tester);
          final changes = <OfflineLoginMode>[];
          await tester.pumpWidget(_app(
            OfflineLoginModeTile(
              mode: OfflineLoginMode.shadow,
              summary: _dirty,
              allowed: true,
              onChange: (m) async => changes.add(m),
            ),
            dark: dark,
          ));
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.textContaining(english ? 'Monitor only' : 'مراقبة فقط'),
              findsWidgets);
          expect(
              find.descendant(
                  of: find.byKey(const Key('offline_login_shadow_summary')),
                  matching: find.textContaining(
                      english ? '5 offline sign-ins' : '5 دخولًا')),
              findsOneWidget,
              reason: 'the summary names how many sign-ins enforce would refuse');
          expect(find.textContaining('2'), findsWidgets);

          await tester.tap(find.byKey(const Key('offline_login_enable_enforce')));
          await tester.pumpAndSettle();
          expect(find.byType(PicPosDialog), findsOneWidget,
              reason: 'a PicPosDialog, not a raw AlertDialog');
          expect(find.byType(AlertDialog), findsNothing);
          expect(changes, isEmpty, reason: 'nothing changes before confirming');

          // Cancel -> still nothing.
          await tester.tap(find.text(english ? 'Cancel' : 'إلغاء').last);
          await tester.pumpAndSettle();
          expect(changes, isEmpty);

          await tester.tap(find.byKey(const Key('offline_login_enable_enforce')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(english ? 'Turn on enforcement' : 'تفعيل الإلزام').last);
          await tester.pumpAndSettle();
          expect(changes, [OfflineLoginMode.enforce]);
          expect(tester.takeException(), isNull);
        });

        testWidgets('enforce: offers the way back to monitoring without a '
            'dialog', (tester) async {
          useLocale(english: english);
          _size(tester);
          final changes = <OfflineLoginMode>[];
          await tester.pumpWidget(_app(
            OfflineLoginModeTile(
              mode: OfflineLoginMode.enforce,
              summary: const ShadowLoginSummary.empty(30),
              allowed: true,
              onChange: (m) async => changes.add(m),
            ),
            dark: dark,
          ));
          await tester.pump();
          expect(find.byKey(const Key('offline_login_enable_enforce')), findsNothing);
          await tester.tap(find.byKey(const Key('offline_login_back_to_shadow')));
          await tester.pumpAndSettle();
          expect(changes, [OfflineLoginMode.shadow]);
          expect(find.byType(PicPosDialog), findsNothing);
          expect(tester.takeException(), isNull);
        });

        testWidgets('a clean shadow log says so', (tester) async {
          useLocale(english: english);
          _size(tester);
          await tester.pumpWidget(_app(
            OfflineLoginModeTile(
              mode: OfflineLoginMode.shadow,
              summary: const ShadowLoginSummary.empty(30),
              allowed: true,
              onChange: (_) async {},
            ),
            dark: dark,
          ));
          await tester.pump();
          expect(
              find.textContaining(english
                  ? 'no offline sign-in would have been refused'
                  : 'لم يكن سيُرفض أي دخول'),
              findsOneWidget);
        });

        testWidgets('without settings_edit both switches are disabled',
            (tester) async {
          useLocale(english: english);
          _size(tester);
          for (final m in OfflineLoginMode.values) {
            await tester.pumpWidget(_app(
              OfflineLoginModeTile(
                mode: m,
                summary: _dirty,
                allowed: false,
                onChange: (_) async => fail('must not be callable'),
              ),
              dark: dark,
            ));
            await tester.pump();
            final key = m == OfflineLoginMode.shadow
                ? 'offline_login_enable_enforce'
                : 'offline_login_back_to_shadow';
            final btn = tester.widget<ButtonStyleButton>(find.byKey(Key(key)));
            expect(btn.onPressed, isNull);
            expect(find.byKey(const Key('offline_login_denied')), findsOneWidget);
          }
        });
      });

      group('[$tag] expiry banner', () {
        Future<void> pumpBanner(WidgetTester t, OfflineStanding s) async {
          useLocale(english: english);
          _size(t);
          await t.pumpWidget(_app(OfflineLoginExpiryBannerView(standing: s), dark: dark));
          await t.pump();
          expect(t.takeException(), isNull);
        }

        testWidgets('2 days left -> warning', (tester) async {
          await pumpBanner(tester,
              const OfflineStanding(OfflineStandingKind.expiring, daysLeft: 2));
          expect(find.byKey(const Key('offline_expiry_warning')), findsOneWidget);
          expect(find.textContaining(english ? '2 days left' : 'بقي يومان'),
              findsOneWidget);
        });

        testWidgets('last day -> warning', (tester) async {
          await pumpBanner(tester,
              const OfflineStanding(OfflineStandingKind.expiring, daysLeft: 1));
          expect(find.textContaining(english ? 'Last day' : 'آخر يوم'),
              findsOneWidget);
        });

        testWidgets('expired -> explicit "connect to the main" state',
            (tester) async {
          await pumpBanner(
              tester, const OfflineStanding(OfflineStandingKind.expired));
          expect(find.byKey(const Key('offline_expiry_expired')), findsOneWidget);
          expect(
              find.textContaining(english
                  ? 'has expired. Connect to the main'
                  : 'انتهت مدة الدخول دون اتصال'),
              findsOneWidget);
        });

        testWidgets('hidden -> renders nothing', (tester) async {
          await pumpBanner(tester, OfflineStanding.hiddenStanding);
          expect(find.byKey(const Key('offline_expiry_warning')), findsNothing);
          expect(find.byKey(const Key('offline_expiry_expired')), findsNothing);
        });

        testWidgets('the shell stack shows it from the provider', (tester) async {
          useLocale(english: english);
          _size(tester);
          await tester.pumpWidget(_app(
            const ShellBanners(),
            dark: dark,
            overrides: [
              offlineStandingProvider.overrideWith((ref) async =>
                  const OfflineStanding(OfflineStandingKind.expiring, daysLeft: 2)),
              currentUserPermissionsProvider.overrideWith((ref) async => <String>[]),
            ],
          ));
          await tester.pump();
          await tester.pump();
          expect(find.byKey(const Key('offline_expiry_warning')), findsOneWidget);
        });
      });
    }
  }

  group('providers on a real database', () {
    test('the switch persists; the shadow summary reads the log', () async {
      DiagnosticLogger.enableTestMode();
      final db = AppDatabase.forTesting();
      await db.getBranches();
      final c = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
      addTearDown(() async {
        c.dispose();
        await db.close();
      });

      expect(await c.read(offlineLoginModeProvider.future), OfflineLoginMode.shadow);
      await ShadowLoginLog(db).record(OfflineLoginDecision.notProvisioned, 4);
      final s = await c.read(offlineShadowSummaryProvider.future);
      expect(s.total, 1);
      expect(s.windowDays, kShadowSummaryDays);

      await c.read(offlineLoginModeActionsProvider).setMode(OfflineLoginMode.enforce);
      expect(await c.read(offlineLoginModeProvider.future), OfflineLoginMode.enforce);
      expect(await db.getSettingValue(OfflineLoginMode.settingKey), 'enforce');

      await c.read(offlineLoginModeActionsProvider).clearShadowLog();
      expect((await c.read(offlineShadowSummaryProvider.future)).isClean, isTrue);
    });
  });
}
