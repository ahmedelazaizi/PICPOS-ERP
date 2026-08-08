// ═══════════════════════════════════════════════════════════════════════════
// B3 — السلف لم تكن تُسوّى محاسبياً: حساب ١١٤٦ يتضخّم للأبد.
// ═══════════════════════════════════════════════════════════════════════════
//
// القيدُ كان سطرين بالصافي:
//     مدين  مصروف الرواتب ٦٢١ = الصافي        ← مُبخَّس بقيمة السلف
//     دائن  النقدية ١١١١      = الصافي
//
// فحسابُ `1146` (سلف الموظفين) **لم يُقيَّد عليه دائنٌ قطّ**: السلفةُ تُدَبَّن
// حين تُصرَف ولا تُدَيَّن حين تُسدَّد، فتظلّ ظاهرةً أصلاً مستحقاً بعد سدادها —
// وتتراكم بلا حدّ. ومصروفُ الرواتب يُبلَّغ أقلَّ من حقيقته بنفس القيمة.
//
// الصحيح ثلاثةُ سطور:
//     مدين  مصروف الرواتب ٦٢١  = المستحقّ (الإجمالي − الجزاءات)
//     دائن  النقدية ١١١١       = الصافي (ما خرج من الخزنة فعلاً)
//     دائن  سلف الموظفين ١١٤٦  = السلفُ المسوّاة
//
// ── قرار المالك (2026-08-08): الجزاءاتُ تُنقص مصروف الرواتب ────────────────
// لا تُقيَّد إيراداً ولا التزاماً. الجزاءُ يعني أنّ الموظف استحقّ أقلَّ، فتكلفةُ
// الأجر انخفضت فعلاً — والقيدُ يتوازن بثلاثةِ سطورٍ بلا تعيينِ حسابٍ جديد.
//
// ── ⚠️ فخٌّ في الكود المفحوص: القيدُ ملفوفٌ في try/catch يبتلع الفشل ──────────
// `catch (e) { debugPrint(...) }` — فقيدٌ غيرُ متوازنٍ يرفضه حارسُ التوازن،
// ويُبتلَع الرفض، ويُصرَف الراتبُ **بلا قيدٍ إطلاقاً** بصمت. فنمطُ العطل هنا
// هو **غيابُ** القيد لا ظهورُ استثناء، ولهذا كلُّ اختبارٍ أدناه يؤكّد على وجودِ
// القيد وسطورِه لا على انعدامِ الاستثناء.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/extensions/hr_extensions.dart';

void main() {
  late AppDatabase db;
  late int employeeId;
  late int safeId;
  late int salaryAccId;
  late int cashAccId;
  late int advanceAccId;

  const salary = 2800.0; // ÷ ٢٨ يوماً في فبراير = ١٠٠ يومياً
  const period = '2026-02';

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

  /// سطورُ قيدِ صرفِ الراتب — مفتاحُها `referenceType` الذي يكتبه الإنتاج.
  Future<List<JournalEntryLine>> salaryEntryLines() async {
    final entries = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals('salary_payment')))
        .get();
    expect(entries.length, 1,
        reason: 'قيدُ الراتب غائبٌ أو مكرَّر — والغيابُ يُبتلَع في catch بصمت');
    return (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(entries.first.id)))
        .get();
  }

  double debitOf(List<JournalEntryLine> lines, int accountId) => lines
      .where((l) => l.accountId == accountId)
      .fold<double>(0, (s, l) => s + l.debit);

  double creditOf(List<JournalEntryLine> lines, int accountId) => lines
      .where((l) => l.accountId == accountId)
      .fold<double>(0, (s, l) => s + l.credit);

  /// صافي حركة حسابٍ عبر **كل** القيود — مدين ناقص دائن.
  Future<double> accountNetBalance(int accountId) async {
    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.accountId.equals(accountId)))
        .get();
    return lines.fold<double>(0, (s, l) => s + l.debit - l.credit);
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    employeeId = await db.into(db.employees).insert(
          EmployeesCompanion.insert(
            name: 'أحمد',
            salary: const Value(salary),
          ),
        );

    // ── تأكيدُ التجهيزة نفسها ──────────────────────────────────────────────
    // المسارُ النقدي والقيدُ كلاهما داخل `if (safe != null)` وداخل فحص
    // `salaryAcc != null && cashAcc != null`. فتجهيزةٌ ناقصةٌ تجعل الاختبار
    // يمرّ على مسارٍ لا يُقيَّد فيه شيء — نجاحٌ كاذب.
    final defaultSafe = await db.getDefaultSafeByType('cash');
    expect(defaultSafe, isNotNull,
        reason: 'بلا خزنة نقدية يُتخطّى مسارُ القيد بالكامل');
    safeId = defaultSafe!.id;
    await (db.update(db.safes)..where((s) => s.id.equals(safeId)))
        .write(const SafesCompanion(balance: Value(50000)));

    final salaryAcc = await db.getAccountByCode('621');
    final cashAcc = await db.getAccountByCode('1111');
    final advanceAcc = await db.getAccountByCode('1146');
    expect(salaryAcc, isNotNull, reason: 'حساب ٦٢١ غير مزروع');
    expect(cashAcc, isNotNull, reason: 'حساب ١١١١ غير مزروع');
    expect(advanceAcc, isNotNull, reason: 'حساب ١١٤٦ غير مزروع');
    salaryAccId = salaryAcc!.id;
    cashAccId = cashAcc!.id;
    advanceAccId = advanceAcc!.id;
  });

  tearDown(() => db.close());

  group('B3 — القيد الثلاثي', () {
    test('سلفةٌ ١٠٠٠ على راتب ٢٨٠٠: ٦٢١ مدين ٢٨٠٠ · ١١١١ دائن ١٨٠٠ · ١١٤٦ دائن ١٠٠٠',
        () async {
      await markPresentFullFebruary();
      await db.recordEmployeeAdvance(
        employeeId: employeeId,
        amount: 1000,
        affectsTreasury: false,
        transactionDate: DateTime(2026, 2, 10),
      );
      final calc = await db.calculateNetSalary(
          employeeId: employeeId, year: 2026, month: 2);

      await db.recordSalaryPayment(
        employeeId: employeeId,
        amount: calc.netSalary,
        period: period,
        payableAmount: calc.payableAmount,
        advancesSettled: calc.advancesSettled,
      );

      final lines = await salaryEntryLines();
      expect(debitOf(lines, salaryAccId), closeTo(2800, 0.01),
          reason: 'المصروفُ كان يُقيَّد بالصافي ١٨٠٠ — مُبخَّساً بقيمة السلفة');
      expect(creditOf(lines, cashAccId), closeTo(1800, 0.01),
          reason: 'النقديةُ بما خرج فعلاً');
      expect(creditOf(lines, advanceAccId), closeTo(1000, 0.01),
          reason: 'هذا السطرُ لم يكن يُكتَب قطّ — ولهذا تضخّم ١١٤٦ للأبد');
    });

    test('القيدُ متوازن — وإلا رفضه الحارسُ وابتلع الرفضَ الـcatch', () async {
      await markPresentFullFebruary();
      await db.recordEmployeeAdvance(
        employeeId: employeeId,
        amount: 1000,
        affectsTreasury: false,
        transactionDate: DateTime(2026, 2, 10),
      );
      final calc = await db.calculateNetSalary(
          employeeId: employeeId, year: 2026, month: 2);

      await db.recordSalaryPayment(
        employeeId: employeeId,
        amount: calc.netSalary,
        period: period,
        payableAmount: calc.payableAmount,
        advancesSettled: calc.advancesSettled,
      );

      final lines = await salaryEntryLines();
      final debit = lines.fold<double>(0, (s, l) => s + l.debit);
      final credit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(debit, closeTo(credit, 0.01));
      expect(debit, closeTo(2800, 0.01));
    });

    test('بلا سلفة: سطران ولا سطرَ ١١٤٦', () async {
      await markPresentFullFebruary();
      final calc = await db.calculateNetSalary(
          employeeId: employeeId, year: 2026, month: 2);

      await db.recordSalaryPayment(
        employeeId: employeeId,
        amount: calc.netSalary,
        period: period,
        payableAmount: calc.payableAmount,
        advancesSettled: calc.advancesSettled,
      );

      final lines = await salaryEntryLines();
      expect(lines.length, 2);
      expect(debitOf(lines, salaryAccId), closeTo(2800, 0.01));
      expect(creditOf(lines, cashAccId), closeTo(2800, 0.01));
      expect(creditOf(lines, advanceAccId), 0,
          reason: 'سطرٌ بصفرٍ يشوّش سجلَّ الحساب بلا فائدة');
    });
  });

  group('B3 — حساب ١١٤٦ يعود إلى الصفر بعد السداد', () {
    test('صرفُ سلفةٍ ثم صرفُ الراتب يُصفّر ١١٤٦', () async {
      await markPresentFullFebruary();

      // سلفةٌ **بأثرٍ محاسبي** — تُدَبِّن ١١٤٦ بـ١٠٠٠ كما في الإنتاج.
      await db.recordEmployeeAdvance(
        employeeId: employeeId,
        amount: 1000,
        transactionDate: DateTime(2026, 2, 10),
      );
      expect(await accountNetBalance(advanceAccId), closeTo(1000, 0.01),
          reason: 'التجهيزة: السلفةُ أصلٌ مستحقٌّ على الموظف');

      final calc = await db.calculateNetSalary(
          employeeId: employeeId, year: 2026, month: 2);
      await db.recordSalaryPayment(
        employeeId: employeeId,
        amount: calc.netSalary,
        period: period,
        payableAmount: calc.payableAmount,
        advancesSettled: calc.advancesSettled,
      );

      expect(await accountNetBalance(advanceAccId), closeTo(0, 0.01),
          reason: 'هذا هو العطلُ بعينه: كان يبقى ١٠٠٠ إلى الأبد بعد السداد');
    });
  });

  group('B3 — الجزاءات تُنقص المصروف (قرار المالك)', () {
    test('جزاءُ ٣٠٠ وسلفةُ ١٠٠٠: ٦٢١ مدين ٢٥٠٠ لا ٢٨٠٠', () async {
      await markPresentFullFebruary();
      await db.recordEmployeeAdvance(
        employeeId: employeeId,
        amount: 1000,
        affectsTreasury: false,
        transactionDate: DateTime(2026, 2, 10),
      );
      await db.recordEmployeeDeduction(
        employeeId: employeeId,
        amount: 300,
        transactionDate: DateTime(2026, 2, 11),
      );
      final calc = await db.calculateNetSalary(
          employeeId: employeeId, year: 2026, month: 2);
      expect(calc.netSalary, closeTo(1500, 0.01), reason: '2800 − 1000 − 300');

      await db.recordSalaryPayment(
        employeeId: employeeId,
        amount: calc.netSalary,
        period: period,
        payableAmount: calc.payableAmount,
        advancesSettled: calc.advancesSettled,
      );

      final lines = await salaryEntryLines();
      expect(debitOf(lines, salaryAccId), closeTo(2500, 0.01),
          reason: 'الجزاءُ يُنقص المصروف — قرار المالك 2026-08-08');
      expect(creditOf(lines, cashAccId), closeTo(1500, 0.01));
      expect(creditOf(lines, advanceAccId), closeTo(1000, 0.01));
      final debit = lines.fold<double>(0, (s, l) => s + l.debit);
      final credit = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(debit, closeTo(credit, 0.01), reason: '٢٥٠٠ = ١٥٠٠ + ١٠٠٠');
    });
  });

  group('B3 — سلفةٌ أكبر من المستحقّ: تُسوّى جزئياً', () {
    test('سلفةُ ٥٠٠٠ على مستحقٍّ ٢٨٠٠ تُسوّي ٢٨٠٠ ويبقى ٢٢٠٠ أصلاً قائماً',
        () async {
      await markPresentFullFebruary();
      await db.recordEmployeeAdvance(
        employeeId: employeeId,
        amount: 5000,
        transactionDate: DateTime(2026, 2, 10),
      );

      final calc = await db.calculateNetSalary(
          employeeId: employeeId, year: 2026, month: 2);
      expect(calc.advancesSettled, closeTo(2800, 0.01),
          reason: 'لا تُسوَّى سلفةٌ أكثر من المستحقّ');
      expect(calc.netSalary, closeTo(0, 0.01));
      expect(calc.totalAdvances, closeTo(5000, 0.01),
          reason: 'المُصرَف ٥٠٠٠ — والمسوَّى منه ٢٨٠٠ فقط');

      await db.recordSalaryPayment(
        employeeId: employeeId,
        amount: calc.netSalary,
        period: period,
        payableAmount: calc.payableAmount,
        advancesSettled: calc.advancesSettled,
      );

      final lines = await salaryEntryLines();
      expect(debitOf(lines, salaryAccId), closeTo(2800, 0.01));
      expect(creditOf(lines, advanceAccId), closeTo(2800, 0.01));
      expect(creditOf(lines, cashAccId), 0,
          reason: 'لم يخرج نقدٌ — فلا سطرَ نقديةٍ بصفر');

      expect(await accountNetBalance(advanceAccId), closeTo(2200, 0.01),
          reason: 'الباقي أصلٌ قائمٌ فعلاً — لا يجوز محقُه ولا تسويتُه');
    });
  });

  group('B3 — حارسُ الثابت قبل أي كتابة', () {
    test('مستحقٌّ لا يساوي الصافي + المسوّى يُرفَض صراحةً', () async {
      await expectLater(
        db.recordSalaryPayment(
          employeeId: employeeId,
          amount: 1800,
          period: period,
          payableAmount: 2800,
          advancesSettled: 500, // ‏1800 + 500 ≠ 2800
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('الرفضُ لا يترك صفَّ راتبٍ ولا حركةَ خزنة', () async {
      final safeBefore = (await (db.select(db.safes)
                ..where((s) => s.id.equals(safeId)))
              .getSingle())
          .balance;

      await expectLater(
        db.recordSalaryPayment(
          employeeId: employeeId,
          amount: 1800,
          period: period,
          payableAmount: 2800,
          advancesSettled: 500,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(await db.select(db.salaryPayments).get(), isEmpty,
          reason: 'الحارسُ قبل الكتابة لا بعدها');
      final safeAfter = (await (db.select(db.safes)
                ..where((s) => s.id.equals(safeId)))
              .getSingle())
          .balance;
      expect(safeAfter, safeBefore);
    });
  });

  group('B3 — المسارُ القديم ما زال يعمل (المكافآت وما شابه)', () {
    test('بلا المعاملين الجديدين: سطران بالمبلغ نفسه', () async {
      await db.recordSalaryPayment(
        employeeId: employeeId,
        amount: 500,
        period: period,
        type: 'bonus',
      );

      final entries = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('salary_payment')))
          .get();
      expect(entries.length, 1);
      final lines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(entries.first.id)))
          .get();
      expect(lines.length, 2);
      expect(debitOf(lines, salaryAccId), closeTo(500, 0.01));
      expect(creditOf(lines, cashAccId), closeTo(500, 0.01));
      expect(creditOf(lines, advanceAccId), 0,
          reason: 'المكافأةُ لا تُسوّي سلفةً — لا سطرَ ١١٤٦');
    });
  });
}
