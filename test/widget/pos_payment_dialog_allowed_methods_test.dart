import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/pos/widgets/pos_dialogs.dart';

/// `allowedMethods` on the shared checkout dialog (طلب ٢).
///
/// The PicPos payment panel lost its method buttons, so this dialog became the
/// only place a method is chosen — and the per-method `PermissionGuard`s that
/// wrapped those buttons had to move here.
///
/// The FIRST test is the important one: it is the UralCash no-regression
/// assertion. That till calls `showPaymentDialog` without the new argument, so
/// `allowedMethods` is null and every chip must still render.
void main() {
  Future<void> openDialog(
    WidgetTester tester, {
    Set<String>? allowedMethods,
    String initialMethod = 'cash',
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => PosDialogs.showPaymentDialog(
                  context,
                  totalAmount: 100,
                  initialMethod: initialMethod,
                  allowedMethods: allowedMethods,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('null allowedMethods renders all five chips (UralCash unchanged)',
      (tester) async {
    await openDialog(tester);

    expect(find.text('نقدي'), findsOneWidget);
    expect(find.text('بطاقة (بنك)'), findsOneWidget);
    expect(find.text('كليك'), findsOneWidget);
    expect(find.text('آجل'), findsOneWidget);
    expect(find.text('متعدد'), findsOneWidget);
    expect(find.text('إتمام الدفع'), findsOneWidget);
  });

  testWidgets('a restricted set renders only the permitted chips',
      (tester) async {
    await openDialog(tester, allowedMethods: {'cash', 'credit'});

    expect(find.text('نقدي'), findsOneWidget);
    expect(find.text('آجل'), findsOneWidget);
    expect(find.text('بطاقة (بنك)'), findsNothing);
    expect(find.text('كليك'), findsNothing);
    expect(find.text('متعدد'), findsNothing);
  });

  testWidgets('a single permitted method renders exactly that chip',
      (tester) async {
    await openDialog(tester, allowedMethods: {'cash'});

    expect(find.text('نقدي'), findsOneWidget);
    expect(find.text('بطاقة (بنك)'), findsNothing);
    expect(find.text('آجل'), findsNothing);
    expect(find.text('متعدد'), findsNothing);
  });

  testWidgets('no permitted method explains itself and disables confirm',
      (tester) async {
    await openDialog(tester, allowedMethods: <String>{});

    expect(find.text('لا تملك صلاحية أي طريقة دفع — راجع المدير'),
        findsOneWidget);

    // A cashier with no payment permission must not be shown a dead dialog
    // with a live confirm button.
    final confirm = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('إتمام الدفع'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets('falls back to a permitted method when the initial one is barred',
      (tester) async {
    // Caller asks for 'cash' but the cashier only has the card permission.
    // Opening with a selected-but-unrenderable chip would leave the dialog
    // looking like nothing is chosen while it silently holds 'cash'.
    await openDialog(tester,
        initialMethod: 'cash', allowedMethods: {'card'});

    expect(find.text('بطاقة (بنك)'), findsOneWidget);
    expect(find.text('نقدي'), findsNothing);

    final confirm = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('إتمام الدفع'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(confirm.onPressed, isNotNull);
  });
}
