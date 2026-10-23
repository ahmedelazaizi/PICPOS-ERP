// test/unit/booking_actions_service_test.dart
//
// وصفُ الحركة في سجلّ العمليات — **يذكر ما تبدّل كلَّه لا أوّلَه**.
//
// الوصفُ كان ثنائيّاً على `movedResource` وحدَها: حركةٌ تبدّل الموظَّفَ
// والوقتَ معاً تُكتب «نقلٌ بين الموظفين» ولا تذكر التأجيلَ أصلاً، فمن
// يقرأ السجلَّ باحثاً عن تأجيلٍ لا يجده. و«بين الموظفين» كانت تُقال كذلك
// للإسناد الأوّل من قائمة الانتظار وللإعادة إليها — وليس في الحالتين
// موظَّفان.
//
// **ملاحظةٌ على التوقيت:** `BookingActionsService` لا تمرّر «الآن» إلى
// الـDAO (لا تأخذه أصلاً)، فقاعدةُ «لا حجزَ في الماضي» تقارن بساعةِ
// النظام. فالمواعيدُ هنا مبنيّةٌ على **غدٍ** لا على تاريخٍ ثابت، وإلّا
// انقلب الاختبارُ أحمرَ بمرور اليوم.

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/booking_actions_service.dart';

void main() {
  late AppDatabase db;
  late BookingActionsService service;
  late int serviceId;
  late int resourceA;
  late int resourceB;

  // غداً في العاشرة — والمقارنةُ بساعةِ النظام تبقى صحيحةً أبداً.
  final tomorrow = DateTime.now().add(const Duration(days: 1));
  final at10 = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10);
  final at12 = at10.add(const Duration(hours: 2));
  final at15 = at10.add(const Duration(hours: 5));

  setUp(() async {
    db = AppDatabase.forTesting();
    service = BookingActionsService(db: db);
    serviceId = await db.into(db.bookingServices).insert(
          BookingServicesCompanion.insert(
            name: 'مساج',
            durationMinutes: const Value(60),
          ),
        );
    resourceA = await db.into(db.bookingResources).insert(
          BookingResourcesCompanion.insert(name: 'محمد'),
        );
    resourceB = await db.into(db.bookingResources).insert(
          BookingResourcesCompanion.insert(name: 'ريم'),
        );
  });

  tearDown(() async {
    // لا `db.close()`: يعلّق مؤقّتَ drift في المنطقة الوهميّة فيتجمّد
    // الاختبار.
  });

  Future<List<ActivityLog>> logsFor(int bookingId) =>
      (db.select(db.activityLogs)
            ..where((l) => l.entityType.equals('booking'))
            ..where((l) => l.entityId.equals(bookingId)))
          .get();

  Future<int> seed({int? resourceId, required DateTime startsAt}) =>
      db.createBooking(
        customerName: 'سارة',
        serviceId: serviceId,
        resourceId: resourceId,
        startsAt: startsAt,
      );

  test('نقلٌ وتأجيلٌ معاً — الوصفُ يذكر الاثنين لا النقلَ وحدَه', () async {
    final id = await seed(resourceId: resourceA, startsAt: at10);

    await service.reassign(
      id,
      resourceId: resourceB,
      startsAt: at15,
      userId: null,
      userName: 'مستخدمُ اختبار',
    );

    final logs = await logsFor(id);
    expect(logs, hasLength(1));
    expect(logs.single.action, 'booking_reassign');
    expect(logs.single.description, contains('بين الموظفين'));
    expect(logs.single.description, contains('تأجيل'),
        reason: 'حركةٌ بدّلت الموظَّفَ والوقتَ معاً يجب أن تذكر التأجيلَ '
            'كذلك — وإلّا لم يرها مَن يقرأ باحثاً عن تأجيل');
  });

  test('الإسنادُ الأوّلُ من قائمة الانتظار لا يُوصَف «بين الموظفين»', () async {
    final id = await seed(resourceId: null, startsAt: at10);

    await service.reassign(
      id,
      resourceId: resourceA,
      userId: null,
      userName: 'مستخدمُ اختبار',
    );

    final logs = await logsFor(id);
    expect(logs.single.description, contains('من قائمة الانتظار'));
    expect(logs.single.description, isNot(contains('بين الموظفين')),
        reason: 'لا موظَّفَين هنا — واحدٌ فقط، وهو الجديد');
  });

  test('الإعادةُ إلى قائمة الانتظار لا تُوصَف «بين الموظفين»', () async {
    final id = await seed(resourceId: resourceA, startsAt: at10);

    await service.reassign(
      id,
      clearResource: true,
      userId: null,
      userName: 'مستخدمُ اختبار',
    );

    final logs = await logsFor(id);
    expect(logs.single.description, contains('إلى قائمة الانتظار'));
    expect(logs.single.description, isNot(contains('بين الموظفين')));
  });

  test('التأجيلُ وحدَه يبقى تأجيلاً باسمه', () async {
    final id = await seed(resourceId: resourceA, startsAt: at10);

    await service.reassign(
      id,
      startsAt: at15,
      userId: null,
      userName: 'مستخدمُ اختبار',
    );

    final logs = await logsFor(id);
    expect(logs.single.action, 'booking_reschedule');
    expect(logs.single.description, contains('تأجيلُ حجز'));
  });

  test('التعارضُ يُرجع المعاملةَ كاملةً — لا صفٌّ مبدَّلٌ ولا سطرٌ مكتوب',
      () async {
    // «أحمد» يشغل ريم في ١٢:٠٠، وسارة على محمد في ١٠:٠٠.
    await db.createBooking(
      customerName: 'أحمد',
      serviceId: serviceId,
      resourceId: resourceB,
      startsAt: at12,
    );
    final id = await seed(resourceId: resourceA, startsAt: at10);

    await expectLater(
      service.reassign(
        id,
        resourceId: resourceB,
        startsAt: at12,
        userId: null,
        userName: 'مستخدمُ اختبار',
      ),
      throwsA(isA<BookingConflictException>()),
    );

    final row = await (db.select(db.bookings)..where((b) => b.id.equals(id)))
        .getSingle();
    expect(row.resourceId, resourceA);
    expect(row.startsAt, at10);
    expect(await logsFor(id), isEmpty);
  });

  test('الإنشاءُ يكتب سطرَه بالفعل والمبلغ', () async {
    // Audit B ACC-004: a deposit requires a registered customer.
    final partyId = await db.insertParty(PartiesCompanion.insert(
        name: 'سارة', isCustomer: const Value(true)));
    final id = await service.create(
      customerName: 'سارة',
      partyId: partyId,
      serviceId: serviceId,
      resourceId: resourceA,
      startsAt: at10,
      depositAmount: 50,
      userId: null,
      userName: 'مستخدمُ اختبار',
    );
    final logs = await logsFor(id);
    expect(logs.single.action, 'booking_create');
    expect(logs.single.amount, 50);
  });
}
