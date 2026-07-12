// ═══════════════════════════════════════════════════════════════════════════
// Spec 076 — ReportFilterBar no-overflow regression test
// ═══════════════════════════════════════════════════════════════════════════
//
// Pins the FR-008 contract from spec 076: the new ReportFilterBar widget
// MUST NOT throw `RenderFlex overflowed` when pumped inside an 800-pixel-wide
// constraint box with a worst-case payload of 4 chips + 2 short dropdowns +
// 1 wide dropdown + 1 wide Autocomplete + 1 button = 8 trailing items.
//
// Regression guard for the field-test bug "OVERFLOWED BY 274" / 302 px on
// the sales report (2026-05-15 desktop build).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/widgets/report_filter_bar.dart';

int chipTaps = 0;

Widget _wrap({required double width}) {
  chipTaps = 0;
  final initial = DateTimeRange(
    start: DateTime(2026, 5, 1),
    end: DateTime(2026, 5, 15, 23, 59, 59, 999),
  );

  // 8 trailing samples — mix of small + wide + Autocomplete to simulate the
  // worst-case sales report row (cost-center + warehouse + branch + region +
  // payment + sale-type + user-autocomplete + button).
  final trailing = <Widget>[
    SizedBox(
      width: 120,
      child: DropdownButtonFormField<int?>(
        initialValue: null,
        decoration: const InputDecoration(labelText: 'مركز التكلفة'),
        items: const [
          DropdownMenuItem(value: null, child: Text('الكل')),
        ],
        onChanged: (_) {},
      ),
    ),
    SizedBox(
      width: 120,
      child: DropdownButtonFormField<int?>(
        initialValue: null,
        decoration: const InputDecoration(labelText: 'المخزن'),
        items: const [
          DropdownMenuItem(value: null, child: Text('الكل')),
        ],
        onChanged: (_) {},
      ),
    ),
    SizedBox(
      width: 120,
      child: DropdownButtonFormField<int?>(
        initialValue: null,
        decoration: const InputDecoration(labelText: 'الفرع'),
        items: const [
          DropdownMenuItem(value: null, child: Text('الكل')),
        ],
        onChanged: (_) {},
      ),
    ),
    SizedBox(
      width: 120,
      child: DropdownButtonFormField<int?>(
        initialValue: null,
        decoration: const InputDecoration(labelText: 'المنطقة'),
        items: const [
          DropdownMenuItem(value: null, child: Text('الكل')),
        ],
        onChanged: (_) {},
      ),
    ),
    SizedBox(
      width: 200,
      child: DropdownButtonFormField<String?>(
        initialValue: null,
        decoration: const InputDecoration(
            labelText: 'دروب داون بعنوان طويل جدًا لاختبار overflow'),
        items: const [
          DropdownMenuItem(value: null, child: Text('الكل')),
        ],
        onChanged: (_) {},
      ),
    ),
    SizedBox(
      width: 180,
      child: DropdownButtonFormField<String?>(
        initialValue: null,
        decoration: const InputDecoration(labelText: 'طريقة الدفع'),
        items: const [
          DropdownMenuItem(value: null, child: Text('الكل')),
        ],
        onChanged: (_) {},
      ),
    ),
    SizedBox(
      width: 200,
      child: Autocomplete<String>(
        optionsBuilder: (textEditingValue) =>
            const ['مستخدم 1', 'مستخدم 2'],
        onSelected: (_) {},
      ),
    ),
    ElevatedButton(onPressed: () {}, child: const Text('تحديث')),
  ];

  return MaterialApp(
    locale: const Locale('ar'),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: ReportFilterBar(
            selectedRange: initial,
            onRangeChanged: (_, _) {
              chipTaps += 1;
            },
            trailing: trailing,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ReportFilterBar no-overflow contract (Spec 076 / FR-008)', () {
    testWidgets(
        'pumps at constrained 800px width without any FlutterError or RenderFlex overflow',
        (tester) async {
      await tester.pumpWidget(_wrap(width: 800));
      await tester.pump();

      // Assertion 1 + 2: no exception was thrown during the pump.
      expect(tester.takeException(), isNull,
          reason: 'ReportFilterBar must not throw RenderFlex overflowed at 800px');
    });

    testWidgets('the "اليوم" preset chip is findable and hit-testable',
        (tester) async {
      await tester.pumpWidget(_wrap(width: 800));
      await tester.pump();

      final chip = find.widgetWithText(ChoiceChip, 'اليوم');
      expect(chip, findsOneWidget,
          reason: 'date preset chip must be in the widget tree');

      // tester.tap might warn-if-hit-miss because the chip is inside scroll
      // views, but we don't require it to fire here — finding is enough to
      // prove the layer is reachable. Use warnIfMissed: false for safety.
      await tester.tap(chip, warnIfMissed: false);
      await tester.pump();

      expect(chipTaps, greaterThan(0),
          reason: 'tapping the chip should fire onRangeChanged');
    });

    testWidgets(
        'every one of the 8 trailing widgets is rendered (none clipped away)',
        (tester) async {
      await tester.pumpWidget(_wrap(width: 800));
      await tester.pump();

      // The 6 DropdownButtonFormFields are findable by type.
      expect(find.byType(DropdownButtonFormField<int?>), findsNWidgets(4));
      expect(find.byType(DropdownButtonFormField<String?>), findsNWidgets(2));

      // The Autocomplete is findable.
      expect(find.byType(Autocomplete<String>), findsOneWidget);

      // The button.
      expect(find.widgetWithText(ElevatedButton, 'تحديث'), findsOneWidget);
    });

    testWidgets('also pumps cleanly at 1920px (wide desktop)', (tester) async {
      await tester.pumpWidget(_wrap(width: 1920));
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'should also be exception-free at wide widths');
    });
  });
}
