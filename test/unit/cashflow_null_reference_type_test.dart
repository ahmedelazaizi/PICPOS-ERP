// Regression: قيدٌ يمسّ النقدية و`reference_type` فيه NULL (قيدٌ يدويّ، أو
// مسودّةٌ اعتُمدت ودُفعت للخادم بلا مرجع) كان يختفي من قائمة التدفّقات.
//
// السبب: `je.reference_type NOT IN (...)` تساوي UNKNOWN مع NULL، فلا يدخل
// القيدُ في التشغيلي ولا في الاستثماري/التمويلي، بينما استعلامُ الرصيد
// الافتتاحيّ لا يرشّح على النوع أصلاً — فالقائمةُ تناقض نفسَها بين فترتين.
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
  });

  tearDown(() => db.close());

  Future<double> glCash(int accountId) async {
    final row = await db.customSelect(
      'SELECT COALESCE(SUM(jel.debit - jel.credit), 0) AS b '
      'FROM journal_entry_lines jel '
      'JOIN journal_entries je ON je.id = jel.entry_id '
      'WHERE jel.account_id = ? AND je.is_posted = ${db.sqlBool(true)}',
      variables: [Variable.withInt(accountId)],
    ).getSingle();
    return (row.data['b'] as num).toDouble();
  }

  test('قيدٌ نقديّ بلا reference_type: الإغلاقُ = رصيدُ الأستاذ = افتتاحُ الفترة التالية',
      () async {
    final cash = (await db.getAccountByCode('1111'))!;
    // ACC-006: the counter-account of the NULL-reference entry must not be equity/LT
    // (that is financing now) for it to stay in operating — use other revenue 4121.
    final equity = (await db.getAccountByCode('311'))!;
    final otherIncome = (await db.getAccountByCode('4121'))!;
    await db.createJournalEntry(
      description: 'قيد يدويّ بلا مرجع',
      date: DateTime(2026, 8, 10),
      lines: [
        JournalLine(accountId: cash.id, debit: 700.0, description: 'نقد'),
        JournalLine(accountId: otherIncome.id, credit: 700.0, description: 'إيراد'),
      ],
    );
    // وقيدٌ بمرجعٍ مصنَّف إلى جواره، كي لا يمرّ الاختبارُ بالصدفة.
    await db.createJournalEntry(
      description: 'بيع نقديّ',
      date: DateTime(2026, 8, 12),
      referenceType: 'sale',
      referenceId: 1,
      isAutoPosted: true,
      lines: [
        JournalLine(accountId: cash.id, debit: 200.0, description: 'نقد'),
        JournalLine(accountId: equity.id, credit: 200.0, description: 'مقابل'),
      ],
    );
    final nullRef = await db.customSelect(
      'SELECT COUNT(*) AS c FROM journal_entries WHERE reference_type IS NULL',
    ).getSingle();
    expect(nullRef.data['c'], greaterThan(0),
        reason: 'شرطٌ مسبق: الصفّ الذي نختبره فعلاً reference_type = NULL');

    final aug = await db.getCashFlowStatement(
        DateTime(2026, 8, 1), DateTime(2026, 8, 31));
    final sep = await db.getCashFlowStatement(
        DateTime(2026, 9, 1), DateTime(2026, 9, 30));
    final gl = await glCash(cash.id);

    expect(gl, closeTo(900, 0.01));
    expect((aug['closingBalance'] as num).toDouble(), closeTo(gl, 0.01),
        reason: 'الإغلاق يجب أن يشمل الـ700 ذات المرجع الفارغ');
    expect((sep['openingBalance'] as num).toDouble(),
        closeTo((aug['closingBalance'] as num).toDouble(), 0.01),
        reason: 'القائمةُ لا تناقض نفسها عبر الفترات');
    final op = aug['operating'] as Map<String, dynamic>;
    expect((op['totalInflow'] as num).toDouble(), closeTo(900, 0.01));
  });
}
