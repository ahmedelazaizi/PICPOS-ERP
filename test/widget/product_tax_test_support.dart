// Shared helpers for the product tax-control widget tests (owner item 5).
// Not a test file itself (no `_test.dart` suffix).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/widgets/dialogs/product_tax_fields.dart';

Widget taxTestHost(Widget child, {AppDatabase? db}) {
  final app = MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: child),
    ),
  );
  return db == null
      ? app
      : ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: app,
        );
}

bool taxBoxChecked(WidgetTester tester, Key key) =>
    tester.widget<Checkbox>(find.byKey(key)).value ?? false;

bool taxRateEnabled(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(ProductTaxFields.rateKey)).enabled ??
    true;

ProductTaxController dialogTaxController(WidgetTester tester) =>
    tester.widget<ProductTaxFields>(find.byType(ProductTaxFields)).controller;

/// Dialog probes tolerate only the Ahem-font RenderFlex overflow (see
/// dark_mode_smoke_test.dart); every other error still fails.
void tolerateDialogOverflow() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

void useLargeTestView(WidgetTester tester) {
  tester.view.physicalSize = const Size(3840, 2160);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Opens (boots + seeds) the in-memory database on the REAL event loop.
/// Drift I/O awaited inside the fake-async test zone deadlocks (see
/// dark_mode_smoke_test.dart). Use ONE database per test file: queries left
/// pending in a finished test's zone stall a second boot in the same isolate,
/// and closing a database still referenced by them hangs the same way — so
/// it is not closed (the isolate ends with the file).
Future<AppDatabase> bootTaxTestDb(WidgetTester tester) async {
  late AppDatabase db;
  await tester.runAsync(() async {
    db = AppDatabase.forTesting();
    await db.customSelect('SELECT 1').get();
  });
  return db;
}
