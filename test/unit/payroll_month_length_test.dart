// ═══════════════════════════════════════════════════════════════════════════
// H1 — الأجر اليومي كان مقسوماً على ٣٠ ثابتة.
// ═══════════════════════════════════════════════════════════════════════════
//
// موضعان كانا يقسمان على ٣٠، لا موضع واحد:
//   • calculateNetSalary  → dailyRate  = salary / 30
//   • addOvertimeRecord   → hourlyRate = salary / 30 / 8
//
// فالثابت الذي كان مكسوراً: **شهرٌ كامل الحضور لا يُعطي الراتب**. فبراير
// (٢٨ يوماً) كان يُعطي `salary/30*28` = ٩٣٫٣٣٪ — خصمُ ٦٫٦٧٪ على موظف لم يغب
// يوماً. ويناير (٣١) كان يُعطي `salary/30*31` = ١٠٣٫٣٣٪ — أكثر من راتبه.
//
// كل اختبار هنا يثبّت أعداد الأيام **حرفياً** (٢٨ · ٣١ · ٢٩) لا محسوبةً بنفس
// معادلة الإصلاح، حتى لا يصير الاختبار مرآةً للكود الذي يفحصه.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/extensions/hr_extensions.dart';

void main() {
  late AppDatabase db;
  late int employeeId;

  const salary = 3000.0;

  /// يسجّل حضوراً لأول [dayCount] يوماً من الشهر.
  ///
  /// [dayCount] يُمرَّر حرفياً من الاختبار (٢٨ لفبراير ٢٠٢٦ … إلخ) بدلاً من
  /// حسابه، لأن حسابه هنا يعني استعمال معادلة الإصلاح للتحقّق من الإصلاح.
  Future<void> markPresent(int year, int month, int dayCount) async {
    for (var d = 1; d <= dayCount; d++) {
      await db.into(db.employeeAttendance).insert(
            EmployeeAttendanceCompanion.insert(
              employeeId: employeeId,
              date: DateTime(year, month, d),
              status: const Value('present'),
            ),
          );
    }
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    // ‏`salaryType` **صريحٌ** لا افتراضيّ: افتراضُ السكيما `monthly`، والموديلُ
    // الشهري (قرار المالك 2026-08-09) يدفع الراتبَ كاملاً ما لم يُسجَّل غيابٌ
    // — فيصير الإجماليُّ مستقلاً عن أيام الحضور وتمرّ تأكيداتُ هذا الملف
    // **لسببٍ مختلف** عمّا تدّعيه. وهذا الملفُّ عن مقامِ الأجر اليومي، فمساره
    // هو التراكمُ اليومي. الموديلُ الشهري له `monthly_salary_model_test.dart`.
    employeeId = await db.into(db.employees).insert(
          EmployeesCompanion.insert(
            name: 'أحمد',
            salary: const Value(salary),
            salaryType: const Value('daily'),
          ),
        );
  });

  tearDown(() => db.close());

  group('H1 — شهرٌ كامل الحضور يساوي الراتب، أيّ شهر كان', () {
    test('فبراير ٢٠٢٦ — ٢٨ يوماً حضوراً = الراتب بالضبط', () async {
      await markPresent(2026, 2, 28);

      final calc = await db.calculateNetSalary(
        employeeId: employeeId,
        year: 2026,
        month: 2,
      );

      expect(calc.daysAttended, 28, reason: 'التجهيزة نفسها لم تصل');
      expect(calc.grossPay, closeTo(salary, 0.01),
          reason: 'القسمة على ٣٠ تُعطي 2800 — خصم ٦٫٦٧٪ على شهر كامل الحضور');
      expect(calc.netSalary, closeTo(salary, 0.01));
    });

    test('يناير ٢٠٢٦ — ٣١ يوماً حضوراً = الراتب، لا أكثر', () async {
      await markPresent(2026, 1, 31);

      final calc = await db.calculateNetSalary(
        employeeId: employeeId,
        year: 2026,
        month: 1,
      );

      expect(calc.daysAttended, 31, reason: 'التجهيزة نفسها لم تصل');
      expect(calc.grossPay, closeTo(salary, 0.01),
          reason: 'القسمة على ٣٠ تُعطي 3100 — أكثر من الراتب');
    });

    test('ديسمبر ٢٠٢٦ — الشهر ١٢ لا يلتفّ خطأً (٣١ يوماً)', () async {
      await markPresent(2026, 12, 31);

      final calc = await db.calculateNetSalary(
        employeeId: employeeId,
        year: 2026,
        month: 12,
      );

      expect(calc.daysAttended, 31);
      expect(calc.grossPay, closeTo(salary, 0.01),
          reason: 'حساب آخر يوم في ديسمبر يمرّ بالشهر ١٣ — لا بد أن يُطبَّع');
    });

    test('فبراير ٢٠٢٨ الكبيسة — ٢٩ يوماً حضوراً = الراتب', () async {
      await markPresent(2028, 2, 29);

      final calc = await db.calculateNetSalary(
        employeeId: employeeId,
        year: 2028,
        month: 2,
      );

      expect(calc.daysAttended, 29);
      expect(calc.grossPay, closeTo(salary, 0.01));
    });
  });

  group('H1 — الأجر اليومي مشتقّ من أيام الشهر الحقيقية', () {
    test('فبراير: الأجر اليومي = الراتب ÷ ٢٨', () async {
      await markPresent(2026, 2, 1);

      final calc = await db.calculateNetSalary(
        employeeId: employeeId,
        year: 2026,
        month: 2,
      );

      expect(calc.dailyRate, closeTo(salary / 28, 0.0001));
    });

    test('يناير: الأجر اليومي = الراتب ÷ ٣١', () async {
      await markPresent(2026, 1, 1);

      final calc = await db.calculateNetSalary(
        employeeId: employeeId,
        year: 2026,
        month: 1,
      );

      expect(calc.dailyRate, closeTo(salary / 31, 0.0001));
    });

    test('يوم غياب واحد في فبراير يخصم ١/٢٨ لا ١/٣٠', () async {
      await markPresent(2026, 2, 27);

      final calc = await db.calculateNetSalary(
        employeeId: employeeId,
        year: 2026,
        month: 2,
      );

      expect(calc.daysAttended, 27);
      expect(calc.grossPay, closeTo(salary - salary / 28, 0.01));
    });
  });

  group('H1 — الأجر بالساعة للوقت الإضافي', () {
    test('ساعة إضافية في فبراير تُحسب على ٢٨ يوماً لا ٣٠', () async {
      // ساعتان بمعامل ١٫٥ في فبراير ٢٠٢٦.
      // الصحيح : 2 × (3000 ÷ 28 ÷ 8) × 1.5 = 40.1786
      // القديم : 2 × (3000 ÷ 30 ÷ 8) × 1.5 = 37.5
      await db.addOvertimeRecord(
        employeeId: employeeId,
        date: DateTime(2026, 2, 10),
        hours: 2,
        rate: 1.5,
      );

      final total = await db.getMonthlyOvertimeAmount(employeeId, 2026, 2);

      expect(total, closeTo(2 * (salary / 28 / 8) * 1.5, 0.01));
    });

    test('نفس الساعات في يناير أقلّ — الشهر أطول فاليوم أرخص', () async {
      await db.addOvertimeRecord(
        employeeId: employeeId,
        date: DateTime(2026, 1, 10),
        hours: 2,
        rate: 1.5,
      );

      final total = await db.getMonthlyOvertimeAmount(employeeId, 2026, 1);

      expect(total, closeTo(2 * (salary / 31 / 8) * 1.5, 0.01));
    });
  });
}
