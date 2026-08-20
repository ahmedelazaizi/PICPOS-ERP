import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/booking_overlap.dart';

BookingSlot slot(int startHour, int endHour) => BookingSlot(
      startsAt: DateTime(2026, 8, 20, startHour),
      endsAt: DateTime(2026, 8, 20, endHour),
    );

void main() {
  group('bookingSlotsOverlap', () {
    test('التلاصقُ ليس تداخلاً — المدى نصفُ مفتوح [start, end)', () {
      expect(bookingSlotsOverlap(slot(10, 11), slot(11, 12)), isFalse);
      expect(bookingSlotsOverlap(slot(11, 12), slot(10, 11)), isFalse);
    });

    test('تداخلٌ جزئيّ', () {
      expect(bookingSlotsOverlap(slot(10, 12), slot(11, 13)), isTrue);
      expect(bookingSlotsOverlap(slot(11, 13), slot(10, 12)), isTrue);
    });

    test('احتواءٌ كامل', () {
      expect(bookingSlotsOverlap(slot(10, 14), slot(11, 12)), isTrue);
      expect(bookingSlotsOverlap(slot(11, 12), slot(10, 14)), isTrue);
    });

    test('انفصالٌ تامّ', () {
      expect(bookingSlotsOverlap(slot(10, 11), slot(13, 14)), isFalse);
    });

    test('تطابقٌ تامّ', () {
      expect(bookingSlotsOverlap(slot(10, 11), slot(10, 11)), isTrue);
    });
  });

  group('computeBookingEndsAt', () {
    test('المدّةُ وحدَها بلا فترةِ تنظيف', () {
      expect(
        computeBookingEndsAt(DateTime(2026, 8, 20, 10), 45, 0),
        DateTime(2026, 8, 20, 10, 45),
      );
    });

    test('فترةُ التنظيف تُضاف إلى النهاية فتدخل المقارنة', () {
      expect(
        computeBookingEndsAt(DateTime(2026, 8, 20, 10), 45, 15),
        DateTime(2026, 8, 20, 11),
      );
    });
  });
}
