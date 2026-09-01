// المستودعُ كان يكشف ٣ دوالَّ من ١٠ — فالاستيرادُ والمطابقةُ والتقريرُ
// محجوبةٌ عن كلّ شاشة. وهذا يقيس **الوصولَ** لا المنطق: المنطقُ مختبَرٌ في
// `bank_reconciliation_posted_and_match_test`.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/drift_accounting_repository.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';

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
}
