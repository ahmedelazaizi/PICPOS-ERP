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

/// الحالتان اللتان **تُفرّغان** الوقت — وما عداهما حيٌّ يشغل الموظَّف.
///
/// مصدرٌ واحدٌ لاستعلامِ التعارض ولـ`setBookingStatus` معاً: لو كُتبت
/// القائمةُ في الموضعين لافترقتا عند أوّل قيمةٍ تُضاف، فإمّا صار الإحياءُ
/// لا يُفحَص وإمّا صار الاستعلامُ يعدّ المفرَّغَ مشغولاً.
const List<String> kBookingFreeingStatuses = ['cancelled', 'no_show'];

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
      ..where((b) => b.status.isNotIn(kBookingFreeingStatuses))
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
  ///
  /// **الترشيحُ على `startsAt` وحدَها — لا على التداخل.** فحجزٌ يبدأ ٢٣:٥٠
  /// وينتهي ٠٠:٥٠ يظهر في يومِه ولا يظهر في مدى اليوم التالي. وهي دلالةٌ
  /// مقصودةٌ («ما يبدأ في هذا المدى») تكفي القوائمَ وبطاقاتِ «الحجوزات
  /// القادمة»؛ ومَن أراد تقويماً يوميّاً يعرض «ما **يشغل** هذا اليوم» يحتاج
  /// دلالةَ تداخلٍ صريحةً (`startsAt < to && endsAt > from`) — وذاك تغييرٌ
  /// واعٍ في المستدعي لا تصحيحُ خطأٍ هنا.
  /// (يثبّتها `test/unit/bookings_range_scope_test.dart`.)
  Future<List<Booking>> getBookingsInRange(
    DateTime from,
    DateTime to, {
    List<int>? allowedBranchIds,
  }) {
    final query = select(bookings)
      ..where((b) => b.startsAt.isBiggerOrEqualValue(from))
      ..where((b) => b.startsAt.isSmallerThanValue(to))
      ..orderBy([(b) => OrderingTerm.asc(b.startsAt)]);

    // نفسُ عقدِ نطاقِ الفرع في المستودع كلِّه (`sales_dao.getSalesInvoices`
    // و`purchase_dao`)، ثلاثيُّ الحالات: معدومٌ = وصولٌ كامل · **فارغٌ =
    // يفشل مغلقاً** · `{ids}` = تلك الفروعُ أو صفوفُ الفرعِ المعدوم.
    //
    // والحالةُ الفارغةُ هي بيتُ القصيد: لو بقي `| branchId.isNull()` فيها
    // لرأى مَن لا فرعَ له كلَّ حجزٍ فرعُه معدوم — وفي تنصيبٍ بفرعٍ واحدٍ
    // ذلك **كلُّ** الحجوزات، فتُعرَض «لا وصول» على أنّها «الكلّ».
    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        query.where((b) => b.branchId.isIn(const <int>[]));
      } else {
        query.where(
          (b) => b.branchId.isIn(allowedBranchIds) | b.branchId.isNull(),
        );
      }
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
  /// القاعدةُ صيغت بالرباعيّة `(resourceId, startsAt, endsAt, status)` لا
  /// بـ«الإسناد» عمداً: **التأجيلُ خطرٌ كالإسناد تماماً** — حجزٌ سليمٌ
  /// يُؤجَّل ساعةً قد يقع فوق حجزٍ آخرَ لنفس الموظَّف. ولو حُصر الفحصُ في
  /// دالّةِ إسنادٍ لمرّ التأجيلُ من جانبها بلا فحص.
  ///
  /// **و`status` حقلٌ رابعٌ ذو أثرٍ على التعارض لا ثلاثةٌ فحسب**: استعلامُ
  /// التعارض يستثني `cancelled` و`no_show`، فالانتقالُ إليهما **أو منهما**
  /// يبدّل شَغلَ الوقت. الانتقالُ إليهما يُفرّغ فلا يحتاج فحصاً؛ و**الإحياءُ
  /// منهما يشغل** فيحتاجه، ومحلُّه `setBookingStatus` أدناه. ولا تُكتب
  /// الحالةُ بـ`update(bookings).write(...)` الخام من أيّ مسارٍ آخر —
  /// ذاك يتجاوز الفحصَ بالبناء.
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

      // الطولُ **المخزَّنُ** هو ما يجب أن يبقى صحيحاً — لا مدّةُ الخدمة
      // اليوم. فالصفُّ ينتقل كتلةً واحدةً بطولِه كما وُلد.
      //
      // ولو أُعيد اشتقاقُ النهاية من `service.durationMinutes` هنا لعاد
      // **الأثرُ الرجعيُّ** الذي وُجد تخزينُ `endsAt` أصلاً لمنعه (§٥) — ومن
      // أكثرِ المسارات استعمالاً: قصُّ شعرٍ ٤٥+١٥ محجوزٌ ١٠:٠٠–١١:٠٠، ثم
      // يقصّر المالكُ الخدمةَ إلى ٣٠ بعد شهور، ثم ينقل المضيفُ الحجزَ من
      // أحمدَ إلى ريم **بلا تغيير وقت** — فيصير الصفُّ ١٠:٠٠–١٠:٣٠ صامتاً
      // ويُفتح ١٠:٣٠–١١:٠٠ للحجز والموظَّفةُ ما تزال تعمل. ولو طالت المدّةُ
      // بدل أن تقصر لرُمي `BookingConflictException` كاذبٌ يقول للمضيف إنّ
      // الموظَّفَ مشغولٌ بلا سببٍ ظاهر.
      //
      // و`createBooking` تشتقّ من الخدمة — وذاك صحيحٌ لحجزٍ **جديد**: هناك
      // لا طولَ مخزَّناً بعدُ، ومدّةُ الخدمة اليومَ هي مصدرُ الحقيقة. لا
      // تُوحَّد الدالّتان.
      final newEndsAt =
          newStartsAt.add(current.endsAt.difference(current.startsAt));

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

  /// يبدّل حالةَ الحجز — **والإحياءُ يُعيد فحصَ التعارض داخل نفس المعاملة**.
  ///
  /// `status` هو الحقلُ الرابعُ ذو الأثر على التعارض: استعلامُ التداخل
  /// يستثني `cancelled` و`no_show` (`kBookingFreeingStatuses`)، فالانتقالُ
  /// **من** إحداهما إلى حالةٍ حيّةٍ يُعيد شَغلَ وقتٍ كان قد فُرِّغ.
  ///
  /// والتسريبُ الملموس: حجزُ «أ» على الموظَّف R في ١٠:٠٠ يُلغى، فيُنشأ
  /// حجزُ «ب» على R في ١٠:٠٠ **بحقّ** (اختبارٌ يثبّت جوازَه). ثم يتراجع
  /// أحدُهم عن الإلغاء — أو يقلب `no_show` إلى `confirmed`، وهو ما تنصّ
  /// عليه §٦ صراحةً — فيحمل R حجزين حيَّين متداخلين ولم يجرِ فحصٌ قطّ.
  ///
  /// والاتّجاهُ المعاكس — إلى `cancelled`/`no_show` — **يُفرّغ** فحسب فلا
  /// يحتاج فحصاً ولا يرمي أبداً.
  ///
  /// وهذه هي الدالّةُ التي تُكتب منها الحالة: `update(bookings).write(...)`
  /// الخامُّ يتجاوز الفحصَ بالبناء.
  ///
  /// (`cancelledAt` و`cancelReason` لا تُكتبان هنا عمداً: حوارُ الإلغاء
  /// بمخارجه الثلاثة — ردٌّ · مصادرةٌ · تأجيل — مشروعُ العربون ٣، وهو
  /// صاحبُ السببِ والوقت.)
  Future<void> setBookingStatus(
    int bookingId,
    String status, {
    DateTime? now,
  }) {
    return transaction(() async {
      final currentTime = now ?? DateTime.now();
      final current = await (select(bookings)
            ..where((b) => b.id.equals(bookingId)))
          .getSingle();

      final wasFreeing = kBookingFreeingStatuses.contains(current.status);
      final becomesFreeing = kBookingFreeingStatuses.contains(status);

      // إحياءٌ: كان مفرَّغاً فصار حيّاً. والوقتُ الذي أُفرغ ربّما شُغل في
      // الأثناء. وحجزٌ بلا موظَّفٍ لا يشارك في الفحص كعادته.
      if (wasFreeing && !becomesFreeing && current.resourceId != null) {
        final clashes = await getOverlappingBookings(
          current.resourceId!,
          current.startsAt,
          current.endsAt,
          excludeBookingId: bookingId, // لا يتعارض مع نفسِه
        );
        if (clashes.isNotEmpty) {
          throw BookingConflictException(
            'تعذّرت إعادةُ الحجز — الوقتُ شُغل بعد إلغائه: '
            '${clashes.length} حجزٌ متعارض',
          );
        }
      }

      await (update(bookings)..where((b) => b.id.equals(bookingId))).write(
        BookingsCompanion(
          status: Value(status),
          updatedAt: Value(currentTime),
        ),
      );
    });
  }
}
