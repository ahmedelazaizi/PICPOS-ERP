// lib/services/booking_actions_service.dart
//
// السجلُّ يُكتب من **الخدمة** لا من الودجت: لو كُتب في الودجت لمرّ كلُّ
// مسارٍ آخرَ يكتب حجزاً بلا أثر.

// `show Value` وحدَه: استيرادُ drift كاملاً هنا يجرّ `Column` و`Table`
// وأخواتِهما إلى مجالٍ يستورد حزمةَ القاعدة أصلاً، فتتصادم الأسماء.
import 'package:drift/drift.dart' show Value;

import '../data/database/database.dart';

/// أفعالُ الحجز التي تُكتب في سجلّ النشاط — إنشاءٌ ونقلٌ وتأجيل.
///
/// **الاسمُ `BookingActionsService` لا `BookingService` عمداً، ولا يُعاد:**
/// drift يولّد `class BookingService extends DataClass` في
/// `database.g.dart` — صفَّ جدولِ `BookingServices` مفرَداً. وملفُّ
/// `lib/data/providers/providers.dart` يستورد حزمةَ القاعدة **ويعيد
/// تصديرَها**، فصفُّ الجدول في مجال كلِّ ملفٍّ يمسّ المزوِّدات. فلو حمل
/// هذا الصنفُ الاسمَ نفسَه لانفجر أوّلُ ملفٍّ يجمع بينهما بـ
/// `ambiguous_import` — وهي ضريبةٌ يدفعها المستودعُ ثلاثَ مرّاتٍ بالفعل
/// في `Printer` (`hide Printer` في `lib/services/invoice_generator.dart`
/// وملفَّي طباعةٍ آخرين). واليومَ لا مستدعيَ لهذا الصنف فالتسميةُ مجّانيّة،
/// وغداً — مع أوّل مزوِّدٍ أو شاشةِ حجوزات — جدارٌ.
class BookingActionsService {
  final AppDatabase _db;

  BookingActionsService({required AppDatabase db}) : _db = db;

  Future<int> create({
    required String customerName,
    String? customerPhone,
    int? partyId,
    required int serviceId,
    int? resourceId,
    required DateTime startsAt,
    double depositAmount = 0,
    String? notes,
    int? branchId,
    required int? userId,
    required String userName,
  }) async {
    final id = await _db.createBooking(
      customerName: customerName,
      customerPhone: customerPhone,
      partyId: partyId,
      serviceId: serviceId,
      resourceId: resourceId,
      startsAt: startsAt,
      depositAmount: depositAmount,
      notes: notes,
      branchId: branchId,
      createdBy: userId,
    );
    await _db.logActivity(
      userId: userId,
      userName: userName,
      action: 'booking_create',
      // `entityType` هو ما تُرشِّح عليه شاشةُ سجلّ الحجز الواحد.
      entityType: 'booking',
      entityId: id,
      description: 'حجزٌ جديد لـ$customerName في ${startsAt.toIso8601String()}',
      amount: depositAmount,
      branchId: branchId,
    );
    return id;
  }

  /// نقلٌ أو تأجيلٌ — **ويُسجَّل بقيمتَيه السابقةِ واللاحقة.**
  ///
  /// «مَن نقل حجزَ الزبون من فلانٍ إلى فلان» و«مَن أجّل الموعد» سؤالان
  /// يُسألان عند الخلاف، ولا يجيبهما إلا سطرٌ مكتوب.
  ///
  /// **والخطواتُ الأربعُ في معاملةٍ واحدة** — القراءةُ السابقةُ والتعديلُ
  /// والقراءةُ اللاحقةُ والتسجيل. عطلٌ بين التعديل والتسجيل كان يترك نقلاً
  /// وقع في القاعدة بلا سطرٍ يجيب عنه، وهو بالضبط ما تقول §٦ إنه يجب أن
  /// يبقى مُجاباً دائماً. وdrift ينفّذ المعاملةَ الداخليّةَ في
  /// `updateBookingSlot` بـ`SAVEPOINT` فلا تعارض.
  Future<void> reassign(
    int bookingId, {
    int? resourceId,
    bool clearResource = false,
    DateTime? startsAt,
    required int? userId,
    required String userName,
  }) {
    return _db.transaction(() async {
      final before = await (_db.select(_db.bookings)
            ..where((b) => b.id.equals(bookingId)))
          .getSingle();

      await _db.updateBookingSlot(
        bookingId,
        resourceId: resourceId,
        clearResource: clearResource,
        startsAt: startsAt,
      );

      final after = await (_db.select(_db.bookings)
            ..where((b) => b.id.equals(bookingId)))
          .getSingle();

      final movedResource = before.resourceId != after.resourceId;
      final rescheduled = before.startsAt != after.startsAt;

      await _db.logActivity(
        userId: userId,
        userName: userName,
        action: movedResource ? 'booking_reassign' : 'booking_reschedule',
        entityType: 'booking',
        entityId: bookingId,
        description: _moveDescription(
          customerName: after.customerName,
          beforeResourceId: before.resourceId,
          afterResourceId: after.resourceId,
          movedResource: movedResource,
          rescheduled: rescheduled,
        ),
        oldValue: 'resource=${before.resourceId} start=${before.startsAt}',
        newValue: 'resource=${after.resourceId} start=${after.startsAt}',
        branchId: after.branchId,
      );
    });
  }

  /// تبديلُ الحالة — **وهو المسارُ الذي كان يقع بلا أثر**.
  ///
  /// ═══ 🔴 لماذا غلافٌ، ولماذا هو الأخطر ═══
  ///
  /// `create` و`reassign` تكتبان في سجلّ النشاط، و`setBookingStatus` كانت
  /// تُنادى **مباشرةً** فتبدّل الحالةَ بلا سطر. ومَن وسم حجزاً عليه عربونٌ
  /// بـ«لم يحضر» يقرّر مصيرَ مالِ عميلٍ — و«مَن فعلها ومتى» سؤالٌ يُسأل عند
  /// الخلاف ولا يجيبه إلّا سطرٌ مكتوب.
  ///
  /// **والفحصُ يبقى في الـDAO لا هنا:** إحياءُ حجزٍ ملغًى يعيد شَغلَ وقتٍ قد
  /// شُغل في الأثناء، و`setBookingStatus` تعيد فحصَ التعارض داخل معاملتها.
  /// فهذا الغلافُ يمرّ بها ولا يكتب `update(bookings)` خاماً — ذاك يتجاوز
  /// الفحصَ بالبناء.
  ///
  /// **والخطواتُ في معاملةٍ واحدة**: عطلٌ بين التبديل والتسجيل كان يترك
  /// تبديلاً وقع بلا سطرٍ يجيب عنه — نفسُ علّة `reassign`.
  ///
  /// ⚠️ **والإلغاءُ ليس من هنا** — له [cancel] بفعله الخاصّ `booking_cancel`
  /// وسببِه ووقتِه.
  Future<void> setStatus(
    int bookingId,
    String status, {
    required int? userId,
    required String userName,
  }) {
    return _db.transaction(() async {
      final before = await (_db.select(_db.bookings)
            ..where((b) => b.id.equals(bookingId)))
          .getSingle();

      await _db.setBookingStatus(bookingId, status);

      final after = await (_db.select(_db.bookings)
            ..where((b) => b.id.equals(bookingId)))
          .getSingle();

      await _db.logActivity(
        userId: userId,
        userName: userName,
        action: 'booking_status',
        entityType: 'booking',
        entityId: bookingId,
        description: _statusDescription(
          customerName: after.customerName,
          to: after.status,
          depositAmount: after.depositAmount,
        ),
        oldValue: before.status,
        newValue: after.status,
        branchId: after.branchId,
      );
    });
  }

  /// إلغاءُ حجزٍ بسببِه — فعلٌ مستقلٌّ عن [setStatus].
  ///
  /// `cancelledAt` و`cancelReason` يُكتبان هنا، وهما ما لا تكتبه
  /// `setBookingStatus` عمداً. ومصيرُ العربون (‏ردٌّ · مصادرةٌ · تأجيل)
  /// **لا يُقرَّر هنا**: `depositStatus` يبقى كما هو، فالإلغاءُ وحدَه لا
  /// يصادر مالاً. مَن أراد المصادرةَ يقولها فعلاً منفصلاً.
  Future<void> cancel(
    int bookingId, {
    String? reason,
    required int? userId,
    required String userName,
  }) {
    return _db.transaction(() async {
      final before = await (_db.select(_db.bookings)
            ..where((b) => b.id.equals(bookingId)))
          .getSingle();

      await _db.setBookingStatus(bookingId, 'cancelled');
      await (_db.update(_db.bookings)..where((b) => b.id.equals(bookingId)))
          .write(
        BookingsCompanion(
          cancelledAt: Value(DateTime.now()),
          cancelReason: Value(reason),
        ),
      );

      await _db.logActivity(
        userId: userId,
        userName: userName,
        action: 'booking_cancel',
        entityType: 'booking',
        entityId: bookingId,
        description: reason == null || reason.trim().isEmpty
            ? 'إلغاءُ حجز ${before.customerName}'
            : 'إلغاءُ حجز ${before.customerName} — $reason',
        oldValue: before.status,
        newValue: 'cancelled',
        branchId: before.branchId,
      );
    });
  }

  /// وصفُ تبديل الحالة.
  ///
  /// ⚠️ **يذكر العربونَ حين يكون له وجود** — لا ليقول إن مالاً تحرّك (لم
  /// يتحرّك: `depositStatus` لا يتبدّل هنا)، بل ليجعل السطرَ مفهوماً لمن
  /// يقرؤه لاحقاً: «لم يحضر وعليه عربون» سطرٌ يُوقف القارئ، و«لم يحضر»
  /// وحدَها لا تُوقفه.
  ///
  /// ولهذا **لا يُمرَّر `amount`** إلى السجلّ: ذاك حقلُ مالٍ تحرّك، وتبديلُ
  /// الحالة لا يحرّك شيئاً. وملؤه كان يجعل التقاريرَ تجمع عربوناً لم يُقبَض.
  static String _statusDescription({
    required String customerName,
    required String to,
    required double depositAmount,
  }) {
    final label = _statusLabels[to] ?? to;
    final base = 'حجزُ $customerName صار «$label»';
    if (depositAmount <= 0) return base;
    return '$base — وعليه عربونٌ $depositAmount';
  }

  /// تسمياتُ الحالات كما تُعرض — سطرُ السجلّ يُقرأ بالعربيّة لا بالمفتاح.
  static const Map<String, String> _statusLabels = {
    'pending': 'بانتظار التأكيد',
    'confirmed': 'مؤكَّد',
    'seated': 'تم الحضور',
    'in_service': 'قيد الخدمة',
    'completed': 'مكتمل',
    'cancelled': 'ملغي',
    'no_show': 'لم يحضر',
  };

  /// وصفُ الحركة — **يذكر ما تبدّل كلَّه لا أوّلَه**.
  ///
  /// كان الوصفُ ثنائيّاً على `movedResource` وحدَها، فالحركةُ التي تبدّل
  /// الموظَّفَ والوقتَ معاً تُكتب «نقلٌ بين الموظفين» ولا تذكر التأجيلَ
  /// أصلاً — فمن يقرأ السجلَّ باحثاً عن تأجيلٍ لا يجده مذكوراً.
  ///
  /// و«بين الموظفين» كانت تُقال كذلك للإسناد الأوّل (من قائمة الانتظار)
  /// وللإعادة إليها — وليس في الحالتين موظَّفان.
  static String _moveDescription({
    required String customerName,
    required int? beforeResourceId,
    required int? afterResourceId,
    required bool movedResource,
    required bool rescheduled,
  }) {
    final parts = <String>[];
    if (movedResource) {
      if (beforeResourceId == null) {
        parts.add('إسنادُ حجز $customerName من قائمة الانتظار');
      } else if (afterResourceId == null) {
        parts.add('إعادةُ حجز $customerName إلى قائمة الانتظار');
      } else {
        parts.add('نقلُ حجز $customerName بين الموظفين');
      }
    }
    if (rescheduled) {
      parts.add(movedResource
          ? 'مع تأجيل الموعد'
          : 'تأجيلُ حجز $customerName');
    }
    // نداءٌ لم يبدّل شيئاً — يُسجَّل كما هو لا يُبتلع: «مَن حاول» سؤالٌ
    // يُسأل هو الآخر.
    if (parts.isEmpty) {
      return 'تعديلُ حجز $customerName بلا تبدُّل';
    }
    return parts.join(' ');
  }
}
