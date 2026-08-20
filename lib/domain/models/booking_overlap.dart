//
// حسابُ تداخلِ المواعيد — خالصٌ بلا قاعدةِ بيانات.
//
// موضعُه `domain/models` لأنّ حارسَ المستودع يفرض أن تعيش الحساباتُ الخالصة
// هناك، ولأنّ اختبارَه حينئذٍ لا يحتاج `AppDatabase` ولا مؤقّتات drift.

/// مدًى زمنيٌّ نصفُ مفتوح: `[startsAt, endsAt)`.
class BookingSlot {
  final DateTime startsAt;
  final DateTime endsAt;

  const BookingSlot({required this.startsAt, required this.endsAt});
}

/// هل يتداخل المدَيان؟
///
/// نصفُ مفتوحٍ عمداً: موعدٌ ينتهي 11:00 وآخرُ يبدأ 11:00 **لا يتعارضان** —
/// وإلّا استحال رصفُ المواعيد بلا فجوات.
bool bookingSlotsOverlap(BookingSlot a, BookingSlot b) =>
    a.startsAt.isBefore(b.endsAt) && b.startsAt.isBefore(a.endsAt);

/// نهايةُ الموعد = البداية + المدّة + فترةِ التنظيف.
///
/// فترةُ التنظيف تدخل **النهايةَ المخزَّنة** لا المقارنةَ وحدَها، فيسري
/// أثرُها على كلّ استعلامٍ بلا أن يتذكّرها أحد.
DateTime computeBookingEndsAt(
  DateTime startsAt,
  int durationMinutes,
  int bufferMinutes,
) =>
    startsAt.add(Duration(minutes: durationMinutes + bufferMinutes));
