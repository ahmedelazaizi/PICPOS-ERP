// ═══════════════════════════════════════════════════════════════════════════
// موانعُ Go — الدفعةُ ٤: وحدةُ الأجور بمقامٍ واحدٍ صحيح
// ═══════════════════════════════════════════════════════════════════════════
//
// أربعةُ عيوبٍ مستقلّةٍ على مسارٍ مشحون، تُصلَح معاً لأنّها تتشارك المقامَ
// والقسيمة:
//
//   ٢‑١  الأجرُ اليوميُّ يُقسَم على أيّام **التقويم** بينما البسطُ أيّامُ عمل.
//   ٢‑٢  الخصمُ الشهريُّ بنفس المقام الخاطئ.
//   ٢‑٣  ورديّةٌ تعبر منتصفَ الليل تُنتج **صفّين** — دفعٌ مضاعفٌ أو صفر.
//   ٢‑٤  الصرفُ يكتب صفّاً «مدفوع» بلا حركةِ خزنةٍ ولا قيد، صامتاً وبلا إعادة.
//
// ⚠️ **التجهيزةُ تُؤكَّد أوّلاً.** بلا عطلةٍ مسجَّلةٍ يتساوى المقامان
// (‏أيّامُ التقويم = أيّامُ العمل) فتمرّ كلُّ التوكيدات أدناه **لسببٍ خاطئ**.
// ولهذا يُثبَّت أنّ أغسطس ٢٠٢٦ فيه ٢٧ يومَ عملٍ قبل أيِّ توكيدٍ آخر.
//
// وكلُّ رقمٍ متوقَّعٍ مكتوبٌ **حرفيّاً** (٢٧ · ١١١٫١١١١) لا محسوباً بـ
// `workingDaysInMonth`، وإلّا صار الاختبارُ مرآةً للكود الذي يفحصه.
//
// أغسطس ٢٠٢٦: ٣١ يوماً، والجُمَعُ فيه ٤ (‏٧ · ١٤ · ٢١ · ٢٨) ⇒ ٢٧ يومَ عمل.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/extensions/hr_extensions.dart';

void main() {
  late AppDatabase db;

  const salary = 3000.0;
  const augustCalendarDays = 31;
  const augustWorkingDays = 27; // ٣١ − ٤ جُمَع
  const correctDailyRate = salary / augustWorkingDays; // ١١١٫١١١١
  const brokenDailyRate = salary / augustCalendarDays; // ٩٦٫٧٧٤ — ما كان

  /// أيّامُ أغسطس ٢٠٢٦ التي ليست جمعة.
  final workdays = <int>[
    for (var d = 1; d <= augustCalendarDays; d++)
      if (DateTime(2026, 8, d).weekday != DateTime.friday) d,
  ];

  Future<int> newEmployee(String type, {double? hoursPerDay}) =>
      db.into(db.employees).insert(
            EmployeesCompanion.insert(
              name: 'موظف $type',
              salary: const Value(salary),
              salaryType: Value(type),
              hoursPerDay: Value(hoursPerDay ?? 8),
            ),
          );

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    // الجمعةُ عطلةٌ أسبوعيّةٌ على مستوى المنشأة.
    await db.addWorkHoliday(
      name: 'الجمعة',
      weekday: DateTime.friday,
      date: null,
      branchId: null,
    );
  });

  tearDown(() => db.close());

  test('التجهيزةُ نفسُها: أغسطس ٢٠٢٦ = ٢٧ يومَ عمل', () async {
    expect(workdays.length, augustWorkingDays,
        reason: 'حسابُ الاختبار نفسِه');
    expect(await db.workingDaysInMonth(2026, 8, branchId: null),
        augustWorkingDays,
        reason: 'العطلةُ سُجِّلت فعلاً — بدونها يتساوى المقامان وتمرّ كلُّ '
            'التوكيدات لسببٍ خاطئ');
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('٢‑١ — المقامُ أيّامُ عمل، لا أيّامُ تقويم', () {
    test('حضورٌ كاملٌ (٢٧ يوماً) يُعطي الراتبَ كاملاً', () async {
      final id = await newEmployee('daily');
      for (final d in workdays) {
        await db.into(db.employeeAttendance).insert(
              EmployeeAttendanceCompanion.insert(
                employeeId: id,
                date: DateTime(2026, 8, d),
                status: const Value('present'),
              ),
            );
      }

      final calc =
          await db.calculateNetSalary(employeeId: id, year: 2026, month: 8);

      expect(calc.daysAttended, augustWorkingDays);
      // 🔴 المعطوب: ٣٠٠٠ ÷ ٣١ = ٩٦٫٧٧٤
      expect(calc.dailyRate, closeTo(correctDailyRate, 0.0001));
      expect(calc.dailyRate, isNot(closeTo(brokenDailyRate, 0.01)),
          reason: 'المقامُ التقويميُّ لا يعود');
      // 🔴 المعطوب: ٢٦١٢٫٩٠ — نقصُ ١٢٫٩٪ بلا غيابٍ واحد
      expect(calc.grossPay, closeTo(salary, 0.01),
          reason: 'شهرٌ كاملُ الحضور = الراتبُ كاملاً');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('٢‑٢ — الخصمُ الشهريُّ بنفس المقام الصحيح', () {
    test('غيابُ الشهر كلِّه على الشهريِّ يُعطي صفراً لا ٣٨٧٫١٠', () async {
      final id = await newEmployee(kMonthlySalaryType);
      for (final d in workdays) {
        await db.markEmployeeAbsent(id, DateTime(2026, 8, d));
      }

      final calc =
          await db.calculateNetSalary(employeeId: id, year: 2026, month: 8);

      expect(calc.unpaidDays, augustWorkingDays);
      // 🔴 المعطوب: ٣٠٠٠ − ٩٦٫٧٧٤×٢٧ = ٣٨٧٫١٠ لموظفٍ لم يحضر يوماً
      expect(calc.payableAmount, closeTo(0.0, 0.01));
    });

    test('يومُ غيابٍ واحدٍ يخصم ١١١٫١١ لا ٩٦٫٧٧', () async {
      final id = await newEmployee(kMonthlySalaryType);
      await db.markEmployeeAbsent(id, DateTime(2026, 8, 3)); // الاثنين

      final calc =
          await db.calculateNetSalary(employeeId: id, year: 2026, month: 8);

      expect(calc.unpaidDays, 1);
      expect(calc.payableAmount, closeTo(salary - correctDailyRate, 0.01));
    });

    test('غيابٌ مسجَّلٌ يومَ عطلةٍ لا يُخصَم', () async {
      final id = await newEmployee(kMonthlySalaryType);
      await db.markEmployeeAbsent(id, DateTime(2026, 8, 7)); // جمعة

      final calc =
          await db.calculateNetSalary(employeeId: id, year: 2026, month: 8);

      expect(calc.unpaidDays, 0);
      expect(calc.payableAmount, closeTo(salary, 0.01));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('٢‑٣ — ورديّةٌ تعبر منتصفَ الليل = صفٌّ واحد', () {
    Future<List<EmployeeAttendanceData>> rowsOf(int id) =>
        (db.select(db.employeeAttendance)
              ..where((a) => a.employeeId.equals(id)))
            .get();

    test('٢٢:٠٠ ← ٠٦:٠٠ ⇒ صفٌّ واحدٌ ويومٌ واحدٌ وثماني ساعات', () async {
      final id = await newEmployee('daily');
      await db.importDeviceCheckIn(id, DateTime(2026, 8, 3, 22));
      await db.importDeviceCheckOut(id, DateTime(2026, 8, 4, 6));

      // 🔴 المعطوب: صفّان — كلٌّ على يومه التقويميّ
      expect(await rowsOf(id), hasLength(1));

      final calc =
          await db.calculateNetSalary(employeeId: id, year: 2026, month: 8);
      // 🔴 المعطوب: `daysAttended = 2` ⇒ يُدفَع مرّتين لوردية
      expect(calc.daysAttended, 1);
      // 🔴 المعطوب: `hoursWorked = 0` — كلا الصفّين نصفُ بصمة
      expect(calc.hoursWorked, closeTo(8.0, 0.01));
      expect(calc.grossPay, closeTo(correctDailyRate, 0.01));
    });

    test('الأجرُ بالساعة على نفس الورديّة لا يساوي صفراً', () async {
      final id = await newEmployee(kHourlySalaryType);
      await db.importDeviceCheckIn(id, DateTime(2026, 8, 3, 22));
      await db.importDeviceCheckOut(id, DateTime(2026, 8, 4, 6));

      final calc =
          await db.calculateNetSalary(employeeId: id, year: 2026, month: 8);
      // 🔴 المعطوب: صفرٌ — و`payroll_tab` يُعطّل زرَّ الصرف على صافٍ ≤ صفر،
      //    فالموظفُ لا يمكن دفعُه أصلاً من الواجهة.
      expect(calc.hoursWorked, closeTo(8.0, 0.01));
      expect(calc.netSalary, greaterThan(0));
      expect(calc.netSalary, closeTo(8 * (salary / (8 * 27)), 0.01));
    });

    test('عشرُ ليالٍ متتالية: لا ساعاتٍ سالبة، ولا يومٌ زائد', () async {
      final id = await newEmployee(kHourlySalaryType);
      // ٣ ← ١٣ أغسطس، مع تخطّي الجمعة ٧ (‏الورديّةُ لا تبدأ في عطلة).
      for (final d in [3, 4, 5, 6, 8, 9, 10, 11, 12, 13]) {
        await db.importDeviceCheckIn(id, DateTime(2026, 8, d, 22));
        await db.importDeviceCheckOut(id, DateTime(2026, 8, d + 1, 6));
      }

      final calc =
          await db.calculateNetSalary(employeeId: id, year: 2026, month: 8);
      // 🔴 المعطوب: ١٩ صفّاً بتحضيرٍ وانصرافٍ على نفس اليوم بفارقٍ −١٦
      //    ⇒ ساعاتٌ سالبةٌ بالجملة، وصافٍ يُقصَر إلى صفر.
      expect(calc.hoursWorked, greaterThanOrEqualTo(0),
          reason: 'لا ساعاتٍ سالبة');
      expect(calc.hoursWorked, closeTo(80.0, 0.01),
          reason: 'عشرُ ورديّاتٍ × ٨ ساعات');
      expect(calc.daysAttended, 10, reason: '🔴 المعطوب: ١١ (‏ن+١)');
    });

    test('انصرافٌ بعد نافذةِ الورديّة يبقى صفّاً مستقلّاً', () async {
      // بصمةُ انصرافٍ ضاع تحضيرُها: ٤٨ ساعةً بعد التحضير ليست ورديّة.
      final id = await newEmployee('daily');
      await db.importDeviceCheckIn(id, DateTime(2026, 8, 3, 22));
      await db.importDeviceCheckOut(id, DateTime(2026, 8, 5, 22));

      final rows = await rowsOf(id);
      expect(rows, hasLength(2),
          reason: 'الضمُّ محدودٌ بنافذةِ ورديّةٍ معقولة — لا يلصق يومَين '
              'لا علاقةَ بينهما');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('#١٠ — إجازةٌ تعبر عطلةً لا تُضخّم الراتب', () {
    test('إجازةُ ٧ أيّامٍ تشمل جمعةً ⇒ ٦ أيّامٍ مدفوعةٍ لا ٧', () async {
      final id = await newEmployee('daily');
      // ٣ ← ٩ أغسطس، وفيها الجمعةُ ٧.
      final leaveId = await db.requestLeave(
        employeeId: id,
        leaveType: 'annual',
        startDate: DateTime(2026, 8, 3),
        endDate: DateTime(2026, 8, 9),
        days: 7,
      );
      await db.updateLeaveStatus(leaveId, 'approved', 1);

      final calc =
          await db.calculateNetSalary(employeeId: id, year: 2026, month: 8);

      // 🔴 لو رُشِّح المقامُ ولم يُرشَّح البسط: ٧ أيّامٍ × ١١١٫١١ ⇒ الراتبُ
      //    يزيد بيومٍ لم يكن يومَ عمل. والطرفان الآن متماثلان.
      expect(calc.daysAttended, 6,
          reason: '`_writeLeaveAttendance` تكتب صفّاً لكلِّ يومٍ تقويميّ '
              'شاملاً الجمعة — والبسطُ يرشّحها كما يرشّحها المقام');
      expect(calc.grossPay, closeTo(6 * correctDailyRate, 0.01));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('٢‑٤ — الصرفُ يفشل صريحاً ويبقى قابلاً للإعادة', () {
    Future<int> journalCount() async => (await (db.select(db.journalEntries)
              ..where((e) => e.referenceType.equals('salary_payment')))
            .get())
        .length;

    test('بلا خزنةٍ نقديّةٍ نشِطة: يرمي، ولا يترك صفّاً، والإعادةُ تنجح',
        () async {
      final id = await newEmployee(kMonthlySalaryType);
      final safe = await db.getDefaultSafeByType('cash');
      expect(safe, isNotNull, reason: 'شرطٌ مسبق');

      // تعطيلُ كلِّ الخزائن النقديّة.
      await (db.update(db.safes)..where((s) => s.safeType.equals('cash')))
          .write(const SafesCompanion(isActive: Value(false)));

      // 🔴 المعطوب: يُرجع مُعرِّفاً — «مدفوع» في الرواتب وصفرٌ في الأستاذ.
      await expectLater(
        db.recordSalaryPayment(
            employeeId: id, amount: salary, period: '2026-08'),
        throwsA(isA<StateError>()),
      );
      expect(await db.select(db.salaryPayments).get(), isEmpty,
          reason: 'المعاملةُ تُرجِع صفَّ الراتب — وإلّا صار الفهرسُ الفريدُ '
              'يمنع الإعادةَ إلى الأبد');
      expect(await journalCount(), 0);

      // الإعادةُ بعد إصلاح السبب — وهي بيتُ القصيد: العطلُ القديم كان
      // يُقفل الفترةَ على الخطأ بلا مسارِ إلغاءٍ في المستودع كلِّه.
      await (db.update(db.safes)..where((s) => s.id.equals(safe!.id)))
          .write(const SafesCompanion(isActive: Value(true)));
      final paymentId = await db.recordSalaryPayment(
          employeeId: id, amount: salary, period: '2026-08');
      expect(paymentId, greaterThan(0));
    });

    test('الصرفُ الناجح يحرّك الخزنةَ والأستاذَ بنفس الرقم', () async {
      final id = await newEmployee(kMonthlySalaryType);
      final safe = await db.getDefaultSafeByType('cash');
      final opening = safe!.balance;

      await db.recordSalaryPayment(
          employeeId: id, amount: salary, period: '2026-08');

      final after = await db.getSafeById(safe.id);
      expect(after!.balance, closeTo(opening - salary, 0.01),
          reason: 'النقدُ خرج فعلاً');

      final entries = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('salary_payment')))
          .get();
      expect(entries, hasLength(1), reason: 'قيدٌ واحدٌ لا صفر');

      final lines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(entries.single.id)))
          .get();
      final debits = lines.fold<double>(0, (s, l) => s + l.debit);
      final credits = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(debits, closeTo(credits, 0.01), reason: 'القيدُ متوازن');
      expect(debits, closeTo(salary, 0.01));
      // الرباطُ الذي يمنع «نقصٌ في الخزنة وصفرٌ في الأستاذ».
      expect(credits, closeTo(opening - after.balance, 0.01),
          reason: 'الأستاذُ والخزنةُ يتحرّكان بنفس الرقم');
    });

    test('حسابُ مصروف الرواتب مفقود: يرمي، والخزنةُ لا تتحرّك', () async {
      final id = await newEmployee(kMonthlySalaryType);
      final safe = await db.getDefaultSafeByType('cash');
      final opening = safe!.balance;

      // ⚠️ **إعادةُ ترميزٍ لا حذف.** `DELETE FROM accounts` يسقط بـ
      // `FOREIGN KEY constraint failed` — `safes.linkedAccountId` وغيرُها
      // تشدُّ الدليل (‏وهو عينُ ما أسقط ٤٦ اختباراً في جلسةٍ سابقة).
      // والمقصودُ محاكاةُ محاسبٍ أعاد هيكلةَ الشجرة، وهي بالضبط إعادةُ ترميز.
      //
      // ويُزال معها ربطُ الغرض: `getMappedAccountCode` تحلّ الغرضَ أوّلاً
      // (`account_mappings`) وتُرجع كودَ الحسابِ **الحاليّ**، فإعادةُ الترميز
      // وحدَها كانت تُنتج كوداً جديداً ما زال يُحلّ — ويمرُّ الاختبارُ لسببٍ
      // خاطئ. بإزالة الربط تسقط الدالّةُ إلى الكود الافتراضيّ `621` الذي لم
      // يعد له حساب.
      const defaultSalaryCode = '621';
      await (db.delete(db.accountMappings)
            ..where((m) => m.purpose.equals('salary_expense')))
          .go();
      await (db.update(db.accounts)
            ..where((a) => a.code.equals(defaultSalaryCode)))
          .write(const AccountsCompanion(code: Value('9XXX-moved')));

      final resolved = await db.getMappedAccountCode(
          'salary_expense', AccountingDao.accountPurposes['salary_expense']!);
      expect(resolved, defaultSalaryCode,
          reason: 'شرطٌ مسبق: الحلُّ يسقط إلى الكود الافتراضيّ');
      expect(await db.getAccountByCode(resolved), isNull,
          reason: 'شرطٌ مسبق: الكودُ المرتقَبُ لم يعد يُحلّ إلى حساب');

      // 🔴 المعطوب: `if (salaryAcc != null && cashAcc != null)` بلا `else`
      //    ⇒ ينجح صامتاً بعد أن خرج النقدُ بالفعل.
      await expectLater(
        db.recordSalaryPayment(
            employeeId: id, amount: salary, period: '2026-08'),
        throwsA(anything),
      );
      final after = await db.getSafeById(safe.id);
      expect(after!.balance, closeTo(opening, 0.01),
          reason: '🔴 المعطوب: خرجت نقديّةٌ بلا قيد');
      expect(await journalCount(), 0);
      expect(await db.select(db.salaryPayments).get(), isEmpty);
    });
  });
}
