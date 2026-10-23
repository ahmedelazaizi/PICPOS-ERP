// إقفال السنة المالية كان بيضاعف **كل** حسابات الميزانية.
//
// ── العطل ────────────────────────────────────────────────────────────────────
// `closeFiscalYear` بيعمل قيد إقفال (سليم ومتوازن)، وبعديه بيعمل **قيد أرصدة
// افتتاحية** بيمدين/يدائن كل حساب ميزانية برصيده التراكمي كما في `fy.endDate`.
//
// بس الأستاذ في النظام ده **مستمر ومش بيتقفل**: `getBalanceSheet` بتجمّع
// `entry_date <= ?` من بداية التاريخ، ومفيش أي تقرير بيستثني
// `reference_type = 'opening_balance'`. فالقيد الافتتاحي **بيتضاف فوق**
// الأرصدة الموجودة أصلاً.
//
// ── ليه ما اتكشفش قبل كده ───────────────────────────────────────────────────
// الميزانية بتفضل **«متوازنة»** لأن الطرفين اتضاعفوا مع بعض. فأي فحص على
// `isBalanced` بيعدّي. الحارس الوحيد اللي بيمسك ده هو مقارنة الإجمالي
// **قبل وبعد** الإقفال — وده اللي الاختبار ده بيعمله.
//
// ── الحل: حذف القيد الافتتاحي ───────────────────────────────────────────────
// في أستاذ مستمر مفيش داعي لقيد افتتاحي أصلاً — الأرصدة بتترحّل تلقائياً
// لأن كل التجميعات تراكمية من بداية التاريخ. البديل (الاحتفاظ بالقيد
// واستثناؤه من كل تقرير تراكمي) بيتطلب تعديل `getBalanceSheet` و
// `getTrialBalance` و`getIncomeStatement` وأي تقرير جاي — وأول واحد يتنسي
// بيرجّع الباج.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;
  late int fyId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    fyId = await db.into(db.fiscalYears).insert(FiscalYearsCompanion(
          name: const Value('2026'),
          startDate: Value(DateTime(2026, 1, 1)),
          endDate: Value(DateTime(2026, 12, 31)),
          isCurrent: const Value(true),
          isClosed: const Value(false),
        ));
  });

  tearDown(() => db.close());

  /// `closeFiscalYear` بيرفض لو فيه فترة شهرية مفتوحة — بوابة سليمة، فالإعداد
  /// بيقفل الشهور قبل ما يقفل السنة زي المسار الحقيقي.
  Future<void> closeYear() async {
    await db.generatePeriodsForYear(
        fyId, DateTime(2026, 1, 1), DateTime(2026, 12, 31));
    // الحارس بيفلتر بـ`year` مش `fiscal_year_id` (accounting_fiscal_dao:105).
    await db.customStatement(
        'UPDATE accounting_periods SET is_closed = 1 WHERE year = 2026');
    await db.closeFiscalYear(fyId, 1);
  }

  Future<void> post(String debitCode, String creditCode, double amount,
      DateTime at) async {
    final dr = await db.getAccountByCode(debitCode);
    final cr = await db.getAccountByCode(creditCode);
    await db.createJournalEntry(
      description: 'test',
      date: at,
      lines: [
        JournalLine(accountId: dr!.id, debit: amount),
        JournalLine(accountId: cr!.id, credit: amount),
      ],
    );
  }

  test('الميزانية بعد الإقفال زي ما هي قبله — مفيش مضاعفة', () async {
    // رأس مال ١٠٠٠ نقدي، ثم شراء مخزون ٤٠٠، ثم بيع ٦٠٠ بتكلفة ٤٠٠.
    await post('1111', '311', 1000, DateTime(2026, 1, 5));
    await post('1136', '1111', 400, DateTime(2026, 2, 5));
    await post('1111', '4121', 600, DateTime(2026, 6, 15));
    await post('5211', '1136', 400, DateTime(2026, 6, 15));

    final before = await db.getBalanceSheet(DateTime(2026, 12, 31));
    final assetsBefore = before['totalAssets'] as double;
    final equityBefore = before['totalEquity'] as double;
    expect(assetsBefore, 1200, reason: 'نقدية 1200 + مخزون 0');

    await closeYear();

    final after = await db.getBalanceSheet(DateTime(2027, 2, 1));
    expect(after['totalAssets'] as double, closeTo(assetsBefore, 0.01),
        reason: 'الأصول اتضاعفت — القيد الافتتاحي اتضاف فوق أستاذ مستمر');
    expect(after['totalEquity'] as double, closeTo(equityBefore, 0.01));
  });

  test('النقدية بالذات ما اتضاعفتش', () async {
    await post('1111', '311', 1000, DateTime(2026, 1, 5));

    await closeYear();

    final cash = await db.getAccountByCode('1111');
    final rows = await db.customSelect(
      'SELECT COALESCE(SUM(l.debit - l.credit), 0) AS bal '
      'FROM journal_entry_lines l JOIN journal_entries e ON e.id = l.entry_id '
      'WHERE l.account_id = ? AND e.is_posted = 1',
      variables: [Variable<int>(cash!.id)],
    ).getSingle();
    expect(rows.data['bal'] as double, closeTo(1000, 0.01),
        reason: 'النقدية الحقيقية 1000 — أي رقم أكبر معناه قيد افتتاحي مكرَّر');
  });

  test('السنة اتقفلت فعلاً والسنة الجاية اتعملت', () async {
    await post('1111', '311', 1000, DateTime(2026, 1, 5));
    await closeYear();

    final closed = await (db.select(db.fiscalYears)
          ..where((f) => f.id.equals(fyId)))
        .getSingle();
    expect(closed.isClosed, isTrue);

    final years = await db.select(db.fiscalYears).get();
    expect(years.any((y) => y.startDate.year == 2027), isTrue,
        reason: 'الإقفال لازم يفتح السنة الجاية');
  });

  test('قيد إقفال النتيجة لسه بيتعمل — مش كل حاجة اتشالت', () async {
    // الإيراد والمصروف لازم يتقفلوا في الأرباح المبقاة. ده الجزء الصح من
    // `closeFiscalYear` واللي ما اتلمسش.
    await post('1111', '4121', 600, DateTime(2026, 6, 15));
    await closeYear();

    final closingJe = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals('fiscal_close')))
        .get();
    expect(closingJe, isNotEmpty, reason: 'قيد إقفال النتيجة لازم يفضل');
  });

  test('مفيش قيد أرصدة افتتاحية اتكتب', () async {
    await post('1111', '311', 1000, DateTime(2026, 1, 5));
    await closeYear();

    final opening = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals('opening_balance')))
        .get();
    expect(opening, isEmpty,
        reason: 'في أستاذ مستمر الأرصدة بتترحّل لوحدها');
  });
}
