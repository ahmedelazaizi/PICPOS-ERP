// ═══════════════════════════════════════════════════════════════════════════
// PIR-008: AppFormDialog Widget Tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Tests the reusable AppFormDialog component renders correctly with
// RTL directionality, title, content, and actions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/widgets/app_form_dialog.dart';

void main() {
  Widget buildTestApp({required Widget child}) {
    return MaterialApp(
      home: Scaffold(body: child),
    );
  }

  group('AppFormDialog', () {
    testWidgets('renders title correctly', (tester) async {
      await tester.pumpWidget(buildTestApp(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const AppFormDialog(
                title: 'عنوان الاختبار',
                content: Text('محتوى'),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('عنوان الاختبار'), findsOneWidget);
      expect(find.text('محتوى'), findsOneWidget);
    });

    testWidgets('renders close button', (tester) async {
      await tester.pumpWidget(buildTestApp(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const AppFormDialog(
                title: 'Test',
                content: Text('Content'),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('close button dismisses dialog', (tester) async {
      await tester.pumpWidget(buildTestApp(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const AppFormDialog(
                title: 'Closeable',
                content: Text('Content'),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Closeable'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Closeable'), findsNothing);
    });

    testWidgets('renders action buttons', (tester) async {
      await tester.pumpWidget(buildTestApp(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AppFormDialog(
                title: 'Actions',
                content: const Text('Content'),
                actions: [
                  TextButton(
                    onPressed: () {},
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton(
                    onPressed: () {},
                    child: const Text('حفظ'),
                  ),
                ],
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('إلغاء'), findsOneWidget);
      expect(find.text('حفظ'), findsOneWidget);
    });

    testWidgets('uses RTL text direction', (tester) async {
      await tester.pumpWidget(buildTestApp(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const AppFormDialog(
                title: 'RTL Test',
                content: Text('Content'),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // AppFormDialog renders: Directionality(RTL) → Dialog → content.
      // So Directionality is an ANCESTOR of Dialog, not a descendant.
      // Verify at least one Directionality in the widget tree is RTL
      // (injected by AppFormDialog.build).
      final directionalities =
          tester.widgetList<Directionality>(find.byType(Directionality));
      expect(
        directionalities.any((d) => d.textDirection == TextDirection.rtl),
        isTrue,
        reason: 'AppFormDialog should inject an RTL Directionality',
      );
    });

    testWidgets('renders title icon when provided', (tester) async {
      await tester.pumpWidget(buildTestApp(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const AppFormDialog(
                title: 'Icon Test',
                content: Text('Content'),
                titleIcon: Icons.settings,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.settings), findsOneWidget);
    });
  });

  group('showAppFormDialog', () {
    testWidgets('convenience function opens dialog', (tester) async {
      await tester.pumpWidget(buildTestApp(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showAppFormDialog(
              context: context,
              title: 'Convenience',
              content: const Text('Via Helper'),
            ),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Convenience'), findsOneWidget);
      expect(find.text('Via Helper'), findsOneWidget);
    });
  });
}
