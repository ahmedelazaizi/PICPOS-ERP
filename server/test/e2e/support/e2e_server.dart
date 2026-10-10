// خادم سحابة حقيقي للاختبارات الطرفية (E2E) عبر HTTP.
//
// يفتح مخططًا (schema) معزولًا في Postgres الاختباري، يبذر شركة العرض
// (seedDemo) + شركة ثانية فارغة (للعزل بين المستأجرين)، ثم يخدم
// `app.handler` على منفذ حر ويطبع سطرًا واحدًا:
//   E2E_READY {"url":"http://127.0.0.1:PORT","adminKey":"...","companyA":"...","companyB":"..."}
//
// يعمل حتى يصله `stop` أو إغلاق stdin، فيُسقط المخطط ويخرج. تُشغّله حزم
// Flutter (mobile*, الجذر) كعملية فرعية لأن تلك الحزم لا تعتمد على picpos_cloud.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:picpos_cloud/picpos_cloud.dart';
import 'package:shelf/shelf_io.dart' as io;

const adminKey = 'e2e-admin-key';
const companyB = '00000000-0000-4000-8000-00000000cb01';

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final schema = 'e2e_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';
  final db = await CloudDatabase.open(
    host: env['TEST_DB_HOST'] ?? 'localhost',
    port: int.parse(env['TEST_DB_PORT'] ?? '55432'),
    database: env['TEST_DB_NAME'] ?? 'picpos_cloud',
    username: env['TEST_DB_USER'] ?? 'picpos',
    password: env['TEST_DB_PASSWORD'] ?? 'picpos_test_only',
    schema: schema,
    maxConnections: 4,
  );
  const secret = 'e2e-secret-0123456789-0123456789-abcdef';
  // --pair-limit=N يرفع حدّ محاولات الاقتران (الافتراضي الإنتاجي 5/عنوان/10 دقائق)
  // كي لا تستهلك اختبارات متعددة على خادم واحد ميزانية بعضها؛ اختبار حدّ المعدل
  // نفسه يعمل بالتوصيل الإنتاجي الافتراضي (CloudServices.create).
  final pairArg = args.where((a) => a.startsWith('--pair-limit=')).firstOrNull;
  final CloudApp app;
  if (pairArg == null) {
    app = (await CloudServices.create(
      db: db,
      tokenSecret: secret,
      adminKey: adminKey,
      provider: MockWhatsAppProvider(),
      pullOverlapMs: 0,
    ))
        .app;
  } else {
    final n = int.parse(pairArg.substring('--pair-limit='.length));
    RateLimiter pair() => RateLimiter(max: n, window: const Duration(minutes: 10));
    await db.migrate();
    app = CloudApp(
      db: db,
      auth: AuthService(db, SessionTokens(secret), pairLimiter: pair()),
      sync: SyncService(db, pullOverlapMs: 0),
      outbox: WhatsAppOutbox(db, MockWhatsAppProvider()),
      adminKey: adminKey,
      admin: AdminService(db, SessionTokens('$secret|manage'), pairLimiter: pair()),
    );
  }  await seedDemo(db, pinIterations: 1000);
  await db.query(
      "INSERT INTO companies (global_id, name, currency, default_tax_rate, integrity_secret) "
      "VALUES (@g, 'Other Tenant', 'JOD', 0, 'x')",
      {'g': companyB});
  final server = await io.serve(app.handler, InternetAddress.loopbackIPv4, 0);

  var closing = false;
  Future<void> shutdown() async {
    if (closing) return;
    closing = true;
    await server.close(force: true);
    try {
      await db.dropSchema();
      await db.close();
    } finally {
      exit(0);
    }
  }

  stdin.transform(utf8.decoder).listen((_) => shutdown(), onDone: shutdown);
  stdout.writeln('E2E_READY ${jsonEncode({
        'url': 'http://127.0.0.1:${server.port}',
        'adminKey': adminKey,
        'companyA': Demo.companyGid,
        'companyB': companyB,
      })}');
}
