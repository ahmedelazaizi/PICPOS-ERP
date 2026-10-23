// العربونُ مالٌ حقيقيّ — قرارُ المالك 2026-08-22 (‏ق-٢) و2026-08-23.
//
// ── العطبُ الذي وُلدت منه ──────────────────────────────────────────────────
// ‏`depositAmount` كان عموداً يُذكَر في سجلّ النشاط فقط: **لا حركةَ خزنةٍ ولا
// قيدٌ محاسبيّ**. فمن دفع ٣٠٠ عربوناً: النقدُ في الدرج، ورصيدُ الخزنة لا
// يعرف، والدفاترُ لا تعرف. وعند التفويتر لا يُخصَم فيُحاسَب العميلُ مرّتين.
//
// ── والقراران اللذان يشكّلان التصميم ───────────────────────────────────────
// ‏١) المقابلُ **حسابُ التزامٍ** `2134 عملاء - دفعات مقدمة` لا إيراد. والإيرادُ
//    يُعترَف به عند التفويتر لا عند القبض.
// ‏٢) (‏قرارُ المالك 2026-08-23) العربونُ **لا يحرّك رصيدَ العميل**: يقعد في
//    حساب الالتزام حتى التفويتر، وحينها يُخصَم (مدين 2134 / دائن حساب
//    العميل). وتحريكُ الرصيد عند القبض **وأيضاً** إقفالُ 2134 عند التفويتر
//    كان سيعدّ الدفعةَ مرّتين.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int serviceId;
  late int partyId;

  /// حسابُ الالتزام — يُقرأ بالكود لا بالرقم المحفوظ: معرّفاتُ الصفوف تتبدّل
  /// بترتيب الزرع، والكودُ هو العقدُ الثابت.
  Future<Account> advancesAccount() async =>
      (await db.getAccountByCode('2134'))!;

  Future<Account> partyArAccount(int id) async {
    final p = await (db.select(db.parties)..where((x) => x.id.equals(id)))
        .getSingle();
    return (await db.getAccountById(p.accountId!))!;
  }

  /// مجموعُ الحركة على حسابٍ بعينه عبر كلّ القيود.
  Future<({double debit, double credit})> movementOn(int accountId) async {
    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.accountId.equals(accountId)))
        .get();
    var dr = 0.0, cr = 0.0;
    for (final l in lines) {
      dr += l.debit;
      cr += l.credit;
    }
    return (debit: dr, credit: cr);
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    serviceId = await db.into(db.bookingServices).insert(
          BookingServicesCompanion.insert(
            name: 'قصّ شعر',
            price: const Value(100),
          ),
        );
    // ⚠️ ‏`insertParty` لا `into(parties).insert`: الأولى وحدَها تُنشئ حسابَ
    // العميل الفرعيَّ (`1121-xxxxx`) وتربطه بـ`parties.accountId`. وطرفٌ بلا
    // حسابٍ لا يقبل قيداً — وهو ما يرفضه خصمُ العربون صراحةً.
    partyId = await db.insertParty(
      PartiesCompanion.insert(name: 'عميل الحجز', isCustomer: const Value(true)),
    );
  });

  tearDown(() => db.close());

  Future<int> book({double deposit = 0}) => db.createBooking(
        customerName: 'عميل الحجز',
        partyId: partyId,
        serviceId: serviceId,
        startsAt: DateTime.now().add(const Duration(days: 1)),
        depositAmount: deposit,
        createdBy: 1,
      );

  group('أخذُ العربون يُنشئ مالاً حقيقيّاً', () {
    test('حجزٌ بلا عربونٍ لا يحرّك خزنةً ولا يكتب قيداً', () async {
      await book();
      expect(await db.select(db.safeTransactions).get(), isEmpty);
      expect(await db.select(db.journalEntries).get(), isEmpty);
    });

    test('حجزٌ بعربونٍ يُنشئ سندَ قبضٍ ويزيد الخزنة', () async {
      await book(deposit: 300);

      final txns = await db.select(db.safeTransactions).get();
      expect(txns, hasLength(1),
          reason: 'العربونُ نقدٌ دخل الدرجَ فعلاً — لا سطرَ سجلٍّ وحدَه');
      expect(txns.single.transactionType, 'receipt');
      expect(txns.single.amount, 300);
      expect(txns.single.partyId, partyId,
          reason: 'يُنسَب للعميل للتتبّع ولو لم يحرّك رصيدَه');
    });

    test('المقابلُ حسابُ التزامٍ لا إيراد', () async {
      await book(deposit: 300);

      final advances = await advancesAccount();
      final m = await movementOn(advances.id);
      expect(m.credit, 300,
          reason: 'الالتزامُ يُدان بالعربون — والإيرادُ يُعترَف عند التفويتر');
      expect(m.debit, 0);

      // ولا يقع على أيّ حسابِ إيرادٍ (٤xxx).
      final revenueLines = await db.customSelect(
        "SELECT COALESCE(SUM(l.credit),0) AS c FROM journal_entry_lines l "
        "JOIN accounts a ON a.id = l.account_id WHERE a.code LIKE '4%'",
      ).getSingle();
      expect(revenueLines.data['c'], 0,
          reason: 'قبضُ عربونٍ ليس بيعاً — الاعترافُ بالإيراد هنا يضخّمه');
    });

    test('رصيدُ العميل لا يتحرّك عند القبض (قرارُ المالك)', () async {
      await book(deposit: 300);
      final p = await (db.select(db.parties)..where((x) => x.id.equals(partyId)))
          .getSingle();
      expect(p.balance, 0,
          reason: 'العربونُ في حساب الالتزام — وتحريكُ الرصيد هنا يعدّه مرّتين');
    });

    test('القيدُ متوازن', () async {
      await book(deposit: 300);
      final lines = await db.select(db.journalEntryLines).get();
      var dr = 0.0, cr = 0.0;
      for (final l in lines) {
        dr += l.debit;
        cr += l.credit;
      }
      expect(dr, closeTo(cr, 0.001));
      expect(dr, 300);
    });

    test('فشلُ ترحيلِ العربون يُسقط الحجزَ معه — لا حجزَ بمالٍ ضائع', () async {
      // لا خزنةَ صالحةً ⇒ سندُ القبض يرمي ⇒ المعاملةُ كلُّها تتراجع.
      await (db.delete(db.safes)).go();
      await expectLater(book(deposit: 300), throwsA(anything));
      expect(await db.select(db.bookings).get(), isEmpty,
          reason: 'حجزٌ نجح وعربونُه فشل يترك مالاً مقبوضاً بلا أثر');
    });
  });

  group('التفويترُ يُطفئ الالتزامَ ولا يحاسب مرّتين', () {
    Future<int> makeInvoice(double total) => db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: 'SINV-BK',
            customerId: Value(partyId),
            warehouseId: 1,
            userId: 1,
            invoiceDate: DateTime.now(),
            total: Value(total),
          ),
        );

    test('الخصمُ: مدين الالتزام / دائن حساب العميل', () async {
      final bookingId = await book(deposit: 300);
      final invoiceId = await makeInvoice(500);

      await db.applyBookingDepositToInvoice(
        bookingId: bookingId,
        invoiceId: invoiceId,
        userId: 1,
      );

      final advances = await advancesAccount();
      final m = await movementOn(advances.id);
      expect(m.credit, 300, reason: 'قبضُ العربون');
      expect(m.debit, 300, reason: 'إطفاؤه عند التفويتر — فيصير صافيه صفراً');

      final ar = await partyArAccount(partyId);
      final arM = await movementOn(ar.id);
      expect(arM.credit, 300,
          reason: 'العميلُ يُدفَع عنه بالعربون — وهذا هو منعُ الحساب مرّتين');
    });

    test('الفاتورةُ تتقدّم مدفوعاً ورصيدُ العميل ينقص الآن', () async {
      final bookingId = await book(deposit: 300);
      final invoiceId = await makeInvoice(500);
      await db.applyBookingDepositToInvoice(
          bookingId: bookingId, invoiceId: invoiceId, userId: 1);

      final inv = await db.getSalesInvoiceById(invoiceId);
      expect(inv!.paid, 300);
      expect(inv.status, 'partial');

      final p = await (db.select(db.parties)..where((x) => x.id.equals(partyId)))
          .getSingle();
      expect(p.balance, -300,
          reason: 'الرصيدُ يتحرّك **الآن** لا عند القبض');
    });

    test('يُكتب invoiceId على الحجز', () async {
      final bookingId = await book(deposit: 300);
      final invoiceId = await makeInvoice(500);
      await db.applyBookingDepositToInvoice(
          bookingId: bookingId, invoiceId: invoiceId, userId: 1);

      final b = await (db.select(db.bookings)
            ..where((x) => x.id.equals(bookingId)))
          .getSingle();
      expect(b.invoiceId, invoiceId,
          reason: 'بدونه لا يُعرَف أنّ الحجزَ فُوتِر — فيُطبَّق العربونُ ثانيةً');
    });

    test('لا يُطبَّق مرّتين', () async {
      final bookingId = await book(deposit: 300);
      final invoiceId = await makeInvoice(500);
      await db.applyBookingDepositToInvoice(
          bookingId: bookingId, invoiceId: invoiceId, userId: 1);

      await expectLater(
        db.applyBookingDepositToInvoice(
            bookingId: bookingId, invoiceId: invoiceId, userId: 1),
        throwsA(anything),
        reason: 'إعادةُ التطبيق تُطفئ التزاماً غيرَ قائمٍ وتُنقص دَيناً مرّتين',
      );
    });
  });

  group('خدمةٌ بلا صنفٍ مربوطٍ لا تُفوتَر', () {
    test('الخدمةُ غيرُ المربوطةِ تُرفَض بسببٍ مسمّى', () async {
      final bookingId = await book(deposit: 0);
      await expectLater(
        db.assertBookingInvoiceable(bookingId),
        throwsA(predicate(
            (e) => e.toString().contains('صنف'),
            'يسمّي السببَ: الخدمةُ بلا صنفٍ مربوط')),
      );
    });

    test('الخدمةُ المربوطةُ بصنفِ خدمةٍ تُقبَل', () async {
      final productId = await db.into(db.products).insert(
            ProductsCompanion.insert(
              name: 'قصّ شعر',
              code: 'SRV-1',
              productType: const Value('service'),
            ),
          );
      await (db.update(db.bookingServices)
            ..where((s) => s.id.equals(serviceId)))
          .write(BookingServicesCompanion(productId: Value(productId)));

      final bookingId = await book(deposit: 0);
      await expectLater(db.assertBookingInvoiceable(bookingId), completes);
    });
  });
}
