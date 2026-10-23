import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';

/// قاعدةُ اختبارٍ بشكل **v195**: `table_reservations` بلا `party_id`، بلا
/// فهارس v196 وبلا `party_dedup_suspects` — ثم `db.runOnUpgrade(Migrator(db),
/// 195, 196)` يمرّ بالمسار الحقيقيّ للترقية. (لا `db.close()`: مؤقّت drift
/// ينتظر في المنطقة الوهميّة فيعلّق الاختبار — كبقيّة اختبارات الترقية.)
Future<AppDatabase> openV195ReservationsDb() async {
  final db = AppDatabase.forTesting();
  await db.customStatement('PRAGMA foreign_keys = OFF');
  await db.customStatement('DROP INDEX IF EXISTS idx_table_reservations_party');
  await db.customStatement('DROP INDEX IF EXISTS idx_bookings_party');
  await db.customStatement('DROP TABLE IF EXISTS party_dedup_suspects');
  await db.customStatement('DROP TABLE table_reservations');
  await db.customStatement('''
CREATE TABLE "table_reservations" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "table_id" INTEGER NOT NULL REFERENCES restaurant_tables (id),
  "customer_name" TEXT NOT NULL,
  "customer_phone" TEXT NULL,
  "reservation_time" INTEGER NOT NULL,
  "party_size" INTEGER NOT NULL DEFAULT 2,
  "notes" TEXT NULL,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
  "global_id" TEXT NULL UNIQUE,
  "last_modified_at" INTEGER NULL,
  "deleted_at" INTEGER NULL,
  "origin_client_id" TEXT NULL,
  "row_version" INTEGER NOT NULL DEFAULT 0
)''');
  await db.customStatement('PRAGMA foreign_keys = ON');
  return db;
}

Future<int> insertTestTable(AppDatabase db, String name) async {
  await db.customStatement(
      'INSERT INTO restaurant_tables (name, capacity) VALUES (?, 4)', [name]);
  final r = await db
      .customSelect('SELECT MAX(id) AS id FROM restaurant_tables')
      .getSingle();
  return (r.data['id'] as num).toInt();
}

Future<int> insertTestServiceId(AppDatabase db) async {
  await db.customStatement(
      "INSERT INTO booking_services (name, price) VALUES ('خدمة', 100)");
  final r = await db
      .customSelect('SELECT MAX(id) AS id FROM booking_services')
      .getSingle();
  return (r.data['id'] as num).toInt();
}

int _gidSeq = 0;

/// طرفٌ بالـSQL الخام (للتحكّم الكامل بالهاتف والنوع). يعيد المعرّف.
Future<int> insertTestParty(
  AppDatabase db,
  String name, {
  String? phone,
  bool customer = true,
  bool supplier = false,
  bool active = true,
  String? branchIds,
}) async {
  await db.customStatement(
    'INSERT INTO parties (name, phone, is_customer, is_supplier, is_active, '
    'is_global, branch_ids, global_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [
      name,
      phone,
      customer ? 1 : 0,
      supplier ? 1 : 0,
      active ? 1 : 0,
      branchIds == null ? 1 : 0,
      branchIds,
      'gid-${name.hashCode}-${phone ?? 'x'}-${DateTime.now().microsecondsSinceEpoch}-${_gidSeq++}',
    ],
  );
  final r =
      await db.customSelect('SELECT MAX(id) AS id FROM parties').getSingle();
  return (r.data['id'] as num).toInt();
}

Future<int> insertTestReservation(
  AppDatabase db,
  int tableId,
  String name,
  String? phone, {
  int? partyId,
  bool hasPartyColumn = true,
}) async {
  final t = DateTime(2030, 1, 1, 19).millisecondsSinceEpoch ~/ 1000;
  if (hasPartyColumn) {
    await db.customStatement(
      'INSERT INTO table_reservations (table_id, customer_name, '
      'customer_phone, reservation_time, party_id) VALUES (?, ?, ?, ?, ?)',
      [tableId, name, phone, t, partyId],
    );
  } else {
    await db.customStatement(
      'INSERT INTO table_reservations (table_id, customer_name, '
      'customer_phone, reservation_time) VALUES (?, ?, ?, ?)',
      [tableId, name, phone, t],
    );
  }
  final r = await db
      .customSelect('SELECT MAX(id) AS id FROM table_reservations')
      .getSingle();
  return (r.data['id'] as num).toInt();
}

Future<int> insertTestBooking(
  AppDatabase db,
  int serviceId,
  String name,
  String? phone, {
  int? partyId,
}) async {
  final s = DateTime(2030, 1, 2, 10).millisecondsSinceEpoch ~/ 1000;
  await db.customStatement(
    'INSERT INTO bookings (customer_name, customer_phone, party_id, '
    'service_id, starts_at, ends_at) VALUES (?, ?, ?, ?, ?, ?)',
    [name, phone, partyId, serviceId, s, s + 1800],
  );
  final r = await db.customSelect('SELECT MAX(id) AS id FROM bookings').getSingle();
  return (r.data['id'] as num).toInt();
}

Future<Map<String, Object?>> rowOf(AppDatabase db, String table, int id) async =>
    (await db.customSelect('SELECT * FROM $table WHERE id = ?',
            variables: [Variable.withInt(id)]).getSingle())
        .data;

Future<int> scalar(AppDatabase db, String sql) async =>
    ((await db.customSelect(sql).getSingle()).data.values.first as num).toInt();
