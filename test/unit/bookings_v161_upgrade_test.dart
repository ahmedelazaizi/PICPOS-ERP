// test/unit/bookings_v161_upgrade_test.dart
//
// ترقيةُ v161 على قاعدةٍ **قائمة** — لا على قاعدةٍ جديدة.
//
// ⚠️ `bookings_v161_constraints_test.dart` يقيس ٢١٨ سطراً كلَّها على
// `AppDatabase.forTesting()`، وهي قاعدةٌ تُبنى بـ`onCreate` من تعريفِ اليوم.
// فهي تُثبت أنّ **التعريفَ** صحيحٌ ولا تمسّ `onUpgrade` بحال. ووقع ما تسمح
// به هذه الفجوة: قاعدةُ المالك وصلت `user_version = 161` و`booking_resources`
// فيها عشرةُ أعمدةٍ بلا `role` ولا `kind` ولا عمودَي الورديّة، فسقطت شاشةُ
// الحجوزات كلُّها بـ`no such column: booking_resources.role` — واختباراتُ
// القيود خضراءُ طوالَ الوقت.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  /// شكلُ `booking_resources` عند v160 **بحرفه** — منقولٌ من `sqlite_master`
  /// على قاعدة المالك الحقيقيّة، لا مكتوباً بالتخمين.
  const v160BookingResources = '''
CREATE TABLE "booking_resources" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "name" TEXT NOT NULL,
  "color_hex" TEXT NOT NULL DEFAULT '#3B82F6',
  "phone" TEXT NULL,
  "employee_id" INTEGER NULL REFERENCES employees (id),
  "is_active" INTEGER NOT NULL DEFAULT 1 CHECK ("is_active" IN (0, 1)),
  "sort_order" INTEGER NOT NULL DEFAULT 0,
  "branch_id" INTEGER NULL REFERENCES branches (id),
  "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
  "deleted_at" INTEGER NULL
)''';

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    // إعادةُ الجدول إلى شكلِ ما قبل الترقية، ثم تشغيلُ الترقية الحقيقيّة فوقه.
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.customStatement('DROP TABLE booking_resources');
    await db.customStatement(v160BookingResources);
    await db.customStatement(
      "INSERT INTO booking_resources (id, name, color_hex) "
      "VALUES (1, 'محمد', '#3B82F6')",
    );
    await db.customStatement('PRAGMA foreign_keys = ON');
  });

  Future<Set<String>> resourceColumns() async {
    final rows = await db.customSelect('PRAGMA table_info(booking_resources)').get();
    return rows.map((r) => r.data['name'] as String).toSet();
  }

  test('الترقيةُ من v160 تُضيف أعمدةَ المورد الأربعة فعلاً', () async {
    expect(await resourceColumns(), isNot(contains('role')),
        reason: 'التجهيزةُ نفسُها لازم تبدأ بلا العمود وإلّا لا تقيس شيئاً');

    await db.runOnUpgrade(Migrator(db), 160, 161);

    expect(
      await resourceColumns(),
      containsAll(<String>[
        'role',
        'kind',
        'shift_start_minutes',
        'shift_end_minutes',
      ]),
    );
  });

  test('والصفُّ القائمُ ينجو من إعادة البناء', () async {
    await db.runOnUpgrade(Migrator(db), 160, 161);

    final rows =
        await db.customSelect('SELECT name FROM booking_resources').get();
    expect(rows.map((r) => r.data['name']), contains('محمد'));
  });

  test('قاعدةٌ خُتمت 161 والأعمدةُ ناقصةٌ — حالةُ المالك بعينها — تُصلَّح',
      () async {
    // ⚠️ هذه هي الحالةُ الواقعة: `_safeMigrate` ابتلع
    // `no such column: "role"` كأنّه خطأٌ عديمُ الأثر، فخُتمت القاعدةُ 161
    // والأعمدةُ لم تُضَف — و`from < 161` لا يمكن أن يعود أبداً. فإصلاحُ
    // خطوةِ 161 وحدَه لا ينفع هذه القاعدة: تحتاج خطوةً **جديدة**.
    await db.runOnUpgrade(Migrator(db), 161, 162);

    expect(
      await resourceColumns(),
      containsAll(<String>[
        'role',
        'kind',
        'shift_start_minutes',
        'shift_end_minutes',
      ]),
    );
  });

  test('والإصلاحُ لا يمسّ قاعدةً أعمدتُها موجودةٌ أصلاً', () async {
    // تنصيبةٌ جديدةٌ وُلدت بـ`onCreate` عند 161 تملك الأعمدةَ وفيها بيانات.
    // إعادةُ بنائها بـ`newColumns` تكتب الافتراضاتِ فوقَ القيم — فالخطوةُ
    // لا بدّ أن تفحص قبل أن تُصلح.
    await db.runOnUpgrade(Migrator(db), 161, 162);
    await db.customStatement(
        "UPDATE booking_resources SET role = 'حلّاق' WHERE id = 1");

    await db.runOnUpgrade(Migrator(db), 161, 162);

    final rows =
        await db.customSelect('SELECT role FROM booking_resources').get();
    expect(rows.single.data['role'], 'حلّاق');
  });

  test('والاستعلامُ الذي سقط عند المالك يعمل بعد الترقية', () async {
    // ⚠️ هذا هو العطبُ بعينه: `watchBookingsBoard` تجمع `booking_resources`
    // فتطلب `role`، فتسقط الشاشةُ كلُّها بـSqliteException قبل أن تُرسم.
    await db.runOnUpgrade(Migrator(db), 160, 161);

    await expectLater(
      db.customSelect('SELECT role, kind, shift_start_minutes, '
              'shift_end_minutes FROM booking_resources')
          .get(),
      completes,
    );
  });
}
