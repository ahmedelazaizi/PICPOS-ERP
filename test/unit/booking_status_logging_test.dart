// test/unit/booking_status_logging_test.dart
//
// ═══ 🔴 المسارُ الذي كان يقع بلا أثر ═══
//
// `create` و`reassign` تكتبان في سجلّ النشاط منذ البداية، و**تبديلُ الحالة
// كان يُنادى على الـDAO مباشرةً** فيقع بلا سطر. ومَن وسم حجزاً عليه عربونٌ
// بـ«لم يحضر» يقرّر مصيرَ مالِ عميل — و«مَن فعلها ومتى» سؤالٌ يُسأل عند
// الخلاف ولا يجيبه إلّا سطرٌ مكتوب.
//
// وهذا الحارسُ يسقط أحمرَ إن نُودي الـDAO من الشاشة رأساً أو حُذف الغلاف.
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/booking_actions_service.dart';

void main() {
  late AppDatabase db;
  late BookingActionsService svc;
  late int actorId;

  setUp(() async {
    db = AppDatabase.forTesting();
    svc = BookingActionsService(db: db);
    // ⚠️ **مستخدمٌ حقيقيّ لا رقمٌ مخترَع**: `AppDatabase.forTesting()` يُنفِذ
    // المفاتيحَ الأجنبية، و`activity_logs.user_id` يشير إلى `users`. فرقمٌ
    // لا وجودَ له يُسقط الكتابةَ بـ`FOREIGN KEY constraint failed` — وهو ما
    // وقع أوّلَ تشغيل. والبديلُ (‏`userId: null` كما في الاختبار المجاور)
    // كان يُخفي أنّ الفاعلَ يُسجَّل أصلاً.
    // AUTHZ-008: the service now enforces the booking permissions itself, so
    // the actor holds the codes these logging tests exercise.
    final roleId = await db.insertRole(name: 'booking-log-role');
    final perms = await db.getAllPermissions();
    await db.setRolePermissions(roleId, [
      for (final c in const ['bookings_status', 'bookings_cancel', 'bookings_add', 'bookings_assign'])
        perms.firstWhere((p) => p.code == c).id,
    ]);
    actorId = await db.into(db.users).insert(
          UsersCompanion.insert(
            username: 'booking_log_test_user',
            passwordHash: 'x',
            displayName: 'ريم أحمد',
            roleId: Value(roleId),
          ),
        );
  });

  tearDown(() async {
    // لا `db.close()` — يعلّق مؤقّتَ drift في المنطقة الوهميّة.
  });

  Future<int> seedBooking({double deposit = 0}) async {
    final serviceId = await db.into(db.bookingServices).insert(
          BookingServicesCompanion.insert(name: 'قص شعر'),
        );
    return db.into(db.bookings).insert(
          BookingsCompanion.insert(
            customerName: 'أحمد محمد',
            serviceId: serviceId,
            startsAt: DateTime(2026, 8, 22, 10),
            endsAt: DateTime(2026, 8, 22, 10, 45),
            depositAmount: Value(deposit),
          ),
        );
  }

  Future<List<ActivityLog>> logsFor(int bookingId) => (db.select(db.activityLogs)
        ..where((l) => l.entityType.equals('booking'))
        ..where((l) => l.entityId.equals(bookingId)))
      .get();

  group('تبديلُ الحالة يُسجَّل', () {
    test('يكتب سطراً بفعلِ `booking_status`', () async {
      final id = await seedBooking();
      await svc.setStatus(id, 'seated', userId: actorId, userName: 'ريم');

      final logs = await logsFor(id);
      expect(logs, hasLength(1));
      expect(logs.single.action, 'booking_status');
      // ⚠️ `entityType` هو ما تُرشِّح عليه شاشةُ العرض — سطرٌ بنوعٍ آخر
      // يُكتب في دلوٍ لا يراه أحد.
      expect(logs.single.entityType, 'booking');
      expect(logs.single.entityId, id);
    });

    test('يسجّل القيمتَين السابقةَ واللاحقة', () async {
      final id = await seedBooking();
      await svc.setStatus(id, 'confirmed', userId: actorId, userName: 'ريم');

      final log = (await logsFor(id)).single;
      expect(log.oldValue, 'pending');
      expect(log.newValue, 'confirmed');
    });

    test('يسجّل الفاعلَ باسمه', () async {
      final id = await seedBooking();
      await svc.setStatus(id, 'no_show', userId: actorId, userName: 'محمد علي');

      final log = (await logsFor(id)).single;
      expect(log.userId, actorId);
      expect(log.userName, 'محمد علي');
    });

    // الحالةُ تتبدّل فعلاً — لا سطرٌ بلا أثرٍ في القاعدة.
    test('الحالةُ تتبدّل في الجدول', () async {
      final id = await seedBooking();
      await svc.setStatus(id, 'in_service', userId: actorId, userName: 'س');

      final row = await (db.select(db.bookings)..where((b) => b.id.equals(id)))
          .getSingle();
      expect(row.status, 'in_service');
    });

    // ⚠️ **العربونُ يُذكر في الوصف** ليُوقف القارئ: «لم يحضر» وحدَها لا
    // تُوقفه، و«لم يحضر وعليه عربون» تُوقفه.
    test('الوصفُ يذكر العربونَ حين يوجد', () async {
      final id = await seedBooking(deposit: 100);
      await svc.setStatus(id, 'no_show', userId: actorId, userName: 'س');

      expect((await logsFor(id)).single.description, contains('عربون'));
    });

    test('ولا يذكره حين لا عربونَ — فلا ضجيج', () async {
      final id = await seedBooking();
      await svc.setStatus(id, 'no_show', userId: actorId, userName: 'س');

      expect((await logsFor(id)).single.description, isNot(contains('عربون')));
    });

    // 🔴 **`amount` يبقى معدوماً عمداً.** ذاك حقلُ مالٍ **تحرّك**، وتبديلُ
    // الحالة لا يحرّك شيئاً (`depositStatus` لا يتبدّل هنا). وملؤه كان
    // يجعل التقاريرَ تجمع عربوناً لم يُقبَض.
    test('لا يملأ `amount` — لا مالَ تحرّك', () async {
      final id = await seedBooking(deposit: 250);
      await svc.setStatus(id, 'no_show', userId: actorId, userName: 'س');

      expect((await logsFor(id)).single.amount, anyOf(isNull, 0));
    });
  });

  group('الإلغاء فعلٌ مستقلّ', () {
    test('يكتب `booking_cancel` لا `booking_status`', () async {
      final id = await seedBooking();
      await svc.cancel(id, reason: 'اعتذر العميل',
          userId: actorId, userName: 'نورا');

      final log = (await logsFor(id)).single;
      expect(log.action, 'booking_cancel');
      expect(log.description, contains('اعتذر العميل'));
    });

    test('يكتب وقتَ الإلغاء وسببَه في الصفّ', () async {
      final id = await seedBooking();
      await svc.cancel(id, reason: 'ازدواج', userId: actorId, userName: 'نورا');

      final row = await (db.select(db.bookings)..where((b) => b.id.equals(id)))
          .getSingle();
      expect(row.status, 'cancelled');
      expect(row.cancelledAt, isNotNull);
      expect(row.cancelReason, 'ازدواج');
    });

    // ⚠️ الإلغاءُ وحدَه **لا يصادر** عربوناً. مصيرُ المال فعلٌ منفصلٌ يقوله
    // صاحبُه — وإلّا صادرت الشاشةُ مالاً بنقرةٍ لا تذكره.
    test('لا يمسّ حالةَ العربون', () async {
      final id = await seedBooking(deposit: 300);
      await svc.cancel(id, userId: actorId, userName: 'نورا');

      final row = await (db.select(db.bookings)..where((b) => b.id.equals(id)))
          .getSingle();
      expect(row.depositStatus, 'held');
      expect(row.depositAmount, 300);
    });

    test('بلا سببٍ يبقى الوصفُ مفهوماً', () async {
      final id = await seedBooking();
      await svc.cancel(id, userId: actorId, userName: 'نورا');

      expect((await logsFor(id)).single.description, contains('إلغاء'));
    });
  });
}
