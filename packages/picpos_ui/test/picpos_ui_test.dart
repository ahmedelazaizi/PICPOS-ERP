import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_ui/picpos_ui.dart';
import 'package:picpos_ui/testing.dart';

double _luminance(Color c) => c.computeLuminance();
double _contrast(Color a, Color b) {
  final x = _luminance(a), y = _luminance(b);
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

Widget _host(Widget child, {Brightness b = Brightness.light, String lang = 'ar', Size size = const Size(411, 891)}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      theme: buildPicPosTheme(b),
      locale: Locale(lang),
      supportedLocales: picposSupportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, w) => Directionality(
        textDirection: lang == 'en' ? TextDirection.ltr : TextDirection.rtl,
        child: w!,
      ),
      home: child,
    ),
  );
}

void main() {
  setUpAll(loadPicPosFonts);

  group('theme', () {
    test('DESIGN.md roles in light and dark', () {
      final l = buildPicPosTheme(Brightness.light);
      final d = buildPicPosTheme(Brightness.dark);
      expect(l.colorScheme.primary, PicPosTokens.brandBlue);
      expect(l.scaffoldBackgroundColor, PicPosTokens.canvas);
      expect(l.colorScheme.surface, PicPosTokens.card);
      expect(l.colorScheme.outlineVariant, PicPosTokens.hairline);
      expect(d.colorScheme.primary, PicPosTokens.brandInkDark);
      expect(d.scaffoldBackgroundColor, PicPosTokens.canvasDark);
      expect(d.colorScheme.surface, PicPosTokens.cardDark);
      expect(d.colorScheme.outlineVariant, PicPosTokens.hairlineDark);
      expect(l.textTheme.bodyMedium!.fontFamily, PicPosFonts.ui);
      expect(l.textTheme.bodyMedium!.fontWeight, FontWeight.w600);
      expect(l.textTheme.titleLarge!.fontWeight, FontWeight.w700);
    });

    test('text contrast ≥ 4.5 and brand ink ≥ 3.0 on cards (DESIGN.md)', () {
      for (final b in Brightness.values) {
        final cs = buildPicPosTheme(b).colorScheme;
        expect(_contrast(cs.onSurface, cs.surface), greaterThanOrEqualTo(4.5), reason: '$b text');
        expect(_contrast(cs.onSurfaceVariant, cs.surface), greaterThanOrEqualTo(4.5), reason: '$b secondary');
        expect(_contrast(cs.primary, cs.surface), greaterThanOrEqualTo(3.0), reason: '$b primary');
        expect(_contrast(cs.onPrimary, cs.primary), greaterThanOrEqualTo(4.5), reason: '$b onPrimary');
      }
    });
  });

  group('l10n', () {
    test('package strings are complete', () {
      expect(picposUiStrings.coverageProblems(), isEmpty);
    });

    test('lookup, params, merge and missing keys', () {
      const t = L10nTable({'hi': ('مرحبا {name}', 'Hi {name}')});
      expect(t.lookup('hi', ar: true, params: {'name': 'سامي'}), 'مرحبا سامي');
      expect(t.lookup('hi', ar: false, params: {'name': 'Sami'}), 'Hi Sami');
      expect(t.lookup('nope', ar: true), 'nope');
      expect(t.merge(const L10nTable({'hi': ('أهلا', 'Hello')})).lookup('hi', ar: false), 'Hello');
      expect(const L10nTable({'x': ('', 'X'), 'y': ('{a}', '{b}')}).coverageProblems(),
          ['x: missing ar', 'y: placeholders differ']);
    });

    test('settings toggle and notify', () {
      final changes = <String>[];
      final s = PicPosAppSettings(onChanged: (s) => changes.add('${s.locale.languageCode}/${s.themeMode.name}'));
      expect(s.isArabic, isTrue);
      s.toggleLocale();
      s.toggleDark();
      s.themeMode = ThemeMode.dark; // no-op
      expect(changes, ['en/light', 'en/dark']);
    });
  });

  group('adaptive scaffold', () {
    const dests = [
      PicPosDestination(icon: Icons.home, label: 'A'),
      PicPosDestination(icon: Icons.check, label: 'B'),
      PicPosDestination(icon: Icons.bar_chart, label: 'C'),
      PicPosDestination(icon: Icons.book, label: 'D'),
      PicPosDestination(icon: Icons.notifications, label: 'E'),
      PicPosDestination(icon: Icons.settings, label: 'F'),
    ];

    testWidgets('phone: bottom bar with More overflow sheet', (tester) async {
      tester.view.physicalSize = const Size(411, 891);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var selected = 0;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (context, set) => PicPosAdaptiveScaffold(
          destinations: dests,
          selectedIndex: selected,
          onSelected: (i) => set(() => selected = i),
          body: const SizedBox.expand(),
        ),
      )));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationDestination), findsNWidgets(5));
      expect(find.text('المزيد'), findsOneWidget);
      await tester.tap(find.text('المزيد'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('F'));
      await tester.pumpAndSettle();
      expect(selected, 5);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tablet: navigation rail on the start side (right in Arabic)', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final lang in ['ar', 'en']) {
        await tester.pumpWidget(_host(
          PicPosAdaptiveScaffold(destinations: dests, selectedIndex: 0, onSelected: (_) {}, body: const SizedBox.expand()),
          lang: lang,
          size: const Size(1280, 800),
        ));
        await tester.pumpAndSettle();
        expect(find.byType(NavigationBar), findsNothing);
        final rail = tester.getRect(find.byType(NavigationRail));
        if (lang == 'ar') {
          expect(rail.right, 1280);
        } else {
          expect(rail.left, 0);
        }
        expect(find.byType(NavigationRailDestination, skipOffstage: false), findsNothing); // not a widget
        expect(find.text('F'), findsOneWidget);
      }
    });

    testWidgets('two-pane only at ≥ 840', (tester) async {
      Widget pane(double w) => _host(Center(
            child: SizedBox(width: w, height: 300, child: const PicPosTwoPane(list: Text('L'), detail: Text('D'))),
          ));
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(pane(600));
      expect(find.text('D'), findsNothing);
      await tester.pumpWidget(pane(900));
      expect(find.text('D'), findsOneWidget);
    });
  });

  group('widgets', () {
    final rows = [
      ('الصندوق', '1,250.500'),
      ('البنك العربي', '-300.000'),
    ];
    final cols = [
      PicPosColumn<(String, String)>(label: 'الحساب', value: (r) => r.$1, flex: 3),
      PicPosColumn<(String, String)>(label: 'الرصيد', value: (r) => r.$2, numeric: true),
    ];

    testWidgets('data list: cards below 600 dp, table above', (tester) async {
      await tester.pumpWidget(_host(Scaffold(body: SizedBox(width: 400, child: PicPosDataList(columns: cols, rows: rows)))));
      expect(find.text('الرصيد'), findsNWidgets(2)); // label repeated per card
      await tester.pumpWidget(_host(
        Scaffold(body: SizedBox(width: 700, child: PicPosDataList(columns: cols, rows: rows))),
        size: const Size(1280, 800),
      ));
      expect(find.text('الرصيد'), findsOneWidget); // one table header
      final amount = tester.widget<Text>(find.text('-300.000'));
      expect(amount.textDirection, TextDirection.ltr);
    });

    testWidgets('KPI stripe follows the start side', (tester) async {
      for (final (lang, startRight) in [('ar', true), ('en', false)]) {
        await tester.pumpWidget(_host(
          const Scaffold(body: Center(child: SizedBox(width: 300, child: KpiCard(label: 'صافي المبيعات', value: '12,500.000', icon: Icons.payments)))),
          lang: lang,
        ));
        final card = tester.getRect(find.byType(KpiCard));
        final stripe = tester.getRect(find.descendant(of: find.byType(KpiCard), matching: find.byType(ColoredBox)).first);
        expect(stripe.width, 3);
        expect(startRight ? stripe.right == card.right : stripe.left == card.left, isTrue, reason: lang);
      }
    });

    test('as-of tone thresholds', () {
      const w = Duration(minutes: 15), s = Duration(minutes: 60);
      expect(AsOfBadge.toneFor(const Duration(minutes: 5), w, s), PicPosTone.neutral);
      expect(AsOfBadge.toneFor(const Duration(minutes: 15), w, s), PicPosTone.warning);
      expect(AsOfBadge.toneFor(const Duration(minutes: 61), w, s), PicPosTone.error);
    });

    testWidgets('header, block, pills, badge and empty state render in dark EN without overflow', (tester) async {
      final now = DateTime.utc(2026, 2, 1, 9);
      await tester.pumpWidget(_host(
        Scaffold(
          body: ListView(children: [
            const PicPosPageHeader(title: 'Dashboard', subtitle: 'Today', icon: Icons.dashboard, actions: [StatusPill(label: 'Cloud', tone: PicPosTone.brand)]),
            PicPosBlock(title: 'Cash', subtitle: 'GL balances', child: AsOfBadge(asOf: now.subtract(const Duration(minutes: 20)), now: now)),
            const SizedBox(height: 400, child: EmptyState(icon: Icons.inbox, title: 'Nothing yet', message: 'Pending approvals appear here.')),
          ]),
        ),
        b: Brightness.dark,
        lang: 'en',
      ));
      expect(find.textContaining('Stale data'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
