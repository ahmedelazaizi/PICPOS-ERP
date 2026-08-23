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

  /// لوحةُ الحجوزات **حيّةً** — كلُّ حجزٍ موصولٌ بخدمته ومورده.
  ///
  /// ═══ لماذا `watch` لا `get` ═══
  ///
  /// اللوحةُ تعرض «الآن»: حجزٌ يُنشأ من جهازٍ آخرَ أو حالةٌ تتبدّل من نافذةٍ
  /// أخرى يجب أن تظهر بلا أن يُحدِّث أحدٌ بيده. وهو نفسُ الدرسِ المقيسِ في
  /// قائمة الفواتير (2026-08-23) حيث كان التحديثُ يقع بيدِ المستخدم وحدَه.
  ///
  /// ═══ والوصلُ يساريٌّ عن قصد ═══
  ///
  /// حجزٌ بلا موردٍ مسموحٌ (لا أحدَ يتعارض عليه)، ووصلٌ داخليٌّ كان
  /// **يُسقطه من اللوحة صامتاً** — فيختفي موعدٌ قائمٌ لأنّ أحداً لم يُسنِده
  /// لموظَّف. والخدمةُ مطلوبةٌ بالمخطّط فوصلُها داخليٌّ بلا خطر.
  ///
  /// ونطاقُ الفرع بنفس عقد [getBookingsInRange] الثلاثيّ: معدومٌ = وصولٌ
  /// كامل · فارغٌ = يفشل مغلقاً · `{ids}` = تلك الفروعُ أو الفرعُ المعدوم.
  Stream<List<BookingBoardRow>> watchBookingsBoard(
    DateTime from,
    DateTime to, {
    List<int>? allowedBranchIds,
  }) {
    final query = select(bookings).join([
      innerJoin(
        bookingServices,
        bookingServices.id.equalsExp(bookings.serviceId),
      ),
      leftOuterJoin(
        bookingResources,
        bookingResources.id.equalsExp(bookings.resourceId),
      ),
    ])
      ..where(bookings.startsAt.isBiggerOrEqualValue(from))
      ..where(bookings.startsAt.isSmallerThanValue(to))
      ..orderBy([OrderingTerm.asc(bookings.startsAt)]);

    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        query.where(bookings.branchId.isIn(const <int>[]));
      } else {
        query.where(
          bookings.branchId.isIn(allowedBranchIds) |
              bookings.branchId.isNull(),
        );
      }
    }

    return query.watch().map((rows) {
      return rows.map((row) {
        final b = row.readTable(bookings);
        final s = row.readTable(bookingServices);
        final r = row.readTableOrNull(bookingResources);
        return BookingBoardRow(
          id: b.id,
          startsAt: b.startsAt,
          endsAt: b.endsAt,
          customerName: b.customerName,
          customerPhone: b.customerPhone,
          partyId: b.partyId,
          invoiceId: b.invoiceId,
          notes: b.notes,
          status: b.status,
          depositAmount: b.depositAmount,
          depositStatus: b.depositStatus,
          serviceId: s.id,
          serviceName: s.name,
          serviceColorHex: s.colorHex,
          servicePrice: s.price,
          resourceId: r?.id,
          resourceName: r?.name,
          resourceRole: r?.role,
          resourceKind: r?.kind,
          resourceColorHex: r?.colorHex,
        );
      }).toList();
    });
  }

  /// عملاءُ الحجوزات مُجمَّعين — زياراتٌ وإنفاقٌ وآخرُ زيارةٍ وخدمةٌ مفضَّلة.
  ///
  /// ═══ التجميعُ على الهاتف لا على الاسم ═══
  ///
  /// الاسمُ يُكتب مرّتين بهجاءٍ مختلفٍ («أحمد محمد» و«احمد محمد») فينقسم
  /// العميلُ الواحدُ صفَّين، ورقمُ الهاتف هو ما يكتبه الموظَّفُ ثابتاً.
  /// ومن لا هاتفَ له يُجمَّع على اسمه — أهونُ من إسقاطه.
  ///
  /// ⚠️ **والملغى والمتخلّفُ ليسا زيارة**: عدُّهما يضخّم ولاءَ العميل ويرفعه
  /// فئةً لم يبلغها، وهي نفسُ قاعدةِ `occupiesTime` في اللوحة.
  Stream<List<BookingCustomerRow>> watchBookingCustomers({
    List<int>? allowedBranchIds,
  }) {
    final query = select(bookings).join([
      innerJoin(
        bookingServices,
        bookingServices.id.equalsExp(bookings.serviceId),
      ),
    ])
      ..where(bookings.status.isNotIn(const ['cancelled', 'no_show']));

    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        query.where(bookings.branchId.isIn(const <int>[]));
      } else {
        query.where(
          bookings.branchId.isIn(allowedBranchIds) |
              bookings.branchId.isNull(),
        );
      }
    }

    return query.watch().map((rows) {
      final byKey = <String, _CustomerAgg>{};
      for (final row in rows) {
        final b = row.readTable(bookings);
        final s = row.readTable(bookingServices);
        final key = (b.customerPhone?.trim().isNotEmpty ?? false)
            ? 'p:${b.customerPhone!.trim()}'
            : 'n:${b.customerName.trim()}';
        final agg = byKey.putIfAbsent(
          key,
          () => _CustomerAgg(b.customerName, b.customerPhone, b.partyId),
        );
        agg.add(s.name, s.price, b.startsAt);
      }

      final out = byKey.values.map((a) => a.toRow()).toList()
        // الأكثرُ إنفاقاً أوّلاً — وهو ترتيبُ التصميم.
        ..sort((x, y) => y.spend.compareTo(x.spend));
      return out;
    });
  }

  /// تذكيراتُ الحجوزات — مع اسمِ العميل وموعدِه.
  ///
  /// ⚠️ الحالاتُ `scheduled` · `opened` · `dismissed` — **لا `sent`**. رابطُ
  /// `wa.me` يفتح واتساب برسالةٍ مُعبّأةٍ ولا يُثبت إرسالاً، فتسميةُ
  /// «أُرسلت» ادّعاءٌ لا يملكه التطبيق.
  Stream<List<BookingReminderRow>> watchBookingReminders({
    List<int>? allowedBranchIds,
  }) {
    final query = select(bookingReminders).join([
      innerJoin(bookings, bookings.id.equalsExp(bookingReminders.bookingId)),
      innerJoin(
        bookingServices,
        bookingServices.id.equalsExp(bookings.serviceId),
      ),
    ])
      ..where(bookingReminders.deletedAt.isNull())
      ..orderBy([OrderingTerm.asc(bookingReminders.scheduledAt)]);

    if (allowedBranchIds != null) {
      if (allowedBranchIds.isEmpty) {
        query.where(bookings.branchId.isIn(const <int>[]));
      } else {
        query.where(
          bookings.branchId.isIn(allowedBranchIds) |
              bookings.branchId.isNull(),
        );
      }
    }

    return query.watch().map((rows) => rows.map((row) {
          final rem = row.readTable(bookingReminders);
          final b = row.readTable(bookings);
          final s = row.readTable(bookingServices);
          return BookingReminderRow(
            id: rem.id,
            bookingId: b.id,
            customerName: b.customerName,
            customerPhone: b.customerPhone,
            serviceName: s.name,
            bookingStartsAt: b.startsAt,
            scheduledAt: rem.scheduledAt,
            channel: rem.channel,
            state: rem.state,
            offsetMinutes: rem.offsetMinutes,
          );
        }).toList());
  }

  // ════════════════════ إدارةُ الخدمات والموارد ════════════════════
  //
  // ⚠️ **كانت غائبةً تماماً** حتى بلاغِ المالك 2026-08-23 «ازاى هربط الخدمة
  // بمورد او جهاز». الجداولُ مشحونةٌ والشاشةُ تقرأ، ولا موضعَ واحدٌ في
  // المستودع **يكتب** خدمةً أو مورداً. فلا سبيلَ لتعريف أيٍّ منهما إلّا
  // بالكتابة المباشرة في القاعدة — أي أنّ الحجوزاتِ كلَّها غيرُ قابلةٍ
  // للاستعمال عمليّاً.

  /// يُنشئ خدمةً أو يعدّلها. `id` معدومٌ ⇒ إنشاء.
  ///
  /// و[productId] هو ما يجعل حجوزَها **قابلةً للتفويتر**
  /// (‏`assertBookingInvoiceable`) — ويجب أن يشير إلى صنفٍ من نوع `service`.
  Future<int> upsertBookingService({
    int? id,
    required String name,
    required int durationMinutes,
    required int bufferMinutes,
    required double price,
    required String colorHex,
    int? productId,
    bool isActive = true,
  }) async {
    if (durationMinutes <= 0) {
      throw ArgumentError('مدّة الخدمة يجب أن تكون أكبر من صفر');
    }
    if (bufferMinutes < 0) throw ArgumentError('الفاصل لا يكون سالباً');
    if (price < 0) throw ArgumentError('السعر لا يكون سالباً');

    // ⚠️ يُتحقَّق من **نوع** الصنف لا وجودِه فحسب: ربطُ خدمةٍ بصنفٍ مخزونيٍّ
    // يجعل تفويترَها يخصم من المخزون شيئاً لا يُخزَّن.
    if (productId != null) {
      final p = await (select(products)..where((x) => x.id.equals(productId)))
          .getSingleOrNull();
      if (p == null) throw ArgumentError('الصنف المختار غير موجود');
      if (p.productType != 'service') {
        throw ArgumentError(
          'الصنف «${p.name}» ليس من نوع «خدمة» — اختر صنفاً خدميّاً، وإلّا '
          'خصم تفويترُ الحجز من المخزون صنفاً لا يُخزَّن.',
        );
      }
    }

    final companion = BookingServicesCompanion(
      id: id == null ? const Value.absent() : Value(id),
      name: Value(name.trim()),
      durationMinutes: Value(durationMinutes),
      bufferMinutes: Value(bufferMinutes),
      price: Value(price),
      colorHex: Value(colorHex),
      productId: Value(productId),
      isActive: Value(isActive),
    );

    if (id == null) return into(bookingServices).insert(companion);
    await (update(bookingServices)..where((s) => s.id.equals(id)))
        .write(companion);
    return id;
  }

  /// يُنشئ مورداً (موظَّفاً أو جهازاً) أو يعدّله.
  ///
  /// والورديّةُ **دقائقُ من منتصف الليل** — والقيدُ في الجدول يرفض ما خرج
  /// عن المدى، فيُتحقَّق هنا برسالةٍ مفهومةٍ بدل استثناءِ SQL.
  Future<int> upsertBookingResource({
    int? id,
    required String name,
    String? role,
    required String kind,
    required String colorHex,
    int? shiftStartMinutes,
    int? shiftEndMinutes,
    String? phone,
    bool isActive = true,
  }) async {
    if (kind != 'staff' && kind != 'device') {
      throw ArgumentError('نوع المورد يكون «موظَّف» أو «جهاز»');
    }
    for (final m in [shiftStartMinutes, shiftEndMinutes]) {
      if (m != null && (m < 0 || m > 1440)) {
        throw ArgumentError('وقت الورديّة خارج اليوم');
      }
    }

    final companion = BookingResourcesCompanion(
      id: id == null ? const Value.absent() : Value(id),
      name: Value(name.trim()),
      role: Value(role?.trim().isEmpty ?? true ? null : role!.trim()),
      kind: Value(kind),
      colorHex: Value(colorHex),
      shiftStartMinutes: Value(shiftStartMinutes),
      shiftEndMinutes: Value(shiftEndMinutes),
      phone: Value(phone?.trim().isEmpty ?? true ? null : phone!.trim()),
      isActive: Value(isActive),
    );

    if (id == null) return into(bookingResources).insert(companion);
    await (update(bookingResources)..where((r) => r.id.equals(id)))
        .write(companion);
    return id;
  }

  /// حذفٌ منطقيٌّ لخدمة — **ويُرفَض إن كانت مستعملةً في حجزٍ قائم**.
  ///
  /// الحذفُ الصلبُ كان سيكسر المفتاحَ الأجنبيّ لحجوزٍ ماضية، والحذفُ المنطقيُّ
  /// بلا فحصٍ يترك حجزاً حيّاً يشير إلى خدمةٍ مخفيّةٍ فيُعرَض بلا اسم.
  Future<void> softDeleteBookingService(int id, {DateTime? now}) async {
    final live = await (select(bookings)
          ..where((b) =>
              b.serviceId.equals(id) &
              b.status.isNotIn(const ['cancelled', 'no_show', 'completed']))
          ..limit(1))
        .getSingleOrNull();
    if (live != null) {
      throw StateError(
        'لا يمكن حذف الخدمة: عليها حجزٌ قائم. ألغِ الحجزَ أو أكمِله أوّلاً.',
      );
    }
    await (update(bookingServices)..where((s) => s.id.equals(id)))
        .write(BookingServicesCompanion(deletedAt: Value(now ?? DateTime.now())));
  }

  /// حذفٌ منطقيٌّ لمورد — بنفس الحارس.
  Future<void> softDeleteBookingResource(int id, {DateTime? now}) async {
    final live = await (select(bookings)
          ..where((b) =>
              b.resourceId.equals(id) &
              b.status.isNotIn(const ['cancelled', 'no_show', 'completed']))
          ..limit(1))
        .getSingleOrNull();
    if (live != null) {
      throw StateError(
        'لا يمكن حذف المورد: عليه حجزٌ قائم. انقل الحجزَ أو ألغِه أوّلاً.',
      );
    }
    await (update(bookingResources)..where((r) => r.id.equals(id)))
        .write(
            BookingResourcesCompanion(deletedAt: Value(now ?? DateTime.now())));
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
  }) async {
    final newBookingId = await transaction(() async {
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

      final bookingId = await into(bookings).insert(
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

      // ── العربونُ مالٌ حقيقيّ (‏ق-٢، قرارُ المالك 2026-08-22) ────────────
      // كان عموداً يُذكَر في سجلّ النشاط فقط: لا حركةَ خزنةٍ ولا قيد. فمن
      // دفع ٣٠٠ عربوناً كان النقدُ في الدرج ورصيدُ الخزنة لا يعرف والدفاترُ
      // لا تعرف.
      //
      // والمقابلُ **حسابُ التزامٍ** `2134` لا إيراد: قبضُ العربون ليس بيعاً،
      // والاعترافُ بالإيراد يقع عند التفويتر. ولو تُرك للتصنيف الافتراضيّ
      // لسقط على `4299` (إيراد) — بل و**أُنشئ** إن لم يوجد.
      //
      // و`skipPartyBalance` عن قصد: الالتزامُ يُطفأ عند التفويتر بـ«مدين
      // الالتزام / دائن حساب العميل»، فتحريكُ الرصيد هنا أيضاً يعدّ الدفعةَ
      // مرّتين (‏قرارُ المالك 2026-08-23).
      //
      // ⚠️ وداخلَ نفسِ المعاملة: حجزٌ نجح وعربونُه فشل يترك مالاً مقبوضاً
      //    بلا أثرٍ في أيّ دفتر — وهو أسوأُ من رفض الحجز.
      if (depositAmount > 0) {
        final advances = await getAccountByCode(
          AccountingDaoReadsExt.accountPurposes['customer_advances']!,
        );
        await createReceiptVoucher(
          amount: depositAmount,
          category: 'booking_deposit',
          description: 'عربون حجز #$bookingId — $customerName',
          partyId: partyId,
          userId: createdBy,
          linkedAccountId: advances?.id,
          skipPartyBalance: true,
          operatingBranchId: branchId,
        );
      }

      return bookingId;
    });

    // ── التذكيرُ **خارجَ** المعاملة عمداً ────────────────────────────────
    // العربونُ أعلاه داخلَها لأنّ فشلَه يترك مالاً مقبوضاً بلا أثرٍ في أيّ
    // دفتر. والتذكيرُ نقيضُه: لا مالَ فيه، وإسقاطُ حجزٍ مؤكَّدٍ لأنّ صفَّ
    // تذكيرٍ تعذّر ضررٌ محضٌ بلا مقابل. فيُبتلَع فشلُه ويبقى الحجز.
    try {
      await _scheduleBookingReminder(
        bookingId: newBookingId,
        customerPhone: customerPhone,
        startsAt: startsAt,
      );
    } catch (e) {
      unawaited(DiagnosticLogger.log(
        'BOOKING-REMINDER',
        'تعذّر جدولةُ تذكيرٍ للحجز #$newBookingId — الحجزُ قائم: $e',
      ));
    }

    return newBookingId;
  }

  /// المهلةُ المحفوظةُ للتذكير بالدقائق — أو الافتراضُ عند غيابٍ أو فساد.
  ///
  /// ⚠️ **قراءةٌ غيرُ متزامنة عن قصد.** القراءةُ المتزامنة
  /// (`SettingsRepositoryCached.get`) ترجع `null` عند إخفاق الكاش بنفس ما
  /// ترجعه عند غياب المفتاح، فتموت الميزةُ صامتةً ما لم يُسجَّل المفتاحُ في
  /// `preloadKeys`. وهذا المسارُ `async` أصلاً فلا يدفع ثمناً.
  ///
  /// ⚠️ و**السالبُ يسقط على الافتراض** لا يُمرَّر: القيدُ
  /// `offset_minutes >= 0` يرفضه، فتمريرُه يحوّل إعداداً فاسداً إلى حجزٍ
  /// بلا تذكيرٍ بدل تذكيرٍ بالافتراض.
  Future<int> _bookingReminderOffsetMinutes() async {
    final raw = await getSettingValue(bookingReminderOffsetKey);
    final parsed = int.tryParse(raw ?? '');
    if (parsed == null || parsed < 0) return bookingReminderOffsetDefault;
    return parsed;
  }

  /// يُدرج صفَّ تذكيرٍ واحداً لحجزٍ جديد.
  ///
  /// ⚠️ **ولا تذكيرَ بلا هاتف**: `whatsappReminderLink` ترجع `null` بلا رقم،
  /// فالصفُّ يظهر في القائمة بزرٍّ لا يعمل — زينةٌ تُوهم المضيفَ أنّ العميلَ
  /// سيُذكَّر (‏قرارُ المالك 2026-08-23).
  ///
  /// ⚠️ و**المستحقُّ فوراً يُنشَأ ولا يُتخطّى**: حجزٌ بعد عشر دقائقَ ومهلةٌ
  /// ستّون يعطي `scheduledAt` في الماضي. العميلُ ما زال يستحقّ تذكيراً،
  /// و`isReminderDue` تعرضه مستحقّاً فيراه المضيفُ ويرسله (‏قرارُ المالك).
  Future<void> _scheduleBookingReminder({
    required int bookingId,
    required String? customerPhone,
    required DateTime startsAt,
  }) async {
    if (customerPhone == null || customerPhone.trim().isEmpty) return;

    final offset = await _bookingReminderOffsetMinutes();
    await into(bookingReminders).insert(
      BookingRemindersCompanion.insert(
        bookingId: bookingId,
        offsetMinutes: Value(offset),
        scheduledAt: reminderScheduleFor(startsAt, offset),
      ),
    );
  }

  /// يختم تذكيراً بأنّ رابطَه فُتح — بمن فتحه ومتى.
  ///
  /// ⚠️ **`opened` لا `sent`.** رابطُ `wa.me` يفتح واتساب برسالةٍ مُعبّأةٍ
  /// ولا يُثبت إرسالاً، والقيدُ يرفض `sent` أصلاً. فما يُسجَّل هو ما يملك
  /// التطبيقُ إثباتَه.
  ///
  /// ⚠️ وبدونه يبقى كلُّ صفٍّ `scheduled` أبداً: `isReminderDue` تعرضه
  /// مستحقّاً بلا نهاية، فتتراكم القائمةُ بما عُولج فعلاً ولا يميّز المضيفُ
  /// ما أرسله ممّا لم يُرسله — أي أنّ المولِّدَ يملأ قائمةً لا تُفرَّغ.
  Future<void> markBookingReminderOpened(
    int reminderId, {
    int? userId,
    DateTime? now,
  }) async {
    await (update(bookingReminders)..where((r) => r.id.equals(reminderId)))
        .write(
      BookingRemindersCompanion(
        state: const Value('opened'),
        openedAt: Value(now ?? DateTime.now()),
        openedBy: Value(userId),
      ),
    );
  }

  /// يرفض تفويترَ حجزٍ خدمتُه غيرُ مربوطةٍ بصنف.
  ///
  /// ‏قرارُ المالك: «وخدمةٌ بلا صنفٍ مربوطٍ لا تُفوتَر». والبديلُ — اختراعُ
  /// صنفٍ لحظةَ التفويتر — يُنشئ أصنافاً شبحيّةً لا تُدار ولا تُسعَّر ولا
  /// تدخل تقريراً، ويجعل رقمَ الفاتورة بلا مرجعٍ في كتالوج الأصناف.
  Future<void> assertBookingInvoiceable(int bookingId) async {
    final booking = await (select(bookings)
          ..where((b) => b.id.equals(bookingId)))
        .getSingle();
    final service = await (select(bookingServices)
          ..where((s) => s.id.equals(booking.serviceId)))
        .getSingle();

    if (service.productId == null) {
      throw StateError(
        'لا يمكن تفويتر الحجز: الخدمة «${service.name}» غير مربوطة بصنف. '
        'اربطها بصنف من نوع «خدمة» من شاشة الخدمات ثم أعد المحاولة.',
      );
    }

    final product = await (select(products)
          ..where((p) => p.id.equals(service.productId!)))
        .getSingleOrNull();
    if (product == null) {
      throw StateError(
        'لا يمكن تفويتر الحجز: صنف الخدمة «${service.name}» محذوف أو غير '
        'موجود. أعد ربط الخدمة بصنف قائم.',
      );
    }
  }

  /// يُطفئ التزامَ العربون على فاتورةٍ بعينها — **بلا حركةِ نقدٍ ثانية**.
  ///
  /// النقدُ دخل الخزنةَ لحظةَ الحجز، فتكرارُه هنا يضخّم الدرج. الواقعُ
  /// المحاسبيُّ الوحيدُ المتبقّي هو: **مدين `2134` / دائن حساب العميل** —
  /// الالتزامُ يُطفأ ودَينُ العميل ينقص بما دفعه مقدَّماً. وهذا بعينه ما
  /// يمنع محاسبتَه مرّتين.
  ///
  /// ورصيدُ الطرف يتحرّك **هنا** لا عند القبض (‏قرارُ المالك 2026-08-23).
  ///
  /// ⚠️ و`Bookings.invoiceId` يُكتب في نفس المعاملة: بدونه لا يُعرَف أنّ
  ///    الحجزَ فُوتِر، فيُطبَّق العربونُ ثانيةً على فاتورةٍ أخرى.
  Future<void> applyBookingDepositToInvoice({
    required int bookingId,
    required int invoiceId,
    int? userId,
  }) async {
    return transaction(() async {
      final booking = await (select(bookings)
            ..where((b) => b.id.equals(bookingId)))
          .getSingle();

      if (booking.depositAmount <= 0) {
        throw StateError('لا عربون على هذا الحجز.');
      }
      if (booking.invoiceId != null) {
        throw StateError(
          'عربون هذا الحجز مُطبَّقٌ سلفاً على الفاتورة #${booking.invoiceId}.',
        );
      }
      final partyId = booking.partyId;
      if (partyId == null) {
        throw StateError(
          'لا يمكن خصم العربون: الحجز غير مرتبط بعميل مسجَّل.',
        );
      }

      final invoice = await (select(salesInvoices)
            ..where((i) => i.id.equals(invoiceId)))
          .getSingle();
      if (invoice.customerId != partyId) {
        throw StateError(
          'لا يمكن خصم العربون: الفاتورة ليست على نفس عميل الحجز.',
        );
      }

      final party =
          await (select(parties)..where((p) => p.id.equals(partyId))).getSingle();
      final advances = await getAccountByCode(
        AccountingDaoReadsExt.accountPurposes['customer_advances']!,
      );
      if (advances == null || party.accountId == null) {
        throw StateError(
          'لا يمكن خصم العربون: حساب الدفعات المقدمة أو حساب العميل غير مهيّأ.',
        );
      }

      final amount = booking.depositAmount;

      await createJournalEntry(
        description: 'خصم عربون حجز #$bookingId من الفاتورة '
            '#${invoice.invoiceNumber}',
        date: DateTime.now(),
        isAutoPosted: true,
        referenceType: 'booking_deposit_applied',
        referenceId: bookingId,
        branchId: booking.branchId ?? invoice.branchId,
        lines: [
          JournalLine(accountId: advances.id, debit: amount, credit: 0),
          JournalLine(accountId: party.accountId!, debit: 0, credit: amount),
        ],
      );

      final newPaid = invoice.paid + amount;
      final newStatus = (invoice.total - newPaid) <= 0 ? 'paid' : 'partial';
      await (update(salesInvoices)..where((i) => i.id.equals(invoiceId))).write(
        SalesInvoicesCompanion(
          paid: Value(newPaid),
          status: Value(newStatus),
        ),
      );

      await adjustPartyBalance(partyId, -amount);

      await (update(bookings)..where((b) => b.id.equals(bookingId)))
          .write(BookingsCompanion(invoiceId: Value(invoiceId)));
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

      // ── التذكيرُ يتبع الموعدَ وإلّا صار يتيماً ──────────────────────────
      // صفٌّ بقي على موعدٍ لم يعد قائماً أسوأُ من لا صفّ: المضيفُ يرسل
      // للعميل ساعةً خطأ.
      //
      // ⚠️ و**بالمهلة المخزَّنة في الصفّ** لا بالإعداد اليوم — وهذا نصُّ
      // تعليقِ العمود: «يُخزَّن ليبقى التذكيرُ مفهوماً بعد تأجيل الموعد،
      // ويُعاد جدولتُه منه». ولو قُرئ الإعدادُ هنا لَغيّر تبديلُه تذكيراتٍ
      // قديمةً بأثرٍ رجعيٍّ عند أوّل نقل.
      //
      // ⚠️ و`scheduled` وحدَها: تذكيرٌ `opened` تاريخٌ وقع فعلاً، وتحريكُ
      // موعدِه يكذب على سجلٍّ تمّ.
      if (startsAt != null) {
        final live = await (select(bookingReminders)
              ..where((r) =>
                  r.bookingId.equals(bookingId) &
                  r.deletedAt.isNull() &
                  r.state.equals('scheduled')))
            .get();
        for (final reminder in live) {
          await (update(bookingReminders)..where((r) => r.id.equals(reminder.id)))
              .write(
            BookingRemindersCompanion(
              scheduledAt: Value(
                reminderScheduleFor(newStartsAt, reminder.offsetMinutes),
              ),
            ),
          );
        }
      }
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

/// مُجمِّعُ عميلٍ أثناء المسح — داخليٌّ لا يُصدَّر.
class _CustomerAgg {
  _CustomerAgg(this.name, this.phone, this.partyId);

  final String name;
  final String? phone;
  final int? partyId;

  int visits = 0;
  double spend = 0;
  DateTime? last;

  /// عددُ مرّاتِ كلِّ خدمة — لاشتقاق «المفضَّلة».
  final Map<String, int> _services = {};

  void add(String serviceName, double price, DateTime at) {
    visits++;
    spend += price;
    if (last == null || at.isAfter(last!)) last = at;
    _services[serviceName] = (_services[serviceName] ?? 0) + 1;
  }

  /// الأكثرُ تكراراً — وعند التعادل يفوز الأسبقُ إدراجاً (ثابتٌ لا عشوائيّ).
  String? get favourite {
    String? best;
    var bestCount = 0;
    for (final e in _services.entries) {
      if (e.value > bestCount) {
        best = e.key;
        bestCount = e.value;
      }
    }
    return best;
  }

  BookingCustomerRow toRow() => BookingCustomerRow(
        name: name,
        phone: phone,
        partyId: partyId,
        visits: visits,
        spend: spend,
        favouriteService: favourite,
        lastVisit: last,
      );
}
