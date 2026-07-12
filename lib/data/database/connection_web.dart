import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// Open database connection for web platform using IndexedDB
QueryExecutor openConnection() {
  return DatabaseConnection.delayed(
    Future(() async {
      final result = await WasmDatabase.open(
        databaseName: 'cashier_market',
        sqlite3Uri: Uri.parse('sqlite3.wasm'),
        driftWorkerUri: Uri.parse('drift_worker.js'),
      );
      return result.resolvedExecutor;
    }),
  );
}
