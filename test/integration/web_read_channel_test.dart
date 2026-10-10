// م3-5 — قناة قراءة الويب `GET /webdb?ticket=...` على خادم shelf حقيقي
// (localhost) وقاعدة SQLite في الذاكرة، من الدخول إلى الاستعلام:
//   POST /api/web/session → POST /api/web/ws-ticket → WebSocket /webdb → drift.
//
// المثبَت: تذكرة صحيحة تعمل؛ استعمالها ثانيةً يرفض؛ الكتابة عبر القناة
// ترفض؛ جدول غير مسموح لهذا المستخدم يرفض؛ وإغلاق القناة عند تعطيل المستخدم
// أو تغيّر دوره أو إلغاء جلسته.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
// ignore: experimental_member_use
import 'package:drift/remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_auth_middleware.dart';
import 'package:ural_erp/services/api/api_handler.dart';
import 'package:ural_erp/services/api/api_session_token.dart';
import 'package:ural_erp/services/api/api_web_session_handler.dart';
import 'package:ural_erp/services/api/web_session_guard.dart';
import 'package:ural_erp/services/web_read/drift_json_channel.dart';
import 'package:ural_erp/services/web_read/web_read_channel_host.dart';
import 'package:web_socket_channel/io.dart';

/// عميل بلا جداول معرَّفة؛ SQL خام فقط (التحقق على المضيف).
class _RawDb extends GeneratedDatabase {
  _RawDb(super.connection) : super.connect();

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  int get schemaVersion => 1;
}

/// الرفضُ سببُه سياسة قراءة الويب (لا خطأ SQL عارض).
final _policyViolation = predicate<Object>(
  (e) => e.toString().contains('WebReadPolicyViolation'),
  'WebReadPolicyViolation',
);

void main() {
  late AppDatabase db;
  late int userId;
  late int otherRoleId;
  late HttpServer server;
  late Uri base;

  Future<void> start(shelf.Handler router) async {
    final handler = const shelf.Pipeline()
        .addMiddleware(ApiAuthMiddleware.createMiddleware())
        .addHandler(router);
    server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
  }

  setUp(() async {
    // عملاء drift عدة فوق منفِّذ واحد عن قصد (قراءة فقط) — نكتم التحذير.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    ApiSessionToken.deriveKey('chan-seed');
    ApiSessionToken.clearRevokedForTesting();
    ApiAuthMiddleware.setToken('bearer-xyz');
    WebWsTicketStore.clear();
    WebOriginPolicy.configure(const []);
    WebSessionGuard.configure(null);

    db = AppDatabase.forTesting();
    // دور بلا أي صلاحية: يقرأ الجداول المرجعية فقط (units) لا المبيعات.
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
              name: 'مراقب', isSystemRole: const Value(false)),
        );
    otherRoleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
              name: 'دور آخر', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'viewer',
      password: 'pw-viewer-1',
      displayName: 'Viewer',
      roleId: roleId,
    );
  });

  tearDown(() async {
    await server.close(force: true);
    ApiSessionToken.clearKey();
    ApiAuthMiddleware.clearToken();
    WebWsTicketStore.clear();
    WebSessionGuard.configure(null);
    await db.close();
  });

  Future<String> login() async {
    final r = await http.post(
      base.resolve('/api/web/session'),
      body: jsonEncode({'username': 'viewer', 'password': 'pw-viewer-1'}),
    );
    expect(r.statusCode, 200, reason: r.body);
    return (jsonDecode(r.body) as Map)['token'] as String;
  }

  Future<String> ticketFor(String token) async {
    final r = await http.post(
      base.resolve('/api/web/ws-ticket'),
      headers: {ApiSessionToken.headerName: token},
    );
    expect(r.statusCode, 200, reason: r.body);
    return (jsonDecode(r.body) as Map)['ticket'] as String;
  }

  IOWebSocketChannel connect(String ticket) => IOWebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:${server.port}/webdb?ticket=$ticket'),
      );

  Future<_RawDb> openClient(String ticket) async {
    final ws = connect(ticket);
    await ws.ready;
    return _RawDb(
      DatabaseConnection.delayed(
        connectToRemoteAndInitialize(driftJsonChannel(ws)),
      ),
    );
  }

  /// خادم عبر `ApiHandler.buildRouter` الحقيقي (يثبت التوصيل في الموجِّه).
  Future<void> startReal() => start(ApiHandler(db).buildRouter().call);

  /// خادم بدوريّة فحص قصيرة لاختبارات الإغلاق.
  Future<void> startFastCheck() {
    WebSessionGuard.configure(db);
    final router = Router()
      ..post('/api/web/session', ApiWebSessionHandler(db).login)
      ..post('/api/web/ws-ticket', ApiWebSessionHandler(db).issueTicket)
      ..get(
        '/webdb',
        WebReadChannelHost(db, checkInterval: const Duration(milliseconds: 100))
            .handle,
      );
    return start(router.call);
  }

  test('تذكرة صحيحة: قراءة جدول مسموح تعمل', () async {
    await startReal();
    final ticket = await ticketFor(await login());
    final client = await openClient(ticket);
    final rows = await client.customSelect('select count(*) as n from units').get();
    final direct = await db.customSelect('select count(*) as n from units').get();
    expect(rows.single.read<int>('n'), direct.single.read<int>('n'));
    await client.close();
  });

  test('تذكرة مستعملة مرة ثانية تُرفض (قبل الترقية)', () async {
    await startReal();
    final ticket = await ticketFor(await login());
    final first = await openClient(ticket);
    await first.customSelect('select 1 as x').get();

    final second = connect(ticket);
    await expectLater(second.ready, throwsA(anything));
    await first.close();
  });

  test('تذكرة مجهولة أو بلا ticket تُرفض', () async {
    await startReal();
    await expectLater(connect('bogus').ready, throwsA(anything));
    final plain = await http.get(base.resolve('/webdb'));
    expect(plain.statusCode, 401);
  });

  test('Origin غريب يُرفض على /webdb', () async {
    await startReal();
    final ticket = await ticketFor(await login());
    final ws = IOWebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:${server.port}/webdb?ticket=$ticket'),
      headers: {'Origin': 'https://evil.example'},
    );
    await expectLater(ws.ready, throwsA(anything));
  });

  test('الكتابة عبر القناة تُرفض ولا تمسّ القاعدة', () async {
    await startReal();
    final client = await openClient(await ticketFor(await login()));
    final before =
        (await db.customSelect('select count(*) as n from units').get())
            .single
            .read<int>('n');
    await expectLater(
      client.customStatement(
        "insert into units (name, symbol) values ('x','x')",
      ),
      throwsA(_policyViolation),
    );
    await expectLater(
      client.customStatement('delete from units'),
      throwsA(_policyViolation),
    );
    final after =
        (await db.customSelect('select count(*) as n from units').get())
            .single
            .read<int>('n');
    expect(after, before);
    await client.close();
  });

  test('جدول غير مسموح لهذا المستخدم يُرفض (مبيعات/مستخدمون/POS)', () async {
    await startReal();
    final client = await openClient(await ticketFor(await login()));
    for (final sql in [
      'select * from sales_invoices',
      'select * from users',
      'select * from pos_terminals',
      'select name from sqlite_master',
      'pragma table_info(units)',
    ]) {
      await expectLater(client.customSelect(sql).get(), throwsA(_policyViolation),
          reason: sql);
    }
    // والقناة ما زالت حيّة للمسموح بعد الرفض.
    await client.customSelect('select 1 as x').get();
    await client.close();
  });

  test('تعطيل المستخدم يغلق القناة (4401)', () async {
    await startFastCheck();
    final ws = connect(await ticketFor(await login()));
    await ws.ready;
    final done = ws.stream.drain<void>();
    await (db.update(db.users)..where((u) => u.id.equals(userId)))
        .write(const UsersCompanion(isActive: Value(false)));
    await done.timeout(const Duration(seconds: 5));
    expect(ws.closeCode, kWebChannelSessionEnded);
  });

  test('تغيّر دور المستخدم يغلق القناة', () async {
    await startFastCheck();
    final ws = connect(await ticketFor(await login()));
    await ws.ready;
    final done = ws.stream.drain<void>();
    await (db.update(db.users)..where((u) => u.id.equals(userId)))
        .write(UsersCompanion(roleId: Value(otherRoleId)));
    await done.timeout(const Duration(seconds: 5));
    expect(ws.closeCode, kWebChannelSessionEnded);
  });

  test('إلغاء sid الجلسة يغلق القناة', () async {
    await startFastCheck();
    final token = await login();
    final sid = ApiSessionToken.verifyWeb(token)!.sid;
    final ws = connect(await ticketFor(token));
    await ws.ready;
    final done = ws.stream.drain<void>();
    ApiSessionToken.revokeSid(sid);
    await done.timeout(const Duration(seconds: 5));
    expect(ws.closeCode, kWebChannelSessionEnded);
  });

  group('إبطال جلسة الويب عبر HTTP (بند الأمن 1/ج)', () {
    Future<int> ticketStatus(String token) async => (await http.post(
          base.resolve('/api/web/ws-ticket'),
          headers: {ApiSessionToken.headerName: token},
        ))
            .statusCode;

    test('POST /api/web/logout يُبطل الرمز فوراً ولا تُصدَر له تذكرة', () async {
      await startReal();
      final token = await login();
      expect(await ticketStatus(token), 200);

      final out = await http.post(
        base.resolve('/api/web/logout'),
        headers: {ApiSessionToken.headerName: token},
      );
      expect(out.statusCode, 200, reason: out.body);
      expect(ApiSessionToken.verifyWeb(token), isNull);
      expect(await ticketStatus(token), 401);
    });

    test('logout بلا رمز ويب يُرفض 401', () async {
      await startReal();
      final r = await http.post(base.resolve('/api/web/logout'));
      expect(r.statusCode, 401);
    });

    test('تعطيل المستخدم يُبطل الرمز على HTTP (دون انتظار انتهائه)', () async {
      await startReal();
      final token = await login();
      expect(await ticketStatus(token), 200);
      await (db.update(db.users)..where((u) => u.id.equals(userId)))
          .write(const UsersCompanion(isActive: Value(false)));
      WebSessionGuard.userChanged(userId); // ما يفعله putUser (يُسقط الكاش)
      expect(await ticketStatus(token), 401);
    });

    test('تغيّر دور المستخدم بعد الإصدار يُبطل الرمز', () async {
      await startReal();
      final token = await login();
      expect(await ticketStatus(token), 200);
      await (db.update(db.users)..where((u) => u.id.equals(userId)))
          .write(UsersCompanion(roleId: Value(otherRoleId)));
      WebSessionGuard.userChanged(userId);
      expect(await ticketStatus(token), 401);
    });

    test('revokeUser (تغيير كلمة المرور/التعطيل) يُبطل رموزه السابقة فقط',
        () async {
      await startReal();
      final old = await login();
      expect(await ticketStatus(old), 200);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      WebSessionGuard.userChanged(userId, revokeSessions: true);
      expect(await ticketStatus(old), 401);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(await ticketStatus(await login()), 200);
    });
  });
}
