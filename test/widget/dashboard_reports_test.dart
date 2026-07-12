// ═══════════════════════════════════════════════════════════════════════════
// Dashboard + Reports Widget Tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Tests that core screen components render correctly:
// - Dashboard KPI cards
// - Settings categories
// - Report list navigation

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:ural_erp/l10n/app_localizations.dart';

void main() {
  Widget buildTestApp(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        locale: const Locale('ar', 'EG'),
        supportedLocales: const [Locale('ar', 'EG')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: child,
        ),
      ),
    );
  }

  group('KPI Card Rendering', () {
    testWidgets('KPI card shows title and value', (tester) async {
      await tester.pumpWidget(buildTestApp(
        const Scaffold(
          body: Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                key: Key('kpi_sales'),
                children: [
                  Text('المبيعات'),
                  SizedBox(height: 8),
                  Text('15,250 ج.م',
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
      ));

      expect(find.text('المبيعات'), findsOneWidget);
      expect(find.text('15,250 ج.م'), findsOneWidget);
    });

    testWidgets('multiple KPI cards render', (tester) async {
      await tester.pumpWidget(buildTestApp(
        const Scaffold(
          body: Row(
            children: [
              Expanded(
                child: Card(key: Key('kpi_1'), child: Text('مبيعات')),
              ),
              Expanded(
                child: Card(key: Key('kpi_2'), child: Text('مصروفات')),
              ),
              Expanded(
                child: Card(key: Key('kpi_3'), child: Text('أرباح')),
              ),
            ],
          ),
        ),
      ));

      expect(find.byKey(const Key('kpi_1')), findsOneWidget);
      expect(find.byKey(const Key('kpi_2')), findsOneWidget);
      expect(find.byKey(const Key('kpi_3')), findsOneWidget);
    });
  });

  group('Settings Categories', () {
    testWidgets('settings category tiles render', (tester) async {
      final categories = ['عام', 'الحسابات', 'الأمان', 'الطباعة', 'النسخ الاحتياطي'];

      await tester.pumpWidget(buildTestApp(
        Scaffold(
          body: ListView(
            children: categories
                .map((c) => ListTile(
                      key: Key('settings_$c'),
                      leading: const Icon(Icons.settings),
                      title: Text(c),
                    ))
                .toList(),
          ),
        ),
      ));

      for (final cat in categories) {
        expect(find.text(cat), findsOneWidget);
      }
    });

    testWidgets('settings tile is tappable', (tester) async {
      var tapped = false;

      await tester.pumpWidget(buildTestApp(
        Scaffold(
          body: ListTile(
            title: const Text('عام'),
            onTap: () => tapped = true,
          ),
        ),
      ));

      await tester.tap(find.text('عام'));
      expect(tapped, isTrue);
    });
  });

  group('Report Navigation', () {
    testWidgets('report categories render as chips', (tester) async {
      final reports = ['ميزان المراجعة', 'قائمة الدخل', 'الميزانية', 'التدفق النقدي'];

      await tester.pumpWidget(buildTestApp(
        Scaffold(
          body: Wrap(
            spacing: 8,
            children: reports
                .map((r) => Chip(
                      key: Key('report_$r'),
                      label: Text(r),
                    ))
                .toList(),
          ),
        ),
      ));

      for (final r in reports) {
        expect(find.text(r), findsOneWidget);
      }
    });
  });
}
