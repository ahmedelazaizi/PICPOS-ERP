// بند الأمن 1/أ — تسريب GET /api/users (cardCode + الهاش) ورمز الويب.
//
// يمرّ الطلب عبر ApiAuthMiddleware الحقيقي + ApiHandler.buildRouter فوق
// SQLite في الذاكرة (بلا شبكة):
//   * رمز ويب لكاشير ⇒ 403 على GET /api/users (بوابة قراءة الجداول).
//   * رمز ويب لمن يملك users_manage ⇒ 200 لكن بلا cardCode/passwordHash/Salt.
//   * عميل LAN مصادَق (bearer + جلسة جهاز) ⇒ يحتفظ بسلوكه: cardCode والهاش.
//   * bearer بلا جلسة وبلا نافذة إقران ⇒ لا cardCode ولا هاش.

import 'dart:convert';

import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_auth_middleware.dart';
import 'package:ural_erp/services/api/api_handler.dart';
import 'package:ural_erp/services/api/api_session_token.dart';
import 'package:ural_erp/services/api/api_web_session_handler.dart';
import 'package:ural_erp/services/api/web_session_guard.dart';

void main() {
  late AppDatabase db;
  late shelf.Handler handler;
  late int cashierId;
  late int managerId;

  setUp(() async {
    ApiSessionToken.deriveKey('users-leak-seed');
    ApiSessionToken.clearRevokedForTesting();
    ApiAuthMiddleware.setToken('bearer-xyz');
    ApiAuthMiddleware.closePairingWindow();
    WebOriginPolicy.configure(const []);
    ApiAuthMiddleware.enableWebSessionWrites();

    db = AppDatabase.forTesting();
    final cashierRole = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
        );
    final managerRole = await db.into(db.roles).insert(
          RolesCompanion.insert(
              name: 'مدير مستخدمين', isSystemRole: const Value(false)),
        );
    final perm = await (db.select(db.permissions)
          ..where((p) => p.code.equals('users_manage')))
        .getSingle();
    await db.into(db.rolePermissions).insert(
          RolePermissionsCompanion.insert(
              roleId: managerRole, permissionId: perm.id),
          mode: InsertMode.insertOrIgnore,
        );
    cashierId = await db.createUser(
      username: 'cashier1',
      password: 'pw-cashier-1',
      displayName: 'Cashier',
      roleId: cashierRole,
      cardCode: 'CASHIER-CARD-111',
    );
    managerId = await db.createUser(
      username: 'manager1',
      password: 'pw-manager-1',
      displayName: 'Manager',
      roleId: managerRole,
      cardCode: 'MANAGER-CARD-222',
    );

    // الأدمن (id=1) هو الصفّ الذي يظهر دائماً في /api/users: نعطيه بطاقة.
    await (db.update(db.users)..where((u) => u.username.equals('admin')))
        .write(const UsersCompanion(cardCode: Value('ADMIN-CARD-000')));

    handler = const shelf.Pipeline()
        .addMiddleware(ApiAuthMiddleware.createMiddleware())
        .addHandler(ApiHandler(db).buildRouter().call);
  });

  tearDown(() async {
    ApiSessionToken.clearKey();
    ApiAuthMiddleware.clearToken();
    ApiAuthMiddleware.disableWebSessionWrites();
    WebSessionGuard.configure(null);
    await db.close();
  });

  Future<shelf.Response> getUsers(Map<String, String> headers) async =>
      await handler(
        shelf.Request('GET', Uri.parse('http://localhost/api/users'),
            headers: headers),
      );

  String webToken(int userId, int roleId) =>
      ApiSessionToken.mintWeb(userId, roleId: roleId, bindRole: true);

  Future<int> roleOf(int userId) async => (await (db.select(db.users)
            ..where((u) => u.id.equals(userId)))
          .getSingle())
      .roleId!;

  group('رمز ويب', () {
    test('كاشير بلا users_manage لا يستطيع GET /api/users (403) ولا يظهر cardCode',
        () async {
      final r = await getUsers({
        ApiSessionToken.headerName: webToken(cashierId, await roleOf(cashierId)),
      });
      expect(r.statusCode, 403);
      final body = await r.readAsString();
      expect(body, isNot(contains('cardCode')));
      expect(body, isNot(contains('CARD-')));
      expect(body, isNot(contains('passwordHash')));
    });

    test('حتى مع users_manage: لا cardCode ولا passwordHash ولا passwordSalt',
        () async {
      final r = await getUsers({
        ApiSessionToken.headerName: webToken(managerId, await roleOf(managerId)),
      });
      expect(r.statusCode, 200);
      final body = await r.readAsString();
      final users =
          (jsonDecode(body) as Map)['users'] as List<dynamic>;
      expect(users, isNotEmpty);
      for (final u in users.cast<Map<String, dynamic>>()) {
        expect(u.containsKey('cardCode'), isFalse);
        expect(u.containsKey('passwordHash'), isFalse);
        expect(u.containsKey('passwordSalt'), isFalse);
      }
      expect(body, isNot(contains('CARD-')));
    });

    test('مسار تحت بادئة الويب غير مدرج في قائمة سماح GET يُرفض 403', () async {
      ApiAuthMiddleware.webSessionPrefixes = ['/api/not-allowlisted'];
      final r = await handler(shelf.Request(
        'GET',
        Uri.parse('http://localhost/api/not-allowlisted'),
        headers: {
          ApiSessionToken.headerName:
              webToken(managerId, await roleOf(managerId)),
        },
      ));
      expect(r.statusCode, 403);
    });
  });

  group('عميل LAN مصادَق (السلوك الشرعي محفوظ)', () {
    test('bearer + جلسة جهاز ⇒ cardCode والهاش يصلان للمزامنة', () async {
      final r = await getUsers({
        'authorization': 'Bearer bearer-xyz',
        ApiSessionToken.headerName: ApiSessionToken.mint(managerId),
      });
      expect(r.statusCode, 200);
      final users = ((jsonDecode(await r.readAsString()) as Map)['users']
              as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final admin = users.firstWhere((u) => u['username'] == 'admin');
      expect(admin['cardCode'], 'ADMIN-CARD-000');
      expect(admin['passwordHash'], isNotEmpty);
    });

    test('bearer بلا جلسة وبلا نافذة إقران ⇒ لا cardCode ولا هاش', () async {
      final r = await getUsers({'authorization': 'Bearer bearer-xyz'});
      expect(r.statusCode, 200);
      final body = await r.readAsString();
      expect(body, isNot(contains('cardCode')));
      expect(body, isNot(contains('CARD-')));
      expect(body, isNot(contains('passwordHash')));
      expect(body, contains('admin'));
    });

    test('نافذة الإقران مفتوحة + رمز ويب ⇒ لا اعتمادات رغم النافذة', () async {
      ApiAuthMiddleware.openPairingWindow();
      addTearDown(ApiAuthMiddleware.closePairingWindow);
      final r = await getUsers({
        ApiSessionToken.headerName: webToken(managerId, await roleOf(managerId)),
      });
      expect(r.statusCode, 200);
      final body = await r.readAsString();
      expect(body, isNot(contains('CARD-')));
      expect(body, isNot(contains('passwordHash')));
    });
  });
}
