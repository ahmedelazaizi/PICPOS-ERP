// ═══════════════════════════════════════════════════════════════════════════
// v152 — قيود قاعدة البيانات لمنعَي B1 و B2.
// ═══════════════════════════════════════════════════════════════════════════
//
// الحارسان الموجودان كودُ تطبيق:
//   • recordSalaryPayment بيفحص وجود صرف سابق قبل الإدراج
//   • importDeviceCheckIn بيعمل upsert على (employeeId, date)
//
// الاتنين بيقفلوا الضغط المكرر على نفس الجهاز — وبس. كاتب متزامن من جهاز تاني
// بيقرا «مفيش صف سابق» في نفس اللحظة، فالاتنين بيعدّوا الفحص ويكتبوا. والفحص
// -ثم-الكتابة من غير قيد فريد سباقٌ بحكم التعريف.
//
// الاختبار ده بيدخل **من تحت** حارس التطبيق (إدراج مباشر على الجدول) — وده
// بالظبط اللي بيعمله المسار المتزامن. لو القيد مش موجود، الإدراجان بينجحوا
// والاختبار بيفشل.
//
// ملاحظة مقصودة: `period` عمود nullable، وSQLite بيعتبر الـNULLات متمايزة في
// الفهرس الفريد. فصفوف بلا فترة مش محروسة — **مطابقةً** لحارس التطبيق اللي
// بيترجم `period.equals(null)` لـ`= NULL` اللي عمره ما بيتحقق. التطابق بين
// الطبقتين مقصود؛ اختلافهما بينتج رفضاً من القاعدة بلا رسالة مفهومة.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int employeeId;
  late int otherEmployeeId;

  final day = DateTime(2026, 8, 3);

  Future<bool> indexExists(String name) async {
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master "
            "WHERE type = 'index' AND name = '$name'")
        .get();
    return rows.isNotEmpty;
  }

  Future<int> insertSalaryDirect({
    required int empId,
    String? period,
    String type = 'salary',
    double amount = 3000,
  }) =>
      db.into(db.salaryPayments).insert(SalaryPaymentsCompanion.insert(
            employeeId: empId,
            amount: amount,
            paymentDate: DateTime(2026, 8, 28),
            period: Value(period),
            type: Value(type),
          ));

  Future<int> insertAttendanceDirect({
    required int empId,
    required DateTime date,
  }) =>
      db.into(db.employeeAttendance).insert(
          EmployeeAttendanceCompanion.insert(employeeId: empId, date: date));

  setUp(() async {
    db = AppDatabase.forTesting();
    employeeId = await db.into(db.employees).insert(
        EmployeesCompanion.insert(name: 'أحمد', salary: const Value(3000)));
    otherEmployeeId = await db.into(db.employees).insert(
        EmployeesCompanion.insert(name: 'سارة', salary: const Value(2000)));
  });

  tearDown(() => db.close());

  group('الفهارس موجودة على تنصيب جديد', () {
    test('فهرس تكرار الراتب', () async {
      expect(await indexExists(kSalaryPaymentDedupIndexName), isTrue,
          reason: 'createAll() ما بيصدّرش الفهارس الخام — لازم onCreate يعملها');
    });

    test('فهرس تكرار يوم الحضور', () async {
      expect(await indexExists(kAttendanceDayDedupIndexName), isTrue);
    });
  });

  group('B1 — الراتب: القيد بيمسك اللي حارس التطبيق مش قادر عليه', () {
    test('صرفان لنفس (موظف، فترة، نوع) بالإدراج المباشر بيترفضوا', () async {
      await insertSalaryDirect(empId: employeeId, period: '2026-08');
      await expectLater(
        insertSalaryDirect(empId: employeeId, period: '2026-08'),
        throwsA(anything),
        reason: 'ده مسار الكاتب المتزامن — بيعدّي من تحت حارس التطبيق',
      );
      final rows = await db.select(db.salaryPayments).get();
      expect(rows.length, 1);
    });

    test('فترة تانية بتعدّي', () async {
      await insertSalaryDirect(empId: employeeId, period: '2026-08');
      await insertSalaryDirect(empId: employeeId, period: '2026-09');
      expect((await db.select(db.salaryPayments).get()).length, 2);
    });

    test('نوع تاني لنفس الفترة بيعدّي — التزام مختلف مش تكرار', () async {
      await insertSalaryDirect(empId: employeeId, period: '2026-08');
      await insertSalaryDirect(
          empId: employeeId, period: '2026-08', type: 'bonus', amount: 500);
      expect((await db.select(db.salaryPayments).get()).length, 2);
    });

    test('موظف تاني لنفس الفترة بيعدّي', () async {
      await insertSalaryDirect(empId: employeeId, period: '2026-08');
      await insertSalaryDirect(empId: otherEmployeeId, period: '2026-08');
      expect((await db.select(db.salaryPayments).get()).length, 2);
    });
  });

  group('B2 — الحضور: صف واحد لكل (موظف، يوم)', () {
    test('صفّان لنفس اليوم بالإدراج المباشر بيترفضوا', () async {
      await insertAttendanceDirect(empId: employeeId, date: day);
      await expectLater(
        insertAttendanceDirect(empId: employeeId, date: day),
        throwsA(anything),
        reason: 'صف حضور مكرر = يوم عمل مدفوع مرتين',
      );
      expect((await db.select(db.employeeAttendance).get()).length, 1);
    });

    test('يوم تاني بيعدّي', () async {
      await insertAttendanceDirect(empId: employeeId, date: day);
      await insertAttendanceDirect(
          empId: employeeId, date: DateTime(2026, 8, 4));
      expect((await db.select(db.employeeAttendance).get()).length, 2);
    });

    test('موظف تاني لنفس اليوم بيعدّي', () async {
      await insertAttendanceDirect(empId: employeeId, date: day);
      await insertAttendanceDirect(empId: otherEmployeeId, date: day);
      expect((await db.select(db.employeeAttendance).get()).length, 2);
    });
  });
}
