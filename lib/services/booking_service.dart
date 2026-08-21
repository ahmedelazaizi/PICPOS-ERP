// lib/services/booking_service.dart
//
// السجلُّ يُكتب من **الخدمة** لا من الودجت: لو كُتب في الودجت لمرّ كلُّ
// مسارٍ آخرَ يكتب حجزاً بلا أثر.

import '../data/database/database.dart';

class BookingService {
  final AppDatabase _db;

  BookingService({required AppDatabase db}) : _db = db;

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
  Future<void> reassign(
    int bookingId, {
    int? resourceId,
    bool clearResource = false,
    DateTime? startsAt,
    required int? userId,
    required String userName,
  }) async {
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
    await _db.logActivity(
      userId: userId,
      userName: userName,
      action: movedResource ? 'booking_reassign' : 'booking_reschedule',
      entityType: 'booking',
      entityId: bookingId,
      description: movedResource
          ? 'نقلُ حجز ${after.customerName} بين الموظفين'
          : 'تأجيلُ حجز ${after.customerName}',
      oldValue: 'resource=${before.resourceId} start=${before.startsAt}',
      newValue: 'resource=${after.resourceId} start=${after.startsAt}',
      branchId: after.branchId,
    );
  }
}
