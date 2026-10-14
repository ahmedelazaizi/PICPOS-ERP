// م3-7 — الكتابة من عميل الويب عبر HTTP (لا كتابة مباشرة على القاعدة) على خادم
// shelf حقيقي وقاعدة SQLite في الذاكرة:
//   دخول → webSessionProvider → ClientWriteInterceptor.createReceipt
//        → POST /api/receipts بـ X-Session-Token (aud:'web') → ApiDataHandler.
//
// المضيف يعمل في **Isolate مستقل** (كما في الواقع: المتصفّح والمضيف عمليتان).
// السبب: `SyncInterceptor.instance` حالة ساكنة على مستوى العملية؛ لو شارك
// المضيفُ عمليةَ العميل لرأى نفسه «وضع عميل» وحاول إرسال قيوده إلى نفسه.
//
// المثبَت: السند يُنشأ على المضيف ويظهر عبر قناة /webdb؛ انقطاع الخادم يرمي
// MirrorOfflineException (شبكة) برسالة عربية؛ مستخدم بلا صلاحية يُرفض (403) بخطأ
// خادم لا شبكة؛ والمسارات مغلقة لرمز الويب ما لم يُفعَّل enableWebSessionWrites.
//
// `WebSession.treatAsWebForTesting` يجعل VM يتصرّف كمتصفّح (kIsWeb = false هنا).
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart' show Value, Variable, driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:ural_erp/data/database/sync_interceptor.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/services/api/api_auth_middleware.dart';
import 'package:ural_erp/services/api/api_handler.dart';
import 'package:ural_erp/services/api/api_session_token.dart';
import 'package:ural_erp/services/client_write_interceptor.dart';
import 'package:ural_erp/services/server_proxy.dart';
import 'package:ural_erp/services/write_router.dart';
import 'package:ural_erp/web/web_providers.dart';
import 'package:ural_erp/web/web_session.dart';

/// رسالة بدء المضيف: منفذ الإرجاع + هل تُفتح مسارات الكتابة لرمز الويب.
class _HostArgs {
  const _HostArgs(this.reply, this.enableWrites);
  final SendPort reply;
  final bool enableWrites;
}

/// نقطة دخول الـIsolate: قاعدة في الذاكرة + خادم shelf حقيقي. يرسل المنفذ ثم
/// ينتظر أي رسالة ليُغلق.
Future<void> _hostMain(_HostArgs args) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  ApiSessionToken.deriveKey('write-seed');
  ApiAuthMiddleware.setToken('bearer-xyz');
  if (args.enableWrites) ApiAuthMiddleware.enableWebSessionWrites();

  final db = AppDatabase.forTesting();
  await db.customSelect('select 1').get();
  final now = DateTime.now();
  await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(
        name: '${now.year}-w',
        startDate: DateTime(now.year, 1, 1),
        endDate: DateTime(now.year, 12, 31),
        isClosed: const Value(false),
      ));
  await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'صندوق الويب',
        balance: const Value(0),
        isDefault: const Value(true),
        safeType: const Value('cash'),
        globalId: const Value('gid-safe-web'),
      ));
  // دور بلا أي صلاحية لاختبار الرفض.
  final roleId = await db.into(db.roles).insert(
        RolesCompanion.insert(name: 'مراقب', isSystemRole: const Value(false)),
      );
  await db.createUser(
    username: 'viewer',
    password: 'pw-viewer-1',
    displayName: 'Viewer',
    roleId: roleId,
  );

  final handler = const shelf.Pipeline()
      .addMiddleware(ApiAuthMiddleware.createMiddleware())
      .addHandler(ApiHandler(db).buildRouter().call);
  final server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);

  final control = ReceivePort();
  args.reply.send([server.port, control.sendPort]);
  await control.first; // أي رسالة = إيقاف
  await server.close(force: true);
  await db.close();
}

/// إحماء: طلب GET /api/health قبل الاختبارات الحساسة يدفع تكلفة أول اتصال
/// (JIT/فتح المقبس) على runner بطيء فلا تُحسب ضمن مهلة طلب الكتابة.
Future<void> _warmUp(String baseUrl) async {
  final client = HttpClient();
  try {
    final req = await client
        .getUrl(Uri.parse('$baseUrl/api/health'))
        .timeout(const Duration(seconds: 60));
    final res = await req.close().timeout(const Duration(seconds: 60));
    await res.drain<void>();
  } finally {
    client.close(force: true);
  }
}

void main() {
  // مهلة ServerProxy قابلة للحقن (الافتراضي 8s للإنتاج): نرفعها هنا لأن المضيف
  // في Isolate على runner بطيء (TimeoutException after 8s على GitHub Actions).
  final defaultTimeout = ServerProxy.requestTimeout;
  setUpAll(() => ServerProxy.requestTimeout = const Duration(seconds: 60));
  tearDownAll(() => ServerProxy.requestTimeout = defaultTimeout);

  late ReceivePort replies;
  late SendPort hostControl;
  late Isolate hostIsolate;
  late String baseUrl;
  late ProviderContainer container;
  var hostStopped = false;

  Future<void> startHost({required bool enableWrites}) async {
    replies = ReceivePort();
    hostIsolate =
        await Isolate.spawn(_hostMain, _HostArgs(replies.sendPort, enableWrites));
    final msg = await replies.first as List;
    baseUrl = 'http://127.0.0.1:${msg[0]}';
    hostControl = msg[1] as SendPort;
    hostStopped = false;
    await _warmUp(baseUrl);
  }

  void stopHost() {
    if (hostStopped) return;
    hostStopped = true;
    hostControl.send('stop');
  }

  setUp(() {
    container = ProviderContainer();
    WebSession.treatAsWebForTesting = true;
  });

  tearDown(() async {
    container.dispose();
    WebSession.treatAsWebForTesting = false;
    WebSession.active = null;
    SyncInterceptor.instance = null;
    SyncInterceptor.currentUserId = null;
    ServerProxy.instance.clearSessions();
    stopHost();
    // مهلة قصيرة لإغلاق المضيف ثم إنهاء قسريّ احتياطاً.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    hostIsolate.kill(priority: Isolate.immediate);
    replies.close();
  });

  /// دخول ثم تشغيل مسار الويب (الجلسة + قاعدة القناة + المعترِض).
  Future<WebSession> signIn(String user, String pass) async {
    final session = await WebAuthClient()
        .login(baseUrl: baseUrl, username: user, password: pass);
    container.dispose();
    container = ProviderContainer(overrides: webProviderOverrides);
    container.read(webSessionProvider.notifier).signIn(session);
    // يبني قاعدة القناة ويثبّت المعترِض، ويفتح القناة فعلاً قبل أي انقطاع.
    await container.read(databaseProvider).customSelect('select 1').get();
    return session;
  }

  Future<int> countByGid(String gid) async {
    final rows = await container.read(databaseProvider).customSelect(
        'select count(*) as n from safe_transactions where global_id = ?',
        variables: [Variable<String>(gid)]).get();
    return rows.single.data['n'] as int;
  }

  group('مضيف بمسارات كتابة مفعّلة', () {
    setUp(() => startHost(enableWrites: true));

    test('الويب = وضع «مرآة»: المعترِض في وضع العميل والجلسة تُختم', () async {
      final s = await signIn('admin', 'admin');
      expect(WriteRouter.isWebClient, isTrue);
      expect(WriteRouter.isMirrorActive, isTrue);
      expect(SyncInterceptor.isClientMode, isTrue);
      expect(SyncInterceptor.currentUserId, s.userId);
      expect(ServerProxy.instance.hasSessionToken(s.userId), isTrue);
    });

    test('سند قبض من عميل الويب يمرّ عبر HTTP ويظهر عبر قناة /webdb', () async {
      final s = await signIn('admin', 'admin');
      const gid = 'gid-receipt-web-1';
      final webDb = container.read(databaseProvider);
      final safes = await webDb.customSelect("select id from safes where global_id = 'gid-safe-web'").get();
      final safeId = safes.single.data['id'] as int;
      expect(await countByGid(gid), 0);

      final serverId = await ClientWriteInterceptor.createReceipt(
        amount: 125,
        category: 'other',
        description: 'سند من الويب',
        safeId: safeId,
        userId: s.userId,
        globalId: gid,
      );
      expect(serverId, isNotNull);

      // يظهر عبر قناة القراءة بالمعرّف الذي أعاده المضيف نفسه.
      final viaWeb = await webDb.customSelect(
          'select id, amount, safe_id from safe_transactions '
          'where global_id = ?',
          variables: [const Variable<String>(gid)]).get();
      expect(viaWeb, hasLength(1));
      expect(viaWeb.single.data['id'], serverId);
      expect(viaWeb.single.data['amount'], 125);
      expect(viaWeb.single.data['safe_id'], safeId);
    });

    test('تكرار نفس globalId لا يضاعف السند (idempotent)', () async {
      final s = await signIn('admin', 'admin');
      final webDb = container.read(databaseProvider);
      final safeId = (await webDb.customSelect("select id from safes where global_id = 'gid-safe-web'").get())
          .single
          .data['id'] as int;
      for (var i = 0; i < 2; i++) {
        await ClientWriteInterceptor.createReceipt(
          amount: 10,
          category: 'other',
          safeId: safeId,
          userId: s.userId,
          globalId: 'gid-receipt-web-dup',
        );
      }
      expect(await countByGid('gid-receipt-web-dup'), 1);
    });

    test('انقطاع الخادم يرمي MirrorOfflineException (شبكة) برسالة عربية',
        () async {
      await signIn('admin', 'admin');
      stopHost();
      await Future<void>.delayed(const Duration(milliseconds: 500));

      await expectLater(
        ClientWriteInterceptor.createReceipt(amount: 5, category: 'other'),
        throwsA(isA<MirrorOfflineException>()
            .having((e) => e.isNetworkIssue, 'isNetworkIssue', isTrue)
            .having((e) => e.toString(), 'message', contains('فقد الاتصال'))),
      );
    });

    test('مستخدم بلا صلاحية يُرفض (403) بخطأ خادم لا بخطأ شبكة', () async {
      await signIn('viewer', 'pw-viewer-1');

      await expectLater(
        ClientWriteInterceptor.createReceipt(amount: 5, category: 'other'),
        throwsA(isA<MirrorOfflineException>()
            .having((e) => e.isNetworkIssue, 'isNetworkIssue', isFalse)
            .having((e) => e.detail, 'detail', contains('403'))),
      );
    });
  });

  group('مضيف بلا تفعيل (الافتراضي)', () {
    setUp(() => startHost(enableWrites: false));

    test('المسارات مغلقة لرمز الويب ما لم تُفعَّل enableWebSessionWrites',
        () async {
      await signIn('admin', 'admin');
      await expectLater(
        ClientWriteInterceptor.createReceipt(amount: 5, category: 'other'),
        throwsA(isA<MirrorOfflineException>()
            .having((e) => e.isNetworkIssue, 'isNetworkIssue', isFalse)
            .having((e) => e.detail, 'detail', contains('401'))),
      );
    });
  });
}
