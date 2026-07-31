import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/pos_picpos/widgets/picpos_numeric_keypad_dialog.dart';

/// The cart-cell numeric keypad (طلب ٣).
///
/// The behaviours asserted here are the ones that make it safe to point at the
/// cart: the first key REPLACES rather than appends, out-of-range values cannot
/// be confirmed, and cancelling returns null so the caller leaves the model
/// untouched.
void main() {
  /// Targets a keypad button by its stable key.
  ///
  /// Matching a key by its visible text is NOT usable here: the read-back field
  /// can be showing the same digit, so such a finder matches two widgets.
  Finder keypadKey(String id) => find.byKey(ValueKey('keypad-$id'));

  /// Opens the dialog and captures what it returned.
  Future<void> open(
    WidgetTester tester, {
    required String title,
    required double initialValue,
    int decimals = 2,
    double? min,
    double? max,
    required void Function(double?) onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                final v = await PicPosNumericKeypadDialog.show(
                  context,
                  title: title,
                  initialValue: initialValue,
                  decimals: decimals,
                  min: min,
                  max: max,
                );
                onResult(v);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('seeds the field with the current value', (tester) async {
    await open(tester,
        title: 'الكمية', initialValue: 3, onResult: (_) {});

    expect(find.text('الكمية'), findsOneWidget);
    expect(find.widgetWithText(TextField, '3'), findsOneWidget);
  });

  testWidgets('first key REPLACES the seeded value, later keys append',
      (tester) async {
    double? result;
    await open(tester,
        title: 'الكمية', initialValue: 1, onResult: (v) => result = v);

    await tester.tap(keypadKey('7'));
    await tester.pump();
    // The bug this guards: AppOSK would have made this '17'.
    expect(find.widgetWithText(TextField, '7'), findsOneWidget);

    await tester.tap(keypadKey('5'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '75'), findsOneWidget);

    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(result, 75);
  });

  testWidgets('cancel returns null so the caller leaves the model alone',
      (tester) async {
    double? result = -1;
    await open(tester,
        title: 'السعر', initialValue: 9, onResult: (v) => result = v);

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('rejects a discount above the max', (tester) async {
    double? result = -1;
    await open(tester,
        title: 'الخصم %',
        initialValue: 0,
        min: 0,
        max: 100,
        onResult: (v) => result = v);

    await tester.tap(keypadKey('1'));
    await tester.pump();
    await tester.tap(keypadKey('5'));
    await tester.pump();
    await tester.tap(keypadKey('0'));
    await tester.pump();

    expect(find.text('أكبر قيمة مسموحة 100'), findsOneWidget);

    // Confirm is disabled — tapping it must neither pop nor yield a value.
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(result, -1, reason: 'the dialog should still be open');
    expect(find.text('الخصم %'), findsOneWidget);
  });

  testWidgets('rejects a zero quantity', (tester) async {
    double? result = -1;
    await open(tester,
        title: 'الكمية',
        initialValue: 2,
        min: 0.01,
        onResult: (v) => result = v);

    await tester.tap(keypadKey('0'));
    await tester.pump();

    expect(find.textContaining('أقل قيمة مسموحة'), findsOneWidget);
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(result, -1);
  });

  testWidgets('keeps 3 decimals for a weighed quantity', (tester) async {
    double? result;
    await open(tester,
        title: 'الكمية',
        initialValue: 1,
        decimals: 3,
        min: 0.001,
        onResult: (v) => result = v);

    for (final k in ['1', '.', '2', '3', '4']) {
      await tester.tap(keypadKey(k));
      await tester.pump();
    }
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();

    expect(result, 1.234);
  });

  testWidgets('rounds to the allowed decimals rather than storing more',
      (tester) async {
    double? result;
    await open(tester,
        title: 'السعر',
        initialValue: 0,
        decimals: 2,
        min: 0,
        onResult: (v) => result = v);

    for (final k in ['1', '.', '2', '3', '4', '5']) {
      await tester.tap(keypadKey(k));
      await tester.pump();
    }
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();

    expect(result, 1.23);
  });

  testWidgets('C clears and blocks confirm until something is typed',
      (tester) async {
    double? result = -1;
    await open(tester,
        title: 'السعر', initialValue: 5, min: 0, onResult: (v) => result = v);

    await tester.tap(keypadKey('clear'));
    await tester.pump();

    expect(find.text('قيمة غير صحيحة'), findsOneWidget);
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(result, -1);
  });
}
