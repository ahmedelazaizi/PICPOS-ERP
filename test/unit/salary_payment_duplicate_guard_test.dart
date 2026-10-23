// ═══════════════════════════════════════════════════════════════════════════
// B1 — «صرف الراتب» كان بيتنفّذ كل مرة يتضغط فيها. ضغطتين = راتبان.
// ═══════════════════════════════════════════════════════════════════════════
//
// `recordSalaryPayment` كانت بتـ`insert` صف `salary_payments` جديد بلا أي فحص
// لوجود صرف سابق لنفس `(employeeId, period, type)`، والزر بيفضل مفعّل. فكل
// ضغطة كانت بتنتج:
//   • صف راتب جديد
//   • سند صرف نقدي جديد ورصيد الخزنة بينقص تاني
//   • قيد يومية جديد
//
// وحارس التكرار في `createJournalEntry` مكانش بينفع هنا لأن مفتاحه
// `referenceId = salaryPayments.id` — و`id` **جديد كل مرة**، فالحارس بيشوف
// عملية جديدة تماماً في كل ضغطة.
//
// ⚠️ الصح المعماري قيد فريد على (employee_id, period, type) في السكيما. تغيير
// السكيما محتاج build_runner — متجمّد في جلسات الوكيل (شوف
// docs/superpowers/handoff) — فالحارس هنا على مستوى التطبيق داخل نفس
// الـtransaction. القيد على مستوى قاعدة البيانات لسه مطلوب كطبقة تانية.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/extensions/hr_extensions.dart';

void main() {
  late AppDatabase db;
  late int employeeId;
  late int otherEmployeeId;
  late int safeId;

  const openingBalance = 10000.0;

  Future<double> safeBalance() async {
    final s = await (db.select(db.safes)..where((t) => t.id.equals(safeId)))
        .getSingle();
    return s.balance;
  }

  Future<int> paymentCount() async =>
      (await db.select(db.salaryPayments).get()).length;

  setUp(() async {
    db = AppDatabase.forTesting();
    employeeId = await db.into(db.employees).insert(EmployeesCompanion.insert(
        name: 'أحمد محمد', salary: const Value(3000.0)));
    otherEmployeeId = await db.into(db.employees).insert(
        EmployeesCompanion.insert(name: 'سارة علي', salary: const Value(2000.0)));

    // لازم نفس الخزنة اللي recordSalaryPayment بتحلّها إنتاجياً. الإصدار الأول
    // من الاختبار ده أنشأ خزنة جديدة وأكّد على رصيدها — لكن forTesting() بيزرع
    // خزنة افتراضية بالفعل، فالصرف كان بينزل عليها والاختبار بيراقب خزنة
    // ما حدش بيلمسها. تجهيزة زي دي بتعدّي على مسار مش المسار المقصود.
    final defaultSafe = await db.getDefaultSafeByType('cash');
    expect(defaultSafe, isNotNull,
        reason: 'المسار النقدي في recordSalaryPayment بيتخطّى بالكامل بلا خزنة');
    safeId = defaultSafe!.id;
    await (db.update(db.safes)..where((t) => t.id.equals(safeId)))
        .write(const SafesCompanion(balance: Value(openingBalance)));
  });

  tearDown(() => db.close());

  test('الصرف الأول بينجح وبينقص الخزنة مرة واحدة', () async {
    final id = await db.recordSalaryPayment(
        employeeId: employeeId, amount: 3000, period: '2026-08');
    expect(id, isPositive);
    expect(await paymentCount(), 1);
    expect(await safeBalance(), openingBalance - 3000);
  });

  test('الضغطة التانية لنفس الموظف ونفس الفترة بترفض', () async {
    await db.recordSalaryPayment(
        employeeId: employeeId, amount: 3000, period: '2026-08');
    await expectLater(
      db.recordSalaryPayment(
          employeeId: employeeId, amount: 3000, period: '2026-08'),
      throwsA(isA<StateError>()),
      reason: 'ضغطتين على «صرف الراتب» كانوا بينتجوا راتبين',
    );
  });

  test('ولا بتسيب أي أثر: صف واحد ورصيد منقوص مرة واحدة', () async {
    await db.recordSalaryPayment(
        employeeId: employeeId, amount: 3000, period: '2026-08');
    try {
      await db.recordSalaryPayment(
          employeeId: employeeId, amount: 3000, period: '2026-08');
    } catch (_) {/* متوقّع */}

    expect(await paymentCount(), 1, reason: 'كان بيبقى صفّين');
    expect(await safeBalance(), openingBalance - 3000,
        reason: 'النقدية كانت بتتصرف مرتين — ٦٠٠٠ بدل ٣٠٠٠');
    final vouchers = await (db.select(db.safeTransactions)
          ..where((t) => t.category.equals('salaries')))
        .get();
    expect(vouchers.length, 1, reason: 'سند صرف واحد بس');
  });

  test('فترة تانية لنفس الموظف بتعدّي', () async {
    await db.recordSalaryPayment(
        employeeId: employeeId, amount: 3000, period: '2026-08');
    final id = await db.recordSalaryPayment(
        employeeId: employeeId, amount: 3000, period: '2026-09');
    expect(id, isPositive);
    expect(await paymentCount(), 2);
  });

  test('موظف تاني لنفس الفترة بيعدّي', () async {
    await db.recordSalaryPayment(
        employeeId: employeeId, amount: 3000, period: '2026-08');
    final id = await db.recordSalaryPayment(
        employeeId: otherEmployeeId, amount: 2000, period: '2026-08');
    expect(id, isPositive);
    expect(await paymentCount(), 2);
  });

  test('نوع تاني (مكافأة) لنفس الفترة بيعدّي — مش نفس الالتزام', () async {
    await db.recordSalaryPayment(
        employeeId: employeeId, amount: 3000, period: '2026-08');
    final id = await db.recordSalaryPayment(
        employeeId: employeeId, amount: 500, period: '2026-08', type: 'bonus');
    expect(id, isPositive);
    expect(await paymentCount(), 2);
  });
}
