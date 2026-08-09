// ═══════════════════════════════════════════════════════════════════════════
// اعتمادُ الإجازة مرّتين كان يخصم الرصيدَ مرّتين.
// ═══════════════════════════════════════════════════════════════════════════
//
// `updateLeaveStatus(id, 'approved', …)` يخصم `days` من رصيد النوع **كلَّما
// نُودِي**، بلا نظرٍ إلى الحالة السابقة. فطلبٌ معتمدٌ سلفاً يُعتمد ثانيةً
// (نقرةٌ مزدوجة · إعادةُ محاولةٍ بعد خطأِ شبكة · مزامنةٌ تُعيد تطبيق الأمر)
// يخصم ضعفَ أيامه.
//
// والأثرُ ليس تجميلياً: الرصيدُ هو ما يحدّ إجازاتِ الموظف لاحقاً، فخصمٌ
// مضاعَفٌ يحرمه أياماً يستحقها — ولا سجلَّ يقول لماذا.
//
// ⚠️ ولا يظهر العطلُ من الواجهة اليوم (لا مسارَ يعيد اعتمادَ معتمَد)، وهذا
// بالضبط ما يجعله خطراً: يبقى نائماً حتى تُضاف شاشةٌ أو نقطةُ API تفعل.
//
// ── ولماذا كتابةُ الحضور تُعاد بلا ضرر ────────────────────────────────────
// `_writeLeaveAttendance` يكتب بـupsert على مفتاح (موظف، يوم)، فإعادتُه
// تُحدّث الصفَّ نفسَه. الخصمُ وحدَه تراكميّ — ولذلك هو وحدَه ما يحتاج حارساً.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/extensions/hr_extensions.dart';

void main() {
  late AppDatabase db;
  late int employeeId;

  setUp(() async {
    db = AppDatabase.forTesting();
    employeeId = await db.into(db.employees).insert(
        EmployeesCompanion.insert(name: 'موظف الإجازات'));
    await db.initializeLeaveBalances(employeeId, 2026);
  });

  tearDown(() => db.close());

  Future<int> leaveRequest({int days = 5, String type = 'annual'}) =>
      db.into(db.employeeLeaves).insert(EmployeeLeavesCompanion.insert(
            employeeId: employeeId,
            leaveType: type,
            startDate: DateTime(2026, 8, 10),
            endDate: DateTime(2026, 8, 14),
            days: days,
          ));

  Future<int> usedDays({String type = 'annual'}) async {
    final b = await (db.select(db.leaveBalances)
          ..where((b) => b.employeeId.equals(employeeId))
          ..where((b) => b.leaveType.equals(type))
          ..where((b) => b.year.equals(2026)))
        .getSingle();
    return b.usedDays;
  }

  test('الاعتمادُ مرةً يخصم مرةً', () async {
    final id = await leaveRequest(days: 5);
    await db.updateLeaveStatus(id, 'approved', 1);
    expect(await usedDays(), 5);
  });

  test('🔴 الاعتمادُ مرتين لا يخصم مرتين', () async {
    final id = await leaveRequest(days: 5);
    await db.updateLeaveStatus(id, 'approved', 1);
    await db.updateLeaveStatus(id, 'approved', 1);

    expect(await usedDays(), 5,
        reason: 'الرصيدُ يحدّ إجازاتِ الموظف لاحقاً، فخصمٌ مضاعَفٌ يحرمه '
            'أياماً يستحقها ولا سجلَّ يقول لماذا');
  });

  test('اعتمادٌ بعد رفضٍ يخصم مرةً واحدة', () async {
    final id = await leaveRequest(days: 3);
    await db.updateLeaveStatus(id, 'rejected', 1);
    expect(await usedDays(), 0, reason: 'الرفضُ لا يخصم');

    await db.updateLeaveStatus(id, 'approved', 1);
    expect(await usedDays(), 3);
  });

  test('طلبان مستقلّان يُخصمان كلاهما', () async {
    // ضابطٌ يمنع الإفراطَ في الحراسة: الحارسُ يمنع تكرارَ **نفس** الطلب
    // لا خصمَ طلبٍ آخر.
    final a = await leaveRequest(days: 2);
    final b = await leaveRequest(days: 3);
    await db.updateLeaveStatus(a, 'approved', 1);
    await db.updateLeaveStatus(b, 'approved', 1);
    expect(await usedDays(), 5);
  });

  test('حالةُ الطلب وصفوفُ الحضور تُحدَّث ولو لم يُخصم الرصيدُ ثانيةً',
      () async {
    final id = await leaveRequest(days: 5);
    await db.updateLeaveStatus(id, 'approved', 1);
    await db.updateLeaveStatus(id, 'approved', 7);

    final leave = await (db.select(db.employeeLeaves)
          ..where((l) => l.id.equals(id)))
        .getSingle();
    expect(leave.status, 'approved');
    expect(leave.approvedBy, 7,
        reason: 'الحارسُ يمنع الخصمَ المكرَّر لا تحديثَ المعتمِد');
  });
}
