// ═══════════════════════════════════════════════════════════════════════════
// §٣‑٦ — المطابقةُ البنكيّةُ كانت تقرأ دفتراً ليس هو الدفتر.
// ═══════════════════════════════════════════════════════════════════════════
//
// `bank_reconciliation_dao.dart` لم يكن فيه ذكرٌ **واحد** لـ`is_posted` ولا
// لـ`is_deleted`، وثلاثةٌ من استعلاماته تقرأ الأستاذ:
//
//   ‏١) رصيدُ الدفتر في `createReconciliation`
//   ‏٢) المطابقةُ الآليّة في `autoMatchStatementLines`
//   ‏٣) «في الدفتر لا في البنك» في `getReconciliationReport`
//
// فكانت **المسوّدةُ غيرُ المرحَّلة والقيدُ المحذوف** يدخلان الثلاثةَ. وأثرُه
// أنّ المطابقةَ — التي تقوم أصلاً **لكشف الفرق** — تخترع فرقاً أو تخفيه:
//   • رصيدُ الدفتر يخالف الأستاذَ ⇒ «الفرقُ» رقمٌ لا يقابله شيء.
//   • وسطرُ كشفٍ يُغلَق على قيدٍ **محذوف** فيبدو مطابَقاً بلا ما يقابله.
//
// ── وحسابٌ مفردٌ لا شجرة ──────────────────────────────────────────────────
// الحصرُ كان `account_id = ?`. وشجرةُ الحسابات تسمح بحسابِ بنكٍ أبٍ تحته
// فرعيّات، فمطابقةٌ على الأب كانت تقرأ **صفراً** وتعلن الفرقَ كلَّه.
//
// ── وقيدٌ واحدٌ كان يغطّي سطرَين ───────────────────────────────────────────
// المطابقةُ الآليّةُ تُقصي المستعملَ سلفاً، واليدويّةُ كانت تكتب بلا فحص. فسطرا
// كشفٍ يُغلقان على نفس القيد، ويبدو الكشفُ مطابَقاً تماماً بينما حركةٌ بنكيّةٌ
// كاملةٌ بلا ما يقابلها.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;
  late int bankId;
  late int cashId;

  final opDate = DateTime(2026, 5, 10);
  final periodStart = DateTime(2026, 5, 1);
  final periodEnd = DateTime(2026, 5, 31);

  Future<int> account(String code, String name, {int? parentId}) async {
    final existing = await db.getAccountByCode(code);
    if (existing != null) return existing.id;
    return db.createAccount(
      code: code,
      name: name,
      accountType: 'asset',
      parentId: parentId,
    );
  }

  Future<int> deposit(double amount, {bool asDraft = false, int? into}) =>
      db.createJournalEntry(
        description: 'إيداع',
        date: opDate,
        asDraft: asDraft,
        lines: [
          JournalLine(accountId: into ?? bankId, debit: amount),
          JournalLine(accountId: cashId, credit: amount),
        ],
      );

  Future<void> statement(double credit) => db.importBankStatementLines(
        bankAccountId: bankId,
        batchId: 'B-36',
        lines: [
          {
            'date': opDate.add(const Duration(days: 1)),
            'reference': 'DEP',
            'description': 'إيداع',
            'debit': 0.0,
            'credit': credit,
            'balance': credit,
          },
        ],
      );

  Future<double> bookBalance() async {
    final id = await db.createReconciliation(
      bankAccountId: bankId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      statementBalance: 0,
    );
    return (await (db.select(db.bankReconciliations)
              ..where((r) => r.id.equals(id)))
            .getSingle())
        .bookBalance;
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    cashId = await account('1110', 'النقدية');
    bankId = await account('1120', 'البنك الأهلي');
  });

  tearDown(() => db.close());

  // ───────────────────────────────────────────────────────────────────────
  // رصيدُ الدفتر
  // ───────────────────────────────────────────────────────────────────────

  group('§٣‑٦ رصيدُ الدفتر = المرحَّلُ غيرُ المحذوف', () {
    test('مرساة: قيدٌ مرحَّلٌ يدخل الرصيد', () async {
      await deposit(500);
      expect(await bookBalance(), 500.0,
          reason: 'لولاه لمرَّ صفرُ الرصيد أدناه بوصفه «لا بيانات»');
    });

    test('🔴 المسوّدةُ غيرُ المرحَّلة لا تدخل رصيدَ الدفتر', () async {
      await deposit(500);
      await deposit(900, asDraft: true);

      expect(await bookBalance(), 500.0,
          reason: 'كان يُقرأ ١٤٠٠ — رصيدٌ يخالف الأستاذَ، فالفرقُ المُعلَن '
              'رقمٌ مخترَع');
    });

    test('🔴 القيدُ المحذوفُ لا يدخل رصيدَ الدفتر', () async {
      await deposit(500);
      final gone = await deposit(700);
      await (db.update(db.journalEntries)..where((e) => e.id.equals(gone)))
          .write(const JournalEntriesCompanion(isDeleted: Value(true)));

      expect(await bookBalance(), 500.0, reason: 'كان يُقرأ ١٢٠٠');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // المطابقةُ الآليّة
  // ───────────────────────────────────────────────────────────────────────

  group('§٣‑٦ المطابقةُ الآليّةُ لا تُغلق على قيدٍ ليس في الدفتر', () {
    test('مرساة: القيدُ المرحَّلُ يُطابَق', () async {
      await deposit(500);
      await statement(500);

      expect(await db.autoMatchStatementLines(bankId), 1);
    });

    test('🔴 لا تُطابَق مسوّدةٌ غيرُ مرحَّلة', () async {
      await deposit(500, asDraft: true);
      await statement(500);

      expect(await db.autoMatchStatementLines(bankId), 0,
          reason: 'سطرُ الكشف كان يُغلَق على قيدٍ لم يُرحَّل — فيبدو مطابَقاً '
              'وما له في الدفتر أثر');
      expect(await db.getUnmatchedStatementLines(bankId), hasLength(1));
    });

    test('🔴 لا تُطابَق على قيدٍ محذوف', () async {
      final gone = await deposit(500);
      await (db.update(db.journalEntries)..where((e) => e.id.equals(gone)))
          .write(const JournalEntriesCompanion(isDeleted: Value(true)));
      await statement(500);

      expect(await db.autoMatchStatementLines(bankId), 0);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // شجرةُ الحساب
  // ───────────────────────────────────────────────────────────────────────

  test('🔴 حسابُ البنك الأبُ يقرأ حركةَ فروعِه', () async {
    // ⚠️ **رمزٌ لا يصطدم بالشجرة المزروعة.** المحاولةُ الأولى استعملت `1121`
    //    وهو موجودٌ في التجهيزة باسمِ «ذمم عملاء محليون» تحت أبٍ آخر — فأعاد
    //    المساعدُ حساباً قائماً ليس ابناً للبنك، وسقط الفحصُ لسببٍ ليس العطب.
    final child =
        await account('112001', 'البنك الأهلي — فرع أ', parentId: bankId);

    // مرساة: الابنُ ابنٌ فعلاً، والشجرةُ تراه. بدونها يمرُّ صفرُ الرصيد
    // على تجهيزةٍ خاطئةٍ بوصفه عطباً — أو العكس.
    final row = await (db.select(db.accounts)..where((a) => a.id.equals(child)))
        .getSingle();
    expect(row.parentId, bankId, reason: 'التجهيزةُ نفسُها يجب أن تصحّ أوّلاً');
    expect(await db.accountSubtreeIds(bankId), containsAll([bankId, child]));

    await deposit(500, into: child);

    expect(await bookBalance(), 500.0,
        reason: 'الحصرُ على حسابٍ مفردٍ كان يقرأ صفراً ويعلن الفرقَ كلَّه');
  });

  // ───────────────────────────────────────────────────────────────────────
  // المطابقةُ اليدويّة
  // ───────────────────────────────────────────────────────────────────────

  group('§٣‑٦ قيدٌ واحدٌ لا يغطّي سطرَي كشف', () {
    late int lineId;

    setUp(() async {
      await deposit(500);
      final jeLine = await (db.select(db.journalEntryLines)
            ..where((l) => l.accountId.equals(bankId))
            ..limit(1))
          .getSingle();
      lineId = jeLine.id;

      await statement(500); // سطرُ كشفٍ أوّل
      await statement(500); // وثانٍ بنفس المبلغ
    });

    test('مرساة: الإسنادُ الأوّلُ يقع', () async {
      final lines = await db.getUnmatchedStatementLines(bankId);
      await db.manualMatchStatement(
          statementLineId: lines.first.id, journalLineId: lineId);

      expect(await db.getUnmatchedStatementLines(bankId), hasLength(1));
    });

    test('🔴 الإسنادُ الثاني لنفس القيد يُرفَض', () async {
      final lines = await db.getUnmatchedStatementLines(bankId);
      await db.manualMatchStatement(
          statementLineId: lines[0].id, journalLineId: lineId);

      expect(
        () => db.manualMatchStatement(
            statementLineId: lines[1].id, journalLineId: lineId),
        throwsA(isA<StateError>()),
        reason: 'كان يُقبَل بلا فحصٍ فيُعَدّان مطابَقَين اثنَين — وتبدو '
            'المطابقةُ تامّةً بينما حركةٌ بنكيّةٌ بلا ما يقابلها',
      );
      expect(await db.getUnmatchedStatementLines(bankId), hasLength(1),
          reason: 'السطرُ الثاني يبقى غيرَ مطابَقٍ — وهو الحقيقة');
    });

    test('إعادةُ الإسناد لنفس السطر تمرّ — الحارسُ يمنع التكرارَ لا التصحيح',
        () async {
      final lines = await db.getUnmatchedStatementLines(bankId);
      await db.manualMatchStatement(
          statementLineId: lines.first.id, journalLineId: lineId);

      await expectLater(
        db.manualMatchStatement(
            statementLineId: lines.first.id, journalLineId: lineId),
        completes,
      );
    });

    test('نزعُ الأوّل يفتح الإسنادَ للثاني', () async {
      final lines = await db.getUnmatchedStatementLines(bankId);
      await db.manualMatchStatement(
          statementLineId: lines[0].id, journalLineId: lineId);
      await db.unmatchStatement(lines[0].id);

      await expectLater(
        db.manualMatchStatement(
            statementLineId: lines[1].id, journalLineId: lineId),
        completes,
      );
    });
  });
}
