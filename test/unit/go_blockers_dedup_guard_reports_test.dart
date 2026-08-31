// ═══════════════════════════════════════════════════════════════════════════
// §٦‑٤ — قيدٌ ماليٌّ لم يُركَّب: بلاغٌ ظاهرٌ بدل فشلٍ صامت
// ═══════════════════════════════════════════════════════════════════════════
//
// فهرسا B1 (‏`salary_payments(employee_id, period, type)`) وB2
// (‏`employee_attendance(employee_id, date)`) يُنشآن في حلقة الشفاء الذاتيّ
// بـ`CREATE UNIQUE INDEX IF NOT EXISTS`، والحلقةُ تبتلع الفشلَ بـ`catch (_)`.
// فقاعدةٌ فيها تكرارٌ قائمٌ **تخرج بلا حماية ولا أحدَ يعلم**.
//
// ⚠️ **والابتلاعُ يبقى بقرار المالك 2026-09-02.** الصفُّ الزائدُ هنا حركةٌ
// ماليّةٌ — دفعةُ راتبٍ أو يومُ حضورٍ يتحوّل إلى أجر — لا إعدادٌ مكرَّرٌ كما في
// `account_mappings` التي تُسوَّى آليّاً. فحذفُه عند الإقلاع يُتلف مالاً بلا
// مراجعة.
//
// فالمقيسُ هنا شيئان معاً:
//   ١ — **البلاغُ يظهر** ويحمل المفتاحَ المكرَّرَ وعددَه.
//   ٢ — **ولا صفَّ يُحذَف** — السياسةُ لم تتغيّر.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int employeeId;

  setUp(() async {
    db = AppDatabase.forTesting();
    employeeId = await db.into(db.employees).insert(
          EmployeesCompanion.insert(name: 'موظّفُ الاختبار'),
        );
  });

  tearDown(() async => db.close());

  Future<int> attendanceRows() async {
    final r = await db
        .customSelect('SELECT COUNT(*) AS n FROM employee_attendance')
        .getSingle();
    return (r.data['n'] as num).toInt();
  }

  Future<bool> indexExists(String name) async {
    final rows = await db
        .customSelect(
          "SELECT 1 AS x FROM sqlite_master "
          "WHERE type = 'index' AND name = '$name'",
        )
        .get();
    return rows.isNotEmpty;
  }

  test('قاعدةٌ سليمةٌ لا تُنتج بلاغاً', () async {
    expect(await indexExists(kAttendanceDayDedupIndexName), isTrue,
        reason: 'مرساة: القيدُ مُركَّبٌ على قاعدةٍ نظيفة');
    expect(await db.findBlockedDedupIndexes(), isEmpty);
  });

  test('تكرارٌ قائمٌ يُنتج بلاغاً يحمل المفتاحَ وعددَه — ولا يُحذف صفّ',
      () async {
    // تُزرَع الحالةُ التي كانت تصل من استيرادِ بصمةٍ قديم: القيدُ يُرفَع ثمّ
    // يُكرَّر اليوم.
    await db.customStatement(
        'DROP INDEX IF EXISTS $kAttendanceDayDedupIndexName');
    expect(await indexExists(kAttendanceDayDedupIndexName), isFalse);

    final day = DateTime(2026, 3, 15);
    for (var i = 0; i < 2; i++) {
      await db.into(db.employeeAttendance).insert(
            EmployeeAttendanceCompanion.insert(
              employeeId: employeeId,
              date: day,
              status: const Value('present'),
            ),
          );
    }
    expect(await attendanceRows(), 2, reason: 'مرساة: التكرارُ زُرع فعلاً');

    await db.ensureSchemaDefaults();

    // ١ — البلاغ
    final findings = await db.findBlockedDedupIndexes();
    expect(findings.length, 1,
        reason: 'بلاغٌ واحدٌ لقيدِ الحضور — وB1 سليمٌ فلا بلاغَ له');
    expect(findings.single, contains(kAttendanceDayDedupIndexName));
    expect(findings.single, contains('employee_id=$employeeId'),
        reason: 'البلاغُ يجب أن يحمل المفتاحَ المكرَّرَ نفسَه — '
            'وإلّا لم يعرف المحاسبُ ماذا يسوّي');
    expect(findings.single, contains('×2'),
        reason: 'وعددَ التكرار');

    // ٢ — والسياسةُ لم تتغيّر: لا حذفَ ولا تركيبَ قيدٍ فوق بياناتٍ مكرّرة
    expect(await attendanceRows(), 2,
        reason: 'قرارُ المالك: لا تسويةَ آليّةً لحركةٍ ماليّة');
    expect(await indexExists(kAttendanceDayDedupIndexName), isFalse,
        reason: 'القيدُ يبقى غائباً حتى يسوّي المحاسبُ البيانات');
  });
}
