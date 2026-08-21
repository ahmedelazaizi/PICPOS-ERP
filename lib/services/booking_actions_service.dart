// lib/services/booking_actions_service.dart
//
// السجلُّ يُكتب من **الخدمة** لا من الودجت: لو كُتب في الودجت لمرّ كلُّ
// مسارٍ آخرَ يكتب حجزاً بلا أثر.

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
