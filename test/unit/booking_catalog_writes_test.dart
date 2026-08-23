// إدارةُ الخدمات والموارد — وربطُ الخدمة بصنف.
//
// ═══ العطبُ الذي وُلدت منه (بلاغُ المالك 2026-08-23) ═══
//
// «ازاى هربط الخدمة بمورد او جهاز». والقياسُ كشف ما هو أوسعُ من السؤال:
// الجداولُ مشحونةٌ والشاشةُ تقرأ، و**لا موضعَ واحدٌ في المستودع يكتب** خدمةً
// أو مورداً. فلا سبيلَ لتعريف أيٍّ منهما إلّا بالكتابة في القاعدة مباشرةً —
// أي أنّ الحجوزاتِ كلَّها كانت غيرَ قابلةٍ للاستعمال عمليّاً.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  Future<int> serviceProduct({String code = 'SRV-1'}) =>
      db.into(db.products).insert(
            ProductsCompanion.insert(
              name: 'خدمة قصّ',
              code: code,
              productType: const Value('service'),
            ),
          );

  Future<int> stockProduct({String code = 'ITM-1'}) =>
      db.into(db.products).insert(
            ProductsCompanion.insert(name: 'شامبو', code: code),
          );

  group('الخدمات', () {
    test('تُنشأ ثمّ تُعدَّل بنفس المعرِّف', () async {
      final id = await db.upsertBookingService(
        name: 'قصّ شعر',
        durationMinutes: 45,
        bufferMinutes: 10,
        price: 120,
        colorHex: '#0250D3',
      );
      final again = await db.upsertBookingService(
        id: id,
        name: 'قصّ شعر رجالي',
        durationMinutes: 30,
        bufferMinutes: 5,
        price: 150,
        colorHex: '#0250D3',
      );
      expect(again, id, reason: 'التعديلُ لا يُنشئ صفّاً ثانياً');

      final row = await (db.select(db.bookingServices)
            ..where((s) => s.id.equals(id)))
          .getSingle();
      expect(row.name, 'قصّ شعر رجالي');
      expect(row.durationMinutes, 30);
      expect(row.price, 150);
    });

    test('مدّةٌ صفرٌ أو سالبةٌ تُرفَض', () async {
      await expectLater(
        db.upsertBookingService(
            name: 'x',
            durationMinutes: 0,
            bufferMinutes: 0,
            price: 1,
            colorHex: '#000000'),
        throwsA(isA<ArgumentError>()),
        reason: 'مدّةٌ صفرٌ تجعل نهايةَ الحجز = بدايتَه فلا يتعارض مع شيء',
      );
    });

    // ═══ الربطُ — جوهرُ سؤال المالك ═══
    test('تُربَط بصنفٍ من نوع «خدمة» فتصير قابلةً للتفويتر', () async {
      final pid = await serviceProduct();
      final sid = await db.upsertBookingService(
        name: 'قصّ شعر',
        durationMinutes: 45,
        bufferMinutes: 0,
        price: 120,
        colorHex: '#0250D3',
        productId: pid,
      );
      final bookingId = await db.createBooking(
        customerName: 'ع',
        serviceId: sid,
        startsAt: DateTime.now().add(const Duration(days: 1)),
      );
      await expectLater(db.assertBookingInvoiceable(bookingId), completes,
          reason: 'الربطُ هو ما يفتح بابَ التفويتر');
    });

    test('ربطٌ بصنفٍ مخزونيٍّ يُرفَض ويُسمّى السبب', () async {
      final pid = await stockProduct();
      await expectLater(
        db.upsertBookingService(
          name: 'قصّ شعر',
          durationMinutes: 45,
          bufferMinutes: 0,
          price: 120,
          colorHex: '#0250D3',
          productId: pid,
        ),
        throwsA(predicate(
          (e) => e.toString().contains('خدمة'),
          'يقول إنّ الصنفَ ليس خدميّاً',
        )),
        reason: 'ربطٌ بصنفٍ مخزونيٍّ يجعل التفويترَ يخصم من المخزون شيئاً '
            'لا يُخزَّن',
      );
    });

    test('ربطٌ بصنفٍ غيرِ موجودٍ يُرفَض', () async {
      await expectLater(
        db.upsertBookingService(
            name: 'x',
            durationMinutes: 10,
            bufferMinutes: 0,
            price: 1,
            colorHex: '#000000',
            productId: 99999),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('الحذفُ يُرفَض ما دام عليها حجزٌ قائم', () async {
      final sid = await db.upsertBookingService(
          name: 'قصّ',
          durationMinutes: 30,
          bufferMinutes: 0,
          price: 50,
          colorHex: '#000000');
      await db.createBooking(
        customerName: 'ع',
        serviceId: sid,
        startsAt: DateTime.now().add(const Duration(days: 1)),
      );
      await expectLater(
        db.softDeleteBookingService(sid),
        throwsA(isA<StateError>()),
        reason: 'حذفُها يترك حجزاً حيّاً يشير إلى خدمةٍ مخفيّةٍ فيُعرَض بلا اسم',
      );
    });

    test('والحذفُ يمرّ بعد إلغاء الحجز', () async {
      final sid = await db.upsertBookingService(
          name: 'قصّ',
          durationMinutes: 30,
          bufferMinutes: 0,
          price: 50,
          colorHex: '#000000');
      final bid = await db.createBooking(
        customerName: 'ع',
        serviceId: sid,
        startsAt: DateTime.now().add(const Duration(days: 1)),
      );
      await db.setBookingStatus(bid, 'cancelled');
      await expectLater(db.softDeleteBookingService(sid), completes);
    });
  });

  group('الموارد', () {
    test('موظَّفٌ وجهازٌ كلاهما يُقبَل', () async {
      await expectLater(
        db.upsertBookingResource(
            name: 'محمد', kind: 'staff', colorHex: '#0250D3'),
        completes,
      );
      await expectLater(
        db.upsertBookingResource(
            name: 'كابينة الليزر', kind: 'device', colorHex: '#EF4444'),
        completes,
      );
    });

    test('نوعٌ ثالثٌ يُرفَض', () async {
      await expectLater(
        db.upsertBookingResource(
            name: 'x', kind: 'robot', colorHex: '#000000'),
        throwsA(isA<ArgumentError>()),
        reason: 'القيدُ في الجدول يرفضه — ويُقال هنا برسالةٍ مفهومةٍ بدل '
            'استثناءِ SQL',
      );
    });

    test('ورديّةٌ خارجَ اليوم تُرفَض', () async {
      await expectLater(
        db.upsertBookingResource(
          name: 'x',
          kind: 'staff',
          colorHex: '#000000',
          shiftStartMinutes: -1,
        ),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        db.upsertBookingResource(
          name: 'y',
          kind: 'staff',
          colorHex: '#000000',
          shiftEndMinutes: 1441,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('الحذفُ يُرفَض ما دام عليه حجزٌ قائم', () async {
      final rid = await db.upsertBookingResource(
          name: 'محمد', kind: 'staff', colorHex: '#000000');
      final sid = await db.upsertBookingService(
          name: 'قصّ',
          durationMinutes: 30,
          bufferMinutes: 0,
          price: 50,
          colorHex: '#000000');
      await db.createBooking(
        customerName: 'ع',
        serviceId: sid,
        resourceId: rid,
        startsAt: DateTime.now().add(const Duration(days: 1)),
      );
      await expectLater(
        db.softDeleteBookingResource(rid),
        throwsA(isA<StateError>()),
      );
    });
  });
}
