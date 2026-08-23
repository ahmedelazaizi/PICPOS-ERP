// تفويترُ الحجز مقابلَ بيعةِ نقطةِ البيع العاديّة — **الفرقُ يُقاس**.
//
// ═══ لماذا يُقاس هذا تحديداً ═══
//
// قرارُ المالك: التفويترُ يمرّ بنقطة البيع لأنّ مسارَ المال كلَّه هناك.
// فالمساران يمرّان **بنفس الشِّفرة**، وأثرُهما المحاسبيُّ مختلف: التفويترُ
// وحدَه يُطفئ التزامَ العربون (مدين `2134` / دائن حساب العميل) ويكتب
// `Bookings.invoiceId`.
//
// وخطأُ التمييز يقع في اتّجاهين، وكلاهما مالٌ:
//   • تطبيقُه على بيعةٍ عاديّة ⇒ يُخصَم من العميل ما لم يدفعه مقدَّماً.
//   • إغفالُه في التفويتر ⇒ يبقى العربونُ في الالتزام ويُحاسَب العميلُ
//     مرّتين — وهو بلاغُ المالك الأصليّ.
//
// ولهذا الحارسُ يقيس **الاتّجاهين** لا الحالةَ السعيدةَ وحدَها، ويقيس أيضاً
// أنّ العلامةَ **تُفرَّغ** بعد استعمالها: قراءةٌ بلا تفريغٍ تجعل البيعةَ
// التالية تُطبِّق نفسَ العربون ثانيةً.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late int serviceId;
  late int partyId;

  setUp(() async {
    db = AppDatabase.forTesting();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    serviceId = await db.into(db.bookingServices).insert(
          BookingServicesCompanion.insert(
            name: 'قصّ شعر',
            price: const Value(500),
          ),
        );
    partyId = await db.insertParty(
      PartiesCompanion.insert(name: 'عميل', isCustomer: const Value(true)),
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<int> makeBooking({double deposit = 300}) => db.createBooking(
        customerName: 'عميل',
        partyId: partyId,
        serviceId: serviceId,
        startsAt: DateTime.now().add(const Duration(days: 1)),
        depositAmount: deposit,
        createdBy: 1,
      );

  Future<int> makeInvoice({double total = 500}) =>
      db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'SINV-X',
              customerId: Value(partyId),
              warehouseId: 1,
              userId: 1,
              invoiceDate: DateTime.now(),
              total: Value(total),
            ),
          );

  Future<double> partyBalance() async =>
      (await (db.select(db.parties)..where((p) => p.id.equals(partyId)))
              .getSingle())
          .balance;

  group('العلامةُ صريحةٌ وتُفرَّغ', () {
    test('الافتراضُ لا حجزَ معلَّق — أي أنّ البيعةَ عاديّةٌ ما لم يُقَل غيرُ ذلك',
        () {
      expect(container.read(bookingInvoicingProvider), isNull);
    });

    test('takeIfAny تقرأ وتُفرِّغ في نفس النداء', () {
      final n = container.read(bookingInvoicingProvider.notifier);
      n.begin(7);
      expect(n.takeIfAny(), 7);
      expect(n.takeIfAny(), isNull,
          reason: 'قراءةٌ بلا تفريغٍ تجعل البيعةَ التالية تُطبِّق نفسَ العربون');
      expect(container.read(bookingInvoicingProvider), isNull);
    });

    test('clear يلغي التفويترَ المعلَّق — للخروج من الشاشة', () {
      final n = container.read(bookingInvoicingProvider.notifier)..begin(9);
      n.clear();
      expect(container.read(bookingInvoicingProvider), isNull,
          reason: 'حجزٌ معلَّقٌ منسيٌّ يلتصق بأوّل بيعةٍ تالية');
    });
  });

  group('الأثرُ المحاسبيُّ يفترق بين المسارين', () {
    test('بيعةٌ عاديّةٌ: لا عربونَ يُخصَم ولا حجزَ يُلمَس', () async {
      final bookingId = await makeBooking();
      final balanceAfterDeposit = await partyBalance();
      final invoiceId = await makeInvoice();

      // لا `begin` — فالبيعةُ عاديّة. ولا يُنادى الخصمُ أصلاً.
      expect(container.read(bookingInvoicingProvider), isNull);

      expect(await partyBalance(), balanceAfterDeposit,
          reason: 'بيعةٌ عابرةٌ لا تُطفئ عربونَ حجزٍ لا علاقةَ لها به');
      final b = await (db.select(db.bookings)
            ..where((x) => x.id.equals(bookingId)))
          .getSingle();
      expect(b.invoiceId, isNull);
      final inv = await db.getSalesInvoiceById(invoiceId);
      expect(inv!.paid, 0);
    });

    test('تفويترُ حجزٍ: العربونُ يُطفأ والحجزُ يُربَط', () async {
      final bookingId = await makeBooking();
      final invoiceId = await makeInvoice();

      container.read(bookingInvoicingProvider.notifier).begin(bookingId);
      final pending =
          container.read(bookingInvoicingProvider.notifier).takeIfAny();
      expect(pending, bookingId);

      await db.applyBookingDepositToInvoice(
        bookingId: pending!,
        invoiceId: invoiceId,
        userId: 1,
      );

      expect(await partyBalance(), -300,
          reason: 'الرصيدُ يتحرّك عند التفويتر — وهذا منعُ الحساب مرّتين');
      final b = await (db.select(db.bookings)
            ..where((x) => x.id.equals(bookingId)))
          .getSingle();
      expect(b.invoiceId, invoiceId);
      final inv = await db.getSalesInvoiceById(invoiceId);
      expect(inv!.paid, 300);
    });

    test('البيعةُ التاليةَ بعد تفويترٍ عاديّةٌ — لا عربونَ ثانٍ', () async {
      final bookingId = await makeBooking();
      final firstInvoice = await makeInvoice();

      final n = container.read(bookingInvoicingProvider.notifier)
        ..begin(bookingId);
      await db.applyBookingDepositToInvoice(
        bookingId: n.takeIfAny()!,
        invoiceId: firstInvoice,
        userId: 1,
      );
      final balanceAfterFirst = await partyBalance();

      // بيعةٌ ثانيةٌ بلا `begin`.
      expect(container.read(bookingInvoicingProvider), isNull);
      expect(await partyBalance(), balanceAfterFirst,
          reason: 'العلامةُ فُرِّغت، فلا يتكرّر الخصم');
    });
  });

  group('الحارسُ قبل فتحِ نقطة البيع', () {
    test('خدمةٌ بلا صنفٍ مربوطٍ تُرفض — ولا يُفتَح الكاشير', () async {
      final bookingId = await makeBooking(deposit: 0);
      await expectLater(
        db.assertBookingInvoiceable(bookingId),
        throwsA(isA<StateError>()),
        reason: 'فتحُ نقطة البيع ثمّ الفشلُ عند الحفظ يترك سلّةً معلّقة',
      );
    });

    test('خدمةٌ مربوطةٌ تُقبَل', () async {
      final productId = await db.into(db.products).insert(
            ProductsCompanion.insert(
              name: 'قصّ شعر',
              code: 'SRV-9',
              productType: const Value('service'),
            ),
          );
      await (db.update(db.bookingServices)
            ..where((s) => s.id.equals(serviceId)))
          .write(BookingServicesCompanion(productId: Value(productId)));

      final bookingId = await makeBooking(deposit: 0);
      await expectLater(db.assertBookingInvoiceable(bookingId), completes);
    });
  });
}
