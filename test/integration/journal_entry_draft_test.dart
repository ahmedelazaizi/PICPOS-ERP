// test/integration/journal_entry_draft_test.dart
//
// المسودّة **لا تحرّك رصيداً** حتى تُعتمَد — وهذا اختبارُ المال لا الواجهة.
//
// ═══ ما كان قائماً وما كان ناقصاً ═══
//
// مقيسٌ 2026-08-27: آلةُ المسودّة كانت مبنيّةً كلُّها إلّا مدخلَها.
// `isPosted` و`needsApproval` عمودان قائمان؛ وحارسُ الأرصدة في
// `createJournalEntry` مكتوبٌ حرفيّاً `if (shouldPost && …)` وفوقَه تعليقٌ
// «drafts wait for approval»؛ و`approveJournalEntry` كاملٌ بترحيلِه
// وتسجيلِ المعتمِد وإعادةِ حساب الأرصدة.
//
// والناقصُ كان سطرَين: `shouldPost` مثبَّتاً `true` — فلا أحدَ في المستودع
// كلِّه يضع `needsApproval = true`، وشارةُ «بانتظار الاعتماد» وزرُّ
// الاعتماد في الشاشة **ميتان** لأنّهما مسيَّجان بقيمةٍ لا تُكتَب أبداً.
//
// ⚠️ فهذا الاختبارُ يقيس الرقمَ لا الحالة: إنشاءُ مسودّةٍ يُبقي الرصيدَ
//    **صفراً**، واعتمادُها يحرّكه. و«حالةٌ صحيحةٌ ورصيدٌ متحرّك» هو عينُ
//    العطب الذي تمنعه المسودّة.
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

  /// حسابان **تفصيليّان** من الشجرة المزروعة — الصندوقُ ومبيعاتٌ.
  ///
  /// ⚠️ التفصيليّةُ شرطٌ لا تحسين: الـDAO يرفض الترحيلَ على حسابٍ رئيسيٍّ
  ///    برميةٍ صريحة، فـ`startsWith('41')` وحدَه يلتقط الأبَ `41` ويُسقط
  ///    الاختبارَ بسببٍ لا علاقةَ له بالمسودّة.
  Future<(int cash, int sales)> seedAccounts() async {
    final all = await repo.getAllAccounts();
    final cash = all.firstWhere(
        (a) => a.code == '1111' && a.accountNature == 'detail');
    final sales = all.firstWhere(
        (a) => a.code.startsWith('41') && a.accountNature == 'detail');
    return (cash.id, sales.id);
  }

  Future<double> balanceOf(int id) async {
    final all = await repo.getAllAccounts();
    return all.firstWhere((a) => a.id == id).balance;
  }

  /// ⚠️ `approved_by` مقيَّدٌ بـ`REFERENCES users(id)`، فرقمٌ مخترَعٌ يُسقط
  ///    الاعتمادَ بـ787 لا بعطبٍ في المسودّة. ويُقرأ مستخدمٌ مزروعٌ فعليّ.
  Future<int> anExistingUserId() async {
    final users = await db.select(db.users).get();
    expect(users, isNotEmpty, reason: 'البذرةُ تُنشئ مستخدماً على الأقلّ');
    return users.first.id;
  }

  test('المسودّةُ تُحفَظ غيرَ مرحَّلةٍ وبانتظار الاعتماد', () async {
    final (cash, sales) = await seedAccounts();

    final id = await repo.createJournalEntry(
      description: 'قيد تسوية — مسودّة',
      date: DateTime(2026, 8, 27),
      lines: [
        JournalLine(accountId: cash, debit: 500, credit: 0),
        JournalLine(accountId: sales, debit: 0, credit: 500),
      ],
      asDraft: true,
    );

    final entries = await repo.getJournalEntries();
    final entry = entries.firstWhere((e) => e.id == id);

    expect(entry.isPosted, isFalse, reason: 'المسودّةُ لا تُرحَّل');
    expect(entry.needsApproval, isTrue,
        reason: 'وإلّا لم تظهر في شارة «بانتظار الاعتماد» ولا زرِّه');
  });

  test('ولا تحرّك رصيدَ حسابٍ واحدٍ — والرقمُ صفرٌ لا «أقلّ»', () async {
    final (cash, sales) = await seedAccounts();
    final cashBefore = await balanceOf(cash);
    final salesBefore = await balanceOf(sales);

    await repo.createJournalEntry(
      description: 'قيد تسوية — مسودّة',
      date: DateTime(2026, 8, 27),
      lines: [
        JournalLine(accountId: cash, debit: 500, credit: 0),
        JournalLine(accountId: sales, debit: 0, credit: 500),
      ],
      asDraft: true,
    );

    expect(await balanceOf(cash), cashBefore,
        reason: 'رصيدٌ تحرّك بمسودّةٍ = ترحيلٌ بلا اعتماد');
    expect(await balanceOf(sales), salesBefore);
  });

  test('والاعتمادُ يرحّلها ويحرّك الرصيدَ بالقيمة المحسوبة', () async {
    final (cash, sales) = await seedAccounts();
    final cashBefore = await balanceOf(cash);
    final salesBefore = await balanceOf(sales);

    final id = await repo.createJournalEntry(
      description: 'قيد تسوية — مسودّة',
      date: DateTime(2026, 8, 27),
      lines: [
        JournalLine(accountId: cash, debit: 500, credit: 0),
        JournalLine(accountId: sales, debit: 0, credit: 500),
      ],
      asDraft: true,
    );

    await repo.approveJournalEntry(id, await anExistingUserId());

    final entry = (await repo.getJournalEntries()).firstWhere((e) => e.id == id);
    expect(entry.isPosted, isTrue);
    expect(entry.needsApproval, isFalse);

    // ⚠️ قيمةٌ محسوبةٌ لا «> صفر»: نصفُ إصلاحٍ قد يحرّك الرصيدَ بمقدارٍ
    //    خاطئٍ ويمرّ على «تحرّك».
    expect(await balanceOf(cash), closeTo(cashBefore + 500, 0.001));
    expect(await balanceOf(sales), closeTo(salesBefore - 500, 0.001));
  });

  test('والحفظُ العاديُّ يبقى مرحَّلاً فوراً — لا انقلابَ في الافتراض',
      () async {
    final (cash, sales) = await seedAccounts();
    final cashBefore = await balanceOf(cash);

    final id = await repo.createJournalEntry(
      description: 'قيد تسوية — عاديّ',
      date: DateTime(2026, 8, 27),
      lines: [
        JournalLine(accountId: cash, debit: 300, credit: 0),
        JournalLine(accountId: sales, debit: 0, credit: 300),
      ],
    );

    final entry = (await repo.getJournalEntries()).firstWhere((e) => e.id == id);
    expect(entry.isPosted, isTrue,
        reason: 'المُعامِلُ الجديدُ افتراضُه `false` — فلا يتغيّر سلوكُ '
            'أيِّ مستدعٍ قائم');
    expect(entry.needsApproval, isFalse);
    expect(await balanceOf(cash), closeTo(cashBefore + 300, 0.001));
  });

  test('واعتمادُ قيدٍ مرحَّلٍ يُرفَض — فلا يُحسَب الرصيدُ مرّتين', () async {
    final (cash, sales) = await seedAccounts();

    final id = await repo.createJournalEntry(
      description: 'قيد تسوية — عاديّ',
      date: DateTime(2026, 8, 27),
      lines: [
        JournalLine(accountId: cash, debit: 300, credit: 0),
        JournalLine(accountId: sales, debit: 0, credit: 300),
      ],
    );

    await expectLater(
        repo.approveJournalEntry(id, await anExistingUserId()), throwsException);
  });
}
