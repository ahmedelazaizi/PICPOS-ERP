// Spec 029 / US4 — bulk-seed 5,000 products into the local DB.
//
// Usage: `dart run scripts/seed_5k_products.dart [count]`  (default 5000)
//
// Developer convenience for the perf audit recipe. NOT part of the
// test suite — produces real rows in the encrypted SQLCipher DB used
// by the running app, so do NOT run against a production install.
//
// Recipe per quickstart.md §"US4":
//   1. Close the running app.
//   2. `dart run scripts/seed_5k_products.dart`.
//   3. Flip `kPerfDebug` to true in lib/core/diagnostics/perf_trace.dart.
//   4. `flutter run -d windows --release`.
//   5. Open the products screen + inventory screen with the dev
//      console showing.
//   6. Read off the [PERF] lines for first-paint, frame-over-budget,
//      and search-query counts.
//
// Step 3 is reverted before commit — the const stays `false` in
// production. The instrumentation is for runtime audit only.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/widgets.dart';
import 'package:picpos_erp/data/database/database.dart';

Future<void> main(List<String> args) async {
  // Required so getApplicationDocumentsDirectory works outside the
  // Flutter app shell.
  WidgetsFlutterBinding.ensureInitialized();

  final count = args.isNotEmpty ? int.parse(args.first) : 5000;
  print('[SEED] Bulk-inserting $count products into local DB ...');

  final db = AppDatabase();
  final stopwatch = Stopwatch()..start();

  await db.batch((batch) {
    for (var i = 0; i < count; i++) {
      batch.insert(
        db.products,
        ProductsCompanion.insert(
          code: 'PERF-$i',
          name: 'صنف اختبار الأداء رقم $i',
          salePrice: const Value(10),
          costPrice: const Value(7),
          barcode: Value('${1000000 + i}'),
        ),
      );
    }
  });

  stopwatch.stop();
  print('[SEED] Inserted $count rows in ${stopwatch.elapsed.inSeconds}s');
  await db.close();
  exit(0);
}
