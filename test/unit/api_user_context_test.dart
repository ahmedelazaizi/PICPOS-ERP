// Spec 060 (D1-001) — Server-side per-user permission enforcement.
//
// Tests the new ApiUserCtx helper + the X-User-Id header extraction in
// ApiAuthMiddleware. Drives shelf Request objects directly rather than
// spinning up a full server.
//
// Phase 1: helper + 4 wired endpoints (deleteSalesInvoice, putUser,
// deleteUser, setRolePermissions, postJournalEntry). Phase 2 will sweep
// the remaining ~85.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';

void main() {
  group('ApiUserCtx (Spec 060 / D1-001)', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting();
    });

    tearDown(() async {
      await db.close();
    });

    Request makeRequest({int? userId}) {
      return Request(
        'GET',
        Uri.parse('http://localhost:8080/api/test'),
        context: userId != null
            ? {ApiUserCtx.userIdKey: userId}
            : const {},
      );
    }

    test('userIdOf returns null when context is empty', () {
      expect(ApiUserCtx.userIdOf(makeRequest()), isNull);
    });

    test('userIdOf returns stored userId when context has it', () {
      expect(ApiUserCtx.userIdOf(makeRequest(userId: 42)), equals(42));
    });

    // ── الحارسُ الأهمُّ في هذا الملفّ ──────────────────────────────────────
    //
    // كان هنا اختباران يؤكّدان أنّ `isPerUserPermsEnabled` تُرجع `false`
    // افتراضاً وأنّ `requirePermission` **تمرّ تلقائيّاً** حينئذ. كانا خضراوَين
    // ويصفان الواقعَ بدقّة — والواقعُ أنّ ١٠٤ بوّاباتِ صلاحيّةٍ على مسارات
    // POST/PUT/DELETE كانت معطَّلةً على **كلِّ** تنصيبةٍ في الميدان، لأنّ
    // المفتاحَ لا يُزرع في بذرةٍ ولا هجرةٍ ولا خريطةِ افتراضات، وكاتبُه
    // الوحيدُ زرٌّ في الإعدادات.
    //
    // حُذف المفتاحُ ومعه الدالّة. والاختباران استُبدلا بنقيضهما.
    test('لا مفتاحَ يُعطّل البوّابة — لا بغيابه ولا بزرعه مطفأً', () async {
      await db.into(db.users).insert(
            UsersCompanion.insert(
              username: 'flagless_cashier',
              passwordHash: 'x',
              displayName: 'Flagless Cashier',
              roleId: const Value(2), // كاشير — لا يملك sales_delete
            ),
          );
      final cashierId = (await (db.select(db.users)
                ..where((u) => u.username.equals('flagless_cashier')))
              .getSingle())
          .id;

      // (أ) المفتاحُ غائبٌ تماماً — الحالةُ الافتراضيّةُ لكلِّ تنصيبةٍ جديدة.
      var resp = await ApiUserCtx.requirePermission(
          makeRequest(userId: cashierId), db, 'sales_delete');
      expect(resp, isNotNull,
          reason: 'غيابُ المفتاح كان يفتح كلَّ البوّابات — لم يعد');
      expect(resp!.statusCode, equals(403));

      // (ب) المفتاحُ مزروعٌ بـ`false` صراحةً — أسوأُ من غيابه.
      await db.setSetting('server_per_user_perms_enabled', 'false');
      resp = await ApiUserCtx.requirePermission(
          makeRequest(userId: cashierId), db, 'sales_delete');
      expect(resp, isNotNull,
          reason: 'المفتاحُ المطفأ صراحةً لا يُعيد المرورَ التلقائيّ');
      expect(resp!.statusCode, equals(403));
    });

    test('requirePermission returns 401 when no verified session', () async {
      final resp = await ApiUserCtx.requirePermission(
          makeRequest(), db, 'sales_delete');
      expect(resp, isNotNull);
      expect(resp!.statusCode, equals(401));
      // الرسالةُ تسمّي الترويسةَ التي تُقرأ فعلاً، لا `X-User-Id` التي لم
      // تعد تُقرأ منذ أن حلّ محلَّها توكنُ الجلسة الموقَّع.
      expect(await resp.readAsString(), contains('X-Session-Token'));
    });

    test('resolveActor يرفض تعارضَ هويّةِ الجسم مع هويّة الجلسة', () async {
      // ادّعاءٌ مطابقٌ للجلسة يمرّ ويُرجع هويّةَ الجلسة.
      var (actor, reject) =
          ApiUserCtx.resolveActor(makeRequest(userId: 7), 7);
      expect(reject, isNull);
      expect(actor, equals(7));

      // ادّعاءٌ مخالفٌ يُرفَض — وهذا عينُ ما كان يسمح لكاشيرٍ بإبطال فاتورةٍ
      // مدفوعةٍ بإرسال رقم المدير في جسم الطلب.
      (actor, reject) = ApiUserCtx.resolveActor(makeRequest(userId: 7), 1);
      expect(reject, isNotNull);
      expect(reject!.statusCode, equals(403));
      expect(actor, isNull);

      // بلا جلسةٍ لا يُعوَّض بادّعاء الجسم — يُرجَع `null` فيفشل الفحصُ
      // الحرجُ مغلقاً بدل أن يُفحَص على مستخدمٍ اختاره المستدعي.
      (actor, reject) = ApiUserCtx.resolveActor(makeRequest(), 1);
      expect(reject, isNull);
      expect(actor, isNull);
    });

    test('requirePermission returns 403 when user lacks permission',
        () async {
      // Bootstrap admin (id=1) does NOT have sales_delete after spec 062's
      // segregation-of-duties seeder change (only criticalFinancialOps
      // are excluded, but sales_delete is NOT critical) — actually spec
      // 062 still grants sales_delete. We need a NON-admin user.
      // Insert a cashier user via raw INSERT with a cashier role id 2.
      // Cashier role doesn't get sales_delete by default.
      await db.into(db.users).insert(
            UsersCompanion.insert(
              username: 'test_cashier',
              passwordHash: 'x',
              displayName: 'Test Cashier',
              roleId: const Value(2), // cashier
            ),
          );
      final cashierId = (await (db.select(db.users)
                ..where((u) => u.username.equals('test_cashier')))
              .getSingle())
          .id;

      final resp = await ApiUserCtx.requirePermission(
          makeRequest(userId: cashierId), db, 'sales_delete');
      expect(resp, isNotNull);
      expect(resp!.statusCode, equals(403));
    });

    test('requirePermission auto-passes when user has the perm', () async {
      // Bootstrap admin (id=1) has sales_delete (not in criticalFinancialOps).
      final resp = await ApiUserCtx.requirePermission(
          makeRequest(userId: 1), db, 'sales_delete');
      expect(resp, isNull);
    });
  });
}
