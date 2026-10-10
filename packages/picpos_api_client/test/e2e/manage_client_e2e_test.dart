// E2E: عميل `CloudManageClient` الحقيقي (HttpApiTransport) ↔ خادم السحابة
// الحقيقي (عملية فرعية + Postgres) مع دور مكتب يوقّع لقطاته بـ Ed25519 حقيقي.
// يغطي عقد /manage/* كما يستعمله تطبيق الإدارة، وهجمات الإعادة/التبديل/التزوير.
import 'dart:math';

import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:test/test.dart';

import 'support/e2e_cloud.dart';
import 'support/e2e_desktop.dart';

final _rng = Random.secure();
String _id() => List.generate(16, (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

void main() {
  late E2eCloud cloud;
  late E2eDesktop desk;
  const owner = 'e2e-owner';

  CloudManageClient newClient() => CloudManageClient(
        transport: HttpApiTransport(
          kind: TransportKind.cloud,
          baseUri: Uri.parse(cloud.url),
          policy: UrlPolicy.development,
        ),
        headers: const ApiHeaderBuilder(appVersion: '0.1.0+1'),
      );

  Future<CloudManageClient> pairedClient(String userGid) async {
    final c = newClient();
    await c.pair(
        code: await desk.adminPairingCode(userGid),
        deviceId: _id(),
        deviceName: 'E2E',
        appVersion: '0.1.0+1');
    return c;
  }

  setUpAll(() async {
    cloud = await E2eCloud.start(pairLimit: 100);
    desk = await E2eDesktop.link(cloud);
    final r = await desk.pushUsers([
      await desk.userJson(owner, 'owner'),
      await desk.userJson('e2e-branch2', 'branch2', branchScope: [2], permissions: ['mobile_admin_access', 'dashboard_sales_today']),
    ]);
    expect(r.status, 200, reason: '$r');
  });
  tearDownAll(() => cloud.stop());

  test('اقتران ← دخول ← لقطات موقّعة تُتحقَّق بالمفتاح المثبّت، ولقطات مزوّرة تُحسب مرفوضة', () async {
    final client = newClient();
    final pair = await client.pair(
        code: await desk.adminPairingCode(owner), deviceId: _id(), deviceName: 'E2E', appVersion: '0.1.0+1');
    expect(pair.desktopSigningKey, desk.publicKey);
    expect(pair.user?.username, 'owner');
    expect(pair.company.decimals, 3);
    final verifier = PayloadVerifier.fromBase64(pair.desktopSigningKey);

    final rogue = await PayloadSigner.fromSeed(List<int>.filled(32, 77));
    final forged = await buildSignedSnapshot(rogue,
        kind: SnapshotKinds.profitToday, scope: 'all', asOf: DateTime.now().toUtc(), data: {'grossProfit': '999999.000'});
    // ريلاي خبيث: لقطة صحيحة التوقيع لنوع kpi.today تُخزَّن تحت نوع آخر.
    final real = await desk.signed(SnapshotKinds.kpiToday, {'netSales': '51.000', 'invoiceCount': 2});
    final relayed = {...real, 'kind': SnapshotKinds.cash};
    final approvals = await desk.signed(SnapshotKinds.approvalsSalesReturns, {
      'items': [
        {'ref': 'SR-7', 'summary': 'مرتجع', 'amount': '4.500'},
      ],
    });
    final push = await desk.pushSnapshots([real, forged, relayed, approvals]);
    expect(push.status, 200, reason: '$push');

    // بلا جلسة: لا لقطات.
    await expectLater(client.snapshots([]), throwsA(isA<ArgumentError>()));

    await client.login(username: 'owner', password: E2eDesktop.defaultPassword);
    final v = await client.verifiedSnapshots(verifier);
    final kinds = {for (final i in v.items) i.kind};
    expect(kinds, {SnapshotKinds.kpiToday, SnapshotKinds.approvalsSalesReturns});
    expect(v.rejected, 2, reason: 'المزوَّرة + المبدَّلة النوع');
    final kpi = v.find(SnapshotKinds.kpiToday)!.payload as Map;
    expect(kpi['netSales'], '51.000');
    final appr = (v.find(SnapshotKinds.approvalsSalesReturns)!.payload as Map)['items'] as List;
    expect((appr.single as Map)['ref'], 'SR-7');
    expect(v.desktopLastSeenAt, isNotNull);

    // مفتاح مثبّت مختلف (جوال مقترن بمكتب آخر) ← لا شيء يُتحقَّق.
    final other = PayloadVerifier.fromBase64(await rogue.publicKeyBase64());
    final none = await client.verifiedSnapshots(other);
    expect(none.items.where((i) => i.kind != SnapshotKinds.profitToday), isEmpty);
  });

  test('كلمة مرور خاطئة ← unauthorized؛ بعد 5 فشل يُقفل المستخدم (429 rateLimited + retryAfter)', () async {
    await desk.pushUsers([await desk.userJson('e2e-lock', 'locked')]);
    final c = await pairedClient('e2e-lock');
    Future<ApiError> failLogin(String pw) async {
      try {
        await c.login(username: 'locked', password: pw);
      } on ApiError catch (e) {
        return e;
      }
      throw StateError('login unexpectedly succeeded');
    }

    for (var i = 0; i < 5; i++) {
      final e = await failLogin('wrong-pass-');
      expect(e.kind, ApiErrorKind.unauthorized, reason: e.code);
      expect(e.code, 'invalid_credentials');
    }
    final locked = await failLogin(E2eDesktop.defaultPassword);
    expect(locked.kind, ApiErrorKind.rateLimited, reason: '');
    expect(locked.retryAfter, isNotNull);
  });

  test('أرقام لوحة المفاتيح العربية-الهندية تُطابق كلمة مرور ASCII عند الدخول', () async {
    await desk.pushUsers([await desk.userJson('e2e-ar', 'arabic', password: '12345678')]);
    final c = await pairedClient('e2e-ar');
    final s = await c.login(username: 'arabic', password: '\u0661\u0662\u0663\u0664\u0665\u0666\u0667\u0668');
    expect(s.user.username, 'arabic');
  });

  test('إبطال الجهاز من المكتب ← deviceRevoked عند القراءة التالية', () async {
    final c = await pairedClient(owner);
    await c.login(username: 'owner', password: E2eDesktop.defaultPassword);
    final id = c.credentials.deviceId!;
    expect((await desk.revokeAdminDevice(id)).status, 200);
    await expectLater(
      c.snapshots([]),
      throwsA(isA<ApiError>().having((e) => e.kind, 'kind', ApiErrorKind.deviceRevoked)),
    );
  });

  test('إلغاء الاقتران من الجوال ← المكتب يرى revoked والدخول لاحقًا deviceRevoked', () async {
    final c = await pairedClient(owner);
    await c.login(username: 'owner', password: E2eDesktop.defaultPassword);
    final id = c.credentials.deviceId!;
    await c.unpair();
    final row = (await desk.adminDevices()).firstWhere((d) => d['deviceId'] == id);
    expect(row['revoked'], true);
    await expectLater(
      c.login(username: 'owner', password: E2eDesktop.defaultPassword),
      throwsA(isA<ApiError>().having((e) => e.kind, 'kind', ApiErrorKind.deviceRevoked)),
    );
  });

  test('نطاق الفرع: مستخدم الفرع 2 لا يتلقى إلا لقطات الفرع 2', () async {
    await desk.pushSnapshots([
      await desk.signed(SnapshotKinds.kpiToday, {'netSales': '9.000'}, scope: 'branch:2'),
      await desk.signed(SnapshotKinds.kpiToday, {'netSales': '7.000'}, scope: 'branch:3'),
    ]);
    final c = await pairedClient('e2e-branch2');
    await c.login(username: 'branch2', password: E2eDesktop.defaultPassword);
    final v = await c.verifiedSnapshots(PayloadVerifier.fromBase64(desk.publicKey));
    expect({for (final i in v.items) '${i.kind}@${i.scope}'}, {'kpi.today@branch:2'});
    expect(v.rejected, 0);
  });

  test('رمز اقتران مستعمل أو مجهول ← ApiError rejected/unauthorized ولا يقترن', () async {
    final code = await desk.adminPairingCode(owner);
    final a = newClient();
    await a.pair(code: code, deviceId: _id(), deviceName: 'A', appVersion: '1');
    final b = newClient();
    await expectLater(
      b.pair(code: code, deviceId: _id(), deviceName: 'B', appVersion: '1'),
      throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)),
    );
    expect(b.credentials.isPaired, isFalse);
  });

  test('عزل الشركات: جهاز إدارة شركة A لا يقرأ لقطات شركة B', () async {
    final deskB = await E2eDesktop.link(cloud, company: cloud.companyB);
    await deskB.pushUsers([await deskB.userJson('b-owner', 'bowner')]);
    await deskB.pushSnapshots([await deskB.signed(SnapshotKinds.kpiToday, {'netSales': 'B-ONLY'})]);
    final c = await pairedClient(owner);
    await c.login(username: 'owner', password: E2eDesktop.defaultPassword);
    final raw = await c.snapshotsEnvelope([SnapshotKinds.kpiToday]);
    expect(raw.toString(), isNot(contains('B-ONLY')));
    // مستخدم B بحساب A: اسم المستخدم لا ينتمي لـ A ← invalid_credentials.
    await expectLater(
      c.login(username: 'bowner', password: E2eDesktop.defaultPassword),
      throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)),
    );
  });
}
