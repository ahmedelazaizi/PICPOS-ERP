// lib/data/database/daos/bookings_dao.dart
// ---------------------------------------------------------------------------
// BOOKINGS DAO — مواعيدُ الخدمة
// ---------------------------------------------------------------------------

part of '../database.dart';

/// الموظَّفُ مشغولٌ في ذلك المدى.
class BookingConflictException implements Exception {
  final String messageAr;
  BookingConflictException(this.messageAr);
  @override
  String toString() => messageAr;
}

/// الحجزُ حاضرٌ أو مستقبل — لا ماضٍ.
class BookingInPastException implements Exception {
  final String messageAr;
  BookingInPastException(this.messageAr);
  @override
  String toString() => messageAr;
}

extension BookingsDao on AppDatabase {
  /// الحجوزاتُ المتداخلةُ مع مدًى على موظَّفٍ بعينه.
  ///
  /// `excludeBookingId` لازمٌ للتعديل: الحجزُ لا يتعارض مع نفسِه.
  /// و`cancelled`/`no_show` مستثنيان لأنّهما يُفرّغان الوقت.
  /// **قرارُ التداخل يقع في `bookingSlotsOverlap` وحدَها — لا في SQL.**
  ///
  /// الاستعلامُ يضيّق المرشَّحين فقط (نفسُ الموظَّف · حالاتٌ حيّة · نافذةُ
  /// اليوم)، ثم تحكم الدالّةُ الخالصة. ولو كُتب شرطُ التداخل مرّتين — مرّةً
  /// في SQL ومرّةً في دارت — لتباعدا عند أوّل تعديل، ولصار الاختبارُ يشهد
  /// لمصدرٍ غيرِ الذي يعمل في الإنتاج. والمرشَّحون عشراتٌ على الأكثر
  /// (موظَّفٌ واحدٌ في يومٍ واحد) فالكلفةُ مهمَلة.
  Future<List<Booking>> getOverlappingBookings(
    int resourceId,
    DateTime startsAt,
    DateTime endsAt, {
    int? excludeBookingId,
  }) async {
    final windowStart = DateTime(startsAt.year, startsAt.month, startsAt.day);
    final windowEnd = windowStart.add(const Duration(days: 2));

    final query = select(bookings)
      ..where((b) => b.resourceId.equals(resourceId))
      ..where((b) => b.status.isNotIn(['cancelled', 'no_show']))
      ..where((b) => b.startsAt.isBiggerOrEqualValue(windowStart))
      ..where((b) => b.startsAt.isSmallerThanValue(windowEnd));
    if (excludeBookingId != null) {
      query.where((b) => b.id.equals(excludeBookingId).not());
    }

    final candidates = await query.get();
    final target = BookingSlot(startsAt: startsAt, endsAt: endsAt);
    return candidates
        .where((b) => bookingSlotsOverlap(
              target,
              BookingSlot(startsAt: b.startsAt, endsAt: b.endsAt),
            ))
        .toList();
  }

  /// حجوزاتُ مدًى زمنيّ — ونطاقُ الفرع يُحقَن **في الاستعلام** لا في العرض.
  Future<List<Booking>> getBookingsInRange(
    DateTime from,
    DateTime to, {
    List<int>? allowedBranchIds,
  }) {
    final query = select(bookings)
      ..where((b) => b.startsAt.isBiggerOrEqualValue(from))
      ..where((b) => b.startsAt.isSmallerThanValue(to))
      ..orderBy([(b) => OrderingTerm.asc(b.startsAt)]);
    if (allowedBranchIds != null) {
      query.where(
        (b) => b.branchId.isIn(allowedBranchIds) | b.branchId.isNull(),
      );
    }
    return query.get();
  }

  /// ينشئ حجزاً بعد إنفاذ القاعدتين داخل معاملةٍ واحدة.
  ///
  /// SQLite لا يملك قيدَ استبعاد (`EXCLUDE`) كما PostgreSQL، فالإنفاذُ هنا
  /// لا في ودجت — وإلّا مرّ من أيّ مسارٍ آخرَ يكتب حجزاً.
  ///
  /// `now` يُمرَّر صراحةً كي يبقى الاختبارُ حتميّاً.
  Future<int> createBooking({
    required String customerName,
    String? customerPhone,
    int? partyId,
    required int serviceId,
    int? resourceId,
    required DateTime startsAt,
    double depositAmount = 0,
    String? notes,
    int? branchId,
    int? createdBy,
    DateTime? now,
  }) {
    return transaction(() async {
      final currentTime = now ?? DateTime.now();
      if (startsAt.isBefore(currentTime)) {
        throw BookingInPastException(
          'لا يمكن الحجز في الماضي — الحجزُ حاضرٌ أو مستقبل',
        );
      }

      final service = await (select(bookingServices)
            ..where((s) => s.id.equals(serviceId)))
          .getSingle();
      final endsAt = computeBookingEndsAt(
        startsAt,
        service.durationMinutes,
        service.bufferMinutes,
      );

      // حجزٌ بلا موظَّفٍ لا يشارك في الفحص — لا أحدَ يتعارض عليه.
      if (resourceId != null) {
        final clashes =
            await getOverlappingBookings(resourceId, startsAt, endsAt);
        if (clashes.isNotEmpty) {
          throw BookingConflictException(
            'الموظَّفُ مشغولٌ في هذا الوقت — ${clashes.length} حجزٌ متعارض',
          );
        }
      }

      return into(bookings).insert(
        BookingsCompanion.insert(
          customerName: customerName,
          customerPhone: Value(customerPhone),
          partyId: Value(partyId),
          serviceId: serviceId,
          resourceId: Value(resourceId),
          startsAt: startsAt,
          endsAt: endsAt,
          depositAmount: Value(depositAmount),
          notes: Value(notes),
          branchId: Value(branchId),
          createdBy: Value(createdBy),
        ),
      );
    });
  }
}
