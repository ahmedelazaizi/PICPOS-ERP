// سندُ الشيك — **مستندٌ يُكتَب، وقرشٌ لا يتحرّك**.
//
// ═══ قرارُ المالك 2026-09-19 (تصميم «إدارة الشيكات») ═══
//
// التصميمُ يعرض بجوار الشيك «سند القبض **RV-0051**» وزرَّ «عرض السند».
// وقياسُ المسار قبل البناء وجد أنّ **لا سندَ للشيك أصلاً**:
//
// ‏١ — الرابطُ في `commercial_papers.notes` نصٌّ عربيٌّ حرّ:
//     `'ترحيل تلقائي من سند قبض $voucherNumber'`.
// ‏٢ — والرقمُ داخلَه يولّده الحوارُ في ذاكرته (`REC2026…`) **ولا يُخزَّن
//     قطّ**؛ ورقمُ القاعدة الحقيقيُّ `RV-00xx` من `generateInvoiceNumber`.
//     فالنصُّ يسمّي رقماً لا وجودَ له — وهو نفسُه المطبوعُ على الورقة.
// ‏٣ — 🔴 وسندُ القبض بشيكٍ يمرّ بـ`skipSafeTransaction: true` (مواصفة ١٣٣،
//     لمنع ازدواج قيدِ العميل)، فلا يُكتَب صفُّ `safe_transactions`
//     **إطلاقاً** ويعود `transactionId = 0`.
//
// ⇒ قرارُ المالك: **يُنشأ سندٌ حقيقيٌّ للشيك** — صفٌّ برقم `RV-`/`PV-` بلا
//   أثرٍ على الرصيد ولا قيدٍ ثانٍ.
//
// ═══ 🔴 وما وجده القياسُ بعد القرار — ولم يكن معروفاً حين اتُّخذ ═══
//
// قرّاءُ كشف الحساب في `party_dao` **لا يُرشِّحون بالنوع**:
// `getPartyLedger` يسحب كلَّ صفوف `safe_transactions` للطرف، و
// `getPartyTransactions` كذلك. فصفٌّ مستنديٌّ جديدٌ يظهر **سطراً مكرّراً**
// في كشف الحساب بجوار قيد الترحيل الآليّ للورقة — وهو عينُ ازدواجِ مواصفة
// ١٣٣ عائداً من بابٍ آخر.
//
// ولذلك نوعٌ مستقلٌّ `cheque_voucher`:
//   · القرّاءُ الذين يرشّحون `'receipt'`/`'payment'` (حسابُ الرصيد الافتتاحيّ
//     للطرف) يتجاهلونه **بلا تعديلٍ فيهم**؛
//   · والقارئان اللذان لا يرشّحان يُستثنى عندهما صراحةً.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  // ⚠️ المعرّفاتُ تُلتقَط لا تُفترَض: `forTesting()` يزرع صفوفاً ثمّ يمحوها
  //    [_clear]، وعدّادُ `autoIncrement` لا يعود إلى ١ — فالخزنةُ الجديدةُ
  //    ليست `id = 1`، وتثبيتُه يجعل الدالّةَ تقرأ خزنةً غيرَ موجودة.
  late int safeId;
  late int partyId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await _clear(db);
    // ⚠️ الدليلُ يبقى: الترحيلُ الآليُّ للأوراق يرفض العملَ بلا حساب «أوراق
    //    القبض»، فمحوُ الدليل يُسقط الاختبارَ لسببٍ غيرِ المقيس.
    await db.syncDefaultAccounts();
    await _seedFiscalYear(db);
    safeId = await _seedSafe(db, balance: 1000);
    partyId = await _seedParty(db, balance: 0);
  });

  tearDown(() => db.close());

  Future<List<SafeTransactionData>> txns() =>
      db.select(db.safeTransactions).get();

  Future<double> safeBalance() async =>
      (await (db.select(db.safes)..where((s) => s.id.equals(safeId)))
              .getSingle())
          .balance;

  Future<double> partyBalance() async =>
      (await (db.select(db.parties)..where((p) => p.id.equals(partyId)))
              .getSingle())
          .balance;

  group('🔴 سندُ الشيك يُكتَب مستنداً', () {
    test('صفٌّ واحدٌ برقم `RV-` — وكان لا يُكتَب شيء', () async {
      final id = await db.createReceiptVoucher(
        amount: 500,
        category: 'customer_payment',
        partyId: partyId,
        safeId: safeId,
        description: 'قبضٌ بشيك',
        skipJournalEntry: true,
        skipSafeTransaction: true,
        chequeVoucherSafeId: safeId,
      );

      final rows = await txns();
      expect(rows, hasLength(1),
          reason: 'لا سندَ يُكتَب — فلا شيءَ يشير إليه زرُّ «عرض السند»');
      expect(rows.single.voucherNumber, isNotEmpty,
          reason: 'سندٌ بلا رقمٍ لا يُشار إليه');
      expect(id, rows.single.id,
          reason: 'المُنادي لا يستعيد معرّفَ السند — فلا يصل الورقةَ');
      expect(id, greaterThan(0));
    });

    test('🔴 ونوعُه `cheque_voucher` لا `receipt`', () async {
      // حسابُ الرصيد الافتتاحيّ في `party_dao` يجمع
      // `transaction_type = 'receipt'`؛ فصفٌّ بهذا النوع يُعَدّ **دفعةً
      // ثانيةً** من العميل — عينُ ازدواج مواصفة ١٣٣.
      await db.createReceiptVoucher(
        amount: 500,
        category: 'customer_payment',
        partyId: partyId,
        safeId: safeId,
        skipJournalEntry: true,
        skipSafeTransaction: true,
        chequeVoucherSafeId: safeId,
      );
      expect((await txns()).single.transactionType, 'cheque_voucher');
    });

    test('والرصيدُ لا يتحرّك — الشيكُ ورقةٌ لا نقد', () async {
      await db.createReceiptVoucher(
        amount: 500,
        category: 'customer_payment',
        partyId: partyId,
        safeId: safeId,
        skipJournalEntry: true,
        skipSafeTransaction: true,
        chequeVoucherSafeId: safeId,
      );
      expect(await safeBalance(), closeTo(1000, 1e-9),
          reason: 'رصيدُ الخزنة تحرّك بورقةٍ لم تُحصَّل');
      expect((await txns()).single.balanceAfter, closeTo(1000, 1e-9),
          reason: '`balanceAfter` يَعِد برصيدٍ لم يقع');
    });

    test('ورصيدُ الطرف لا يتحرّك — الترحيلُ الآليُّ يملكه', () async {
      await db.createReceiptVoucher(
        amount: 500,
        category: 'customer_payment',
        partyId: partyId,
        safeId: safeId,
        skipJournalEntry: true,
        skipSafeTransaction: true,
        chequeVoucherSafeId: safeId,
      );
      expect(await partyBalance(), closeTo(0, 1e-9),
          reason: 'ذمّةُ العميل نقصت مرّتَين — وهي مواصفة ١٣٣ بعينها');
    });

    test('ولا قيدَ يومية من مسار السند', () async {
      await db.createReceiptVoucher(
        amount: 500,
        category: 'customer_payment',
        partyId: partyId,
        safeId: safeId,
        skipJournalEntry: true,
        skipSafeTransaction: true,
        chequeVoucherSafeId: safeId,
      );
      expect(await db.select(db.journalEntries).get(), isEmpty,
          reason: 'قيدٌ ثانٍ — والورقةُ تكتب قيدَها');
    });

    test('🔴 ورقمُه من **نفس عدّاد** السند النقديّ لا سلسلةٍ ثانية', () async {
      // ⚠️ والبادئةُ لا تُثبَّت في الفحص: `generateInvoiceNumber` يردّ
      //    `'RV'` إلى `'RCPT'` ثمّ **يسمح للمستخدم بتغييرها** من الإعدادات.
      //    فتثبيتُ `'RV-'` يقيس التصميمَ لا النظام. والمقيسُ: نفسُ العائلة،
      //    ورقمان لا يتصادمان — وهو ما يمنع فجوةً في التسلسل.
      await db.createReceiptVoucher(
        amount: 100,
        category: 'customer_payment',
        partyId: partyId,
        safeId: safeId,
        skipJournalEntry: true,
      );
      await db.createReceiptVoucher(
        amount: 500,
        category: 'customer_payment',
        partyId: partyId,
        safeId: safeId,
        skipJournalEntry: true,
        skipSafeTransaction: true,
        chequeVoucherSafeId: safeId,
      );
      final numbers = (await txns()).map((t) => t.voucherNumber).toList();
      expect(numbers, hasLength(2));
      expect(numbers.toSet(), hasLength(2),
          reason: 'رقمان متطابقان — سندان لا يُفرَّق بينهما');
      String family(String v) => v.split('-').first;
      expect(family(numbers[0]), family(numbers[1]),
          reason: 'سندُ الشيك في سلسلةٍ ثانية — فيقرأ المحاسبُ فجوةً في '
              'الترقيم ولا يجد ما يملؤها');
    });

    test('وسندُ الصرف بشيكٍ كذلك', () async {
      final id = await db.createPaymentVoucher(
        amount: 300,
        category: 'supplier_payment',
        partyId: partyId,
        safeId: safeId,
        description: 'صرفٌ بشيك',
        skipJournalEntry: true,
        skipSafeTransaction: true,
        chequeVoucherSafeId: safeId,
      );
      final rows = await txns();
      expect(rows, hasLength(1));
      expect(rows.single.voucherNumber, isNotEmpty);
      expect(rows.single.transactionType, 'cheque_voucher');
      expect(id, rows.single.id);
      expect(await safeBalance(), closeTo(1000, 1e-9));
      expect(await partyBalance(), closeTo(0, 1e-9));
    });
  });

  group('ومراسٍ — ما كان يعمل يبقى كما هو', () {
    test('قبضٌ نقديٌّ يحرّك الرصيدَ ويُكتَب `receipt`', () async {
      await db.createReceiptVoucher(
        amount: 500,
        category: 'customer_payment',
        partyId: partyId,
        safeId: safeId,
        skipJournalEntry: true,
      );
      final rows = await txns();
      expect(rows, hasLength(1));
      expect(rows.single.transactionType, 'receipt');
      expect(await safeBalance(), closeTo(1500, 1e-9),
          reason: 'النقدُ لم يدخل الخزنة');
    });

    test('🔴 وبلا [chequeVoucherSafeId] لا يُكتَب صفٌّ إطلاقاً', () async {
      // مواصفة ١٣٣ الأصليّةُ محروسةٌ في `spec_081_cheque_supplier_je_test`
      // بـ«لا صفَّ». فالصفُّ المستنديُّ **يُطلَب صراحةً** ولا يُفرَض،
      // وإلّا انقلب حارسٌ قائمٌ أحمرَ.
      await db.createReceiptVoucher(
        amount: 500,
        category: 'customer_payment',
        partyId: partyId,
        safeId: safeId,
        skipJournalEntry: true,
        skipSafeTransaction: true,
      );
      expect(await txns(), isEmpty);
    });
  });

  group('والورقةُ تحمل معرّفَ سندها', () {
    test('🔴 `sourceVoucherId` يُخزَّن ويُقرأ — عمودٌ كان بلا كاتب', () async {
      // ⚠️ العمودُ مشحونٌ منذ v174 و**لا يكتبه أحد**: قياسُ المستودع وجد
      //    ذكرَه في تعريف الجدول وفي الهجرة فقط. فالميزةُ مبنيّةٌ ولا تعمل.
      final voucherId = await db.createReceiptVoucher(
        amount: 500,
        category: 'customer_payment',
        partyId: partyId,
        safeId: safeId,
        skipJournalEntry: true,
        skipSafeTransaction: true,
        chequeVoucherSafeId: safeId,
      );

      final paperId = await db.createCommercialPaper(
        paperNumber: 'CH-001',
        type: 'cheque',
        direction: 'received',
        partyId: partyId,
        amount: 500,
        issueDate: DateTime(2026, 9, 8),
        dueDate: DateTime(2026, 9, 15),
        sourceVoucherId: voucherId,
      );

      final paper = await (db.select(db.commercialPapers)
            ..where((p) => p.id.equals(paperId)))
          .getSingle();
      expect(paper.sourceVoucherId, voucherId,
          reason: 'الورقةُ لا تحمل سندَها — فزرُّ «عرض السند» بلا وجهة');

      // والسندُ المُشار إليه موجودٌ فعلاً ويحمل رقماً يُقرأ.
      final voucher = await (db.select(db.safeTransactions)
            ..where((t) => t.id.equals(voucherId)))
          .getSingle();
      expect(voucher.voucherNumber, isNotEmpty);
    });

    test('وورقةٌ بلا سندٍ تبقى `null` لا صفراً', () async {
      // 🔴 صفرٌ معرّفٌ صالحٌ شكلاً ولا يوجد صفٌّ به — فيقرؤه الزرُّ وجهةً
      //    ثمّ لا يجد شيئاً. و`null` تقول «لا سندَ» صراحةً.
      final paperId = await db.createCommercialPaper(
        paperNumber: 'CH-002',
        type: 'cheque',
        direction: 'received',
        partyId: partyId,
        amount: 100,
        issueDate: DateTime(2026, 9, 8),
        dueDate: DateTime(2026, 9, 15),
      );
      final paper = await (db.select(db.commercialPapers)
            ..where((p) => p.id.equals(paperId)))
          .getSingle();
      expect(paper.sourceVoucherId, isNull);
    });
  });

  group('🔴 ولا يظهر سطراً ثانياً في كشف الحساب', () {
    test('كشفُ الحساب لا يعدّه حركةً', () async {
      await db.createReceiptVoucher(
        amount: 500,
        category: 'customer_payment',
        partyId: partyId,
        safeId: safeId,
        skipJournalEntry: true,
        skipSafeTransaction: true,
        chequeVoucherSafeId: safeId,
      );
      // `getPartyTransactions` لا يرشّح بالنوع — وهو ما يغذّي كشفَ الحساب.
      final list = await db.getPartyTransactions(partyId);
      expect(list, isEmpty,
          reason: 'السندُ المستنديُّ يظهر سطرَ دفعةٍ ثانيةً بجوار قيد '
              'الترحيل الآليّ للورقة');
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────

Future<int> _seedSafe(AppDatabase db, {required double balance}) async {
  return db.into(db.safes).insert(
        SafesCompanion.insert(
          name: 'الصندوق',
          balance: Value(balance),
          isDefault: const Value(true),
          safeType: const Value('cash'),
        ),
      );
}

Future<int> _seedParty(AppDatabase db, {required double balance}) async {
  return db.into(db.parties).insert(
        PartiesCompanion.insert(
          name: 'عميل القياس',
          isCustomer: const Value(true),
          balance: Value(balance),
        ),
      );
}

Future<void> _seedFiscalYear(AppDatabase db) async {
  final now = DateTime.now();
  await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          name: '${now.year}',
          startDate: DateTime(now.year, 1, 1),
          endDate: DateTime(now.year, 12, 31),
          isClosed: const Value(false),
        ),
      );
}

Future<void> _clear(AppDatabase db) async {
  await db.delete(db.journalEntryLines).go();
  await db.delete(db.journalEntries).go();
  await db.delete(db.safeTransactions).go();
  await db.delete(db.commercialPapers).go();
  await db.delete(db.accountingPeriods).go();
  await db.delete(db.fiscalYears).go();
  await db.delete(db.accountMappings).go();
  await db
      .update(db.safes)
      .write(const SafesCompanion(linkedAccountId: Value(null)));
  await db.delete(db.safes).go();
  await db.delete(db.parties).go();
}
