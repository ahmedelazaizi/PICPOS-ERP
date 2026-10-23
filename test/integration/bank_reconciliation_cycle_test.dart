// الدورةُ كاملةً على كشفٍ كلُّ أسطره لها ما يقابلها في الدفتر.
// ⚠️ والمقيسُ **قيمةٌ محسوبةٌ يدويّاً** لا «> صفر»: مصالحةٌ قد تتّفق عند
// رقمٍ خاطئٍ وتمرّ خضراء.
import 'package:drift/drift.dart' hide isNotNull, isNull;
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
  //    `test/unit/bank_reconciliation_repository_test.dart` سطر ١٩.
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

  test('🔴 دورةٌ كاملة: استيرادٌ ← آليّةٌ ← يدويّةٌ ← إقفال', () async {
    // قيدان: أحدُهما داخلَ نافذة ±٣ أيّام والآخرُ خارجَها.
    for (final (d, amount) in [
      (DateTime(2026, 5, 10), 500.0),
      (DateTime(2026, 5, 1), 300.0),
    ]) {
      await db.createJournalEntry(
        description: 'إيداع',
        date: d,
        lines: [
          JournalLine(accountId: bankId, debit: amount),
          JournalLine(accountId: cashId, credit: amount),
        ],
      );
    }

    await repo.importBankStatementLines(
      bankAccountId: bankId,
      batchId: 'CYCLE',
      lines: [
        {'date': DateTime(2026, 5, 11), 'reference': 'A', 'description': '',
         'debit': 0.0, 'credit': 500.0, 'balance': 500.0},
        {'date': DateTime(2026, 5, 25), 'reference': 'B', 'description': '',
         'debit': 0.0, 'credit': 300.0, 'balance': 800.0},
      ],
    );

    // مرساة: الاستيرادُ وقع فعلاً.
    expect(await repo.getUnmatchedStatementLines(bankId), hasLength(2));

    // الآليّةُ تمسك الأوّلَ وحدَه (±٣ أيّام).
    expect(await repo.autoMatchStatementLines(bankId), 1);
    final left = await repo.getUnmatchedStatementLines(bankId);
    expect(left, hasLength(1));
    expect(left.single.reference, 'B');

    // واليدويّةُ تُغلق الثاني.
    final id = await repo.createReconciliation(
      bankAccountId: bankId,
      periodStart: DateTime(2026, 5, 1),
      periodEnd: DateTime(2026, 5, 31),
      statementBalance: 800,
    );
    final report = await repo.getReconciliationReport(id);
    final jeLineId = (report['outstandingBookEntries'] as List<QueryRow>)
        .first
        .data['id'] as int;

    await repo.manualMatchStatement(
        statementLineId: left.single.id, journalLineId: jeLineId);

    expect(await repo.getUnmatchedStatementLines(bankId), isEmpty,
        reason: 'الدورةُ تنتهي بصفرِ غيرِ مطابَق');

    // والفرقُ = رصيدُ الكشف − رصيدُ الدفتر، محسوباً يدويّاً: 800 − 800 = 0.
    final finalReport = await repo.getReconciliationReport(id);
    expect(finalReport['bookBalance'], 800.0);
    expect(finalReport['difference'], 0.0);

    await repo.completeReconciliation(id);
    final row = await (db.select(db.bankReconciliations)
          ..where((r) => r.id.equals(id)))
        .getSingle();
    expect(row.status, 'completed');
  });
}
