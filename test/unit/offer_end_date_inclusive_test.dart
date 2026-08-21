// ═══════════════════════════════════════════════════════════════════════════
// العرض كان بيموت الساعة ٠٠:٠٠ من يوم انتهائه — اليوم الأخير كله ضايع.
// ═══════════════════════════════════════════════════════════════════════════
//
// بلاغ مختبِر: «العروض بالنسبة لـx and y والباقة لا تعمل بالشكل الصحيح على
// نقطة البيع / فشلت».
//
// المحرك نفسه سليم: cart_controller.dart:597 فيه switch كامل بالأربع أنواع
// وكل واحد متنفّذ. العطل **قبلهم بمرحلة** — في البوابة اللي كل الأنواع بتعدّي
// منها: `getActiveOffers` بتشترط `endDate >= now`، و`showDatePicker` في
// offer_dialogs.dart:438 بيرجّع **منتصف الليل** وبيتخزّن كما هو.
//
// فعرض تاريخ نهايته «٣١ أغسطس» بيتخزّن 2026-08-31 00:00:00، وأول ما الساعة
// تعدّي منتصف ليل يوم ٣١ بيتشال من القايمة. واليوم الأخير — اللي المستخدم
// فاهم إنه مشمول — بيضيع بالكامل.
//
// والأهم إن المختبِر أول حاجة بيعملها إنه يعمل عرض تجريبي **ينتهي النهاردة**،
// وده ما بيشتغلش ولا مرة أياً كان نوعه. فالعطل الواحد ده بيتقرا كأنه «كل
// أنواع العروض فاشلة».
//
// الإصلاح في الاستعلام لا في الديالوج بقصد: UralCash مطروح وعنده عروض متخزّنة
// بنهايات منتصف ليل بالفعل، فالمقارنة لازم تحترمها من غير هجرة بيانات.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  final now = DateTime.now();
  DateTime dayAt(int offsetDays) =>
      DateTime(now.year, now.month, now.day + offsetDays);

  Future<int> insertOffer({
    required String name,
    DateTime? startDate,
    DateTime? endDate,
    String? barcode,
  }) =>
      db.into(db.offers).insert(OffersCompanion.insert(
            name: name,
            offerPrice: 10,
            startDate: Value(startDate),
            endDate: Value(endDate),
            barcode: Value(barcode),
          ));

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() => db.close());

  group('نهاية العرض شاملة ليوم الانتهاء كله', () {
    test('عرض بينتهي النهاردة لسه فعّال دلوقتي', () async {
      // دي حالة المختبِر بالظبط: عرض اتعمل النهاردة وينتهي النهاردة.
      await insertOffer(name: 'ينتهي اليوم', endDate: dayAt(0));
      final active = await db.getActiveOffers();
      expect(active.map((o) => o.name), contains('ينتهي اليوم'),
          reason: 'كان بيموت ٠٠:٠٠ فما اشتغلش ولا مرة');
    });

    test('عرض بينتهي بكرة فعّال', () async {
      await insertOffer(name: 'ينتهي بكرة', endDate: dayAt(1));
      final active = await db.getActiveOffers();
      expect(active.map((o) => o.name), contains('ينتهي بكرة'));
    });

    test('عرض انتهى إمبارح مش فعّال', () async {
      await insertOffer(name: 'انتهى إمبارح', endDate: dayAt(-1));
      final active = await db.getActiveOffers();
      expect(active.map((o) => o.name), isNot(contains('انتهى إمبارح')),
          reason: 'الإصلاح ما يمدّش العرض ليوم زيادة');
    });

    test('عرض بلا تاريخ نهاية فعّال (سلوك غير متغيّر)', () async {
      await insertOffer(name: 'مفتوح');
      final active = await db.getActiveOffers();
      expect(active.map((o) => o.name), contains('مفتوح'));
    });
  });

  group('بداية العرض', () {
    test('عرض بيبدأ النهاردة فعّال', () async {
      await insertOffer(name: 'يبدأ اليوم', startDate: dayAt(0));
      final active = await db.getActiveOffers();
      expect(active.map((o) => o.name), contains('يبدأ اليوم'));
    });

    test('عرض بيبدأ بكرة مش فعّال', () async {
      await insertOffer(name: 'يبدأ بكرة', startDate: dayAt(1));
      final active = await db.getActiveOffers();
      expect(active.map((o) => o.name), isNot(contains('يبدأ بكرة')));
    });

    test('نافذة يوم واحد: يبدأ وينتهي النهاردة', () async {
      await insertOffer(
          name: 'يوم واحد', startDate: dayAt(0), endDate: dayAt(0));
      final active = await db.getActiveOffers();
      expect(active.map((o) => o.name), contains('يوم واحد'),
          reason: 'أشيع عرض تجريبي على الإطلاق');
    });
  });

  group('watchActiveOffers بيتبع نفس النافذة', () {
    // ده الـstream اللي بتغذّي شاشة العروض وديالوج البيع السريع. اتنسي في أول
    // محاولة إصلاح — الاستعلامان اتصلحوا وهو فضل بيخفي العرض في يومه الأخير.
    test('عرض بينتهي النهاردة بيظهر في الـstream', () async {
      await insertOffer(name: 'stream اليوم', endDate: dayAt(0));
      final emitted = await db.watchActiveOffers().first;
      expect(emitted.map((o) => o.name), contains('stream اليوم'));
    });

    test('عرض انتهى إمبارح ما يظهرش في الـstream', () async {
      await insertOffer(name: 'stream قديم', endDate: dayAt(-1));
      final emitted = await db.watchActiveOffers().first;
      expect(emitted.map((o) => o.name), isNot(contains('stream قديم')));
    });
  });

  group('البحث بالباركود بيتبع نفس النافذة', () {
    test('عرض بينتهي النهاردة بيتلاقى بالباركود', () async {
      await insertOffer(
          name: 'باركود اليوم', endDate: dayAt(0), barcode: 'OFF-1');
      final found = await db.getOfferByBarcode('OFF-1');
      expect(found, isNotNull,
          reason: 'مسح باركود العرض كان بيفشل في يوم انتهائه');
    });

    test('عرض انتهى إمبارح ما يتلاقاش بالباركود', () async {
      await insertOffer(
          name: 'باركود قديم', endDate: dayAt(-1), barcode: 'OFF-2');
      expect(await db.getOfferByBarcode('OFF-2'), isNull);
    });
  });
}
