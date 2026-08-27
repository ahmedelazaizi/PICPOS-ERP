// v167 / المرحلة ٣ — خصمُ العربون: العميلُ يُرسل الحدثَ ولا يُرحّل قيداً.
//
// ═══ لماذا هذا الموضعُ بالذات ═══
//
// الفئةُ التشغيليّةُ كلُّها مسارٌ واردٌ إلّا هنا: `tables_dao` (٨٤١ سطراً)
// و`kitchen_dao` (٤٢٥) فيهما **صفرُ** استدعاءٍ لـ`createJournalEntry`،
// و`bookings_dao` فيه **واحدٌ** — هذا. فهو الحدثُ الماليُّ الوحيدُ الذي
// يحتاج قالبَ المرحلة ٢ كاملاً.
//
// وقبضُ العربون نفسُه ليس هنا: يمرّ بـ`createReceiptVoucher` وهي مُوجَّهةٌ
// سلفاً عبر `submitSafeTransaction`. المتبقّي هو **إطفاؤه** عند التفويتر.
//
// ═══ 🔴 ولماذا لا يكفي مفتاحُ إزالة التكرار ═══
//
// القيدُ يُزال تكرارُه بـ`(referenceType, referenceId)`، و`referenceId` هنا
// رقمُ الحجز **المحلّيّ** — وهو يخالف رقمَه على الخادم بالتصميم. فلو رحّل
// الطرفان لصار قيدان يبدوان مختلفَين، ورصيدُ العميل منقوصاً **ضِعفَ**
// العربون. ولا يكشف ذلك إلّا مصالحةُ ذمم.
//
// ═══ والعربونُ التزامٌ لا إيراد ═══
//
// مقابلُه `2134`، والقيدُ «مدين الالتزام / دائن حساب العميل» — بلا حركةِ
// نقدٍ ثانيةٍ ألبتّة: النقدُ دخل الخزنةَ لحظةَ الحجز، وتكرارُه يضخّم الدرج.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/sync_interceptor.dart';

class _RecordingClient implements SyncInterceptor {
  final List<Map<String, dynamic>> deposits = [];

  @override
  bool get isClientModeImpl => true;

  @override
  bool get isMirrorModeImpl => false;

  @override
  Future<void> submitBookingDepositApplication(
      Map<String, dynamic> req) async {
    deposits.add(req);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late AppDatabase db;
  late int serviceId;
  late int partyId;
  late int bookingId;
  late int invoiceId;

  Future<Booking> booking() async =>
      (db.select(db.bookings)..where((b) => b.id.equals(bookingId)))
          .getSingle();

  Future<int> journalCount() async =>
      (await db.select(db.journalEntries).get()).length;

  Future<double> partyBalance() async =>
      (await (db.select(db.parties)..where((p) => p.id.equals(partyId)))
              .getSingle())
          .balance;

  setUp(() async {
    // ⚠️ التجهيزةُ كلُّها في الوضع المستقلّ عمداً. قبضُ العربون يمرّ
    //    بـ`createReceiptVoucher` وهي مُوجَّهةٌ في وضع العميل، فإنشاءُ الحجز
    //    تحت عميلٍ وهميٍّ كان يترك التجهيزةَ بلا قيدِ قبضٍ أصلاً — فيمرّ
    //    فحصُ «لم يُرحَّل شيء» أخضرَ وهو لا يقيس شيئاً.
    SyncInterceptor.instance = null;
    db = AppDatabase.forTesting();

    serviceId = await db.into(db.bookingServices).insert(
          BookingServicesCompanion.insert(
            name: 'قصّ شعر',
            price: const Value(100),
          ),
        );
    // `insertParty` لا `into(parties).insert`: الأولى وحدَها تُنشئ حسابَ
    // العميل الفرعيَّ وتربطه بـ`parties.accountId`. وطرفٌ بلا حسابٍ يرفضه
    // خصمُ العربون صراحةً.
    partyId = await db.insertParty(
      PartiesCompanion.insert(name: 'عميل الحجز', isCustomer: const Value(true)),
    );

    bookingId = await db.createBooking(
      customerName: 'عميل الحجز',
      partyId: partyId,
      serviceId: serviceId,
      startsAt: DateTime.now().add(const Duration(days: 1)),
      depositAmount: 300,
      createdBy: 1,
    );

    invoiceId = await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: 'SINV-BK',
            customerId: Value(partyId),
            warehouseId: 1,
            userId: 1,
            invoiceDate: DateTime.now(),
            total: const Value(500),
            globalId: const Value('inv-gid-1'),
          ),
        );
  });

  tearDown(() async {
    SyncInterceptor.instance = null;
    await db.close();
  });

  test('الحجزُ يحمل هويّةً عند إنشائه', () async {
    expect((await booking()).globalId, isNotNull,
        reason: 'حجزٌ بلا هويّةٍ لا يُدعى على الخادم، فخصمُ عربونه يُنفَّذ '
            'محلّيّاً — وهو التفاوتُ نفسُه.');
  });

  group('خصمٌ من عميل', () {
    late _RecordingClient client;
    late int journalsBefore;
    late double balanceBefore;

    setUp(() async {
      // القياسُ **بعدَ** التجهيزة: قبضُ العربون كتب قيداً بالفعل، فالمقارنةُ
      // بصفرٍ كانت ستفشل لسببٍ خاطئ.
      journalsBefore = await journalCount();
      balanceBefore = await partyBalance();
      client = _RecordingClient();
      SyncInterceptor.instance = client;
    });

    test('🔴 لا قيدَ يُرحَّل محلّيّاً', () async {
      await db.applyBookingDepositToInvoice(
          bookingId: bookingId, invoiceId: invoiceId, userId: 1);

      expect(await journalCount(), journalsBefore,
          reason: 'العميلُ رحّل القيدَ ⇒ الخادمُ سيرحّله ثانيةً، ومفتاحُ '
              '`(referenceType, referenceId)` لا يمسكهما: الرقمُ محلّيٌّ '
              'ويخالف رقمَ الخادم. النتيجةُ رصيدُ عميلٍ منقوصٌ مرّتين.');
    });

    test('🔴 ولا رصيدَ عميلٍ يتحرّك', () async {
      await db.applyBookingDepositToInvoice(
          bookingId: bookingId, invoiceId: invoiceId, userId: 1);

      expect(await partyBalance(), balanceBefore,
          reason: 'تحريكُ الرصيد محلّيّاً ثمّ عودتُه بالدلتا يخصمه مرّتين.');
    });

    test('🔴 ولا فاتورةَ تتقدّم مدفوعاً ولا حجزَ يُختَم', () async {
      await db.applyBookingDepositToInvoice(
          bookingId: bookingId, invoiceId: invoiceId, userId: 1);

      final inv = await db.getSalesInvoiceById(invoiceId);
      expect(inv!.paid, 0,
          reason: 'تقديمُ المدفوع محلّيّاً يمنع إعادةَ المحاولة لو رُدَّ '
              'الطلب، ويُظهر فاتورةً مسدَّدةً بمالٍ لم يصل الدفاتر.');
      expect((await booking()).invoiceId, isNull,
          reason: '`invoiceId` هو حارسُ عدمِ التكرار على الخادم. كتابتُه '
              'محلّيّاً تجعل إعادةَ الإرسال تبدو مكرَّرةً فتُسقَط، فيضيع '
              'الخصمُ نهائيّاً.');
    });

    test('والحدثُ أُرسل بالهويّتين لا بالرقمين', () async {
      await db.applyBookingDepositToInvoice(
          bookingId: bookingId, invoiceId: invoiceId, userId: 7);

      expect(client.deposits, hasLength(1));
      final req = client.deposits.single;
      expect(req['bookingGlobalId'], (await booking()).globalId,
          reason: 'رقمٌ محلّيٌّ يصل الخادمَ قد يطابق حجزاً آخرَ فيُطفئ '
              'عربونَ عميلٍ غيرِه على فاتورةِ غيرِه.');
      expect(req['invoiceGlobalId'], 'inv-gid-1');
      expect(req['userId'], 7);
    });

    test('وحجزٌ بلا هويّةٍ يفشل صريحاً لا صامتاً', () async {
      await (db.update(db.bookings)..where((b) => b.id.equals(bookingId)))
          .write(const BookingsCompanion(globalId: Value(null)));

      await expectLater(
        db.applyBookingDepositToInvoice(
            bookingId: bookingId, invoiceId: invoiceId, userId: 1),
        throwsA(isA<StateError>()),
        reason: 'التمريرُ الصامتُ يعني تنفيذاً محلّيّاً — أي عينَ التفاوت '
            'الذي تسدّه المرحلة.',
      );
      expect(client.deposits, isEmpty);
      expect(await journalCount(), journalsBefore);
    });

    test('وفاتورةٌ بلا هويّةٍ كذلك', () async {
      await (db.update(db.salesInvoices)..where((i) => i.id.equals(invoiceId)))
          .write(const SalesInvoicesCompanion(globalId: Value(null)));

      await expectLater(
        db.applyBookingDepositToInvoice(
            bookingId: bookingId, invoiceId: invoiceId, userId: 1),
        throwsA(isA<StateError>()),
      );
      expect(client.deposits, isEmpty);
    });
  });

  group('⚓ مرساة: الوضعُ المستقلُّ ما زال يُطفئ الالتزامَ فعلاً', () {
    // بلا هذه المجموعةِ يمرّ كلُّ فحصٍ أعلاه أخضرَ لو كانت التجهيزةُ لا
    // تُرحّل أصلاً — «لم يُرحَّل» يُشبه «مُنِع» تماماً.

    test('القيدُ يُكتَب والرصيدُ ينقص والفاتورةُ تتقدّم', () async {
      final journalsBefore = await journalCount();
      final balanceBefore = await partyBalance();

      await db.applyBookingDepositToInvoice(
          bookingId: bookingId, invoiceId: invoiceId, userId: 1);

      expect(await journalCount(), journalsBefore + 1,
          reason: 'المستقلُّ لا يُرحّل ⇒ فحصُ المنعِ أعلاه بلا معنى.');
      expect(await partyBalance(), balanceBefore - 300);

      final inv = await db.getSalesInvoiceById(invoiceId);
      expect(inv!.paid, 300);
      expect(inv.status, 'partial');
      expect((await booking()).invoiceId, invoiceId);
    });

    test('والقيدُ مدين `2134` / دائن حساب العميل — لا إيراد', () async {
      await db.applyBookingDepositToInvoice(
          bookingId: bookingId, invoiceId: invoiceId, userId: 1);

      final advances = (await db.getAccountByCode('2134'))!;
      final lines = await (db.select(db.journalEntryLines)
            ..where((l) => l.accountId.equals(advances.id)))
          .get();
      var dr = 0.0, cr = 0.0;
      for (final l in lines) {
        dr += l.debit;
        cr += l.credit;
      }
      expect(cr, 300, reason: 'قبضُ العربون');
      expect(dr, 300, reason: 'إطفاؤه عند التفويتر — فيصير صافيه صفراً');
    });
  });
}
