// المستودعُ كان يكشف ٣ دوالَّ من ١٠ — فالاستيرادُ والمطابقةُ والتقريرُ
// محجوبةٌ عن كلّ شاشة. وهذا يقيس **الوصولَ** لا المنطق: المنطقُ مختبَرٌ في
// `bank_reconciliation_posted_and_match_test`.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;
  late DriftAccountingRepository repo;
  late int bankId;
  late int cashId;

  // ⚠️ الرمزُ '1110' غيرُ مبذورٍ (المبذورُ '111' ثمّ '1111'-'1116')؛
  //    فـ`getAccountByCode('1110')!` كانت ترمي في `setUp`. انظر النظيرَ
  //    `bank_reconciliation_posted_and_match_test.dart` سطر ٤١.
  Future<int> account(String code, String name, {int? parentId}) async {
    final existing = await db.getAccountByCode(code);
    if (existing != null) return existing.id;
    return db.createAccount(
        code: code, name: name, accountType: 'asset', parentId: parentId);
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = DriftAccountingRepository(db);
    cashId = await account('1110', 'النقدية');
    bankId = await account('1120', 'البنك');
  });

  tearDown(() => db.close());

  test('مرساة: المستودعُ يبني على نفس القاعدة', () async {
    expect(await repo.getReconciliationSessions(), isEmpty);
  });

  test('🔴 الاستيرادُ يصل المحرّكَ عبر المستودع', () async {
    final n = await repo.importBankStatementLines(
      bankAccountId: bankId,
      batchId: 'B-1',
      lines: [
        {
          'date': DateTime(2026, 5, 10),
          'reference': 'R1',
          'description': 'إيداع',
          'debit': 0.0,
          'credit': 500.0,
          'balance': 500.0,
        }
      ],
    );

    expect(n, 1);
    expect(await repo.getUnmatchedStatementLines(bankId), hasLength(1));
  });

  test('🔴 المطابقةُ الآليّةُ تصل المحرّكَ عبر المستودع', () async {
    await db.createJournalEntry(
      description: 'إيداع',
      date: DateTime(2026, 5, 10),
      lines: [
        JournalLine(accountId: bankId, debit: 500),
        JournalLine(accountId: cashId, credit: 500),
      ],
    );
    await repo.importBankStatementLines(
      bankAccountId: bankId,
      batchId: 'B-2',
      lines: [
        {
          'date': DateTime(2026, 5, 11),
          'reference': 'R2',
          'description': 'إيداع',
          'debit': 0.0,
          'credit': 500.0,
          'balance': 500.0,
        }
      ],
    );

    expect(await repo.autoMatchStatementLines(bankId), 1);
    expect(await repo.getUnmatchedStatementLines(bankId), isEmpty);
  });

  test('🔴 اليدويّةُ والنزعُ والتقريرُ تصل كلُّها', () async {
    await db.createJournalEntry(
      description: 'إيداع',
      date: DateTime(2026, 5, 10),
      lines: [
        JournalLine(accountId: bankId, debit: 900),
        JournalLine(accountId: cashId, credit: 900),
      ],
    );
    final jeLine = await (db.select(db.journalEntryLines)
          ..where((l) => l.accountId.equals(bankId))
          ..limit(1))
        .getSingle();

    await repo.importBankStatementLines(
      bankAccountId: bankId,
      batchId: 'B-3',
      lines: [
        {
          'date': DateTime(2026, 5, 20),
          'reference': 'R3',
          'description': 'إيداع بعيدُ التاريخ',
          'debit': 0.0,
          'credit': 900.0,
          'balance': 900.0,
        }
      ],
    );
    final stmt = (await repo.getUnmatchedStatementLines(bankId)).single;

    await repo.manualMatchStatement(
        statementLineId: stmt.id, journalLineId: jeLine.id);
    expect(await repo.getUnmatchedStatementLines(bankId), isEmpty);

    await repo.unmatchStatement(stmt.id);
    expect(await repo.getUnmatchedStatementLines(bankId), hasLength(1));

    final reconId = await repo.createReconciliation(
      bankAccountId: bankId,
      periodStart: DateTime(2026, 5, 1),
      periodEnd: DateTime(2026, 5, 31),
      statementBalance: 900,
    );
    final report = await repo.getReconciliationReport(reconId);
    expect(report['bookBalance'], 900.0);
    expect(report['unmatchedBankLines'], hasLength(1));
  });

  test('وأسطرُ فترةٍ تُقرأ بالمدى', () async {
    await repo.importBankStatementLines(
      bankAccountId: bankId,
      batchId: 'B-4',
      lines: [
        {
          'date': DateTime(2026, 5, 10),
          'reference': 'داخل',
          'description': '',
          'debit': 0.0,
          'credit': 10.0,
          'balance': 10.0,
        },
        {
          'date': DateTime(2026, 7, 10),
          'reference': 'خارج',
          'description': '',
          'debit': 0.0,
          'credit': 20.0,
          'balance': 30.0,
        },
      ],
    );

    final rows = await repo.getStatementLines(
      bankAccountId: bankId,
      from: DateTime(2026, 5, 1),
      to: DateTime(2026, 5, 31),
    );
    expect(rows.map((r) => r.reference), ['داخل']);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  إقفالُ الجلسة يُحدّث العدّادين — البند المفتوح ٢، أُغلق 2026-09-02
  // ═══════════════════════════════════════════════════════════════════════
  //
  // 🔴 `total_matched`/`total_unmatched` يُحسبان لحظةَ **الإنشاء**، والشاشةُ
  // تُلزم بإنشاء الجلسة **قبل** الاستيراد (المتنُ لا يظهر بلا جلسة). فكان
  // الصفُّ يُختَم `0/0` مهما استُورد وطوبق.
  //
  // ولم يكن يُرى: `getReconciliationReport` يحسب العدَّين **حيَّين**، فالشاشةُ
  // تعرض الصحيحَ والأرشيفُ يحمل الكذب.

  test('🔴 الإقفالُ يُحدّث العدّادين المحفوظَين لا يختمهما كما وُلدا', () async {
    // جلسةٌ تُنشأ والكشفُ فارغٌ تماماً — وهو تدفّقُ الشاشة الفعليّ.
    final id = await repo.createReconciliation(
      bankAccountId: bankId,
      periodStart: DateTime(2026, 5, 1),
      periodEnd: DateTime(2026, 5, 31),
      statementBalance: 0,
    );

    // مرساة: وُلدت `0/0` فعلاً — فلو لم تكن كذلك لما قاس الاختبارُ شيئاً.
    final born = await (db.select(db.bankReconciliations)
          ..where((r) => r.id.equals(id)))
        .getSingle();
    expect(born.totalMatched, 0, reason: 'مرساة: تُولَد بصفر');
    expect(born.totalUnmatched, 0, reason: 'مرساة: تُولَد بصفر');

    // ثمّ يُستورَد ثلاثةُ أسطرٍ ويُطابَق واحدٌ آليّاً (±٣ أيّام بالمبلغ).
    await db.createJournalEntry(
      description: 'إيداع',
      date: DateTime(2026, 5, 10),
      lines: [
        JournalLine(accountId: bankId, debit: 400),
        JournalLine(accountId: cashId, credit: 400),
      ],
    );
    await repo.importBankStatementLines(
      bankAccountId: bankId,
      batchId: 'CLOSE',
      lines: [
        {'date': DateTime(2026, 5, 11), 'reference': 'M', 'description': '',
         'debit': 0.0, 'credit': 400.0, 'balance': 400.0},
        {'date': DateTime(2026, 5, 20), 'reference': 'U1', 'description': '',
         'debit': 0.0, 'credit': 150.0, 'balance': 550.0},
        {'date': DateTime(2026, 5, 21), 'reference': 'U2', 'description': '',
         'debit': 0.0, 'credit': 150.0, 'balance': 700.0},
      ],
    );
    expect(await repo.autoMatchStatementLines(bankId), 1,
        reason: 'المطابقةُ الآليّةُ تمسك الأوّلَ وحدَه');

    await repo.completeReconciliation(id);

    final closed = await (db.select(db.bankReconciliations)
          ..where((r) => r.id.equals(id)))
        .getSingle();
    expect(closed.status, 'completed');
    // القيمتان محسوبتان يدويّاً: واحدٌ طوبق آليّاً واثنان لم يُطابَقا.
    expect(closed.totalMatched, 1,
        reason: 'الصفُّ المختومُ كان يقول 0 بينما التقريرُ يقول 1');
    expect(closed.totalUnmatched, 2,
        reason: 'الصفُّ المختومُ كان يقول 0 بينما التقريرُ يقول 2');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  استئنافُ جلسةٍ مفتوحة — البند المفتوح ١، أُغلق 2026-09-02
  // ═══════════════════════════════════════════════════════════════════════
  //
  // 🔴 `getReconciliationSessions` كانت مُعلَنةً ومُنفَّذةً و**بلا مُنادٍ واحدٍ
  // في `lib`**، والشاشةُ لا تعرض إلّا «جلسة جديدة» — و`createReconciliation`
  // إدراجٌ بلا فحصِ تكرار. فكلُّ فتحٍ للتبويبة كان يُنشئ صفّاً آخر.
  //
  // وهذا يقيس ما تبني عليه الشاشةُ: أنّ الجلسةَ المفتوحةَ **قابلةٌ للعثور**
  // بحسابها وفترتها، وأنّ المقفلةَ تخرج من النتيجة.

  test('🔴 الجلسةُ المفتوحةُ تُوجَد بحسابها وفترتها، والمقفلةُ تخرج', () async {
    final first = await repo.createReconciliation(
      bankAccountId: bankId,
      periodStart: DateTime(2026, 5, 1),
      periodEnd: DateTime(2026, 5, 31, 23, 59, 59),
      statementBalance: 0,
    );

    // ⚠️ بالنوع الصريح لا `dynamic`: هذا ملفُّ اختبارٍ يستورد `database.dart`
    //    أصلاً، فلا عذرَ للديناميكيّ — وأربعةُ `avoid_dynamic_calls` كانت
    //    ترفع خطَّ أساس `analyze` من ٦ إلى ١٠ فتُحمِّر البوّابةَ كلَّها.
    //    (الشاشةُ وحدَها مضطرّةٌ للديناميكيّ: حارسُ `presentation_db_import_guard`
    //    يمنعها من استيراد `data/database`.)
    List<BankReconciliationData> openFor(
            List<BankReconciliationData> all, int acct) =>
        all
            .where((s) =>
                s.bankAccountId == acct &&
                s.status != 'completed' &&
                s.periodStart.month == 5)
            .toList();

    var sessions = await repo.getReconciliationSessions();
    expect(openFor(sessions, bankId).map((s) => s.id), [first],
        reason: 'مرساة: المفتوحةُ تُوجَد — وإلّا فالشاشةُ لا تجد ما تستأنفه');

    // وبعد الإقفال تخرج من نتيجة «المفتوحة» فيعود الزرُّ «جلسة جديدة».
    await repo.completeReconciliation(first);
    sessions = await repo.getReconciliationSessions();
    expect(openFor(sessions, bankId), isEmpty,
        reason: 'المقفلةُ ليست مفتوحةً — وإلّا عُرضت متابعةٌ لجلسةٍ منتهية');
  });
}
