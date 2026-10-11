// E-02 المرحلة أ: الجلسات/الطاولات/الوسيط/health بأسرارٍ مفصولةٍ عن مفتاح القاعدة.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_auth_middleware.dart';
import 'package:ural_erp/services/api/api_handler.dart';
import 'package:ural_erp/services/api/api_session_token.dart';
import 'package:ural_erp/services/api/lan_pairing_service.dart';
import 'package:ural_erp/services/api/server_secrets.dart';
import 'package:ural_erp/services/api/session_key_watch.dart';
import 'package:ural_erp/services/api/table_bill_legacy_acceptance.dart';
import 'package:ural_erp/services/api/table_bill_token.dart';
import 'package:ural_erp/services/secret_store.dart';

Future<void> _noLog(String tag, String msg) async {}

void main() {
  setUpAll(DiagnosticLogger.enableTestMode);
  tearDown(() {
    ApiSessionToken.clearKey();
    TableBillToken.clearKey();
    ApiAuthMiddleware.clearToken();
    ApiAuthMiddleware.clearReady();
    ApiAuthMiddleware.clearPairingService();
  });

  group('الجلسات بمفتاح مفصول', () {
    test('توكن مُصدَر بالمفتاح المشتق القديم يُرفض بعد التحويل', () async {
      // قبل: مفتاح مشتق من بذرة الجهاز (المسار القديم).
      ApiSessionToken.deriveKey('legacy-seed');
      final legacyToken = ApiSessionToken.mint(9);
      final legacyWeb = ApiSessionToken.mintWeb(9);
      expect(ApiSessionToken.verify(legacyToken), 9);

      // بعد: ServerSecrets يضبط سرًّا عشوائياً مستقلاً.
      await ServerSecrets(store: MemorySecretStore(), logger: _noLog).initialize();

      expect(ApiSessionToken.verify(legacyToken), isNull);
      expect(ApiSessionToken.verifyWeb(legacyWeb), isNull);
      expect(ApiSessionToken.verify(ApiSessionToken.mint(9)), 9);
    });

    test('setSigningKey يرفض مفتاحاً قصيراً', () {
      expect(() => ApiSessionToken.setSigningKey(List.filled(8, 1)),
          throwsArgumentError);
    });
  });

  group('رموز الطاولات وعلم القبول القديم (ق-3 أ)', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting());
    tearDown(() => db.close());

    test('القديم يُقبل للتحقق فقط ما دام العلم true؛ الجديد يُصدَر بالجديد؛ '
        'وبعد الإطفاء يُرفض القديم', () async {
      // رمز طاولة مطبوع سابقاً بالمفتاح المشتق.
      TableBillToken.deriveKey('legacy-seed');
      final printed = TableBillToken.mintTable(12);

      await ServerSecrets(store: MemorySecretStore(), logger: _noLog).initialize();
      // الافتراضي (لا قيمة في settings) = مقبول.
      expect(await TableBillLegacyAcceptance.isEnabled(db), isTrue);
      await TableBillLegacyAcceptance.apply(db, 'legacy-seed');

      expect(TableBillToken.verifyTable(printed), 12);
      final fresh = TableBillToken.mintTable(12);
      expect(fresh, isNot(printed), reason: 'الإصدار بالمفتاح الجديد فقط');
      expect(TableBillToken.verifyTable(fresh), 12);

      // المشتق القديم لا يصلح لرمز الجلسة/الرقم (تحقق فقط من verifyTable).
      final openedAt = DateTime.utc(2026, 1, 1);
      TableBillToken.deriveKey('legacy-seed');
      final legacySession =
          TableBillToken.mintSession(orderId: 1, openedAt: openedAt);
      await ServerSecrets(store: MemorySecretStore(), logger: _noLog).initialize();
      await TableBillLegacyAcceptance.apply(db, 'legacy-seed');
      expect(
          TableBillToken.verifySession(legacySession,
              orderId: 1, openedAt: openedAt),
          isFalse);

      // إطفاء العلم.
      await TableBillLegacyAcceptance.disable(db);
      expect(await TableBillLegacyAcceptance.isEnabled(db), isFalse);
      expect(TableBillToken.verifyTable(printed), isNull);
      expect(TableBillToken.verifyTable(TableBillToken.mintTable(12)), 12);

      // وبعد إعادة التشغيل يبقى مطفأً.
      await TableBillLegacyAcceptance.apply(db, 'legacy-seed');
      expect(TableBillToken.verifyTable(printed), isNull);
    });
  });

  group('الوسيط: الجهاز المقترن بلا bearer قديم', () {
    Future<Response> run(Request r) => Future.value(
        ApiAuthMiddleware.createMiddleware()((req) async => Response.ok(
            '${req.context['lanDeviceId']}'))(r));

    test('بلا markReady ولا توكن ⇒ 403 (فشل مغلق)', () async {
      final r = await run(Request('GET', Uri.parse('http://x/api/products')));
      expect(r.statusCode, 403);
    });

    test('مقترن يعمل بعد markReady مع _activeToken == null؛ والقديم/المجهول مرفوض',
        () async {
      final pairing = LanPairingService.forTesting(
        installSecret: 'per-install-secret-with-at-least-32-bytes',
        makeCode: () => 'PAIR1234',
      );
      ApiAuthMiddleware.setPairingService(pairing);
      pairing.issuePairingCode(serverHost: 'h', port: 1);
      final paired = await pairing.pair(
          code: 'PAIR1234', deviceId: 'dev-1', deviceName: 'T', ip: '10.0.0.2');
      ApiAuthMiddleware.clearToken();
      ApiAuthMiddleware.markReady();
      expect(ApiAuthMiddleware.activeToken, isNull);

      final ok = await run(Request('GET', Uri.parse('http://x/api/products'),
          headers: {
            'authorization': 'Bearer ${paired.token}',
            'x-device-id': 'dev-1',
          }));
      expect(ok.statusCode, 200);
      expect(await ApiAuthMiddleware.verifyCredential(paired.token!, 'dev-1'),
          isTrue);

      final bad = await run(Request('GET', Uri.parse('http://x/api/products'),
          headers: {'authorization': 'Bearer nope', 'x-device-id': 'dev-1'}));
      expect(bad.statusCode, 403);
      final none = await run(Request('GET', Uri.parse('http://x/api/products')));
      expect(none.statusCode, 401);
    });
  });

  group('sessionKeyId', () {
    test('/api/health يعلن sessionKeyId (8 hex) ويتغيّر بتدوير الجلسات', () async {
      final db = AppDatabase.forTesting();
      addTearDown(db.close);
      final secrets =
          ServerSecrets(store: MemorySecretStore(), logger: _noLog);
      await secrets.initialize();
      final handler = ApiHandler(db).buildRouter();

      Future<String?> kid() async {
        final res = await handler
            .call(Request('GET', Uri.parse('http://localhost/api/health')));
        final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
        return body['sessionKeyId'] as String?;
      }

      final first = await kid();
      expect(first, matches(RegExp(r'^[0-9a-f]{8}$')));
      expect(first, ApiSessionToken.keyId);
      await secrets.rotate(ServerSecretKind.session);
      expect(await kid(), isNot(first));
    });

    test('بلا مفتاح لا يُعلَن sessionKeyId', () async {
      final db = AppDatabase.forTesting();
      addTearDown(db.close);
      final res = await ApiHandler(db)
          .buildRouter()
          .call(Request('GET', Uri.parse('http://localhost/api/health')));
      final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      expect(body.containsKey('sessionKeyId'), isFalse);
    });

    test('SessionKeyWatch: أول معرّف لا يُبطل؛ تغيّره يُبطل مرة؛ الغياب يتجاهل', () {
      final watch = SessionKeyWatch();
      var calls = 0;
      void inv() => calls++;
      expect(watch.observe('aaaaaaaa', inv), isFalse);
      expect(watch.observe('aaaaaaaa', inv), isFalse);
      expect(watch.observe(null, inv), isFalse);
      expect(watch.observe('bbbbbbbb', inv), isTrue);
      expect(watch.observe('bbbbbbbb', inv), isFalse);
      expect(calls, 1);
    });
  });
}
