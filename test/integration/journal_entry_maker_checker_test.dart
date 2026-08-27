// test/integration/journal_entry_maker_checker_test.dart
//
// **لا يعتمد القيدَ منشئُه** — قرارُ مالك 2026-08-27.
//
// ═══ ما الذي يحرسه هذا الملفّ ═══
//
// «كلُّ قيدٍ يدويٍّ مسودّةٌ حتى يعتمده **غيرُ** منشئه». والشقُّ الأوّل
// (‏مسودّةٌ) يقيسه `journal_entry_draft_test.dart`؛ وهذا الملفُّ للشقّ
// الثاني — وهو الذي يجعل الفصلَ **ضابطاً** لا ترتيباً.
//
// ⚠️ وبلا `created_by` لا ضابطَ أصلاً: مَن أنشأ يستطيع أن يعتمد، فيصير
//    الترحيلُ خطوتَين بيدٍ واحدة — وهو تأخيرٌ لا رقابة.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/drift_accounting_repository.dart';
import 'package:ural_erp/domain/repositories/accounting_repository.dart';

void main() {
  late AppDatabase db;
  late DriftAccountingRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = DriftAccountingRepository(db);
  });

  tearDown(() async => db.close());

  Future<(int cash, int sales)> seedAccounts() async {
    final all = await repo.getAllAccounts();
    final cash = all.firstWhere(
        (a) => a.code == '1111' && a.accountNature == 'detail');
    final sales = all.firstWhere(
        (a) => a.code.startsWith('41') && a.accountNature == 'detail');
    return (cash.id, sales.id);
  }

  Future<int> seedUser(String name) async {
    final existing = await db.select(db.users).get();
    if (existing.length > 1) {
      return existing.firstWhere((u) => u.username != existing.first.username).id;
    }
    return db.into(db.users).insert(
          UsersCompanion.insert(
            username: name,
            passwordHash: 'x',
            passwordSalt: const Value('y'),
            displayName: name,
          ),
        );
  }

  Future<double> balanceOf(int id) async {
    final all = await repo.getAllAccounts();
    return all.firstWhere((a) => a.id == id).balance;
  }

  Future<int> makeDraft(int cash, int sales, int creator) => repo.createJournalEntry(
        description: 'قيد تسوية — مسودّة',
        date: DateTime(2026, 8, 27),
        lines: [
          JournalLine(accountId: cash, debit: 500, credit: 0),
          JournalLine(accountId: sales, debit: 0, credit: 500),
        ],
        asDraft: true,
        createdBy: creator,
      );

  test('منشئُ المسودّة لا يعتمدها — والرصيدُ لا يتحرّك', () async {
    final (cash, sales) = await seedAccounts();
    final maker = (await db.select(db.users).get()).first.id;
    final before = await balanceOf(cash);

    final id = await makeDraft(cash, sales, maker);

    await expectLater(repo.approveJournalEntry(id, maker), throwsException);

    // ⚠️ الرميةُ وحدَها لا تكفي: رميةٌ **بعد** تحريكِ الرصيد تترك الضررَ.
    expect(await balanceOf(cash), before,
        reason: 'الرفضُ يقع قبل أيّ كتابةٍ على الأرصدة');
    final entry = (await repo.getJournalEntries()).firstWhere((e) => e.id == id);
    expect(entry.isPosted, isFalse);
    expect(entry.needsApproval, isTrue);
  });

  test('وغيرُه يعتمدها فتُرحَّل ويتحرّك الرصيدُ بالقيمة المحسوبة', () async {
    final (cash, sales) = await seedAccounts();
    final maker = (await db.select(db.users).get()).first.id;
    final checker = await seedUser('checker');
    expect(checker, isNot(maker));

    final before = await balanceOf(cash);
    final id = await makeDraft(cash, sales, maker);

    await repo.approveJournalEntry(id, checker);

    final entry = (await repo.getJournalEntries()).firstWhere((e) => e.id == id);
    expect(entry.isPosted, isTrue);
    expect(entry.needsApproval, isFalse);
    expect(await balanceOf(cash), closeTo(before + 500, 0.001));
  });

  test('ومسودّةٌ بلا منشئٍ معروفٍ تُعتمَد — لا نمنع بما لا نعلم', () async {
    // ⚠️ قيودٌ أُنشئت قبل هذا الضابط تحمل `created_by = NULL`. ومنعُها
    //    يُجمّد ما لا يمكن إثباتُ منشئه — فيصير الضابطُ قفلاً لا رقابة.
    final (cash, sales) = await seedAccounts();
    final anyUser = (await db.select(db.users).get()).first.id;

    final id = await repo.createJournalEntry(
      description: 'قيد بلا منشئ',
      date: DateTime(2026, 8, 27),
      lines: [
        JournalLine(accountId: cash, debit: 500, credit: 0),
        JournalLine(accountId: sales, debit: 0, credit: 500),
      ],
      asDraft: true,
    );

    await repo.approveJournalEntry(id, anyUser);
    final entry = (await repo.getJournalEntries()).firstWhere((e) => e.id == id);
    expect(entry.isPosted, isTrue);
  });
}
