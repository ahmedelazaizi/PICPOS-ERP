import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

import '../../core/config/app_config.dart';
import '../../core/config/brand.dart';

/// اسم قاعدة البيانات على الويب.
///
/// كان مثبَّت على `'cashier_market'` — اسم من قبل إعادة التسمية، **ومشترك
/// بين المنتجين**: أي علامتين شغالين على نفس المتصفح كانوا هيفتحوا نفس
/// قاعدة IndexedDB، وde بالظبط اللي طبقة العزل موجودة تمنعه على سطح المكتب
/// (اقرأ `databaseFileNameFor` في `connection_io.dart`).
///
/// نفس التركيبة بتاعة سطح المكتب من غير لاحقة `.db` — WasmDatabase بياخد
/// اسم مش مسار.
String getWebDatabaseName() =>
    '${Brand.dbPrefix}_${AppConfig.flavor.code}';

/// Open database connection for web platform using IndexedDB
QueryExecutor openConnection() {
  return DatabaseConnection.delayed(
    Future(() async {
      final result = await WasmDatabase.open(
        databaseName: getWebDatabaseName(),
        sqlite3Uri: Uri.parse('sqlite3.wasm'),
        driftWorkerUri: Uri.parse('drift_worker.js'),
      );
      return result.resolvedExecutor;
    }),
  );
}
