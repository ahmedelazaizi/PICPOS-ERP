// M2 (plan 2026-10-24, MIR-008 / MIR-012): the console strip - link state +
// current-branch selector - in Arabic (RTL) and English (LTR), light and dark.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/theme/app_theme.dart';
import 'package:picpos_erp/data/providers/mirror_branch_context_provider.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/widgets/mirror_status_strip.dart';
import 'package:picpos_erp/services/mirror_branch_context.dart';
import 'package:picpos_erp/services/mirror_connectivity.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';

const _b1 = MirrorBranch(id: 1, name: 'Cairo');
const _b2 = MirrorBranch(id: 2, name: 'Alex');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  final ctx = MirrorBranchContext.instance;
  final t0 = DateTime.utc(2026, 10, 25, 12);

  setUpAll(() async => I18nCatalog.load());

  setUp(() {
    db = AppDatabase.forTesting();
    NetworkService.instance.debugSetModeForTests(NetworkMode.mirror);
    MirrorConnectivity.debugUseClock(() => t0);
    MirrorState.instance.debugSetForTests(
      serverDisplayName: 'hq:8080',
      lastHandshakeAt: t0.subtract(const Duration(seconds: 5)),
    );
    ctx.debugSet(branches: const [_b1, _b2], current: 1);
  });
  tearDown(() async {
    ctx.reset();
    MirrorConnectivity.debugReset();
    MirrorState.instance.debugSetForTests();
    I18nCatalog.setLocale(const Locale('ar', 'EG'));
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    await db.close();
  });

  Future<void> pumpStrip(
    WidgetTester tester, {
    required Locale locale,
    required ThemeMode mode,
  }) async {
    I18nCatalog.setLocale(locale);
    await tester.binding.setSurfaceSize(const Size(900, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          mirrorConsoleContextProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('ar', 'EG'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          home: const Scaffold(body: Align(
              alignment: Alignment.topCenter, child: MirrorStatusStrip())),
        ),
      ),
    );
    await tester.pump();
  }

  /// Lets the device-local setting write (real async inside the fake zone) finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  const locales = {
    'ar': Locale('ar', 'EG'),
    'en': Locale('en'),
  };
  const modes = {'light': ThemeMode.light, 'dark': ThemeMode.dark};

  for (final l in locales.entries) {
    for (final m in modes.entries) {
      final isEn = l.key == 'en';
      group('${l.key} / ${m.key}', () {
        testWidgets('online: link label + current branch, no overflow',
            (tester) async {
          await pumpStrip(tester, locale: l.value, mode: m.value);
          expect(tester.takeException(), isNull);
          expect(find.text(isEn ? 'Connected to the main server' : 'متصل بالسيرفر الرئيسي'),
              findsOneWidget);
          expect(find.text(isEn ? 'Current branch' : 'الفرع الحالي'),
              findsOneWidget);
          expect(find.byKey(const ValueKey('mirrorCurrentBranchName')), findsOneWidget);
          expect(find.text('Cairo'), findsOneWidget);
          expect(
              Directionality.of(tester.element(find.byType(MirrorStatusStrip))),
              isEn ? TextDirection.ltr : TextDirection.rtl);
          final theme = Theme.of(tester.element(find.byType(MirrorStatusStrip)));
          expect(theme.brightness,
              m.key == 'dark' ? Brightness.dark : Brightness.light);
        });

        testWidgets('switching branch updates the context', (tester) async {
          await pumpStrip(tester, locale: l.value, mode: m.value);
          // the menu lists exactly the manager's branches...
          await tester.tap(find.byKey(const ValueKey('mirrorBranchSelector')));
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.byType(PopupMenuItem<int>), findsNWidgets(2));
          // ...and choosing one goes through the widget's own handler
          final popup = tester.widget<PopupMenuButton<int>>(
              find.byKey(const ValueKey('mirrorBranchSelector')));
          // the handler writes the device-local setting: real async, so it runs
          // outside the fake-async zone
          await tester.runAsync(() async => popup.onSelected!(2));
          await settle(tester);
          expect(ctx.currentBranchId, 2);
          expect(
              tester
                  .widget<Text>(
                      find.byKey(const ValueKey('mirrorCurrentBranchName')))
                  .data,
              'Alex');
          expect(
              await tester.runAsync(
                  () => db.getSettingValue(MirrorBranchContext.settingKey)),
              '2');
        });

        testWidgets('no heartbeat for 10 minutes: honest read-only state',
            (tester) async {
          MirrorState.instance.debugSetForTests(
            serverDisplayName: 'hq:8080',
            lastHandshakeAt: t0.subtract(const Duration(minutes: 10)),
          );
          await pumpStrip(tester, locale: l.value, mode: m.value);
          expect(find.text(isEn ? 'Read-only' : 'قراءة فقط'), findsOneWidget);
          expect(
              find.text(isEn
                  ? 'Connection to the main server lost — the console is read-only until it returns.'
                  : 'فقد الاتصال بالسيرفر الرئيسي — المرآة للقراءة فقط حتى يعود الاتصال.'),
              findsOneWidget,
              reason: 'the banner says exactly what is refused');
        });

        testWidgets('a manager with no branch sees the explicit empty state',
            (tester) async {
          ctx.debugSet(branches: const [], current: null);
          await pumpStrip(tester, locale: l.value, mode: m.value);
          expect(
              find.text(isEn
                  ? 'No branches are assigned to your account'
                  : 'لا فروع مسندة لحسابك'),
              findsOneWidget);
          expect(find.byKey(const ValueKey('mirrorBranchSelector')), findsNothing);
        });
      });
    }
  }

  testWidgets('"check now" asks the main again and shows reconnecting between '
      '30 s and 5 min', (tester) async {
    MirrorState.instance.debugSetForTests(
      serverDisplayName: 'hq:8080',
      lastHandshakeAt: t0.subtract(const Duration(minutes: 2)),
    );
    await pumpStrip(tester,
        locale: const Locale('en'), mode: ThemeMode.light);
    expect(find.text('Reconnecting…'), findsOneWidget);
    expect(find.byKey(const ValueKey('mirrorCheckNow')), findsOneWidget);
  });

  testWidgets('off a mirror the strip collapses to nothing', (tester) async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.client);
    await pumpStrip(tester, locale: const Locale('en'), mode: ThemeMode.light);
    expect(find.byKey(const ValueKey('mirrorStatusStrip')), findsNothing);
  });
}
