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
    // نافذةُ المرشَّحين تُضيّق فقط ولا تقرّر — فيجب أن تحوي كلَّ صفٍّ قد
    // تحكم عليه الدالّةُ الخالصةُ بالتداخل.
    //
    // إلى الوراء يوماً كاملاً: حجزٌ يبدأ ٢٣:٥٠ وينتهي ٠٠:٥٠ يعبر منتصفَ
    // الليل، وبدايتُه تقع قبل منتصف ليل اليوم المطلوب — فبدءُ النافذة من
    // منتصف الليل كان يُسقطه قبل أن تراه الدالّة، فيمرّ تعارضٌ صامت.
    // (يفترض أن لا موعدَ يتجاوز ٢٤ ساعة، وهو صحيحٌ لمواعيد الخدمة.)
    //
    // وإلى الأمام حتى `endsAt` وحدَها: ما يبدأ عند نهاية المطلوب أو بعدها
    // لا يمكن أن يتداخل معه — المدى نصفُ مفتوح.
    final windowStart = startsAt.subtract(const Duration(days: 1));
    final windowEnd = endsAt;

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

  /// يبدّل الموظَّفَ أو الوقتَ أو كليهما — **ويُعيد فحصَ التعارض كاملاً**.
  ///
  /// القاعدةُ صيغت بالثلاثيّة `(resourceId, startsAt, endsAt)` لا
  /// بـ«الإسناد» عمداً: **التأجيلُ خطرٌ كالإسناد تماماً** — حجزٌ سليمٌ
  /// يُؤجَّل ساعةً قد يقع فوق حجزٍ آخرَ لنفس الموظَّف. ولو حُصر الفحصُ في
  /// دالّةِ إسنادٍ لمرّ التأجيلُ من جانبها بلا فحص.
  ///
  /// وحجزٌ وُلد بلا موظَّفٍ **لم يُفحَص قطّ**: أوّلُ فحصٍ حقيقيٍّ له يقع
  /// لحظةَ إسناده، فإن غاب هنا لم يقع أبداً.
  ///
  /// `clearResource` يفصل «لا تغيّر الموظَّف» (‏`resourceId: null`) عن
  /// «أعِدْه إلى قائمة الانتظار» — وإلّا استحال التمييز بينهما.
  Future<void> updateBookingSlot(
    int bookingId, {
    int? resourceId,
    bool clearResource = false,
    DateTime? startsAt,
    DateTime? now,
  }) {
    return transaction(() async {
      final currentTime = now ?? DateTime.now();
      final current = await (select(bookings)
            ..where((b) => b.id.equals(bookingId)))
          .getSingle();

      final newResourceId =
          clearResource ? null : (resourceId ?? current.resourceId);
      final newStartsAt = startsAt ?? current.startsAt;

      if (startsAt != null && newStartsAt.isBefore(currentTime)) {
        throw BookingInPastException(
          'لا يمكن تأجيل الحجز إلى الماضي — الحجزُ حاضرٌ أو مستقبل',
        );
      }

      // النهايةُ تُعاد من مدّةِ الخدمة كي يبقى الطولُ صحيحاً بعد التأجيل.
      final service = await (select(bookingServices)
            ..where((s) => s.id.equals(current.serviceId)))
          .getSingle();
      final newEndsAt = computeBookingEndsAt(
        newStartsAt,
        service.durationMinutes,
        service.bufferMinutes,
      );

      if (newResourceId != null) {
        final clashes = await getOverlappingBookings(
          newResourceId,
          newStartsAt,
          newEndsAt,
          excludeBookingId: bookingId, // لا يتعارض مع نفسِه
        );
        if (clashes.isNotEmpty) {
          throw BookingConflictException(
            'الموظَّفُ مشغولٌ في هذا الوقت — ${clashes.length} حجزٌ متعارض',
          );
        }
      }

      await (update(bookings)..where((b) => b.id.equals(bookingId))).write(
        BookingsCompanion(
          resourceId: Value(newResourceId),
          startsAt: Value(newStartsAt),
          endsAt: Value(newEndsAt),
          updatedAt: Value(currentTime),
        ),
      );
    });
  }
}
