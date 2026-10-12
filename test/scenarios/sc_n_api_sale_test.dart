// سيناريو (ن): فاتورة بيع نقدي عبر HTTP بالمضيف الحقيقي (POST /api/sales بجلسة ويب)،
// وقراءة النتيجة عبر قناة /webdb: مخزون −2، خزينة +200، فاتورة واحدة (idempotent).
// يكمّل test/integration/web_write_path_test.dart (سند القبض) ولا يكرره — هنا المبيعات.
// المضيف في Isolate مستقل (انظر ترويسة الاختبار المرجعي لسبب ذلك).
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
import 'package:ural_erp/services/server_proxy.dart';
import 'package:ural_erp/web/web_providers.dart';
import 'package:ural_erp/web/web_session.dart';

Future<void> _hostMain(SendPort reply) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  ApiSessionToken.deriveKey('sale-seed');
  ApiAuthMiddleware.setToken('bearer-sale');
  ApiAuthMiddleware.enableWebSessionWrites();

  final db = AppDatabase.forTesting();
  await db.customSelect('select 1').get();
  await db.syncDefaultAccounts();
  final wh = (await db.getDefaultWarehouse())!.id;
  final safe = (await db.getDefaultSafeByType('cash'))!.id;
  final pid = await db.insertProduct(ProductsCompanion.insert(
      code: 'API-1',
      name: 'صنف API',
      salePrice: const Value(100),
      costPrice: const Value(60),
      trackInventory: const Value(true)));
  await db.adjustStock(
      productId: pid, warehouseId: wh, quantity: 50, type: 'in', unitCost: 60);
  await db.openShift(1, 0); // مستخدم admin المبذور

  final handler = const shelf.Pipeline()
      .addMiddleware(ApiAuthMiddleware.createMiddleware())
      .addHandler(ApiHandler(db).buildRouter().call);
  final server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
  final control = ReceivePort();
  reply.send([server.port, control.sendPort, pid, wh, safe]);
  await control.first;
  await server.close(force: true);
  await db.close();
}

void main() {
  final defaultTimeout = ServerProxy.requestTimeout;
  setUpAll(() => ServerProxy.requestTimeout = const Duration(seconds: 60));
  tearDownAll(() => ServerProxy.requestTimeout = defaultTimeout);

  late ReceivePort replies;
  late SendPort hostControl;
  late Isolate hostIsolate;
  late String baseUrl;
  late int productId, warehouseId, safeId;
  late ProviderContainer container;

  setUp(() async {
    container = ProviderContainer();
    WebSession.treatAsWebForTesting = true;
    replies = ReceivePort();
    hostIsolate = await Isolate.spawn(_hostMain, replies.sendPort);
    final msg = await replies.first as List;
    baseUrl = 'http://127.0.0.1:${msg[0]}';
    hostControl = msg[1] as SendPort;
    productId = msg[2] as int;
    warehouseId = msg[3] as int;
    safeId = msg[4] as int;
    // إحماء المضيف قبل الطلبات الحساسة للمهلة.
    final c = HttpClient();
    try {
      final req = await c.getUrl(Uri.parse('$baseUrl/api/health'));
      await (await req.close()).drain<void>();
    } finally {
      c.close(force: true);
    }
  });

  tearDown(() async {
    container.dispose();
    WebSession.treatAsWebForTesting = false;
    WebSession.active = null;
    SyncInterceptor.instance = null;
    SyncInterceptor.currentUserId = null;
    ServerProxy.instance.clearSessions();
    hostControl.send('stop');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    hostIsolate.kill(priority: Isolate.immediate);
    replies.close();
  });

  Future<WebSession> signIn() async {
    final session = await WebAuthClient()
        .login(baseUrl: baseUrl, username: 'admin', password: 'admin');
    container.dispose();
    container = ProviderContainer(overrides: webProviderOverrides);
    container.read(webSessionProvider.notifier).signIn(session);
    await container.read(databaseProvider).customSelect('select 1').get();
    return session;
  }

  Map<String, dynamic> salePayload(int userId, String gid) => {
        'invoiceNumber': 'WEB-SALE-1',
        'globalId': gid,
        'warehouseId': warehouseId,
        'userId': userId,
        'subtotal': 200.0,
        'discount': 0.0,
        'tax': 0.0,
        'total': 200.0,
        'paid': 200.0,
        'paymentMethod': 'cash',
        'saleType': 'default',
        'cashSafeId': safeId,
        'items': [
          {
            'productId': productId,
            'quantity': 2.0,
            'unitPrice': 100.0,
            'total': 200.0,
            'costPrice': 60.0,
          }
        ],
      };

  Future<num> scalar(String sql, [List<Variable> v = const []]) async {
    final r = await container
        .read(databaseProvider)
        .customSelect(sql, variables: v)
        .getSingle();
    return r.data.values.first as num;
  }

  test('POST /api/sales بجلسة ويب: فاتورة 200 ← مخزون 48، خزينة 200، قيد متوازن',
      () async {
    final s = await signIn();
    const gid = 'gid-sale-web-1';
    final serverId = await ServerProxy.instance
        .submitSale(salePayload(s.userId, gid), idempotencyKey: gid);
    expect(serverId, isNotNull);

    expect(await scalar('select count(*) from sales_invoices where global_id = ?',
        const [Variable<String>(gid)]), 1);
    expect(await scalar('select total from sales_invoices where global_id = ?',
        const [Variable<String>(gid)]), 200);
    expect(await scalar('select current_stock from products where id = ?',
        [Variable<int>(productId)]), 48);
    expect(await scalar('select balance from safes where id = ?',
        [Variable<int>(safeId)]), 200);
    // القيد: مجموع المدين = مجموع الدائن = 200 (مبيعات) + 120 (تكلفة)
    expect(await scalar('select sum(debit) from journal_entry_lines'), 320);
    expect(await scalar('select sum(credit) from journal_entry_lines'), 320);
  });

  test('تكرار نفس الفاتورة (نفس globalId) لا يضاعف المخزون ولا الخزينة', () async {
    final s = await signIn();
    const gid = 'gid-sale-web-dup';
    for (var i = 0; i < 2; i++) {
      await ServerProxy.instance
          .submitSale(salePayload(s.userId, gid), idempotencyKey: gid);
    }
    expect(await scalar('select count(*) from sales_invoices where global_id = ?',
        const [Variable<String>(gid)]), 1);
    expect(await scalar('select current_stock from products where id = ?',
        [Variable<int>(productId)]), 48);
    expect(await scalar('select balance from safes where id = ?',
        [Variable<int>(safeId)]), 200);
  });
}
