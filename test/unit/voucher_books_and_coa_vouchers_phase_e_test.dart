// المرحلة هـ — E2 + E3: دفاترُ السندات، وطرفا السند من دليل الحسابات.
//
// ‏E3 — الدفتر: الورقةُ التالية تُقترَح، وما خرج عن المدى يُرفَض، والمكرَّرُ
//       يُرفَض، والورقةُ الملغاةُ محروقةٌ لا تُقترَح ولا تُقبَل، والصفوفُ
//       تعبر المزامنةَ بأعمدتها.
// ‏E2 — المستفيدُ أيُّ حسابٍ تفصيليّ: القيدُ يقع عليه؛ وحسابُ الطرف يُردّ إلى
//       الطرف فيتحرّك رصيدُه وكشفُه كما اليوم؛ وخزينةٌ ليست خزنةً = تحويلٌ
//       محاسبيٌّ بلا حركة خزنة.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/models/document_record.dart';
import 'package:picpos_erp/domain/models/voucher_book.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';

void main() {
  late AppDatabase db;
  late int safeId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await _clear(db);
    await db.syncDefaultAccounts();
    await _seedFiscalYear(db);
    safeId = await db.into(db.safes).insert(SafesCompanion.insert(
          name: 'الصندوق',
          balance: const Value(1000),
          isDefault: const Value(true),
          safeType: const Value('cash'),
        ));
  });

  tearDown(() => db.close());

  Future<int> account(String code, {String type = 'asset'}) =>
      db.into(db.accounts).insert(AccountsCompanion.insert(
            code: code,
            name: 'حساب $code',
            accountType: type,
            accountNature: const Value('detail'),
            isSystem: const Value(false),
          ));

  Future<double> safeBalance() async =>
      (await (db.select(db.safes)..where((s) => s.id.equals(safeId)))
              .getSingle())
          .balance;

  Future<List<JournalEntryLine>> jeLines(String refType, int refId) async {
    final je = await (db.select(db.journalEntries)
          ..where((j) =>
              j.referenceType.equals(refType) & j.referenceId.equals(refId)))
        .getSingle();
    return (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(je.id)))
        .get();
  }

  Future<int> cashReceiptRow() => db.createReceiptVoucher(
        amount: 10,
        category: 'other',
        safeId: safeId,
      );

  // ═══════════════════════════════════════════════════════════════════
  // E3 — دفاترُ السندات
  // ═══════════════════════════════════════════════════════════════════
  group('E3 — دفاتر السندات', () {
    test('الورقةُ التالية تُقترَح وتتقدّم بعد الختم', () async {
      final book =
          await db.createVoucherBook(type: 'receipt', rangeFrom: 101, rangeTo: 105);
      expect(await db.suggestNextVoucherBookNumber(book), 101);

      final txn = await cashReceiptRow();
      await db.assignVoucherBookLeaf(txnId: txn, bookId: book, number: 101);
      expect(await db.getVoucherBookLeafOf(txn), (bookId: book, number: 101));
      expect(await db.suggestNextVoucherBookNumber(book), 102);
      expect((await db.getVoucherBook(book))!.remaining, 4);
    });

    test('خارجَ المدى يُرفَض', () async {
      final book =
          await db.createVoucherBook(type: 'receipt', rangeFrom: 101, rangeTo: 105);
      expect(() => db.validateVoucherBookLeaf(book, 100),
          throwsA(isA<VoucherBookException>()));
      expect(() => db.validateVoucherBookLeaf(book, 106),
          throwsA(isA<VoucherBookException>()));
      final txn = await cashReceiptRow();
      await expectLater(
          db.assignVoucherBookLeaf(txnId: txn, bookId: book, number: 200),
          throwsA(isA<VoucherBookException>()));
      expect(await db.getVoucherBookLeafOf(txn), isNull,
          reason: 'ورقةٌ مرفوضةٌ لا تُختَم على السند');
    });

    test('🔴 المكرَّرُ يُرفَض — ورقةٌ واحدةٌ لسندٍ واحد', () async {
      final book =
          await db.createVoucherBook(type: 'receipt', rangeFrom: 1, rangeTo: 50);
      final a = await cashReceiptRow();
      final b = await cashReceiptRow();
      await db.assignVoucherBookLeaf(txnId: a, bookId: book, number: 7);
      await expectLater(
          db.assignVoucherBookLeaf(txnId: b, bookId: book, number: 7),
          throwsA(isA<VoucherBookException>()));
    });

    test('الورقةُ الملغاةُ محروقة: لا تُقترَح ولا تُقبَل', () async {
      final book =
          await db.createVoucherBook(type: 'payment', rangeFrom: 1, rangeTo: 3);
      await db.cancelVoucherBookLeaf(bookId: book, number: 1, reason: 'تالفة');
      expect(await db.suggestNextVoucherBookNumber(book), 2);
      expect(() => db.validateVoucherBookLeaf(book, 1),
          throwsA(isA<VoucherBookException>()));
      final leaves = await db.listCancelledVoucherLeaves(book);
      expect(leaves.single.number, 1);
      expect(leaves.single.reason, 'تالفة');
      // إلغاءُ ورقةٍ مرّتين يُرفَض أيضاً.
      await expectLater(
          db.cancelVoucherBookLeaf(bookId: book, number: 1, reason: 'x'),
          throwsA(isA<VoucherBookException>()));
    });

    test('الدفترُ المستنفَد يُغلَق، والمدى المتداخلُ يُرفَض', () async {
      final book =
          await db.createVoucherBook(type: 'receipt', rangeFrom: 1, rangeTo: 2);
      await db.cancelVoucherBookLeaf(bookId: book, number: 1, reason: 'r');
      await db.cancelVoucherBookLeaf(bookId: book, number: 2, reason: 'r');
      expect((await db.getVoucherBook(book))!.status, 'closed');
      await expectLater(
          db.createVoucherBook(type: 'receipt', rangeFrom: 2, rangeTo: 9),
          throwsA(isA<VoucherBookException>()));
      // نوعٌ آخرُ بنفس المدى جائز.
      expect(
          await db.createVoucherBook(type: 'payment', rangeFrom: 1, rangeTo: 2),
          greaterThan(0));
    });

    test('الدفترُ الافتراضيُّ دفترُ المستخدم', () async {
      await db.createVoucherBook(type: 'receipt', rangeFrom: 1, rangeTo: 9);
      final mine = await db.createVoucherBook(
          type: 'receipt', rangeFrom: 10, rangeTo: 19, holderUserId: 42);
      expect((await db.defaultVoucherBookFor(type: 'receipt', userId: 42))!.id,
          mine);
    });

    test('أعمدةُ المزامنة الخمسة على الجدولَين (إثباتُ وقت التشغيل)',
        () async {
      for (final t in ['voucher_books', 'voucher_book_leaves_cancelled']) {
        final cols = {
          for (final r
              in await db.customSelect('PRAGMA table_info($t)').get())
            r.data['name'] as String,
        };
        expect(
            cols,
            containsAll(const [
              'global_id',
              'last_modified_at',
              'deleted_at',
              'origin_client_id',
              'row_version',
            ]),
            reason: '$t بلا أعمدة الدلتا لا يُسحَب');
      }
    });

    test('المزامنة: الجداولُ في قوائم السحب، والصفوفُ تعبر بأعمدتها',
        () async {
      for (final t in ['voucher_books', 'voucher_book_leaves_cancelled']) {
        expect(DeltaPullService.pullTables, contains(t));
        expect(DeltaPullService.branchScopedPullTables, contains(t));
        expect(DeltaPullService.deltaOnlyTables, contains(t));
      }
      expect(DeltaPullService.pullTables.indexOf('voucher_books'),
          lessThan(DeltaPullService.pullTables
              .indexOf('voucher_book_leaves_cancelled')),
          reason: 'الدفترُ قبل أوراقه — `_upsertRow` يكتب بالترتيب');

      final book = await db.createVoucherBook(
          type: 'receipt', rangeFrom: 1, rangeTo: 9, prefix: 'R-');
      await db.cancelVoucherBookLeaf(bookId: book, number: 3, reason: 'تالفة');
      final txn = await cashReceiptRow();
      await db.assignVoucherBookLeaf(txnId: txn, bookId: book, number: 1);

      // صورةُ ما يرسله الخادمُ بـ`SELECT *` ويكتبه `_upsertRow` بـ
      // `INSERT OR REPLACE` على جهازٍ آخر.
      final other = AppDatabase.forTesting();
      addTearDown(other.close);
      await other.customSelect('SELECT 1').get(); // يفتح ويُنشئ المخطَّط
      for (final table in ['voucher_books', 'voucher_book_leaves_cancelled']) {
        final rows = await db.customSelect('SELECT * FROM $table').get();
        for (final r in rows) {
          final cols = r.data.keys.toList();
          await other.customStatement(
            'INSERT OR REPLACE INTO $table (${cols.join(', ')}) '
            'VALUES (${List.filled(cols.length, '?').join(', ')})',
            [for (final c in cols) r.data[c]],
          );
        }
      }
      final mirrored = await other.listVoucherBooks(type: 'receipt');
      expect(mirrored.single.prefix, 'R-');
      expect(mirrored.single.rangeTo, 9);
      expect((await other.listCancelledVoucherLeaves(book)).single.number, 3);
      final gid = await db.customSelect(
          'SELECT global_id FROM voucher_books WHERE id = ?',
          variables: [Variable<int>(book)]).getSingle();
      expect(gid.data['global_id'], isNotNull,
          reason: 'بلا معرّفٍ عامٍّ لا يلتقي صفّا الجهازين');

      final txnRow = await db.customSelect(
          'SELECT * FROM safe_transactions WHERE id = ?',
          variables: [Variable<int>(txn)]).getSingle();
      expect(txnRow.data['book_id'], book,
          reason: 'عمودُ الدفتر يركب صفَّ السند في السحب العامّ');
      expect(txnRow.data['book_number'], 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // E4 — الشيكُ يُنشأ من سند القبض ويُستعلَم في «إدارة الشيكات»
  // ═══════════════════════════════════════════════════════════════════
  group('E4 — شيكٌ من سند القبض', () {
    test('يظهر في الاستعلام بسنده، وإجراءاتُ الحالة تُرحِّل', () async {
      final partyId = await db.into(db.parties).insert(PartiesCompanion.insert(
            name: 'عميل الشيك',
            isCustomer: const Value(true),
          ));
      // مسارُ شاشة سند القبض بطريقة «شيكات»: صفُّ سندٍ مستنديّ ثمّ الورقة.
      final voucherId = await db.createReceiptVoucher(
        amount: 400,
        category: 'customer_payment',
        partyId: partyId,
        skipJournalEntry: true,
        skipSafeTransaction: true,
        chequeVoucherSafeId: safeId,
      );
      final paperId = await db.createCommercialPaper(
        paperNumber: 'CH-900',
        type: 'cheque',
        direction: 'received',
        partyId: partyId,
        amount: 400,
        issueDate: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 30)),
        bankName: 'بنك',
        notes: 'ترحيل تلقائي من سند قبض | الساحب: أحمد',
        sourceVoucherId: voucherId,
      );

      final papers = await db.select(db.commercialPapers).get();
      final paper = papers.singleWhere((p) => p.id == paperId);
      expect(paper.sourceVoucherId, voucherId,
          reason: 'الاستعلامُ يسمّي سندَ الورقة');
      expect(paper.status, 'pending');

      // التحصيلُ يودع في خزنةٍ بنكيّة — كما في الإنتاج.
      await db.into(db.safes).insert(SafesCompanion.insert(
            name: 'البنك',
            safeType: const Value('bank'),
          ));
      final jeBefore = await db.select(db.journalEntries).get();
      final user = await (db.select(db.users)..limit(1)).getSingle();
      await db.changePaperStatus(
          paperId: paperId, newStatus: 'deposited', changedBy: user.id);
      await db.changePaperStatus(
          paperId: paperId, newStatus: 'cashed', changedBy: user.id);
      final after = await (db.select(db.commercialPapers)
            ..where((p) => p.id.equals(paperId)))
          .getSingle();
      expect(after.status, 'cashed');
      final jeAfter = await db.select(db.journalEntries).get();
      expect(jeAfter.length, greaterThan(jeBefore.length),
          reason: 'إجراءُ الحالة على شاشة الشيكات ما زال يُرحِّل قيدَه');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // E2 — طرفا السند من دليل الحسابات
  // ═══════════════════════════════════════════════════════════════════
  group('E2 — المستفيد والخزينة من الدليل', () {
    test('مستفيدٌ بحسابٍ عامّ: القيدُ يقع عليه والخزنةُ تتحرّك', () async {
      final income = await account('4777', type: 'revenue');
      final txn = await db.createReceiptVoucher(
        amount: 250,
        category: 'other',
        safeId: safeId,
        linkedAccountId: income,
      );
      final lines = await jeLines('receipt_voucher', txn);
      expect(lines.firstWhere((l) => l.accountId == income).credit, 250);
      expect(await safeBalance(), 1250);
    });

    test('صرفٌ لمستفيدٍ بحسابٍ عامّ يقيّده مديناً', () async {
      final expense = await account('5777', type: 'expense');
      final txn = await db.createPaymentVoucher(
        amount: 80,
        category: 'other',
        safeId: safeId,
        linkedAccountId: expense,
      );
      final lines = await jeLines('payment_voucher', txn);
      expect(lines.firstWhere((l) => l.accountId == expense).debit, 80);
      expect(await safeBalance(), 920);
    });

    test('🔴 خزينةٌ ليست خزنة: تحويلٌ محاسبيٌّ بلا حركة خزنة', () async {
      final clearing = await account('1199');
      final other = await account('2199', type: 'liability');
      expect(await db.safeIdForAccount(clearing), isNull);

      final txn = await db.createAccountTransferVoucher(
        isReceipt: true,
        amount: 300,
        treasuryAccountId: clearing,
        beneficiaryAccountId: other,
        category: 'other',
        documentSafeId: safeId,
      );
      expect(await safeBalance(), 1000, reason: 'لا حركةَ على أيّ خزنة');
      final row = await (db.select(db.safeTransactions)
            ..where((t) => t.id.equals(txn)))
          .getSingle();
      expect(row.transactionType, kAccountTransferReceiptTxnType);
      expect(row.balanceAfter, 1000);
      final lines = await jeLines('receipt_voucher', txn);
      expect(lines.firstWhere((l) => l.accountId == clearing).debit, 300);
      expect(lines.firstWhere((l) => l.accountId == other).credit, 300);
      final stored = await db.customSelect(
          'SELECT treasury_account_id FROM safe_transactions WHERE id = ?',
          variables: [Variable<int>(txn)]).getSingle();
      expect(stored.data['treasury_account_id'], clearing);

      final records = await db
          .watchVoucherRecords(direction: VoucherDirection.receipt)
          .first;
      expect(records.single.isAccountTransfer, isTrue,
          reason: 'السجلُّ يعرض التحويلَ موسوماً');
    });

    test('🔴 حسابُ طرفٍ: الطرفُ يُستعاد ورصيدُه وكشفُه يتحرّكان', () async {
      final ar = await account('1219');
      final partyId = await db.into(db.parties).insert(PartiesCompanion.insert(
            name: 'عميل الحساب',
            isCustomer: const Value(true),
            accountId: Value(ar),
          ));
      expect(await db.partyIdForAccount(ar), partyId);
      final options = await db.voucherAccountOptions();
      expect(options.firstWhere((o) => o.id == ar).partyId, partyId);

      final clearing = await account('1198');
      final txn = await db.createAccountTransferVoucher(
        isReceipt: true,
        amount: 120,
        treasuryAccountId: clearing,
        partyId: partyId,
        category: 'customer_payment',
        documentSafeId: safeId,
      );
      final party = await (db.select(db.parties)
            ..where((p) => p.id.equals(partyId)))
          .getSingle();
      expect(party.balance, -120, reason: 'رصيدُ الطرف كما يحرّكه سندُ النقد');
      final lines = await jeLines('receipt_voucher', txn);
      expect(lines.firstWhere((l) => l.accountId == ar).credit, 120,
          reason: 'القيدُ على حساب الطرف نفسِه');

      final statement = await db.getPartyStatement(partyId);
      final entry = statement.where((e) => e.referenceId == txn).single;
      expect(entry.credit, 120, reason: 'كشفُ العميل يُظهر التحويلَ دائناً');
      expect(entry.entryType, 'receipt');
    });

    test('حسابُ خزنةٍ يُردّ إلى خزنته', () async {
      final cash = await account('1197');
      await (db.update(db.safes)..where((s) => s.id.equals(safeId)))
          .write(SafesCompanion(linkedAccountId: Value(cash)));
      expect(await db.safeIdForAccount(cash), safeId);
      final options = await db.voucherAccountOptions(safeIds: {safeId});
      expect(options.firstWhere((o) => o.id == cash).safeId, safeId);
    });
  });
}

Future<void> _seedFiscalYear(AppDatabase db) async {
  final now = DateTime.now();
  await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(
        name: '${now.year}',
        startDate: DateTime(now.year, 1, 1),
        endDate: DateTime(now.year, 12, 31),
        isClosed: const Value(false),
      ));
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
