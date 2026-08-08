// ═══════════════════════════════════════════════════════════════════════════
// B5 — تغطية `calculateNetSalary`. كانت صفراً على مسار السلف والخصومات.
// ═══════════════════════════════════════════════════════════════════════════
//
// H1 وB4 غطّيا مسار الحضور → الإجمالي (أيامُ الشهر · الحالاتُ المدفوعة)، أما
// السلفُ والخصوماتُ والوقتُ الإضافي وقصُّ الصافي عند صفر فلم يمسّها اختبارٌ قطّ.
//
// ولهذا الترتيبُ سببٌ لا شكل: B3 سيمرّر الإجماليَّ والسلفَ إلى قيدِ اليومية،
// ورقمٌ غيرُ مغطّىً حين يُمرَّر يصير رقماً غيرَ مغطّىً **في الدفاتر**. فالتغطيةُ
// أولاً حتى تكون الأرقامُ موثوقةً قبل أن تُصرَف.
//
// الراتبُ ٢٨٠٠ وفبراير ٢٨ يوماً ⇒ الأجرُ اليومي = ١٠٠ بالتدقيق، فكلُّ رقمٍ في
// هذا الملف يُقرأ بلا كسورٍ عشرية تُخفي خطأً.
//
// ⚠️ اختبارُ القصّ أدناه يُثبّت السلوكَ **القائم** لا الصحيح: الصافي يُقَصّ عند
// صفرٍ بينما `totalAdvances` يُبلِّغ السلفةَ كاملةً، فيبدو أنّ السلفةَ سُوِّيت
// وهي لم تُسَوَّ. هذا هو المانعُ الحسابي الذي يُصلحه B3.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/extensions/hr_extensions.dart';

void main() {
  late AppDatabase db;
  late int employeeId;

  const salary = 2800.0; // ÷ ٢٨ يوماً = ١٠٠ يومياً
  const dailyRate = 100.0;

  Future<void> markPresentFullFebruary() async {
    for (var d = 1; d <= 28; d++) {
      await db.into(db.employeeAttendance).insert(
            EmployeeAttendanceCompanion.insert(
              employeeId: employeeId,
              date: DateTime(2026, 2, d),
              status: const Value('present'),
            ),
          );
    }
  }

  Future<EmployeeSalaryCalculation> calcFebruary() => db.calculateNetSalary(
        employeeId: employeeId,
        year: 2026,
        month: 2,
      );

  /// سلفةٌ بلا أثرٍ على الخزنة — يتجنّب مسارَ القيد والخزنة كي يبقى الاختبار
  /// على `calculateNetSalary` وحدها.
  Future<int> advance(double amount, {DateTime? on}) =>
      db.recordEmployeeAdvance(
        employeeId: employeeId,
        amount: amount,
        affectsTreasury: false,
        transactionDate: on ?? DateTime(2026, 2, 10),
      );

  Future<int> deduction(double amount, {DateTime? on}) =>
      db.recordEmployeeDeduction(
        employeeId: employeeId,
        amount: amount,
        transactionDate: on ?? DateTime(2026, 2, 10),
      );

  setUp(() async {
    db = AppDatabase.forTesting();
    // ‏`salaryType: 'daily'` صريحٌ — شوف التعليق في `payroll_month_length_test`:
    // الموديلُ الشهري يجعل الإجماليَّ مستقلاً عن أيام الحضور، فتغطيةُ تركيبِ
    // الإجمالي هنا تصير صامتةً. هذا الملفُّ عن التراكم اليومي؛ الشهريُّ له ملفُّه.
    employeeId = await db.into(db.employees).insert(
          EmployeesCompanion.insert(
            name: 'أحمد',
            salary: const Value(salary),
            salaryType: const Value('daily'),
          ),
        );
  });

  tearDown(() => db.close());

  group('B5 — الإجمالي', () {
    test('شهرٌ كامل الحضور بلا شيءٍ آخر: الإجمالي = الراتب', () async {
      await markPresentFullFebruary();

      final calc = await calcFebruary();

      expect(calc.baseSalary, salary);
      expect(calc.dailyRate, dailyRate);
      expect(calc.daysAttended, 28);
      expect(calc.grossPay, closeTo(salary, 0.01));
      expect(calc.month, 2);
      expect(calc.year, 2026);
    });

    test('الوقتُ الإضافي يُضاف إلى الإجمالي لا إلى الصافي وحده', () async {
      await markPresentFullFebruary();
      // ساعتان × ١٫٥ × (2800 ÷ 28 ÷ 8 = 12.5) = 37.5
      await db.addOvertimeRecord(
        employeeId: employeeId,
        date: DateTime(2026, 2, 12),
        hours: 2,
        rate: 1.5,
      );

      final calc = await calcFebruary();

      expect(calc.overtimeAmount, closeTo(37.5, 0.01));
      expect(calc.grossPay, closeTo(salary + 37.5, 0.01),
          reason: 'الإضافي جزءٌ من الإجمالي — وB3 سيقيّد الإجماليَّ مديناً');
      expect(calc.netSalary, closeTo(salary + 37.5, 0.01));
    });
  });

  group('B5 — السلف', () {
    test('سلفةٌ واحدة تُخصم من الصافي ولا تمسّ الإجمالي', () async {
      await markPresentFullFebruary();
      await advance(500);

      final calc = await calcFebruary();

      expect(calc.totalAdvances, closeTo(500, 0.01));
      expect(calc.grossPay, closeTo(salary, 0.01),
          reason: 'السلفةُ تسويةُ أصلٍ لا مصروفٌ — لا تُنقص الإجمالي');
      expect(calc.netSalary, closeTo(2300, 0.01));
    });

    test('سلفتان تُجمعان', () async {
      await markPresentFullFebruary();
      await advance(300);
      await advance(200, on: DateTime(2026, 2, 20));

      final calc = await calcFebruary();

      expect(calc.totalAdvances, closeTo(500, 0.01));
      expect(calc.netSalary, closeTo(2300, 0.01));
    });

    test('السلفةُ الملغاة لا تُحتسب', () async {
      await markPresentFullFebruary();
      final id = await advance(500);
      await db.cancelEmployeeTransaction(id);

      final calc = await calcFebruary();

      expect(calc.totalAdvances, 0);
      expect(calc.netSalary, closeTo(salary, 0.01));
    });

    test('سلفةُ شهرٍ آخر لا تُحتسب في هذا الشهر', () async {
      await markPresentFullFebruary();
      await advance(500, on: DateTime(2026, 3, 1));
      await advance(400, on: DateTime(2026, 1, 31));

      final calc = await calcFebruary();

      expect(calc.totalAdvances, 0,
          reason: 'نافذةُ الشهر [١ فبراير، ١ مارس) — الطرفان خارجها');
      expect(calc.netSalary, closeTo(salary, 0.01));
    });

    test('سلفةُ أولِ يومٍ في الشهر داخلةٌ في النافذة', () async {
      await markPresentFullFebruary();
      await advance(500, on: DateTime(2026, 2, 1));

      final calc = await calcFebruary();

      expect(calc.totalAdvances, closeTo(500, 0.01));
    });
  });

  group('B5 — الخصومات', () {
    test('خصمٌ يُنقص الصافي ولا يمسّ الإجمالي', () async {
      await markPresentFullFebruary();
      await deduction(300);

      final calc = await calcFebruary();

      expect(calc.totalDeductions, closeTo(300, 0.01));
      expect(calc.grossPay, closeTo(salary, 0.01));
      expect(calc.netSalary, closeTo(2500, 0.01));
    });

    test('الخصمُ والسلفةُ دلوان منفصلان لا يختلطان', () async {
      await markPresentFullFebruary();
      await advance(1000);
      await deduction(300);

      final calc = await calcFebruary();

      expect(calc.totalAdvances, closeTo(1000, 0.01));
      expect(calc.totalDeductions, closeTo(300, 0.01));
      expect(calc.netSalary, closeTo(1500, 0.01),
          reason: '2800 − 1000 − 300 — وهذا القيدُ الذي سيتوازن في B3');
    });

    test('الخصمُ الملغى لا يُحتسب', () async {
      await markPresentFullFebruary();
      final id = await deduction(300);
      await db.cancelEmployeeTransaction(id);

      final calc = await calcFebruary();

      expect(calc.totalDeductions, 0);
      expect(calc.netSalary, closeTo(salary, 0.01));
    });
  });

  group('B5 — قصُّ الصافي عند صفر (سلوكٌ قائم، وهو مانعُ B3)', () {
    test('سلفةٌ أكبر من المستحقّ تُصفّر الصافي ولا تُسلِّبه', () async {
      await markPresentFullFebruary();
      await advance(5000);

      final calc = await calcFebruary();

      expect(calc.netSalary, 0, reason: 'القصُّ يمنع صافياً سالباً');
      expect(calc.totalAdvances, closeTo(5000, 0.01),
          reason: 'وهنا الخلل: يُبلِّغ ٥٠٠٠ مسوّاةً والمستحقُّ ٢٨٠٠ فقط — '
              'قيدُ B3 سيختلّ بـ٢٢٠٠ لو مرّر هذا الرقم كما هو');
      expect(calc.grossPay, closeTo(salary, 0.01),
          reason: 'الإجماليُّ لا يُقَصّ — القصُّ على الصافي وحده');
    });

    test('سلفةٌ تساوي المستحقّ تُعطي صفراً بلا قصّ', () async {
      await markPresentFullFebruary();
      await advance(salary);

      final calc = await calcFebruary();

      expect(calc.netSalary, closeTo(0, 0.01));
    });
  });

  group('B5 — الغياب مع السلف', () {
    test('يومان غيابٌ وسلفةٌ: الخصمان مستقلّان', () async {
      for (var d = 1; d <= 26; d++) {
        await db.into(db.employeeAttendance).insert(
              EmployeeAttendanceCompanion.insert(
                employeeId: employeeId,
                date: DateTime(2026, 2, d),
                status: const Value('present'),
              ),
            );
      }
      await advance(500);

      final calc = await calcFebruary();

      expect(calc.daysAttended, 26);
      expect(calc.grossPay, closeTo(2600, 0.01), reason: '١٠٠ × ٢٦');
      expect(calc.netSalary, closeTo(2100, 0.01));
    });
  });
}
