import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

import '../../core/config/app_config.dart';
import '../../core/config/brand.dart';
import 'pg_config.dart';

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

/// مطابق لتوقيع `connection_io.dart` (يرجع اسم القاعدة بلا لاحقة على الويب).
String getDatabaseFileName() => getWebDatabaseName();

String databaseFileNameFor(AppFlavor flavor) =>
    '${Brand.dbPrefix}_${flavor.code}';

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

// ─── مطابقة توقيعات connection_io.dart (PostgreSQL والنسخ الاحتياطي) ───
// PostgreSQL المباشر ومسارات الملفات غير مدعومة في المتصفح؛ الويب سيقرأ
// عبر drift/remote ويكتب عبر الـ HTTP API (مراحل لاحقة).

/// غير مدعوم في المتصفح.
QueryExecutor openPostgresConnection(PostgresConfig config) =>
    throw UnsupportedError('PostgreSQL المباشر غير مدعوم على الويب');

/// على الويب يرجع رسالة خطأ دائمًا (لا اتصال مباشر بـ PostgreSQL).
Future<String?> testPostgresConnection(PostgresConfig config) async =>
    'PostgreSQL المباشر غير مدعوم على الويب';

/// قاعدة في الذاكرة للاختبارات — غير مدعومة على الويب.
QueryExecutor openTestConnection() =>
    throw UnsupportedError('openTestConnection غير مدعوم على الويب');

Future<String> getDatabasePath() async => getWebDatabaseName();

typedef WalCheckpoint = Future<bool> Function();

/// بديل خفيف لـ `FileSystemEntity` — الـ `path` فقط.
class BackupEntry {
  const BackupEntry(this.path);
  final String path;
}

/// لا نسخ احتياطي بملفات على الويب.
Future<String?> createDatabaseBackup({
  WalCheckpoint? checkpoint,
  bool requireCheckpoint = false,
}) async =>
    null;

Future<bool> restoreDatabaseBackup(String backupPath) async => false;

Future<bool> hasPendingRestore() async => false;

Future<List<BackupEntry>> listBackups() async => const [];

Future<String?> autoBackupOnStartup({WalCheckpoint? checkpoint}) async =>
    null;

Future<bool> exportBackupToPath(String destinationFolder) async => false;

Future<Map<String, dynamic>> getBackupStats() async =>
    {'count': 0, 'totalSize': 0, 'lastBackup': null};
