import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_admin/admin_session.dart';
import 'package:picpos_admin/app.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_api_client/testing.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_ui/picpos_ui.dart';

import 'support.dart';

void main() {
  setUpAll(loadTestFonts);

  testWidgets('pairing and login render signed dashboard and save credentials', (
    tester,
  ) async {
    setSurface(tester, kPhone);
    final signer = await PayloadSigner.fromSeed(List<int>.filled(32, 3));
    final key = await signer.publicKeyBase64();
    final snapshots = [
      await buildSignedSnapshot(
        signer,
        kind: SnapshotKinds.kpiToday,
        scope: 'all',
        asOf: DateTime.now().toUtc(),
        data: {
          'netSales': '51.000',
          'invoiceCount': 2,
          'returns': '0.000',
          'grossProfit': '15.000',
        },
      ),
    ];
    final secrets = MemorySecretStore();
    final transport = FakeTransport(
      TransportKind.cloud,
      handler: (request) {
        switch ('${request.method} ${request.path}') {
          case 'POST /manage/pair':
            return ApiResponse(
              200,
              jsonEncode({
                'deviceToken': 'device-secret',
                'deviceId': (request.body as Map)['deviceId'],
                'desktopSigningKey': key,
                'company': {'name': 'Shop', 'currency': 'JOD', 'decimals': 3},
              }),
            );
          case 'POST /manage/login':
            return const ApiResponse(
              200,
              '{"sessionToken":"session-secret","expiresAt":"2027-02-01T20:00:00.000Z","user":{"globalId":"u1","username":"owner"}}',
            );
          case 'GET /manage/snapshots':
            return ApiResponse(200, jsonEncode({'items': snapshots}));
        }
        return const ApiResponse(404, '{"error":"not_found"}');
      },
    );
    final session = AdminSession(
      secrets,
      clientFactory: (url, credentials) => CloudManageClient(
        transport: transport,
        headers: const ApiHeaderBuilder(appVersion: '0.1.0'),
        credentials: credentials,
      ),
    );
    await tester.pumpWidget(
      PicPosAdminApp(settings: PicPosAppSettings(), session: session),
    );
    await tester.enterText(
      find.byKey(const Key('admin.offer')),
      jsonEncode(
        PairingOffer(
          cloudUrl: Uri.parse('https://cloud.example'),
          code: 'ABCDEFGH',
          desktopSigningKey: key,
        ).toQrJson(),
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('admin.pair')));
    await tester.tap(find.byKey(const Key('admin.pair')));
    await tester.pumpAndSettle();
    expect(secrets.values['admin.deviceToken'], 'device-secret');
    await tester.enterText(find.byKey(const Key('admin.username')), 'owner');
    await tester.enterText(
      find.byKey(const Key('admin.password')),
      '١٢٣٤٥٦٧٨',
    );
    await tester.tap(find.byKey(const Key('admin.login')));
    await tester.pumpAndSettle();
    expect((transport.requests.firstWhere((request) => request.path == '/manage/login').body as Map)['password'], '12345678');
    expect(secrets.values['admin.sessionToken'], 'session-secret');
    expect(find.text('51.000'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('paired dashboard without verified data never asks to pair', (tester) async {
    setSurface(tester, kPhone);
    final signer = await PayloadSigner.fromSeed(List<int>.filled(32, 3));
    final key = await signer.publicKeyBase64();
    final signed = await buildSignedSnapshot(
      signer,
      kind: SnapshotKinds.kpiToday,
      scope: 'all',
      asOf: DateTime.utc(2026, 10, 3, 22, 21, 35),
      data: {'netSales': '51.000'},
    );
    var items = <Map<String, Object?>>[];
    final transport = FakeTransport(
      TransportKind.cloud,
      handler: (request) {
        switch ('${request.method} ${request.path}') {
          case 'POST /manage/pair':
            return ApiResponse(200, jsonEncode({
              'deviceToken': 'device-secret',
              'deviceId': (request.body as Map)['deviceId'],
              'desktopSigningKey': key,
              'company': {'name': 'Shop', 'currency': 'JOD', 'decimals': 3},
            }));
          case 'POST /manage/login':
            return const ApiResponse(200,
                '{"sessionToken":"session-secret","expiresAt":"2027-02-01T20:00:00.000Z","user":{"globalId":"u1","username":"owner"}}');
          case 'GET /manage/snapshots':
            return ApiResponse(200, jsonEncode({'items': items}));
        }
        return const ApiResponse(404, '{"error":"not_found"}');
      },
    );
    final session = AdminSession(
      MemorySecretStore(),
      clientFactory: (url, credentials) => CloudManageClient(
        transport: transport,
        headers: const ApiHeaderBuilder(appVersion: '0.1.0'),
        credentials: credentials,
      ),
    );
    await session.pair(PairingOffer.manual(url: 'https://cloud.example', code: 'ABCDEFGH'),
      confirmKey: (_) async => true,
    );
    await session.login('owner', 'password');
    await tester.pumpWidget(PicPosAdminApp(settings: PicPosAppSettings(), session: session));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد بيانات موثّقة بعد — يتم تحديثها من جهاز المكتب عند المزامنة'), findsWidgets);
    expect(find.text('الجهاز غير مربوط بعد'), findsNothing);
    expect(find.text('اربط الجوال بجهاز المكتب لعرض البيانات.'), findsNothing);
    expect(find.text('يظهر بعد الربط'), findsNothing);

    items = [{...signed, 'asOf': DateTime.utc(2026, 10, 3, 22, 21, 36).toIso8601String()}];
    await session.refresh();
    await tester.pumpAndSettle();
    expect(session.snapshots!.rejected, 1);
    expect(find.text('تعذّر التحقق من بعض البيانات'), findsOneWidget);
    expect(find.text('الجهاز غير مربوط بعد'), findsNothing);
    expect(find.text('يظهر بعد الربط'), findsNothing);
  });

  testWidgets('invalid mobile credentials show Arabic guidance', (tester) async {
    final transport = FakeTransport(
      TransportKind.cloud,
      handler: (request) {
        if (request.path == '/manage/pair') {
          return ApiResponse(200, jsonEncode({
            'deviceToken': 'device-secret',
            'deviceId': (request.body as Map)['deviceId'],
            'desktopSigningKey': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
            'company': {'name': 'Shop', 'currency': 'JOD', 'decimals': 3},
          }));
        }
        return const ApiResponse(401, '{"error":"invalid_credentials"}');
      },
    );
    final session = AdminSession(
      MemorySecretStore(),
      clientFactory: (url, credentials) => CloudManageClient(
        transport: transport,
        headers: const ApiHeaderBuilder(appVersion: '0.1.0'),
        credentials: credentials,
      ),
    );
    await session.pair(
      PairingOffer.manual(url: 'https://cloud.example', code: 'ABCDEFGH'),
      confirmKey: (_) async => true,
    );
    setSurface(tester, kPhone);
    await tester.pumpWidget(PicPosAdminApp(settings: PicPosAppSettings(), session: session));
    await tester.enterText(find.byKey(const Key('admin.username')), 'admin');
    await tester.enterText(find.byKey(const Key('admin.password')), '١٢٣٤٥٦٧٨');
    await tester.tap(find.byKey(const Key('admin.login')));
    await tester.pumpAndSettle();
    expect(find.textContaining('اسم المستخدم أو كلمة مرور الجوال غير صحيحة'), findsOneWidget);
    expect(find.textContaining('invalid_credentials'), findsNothing);
  });

  for (final offline in [false, true]) {
    testWidgets('unpair ${offline ? 'offline' : 'online'} wipes secrets and shows onboarding', (tester) async {
      setSurface(tester, kPhone);
      final secrets = MemorySecretStore();
      final transport = FakeTransport(TransportKind.cloud, handler: (request) {
        switch ('${request.method} ${request.path}') {
          case 'POST /manage/pair':
            return ApiResponse(200, jsonEncode({
              'deviceToken': 'device-secret',
              'deviceId': (request.body as Map)['deviceId'],
              'desktopSigningKey': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
              'user': {'globalId': 'u1', 'username': 'owner', 'displayName': 'Owner'},
              'company': {'name': 'Shop', 'currency': 'JOD', 'decimals': 3},
            }));
          case 'POST /manage/unpair':
            return offline ? const ApiResponse(503, '{"error":"offline"}') : const ApiResponse(204, '');
        }
        return const ApiResponse(404, '{"error":"not_found"}');
      });
      final session = AdminSession(secrets, clientFactory: (url, credentials) => CloudManageClient(
        transport: transport, headers: const ApiHeaderBuilder(appVersion: '0.1.0'), credentials: credentials));
      await session.pair(PairingOffer.manual(url: 'https://cloud.example', code: 'ABCDEFGH'),
      confirmKey: (_) async => true,
    );
      await tester.pumpWidget(PicPosAdminApp(settings: PicPosAppSettings(), session: session));
      await tester.pumpAndSettle();
      expect(find.textContaining('Owner'), findsWidgets);
      await tester.tap(find.byKey(const Key('admin.unpair')));
      await tester.pumpAndSettle();
      expect(find.textContaining('ربط التطبيقات والأجهزة'), findsOneWidget);
      await tester.tap(find.text('فك ربط الجهاز').last);
      await tester.pumpAndSettle();
      expect(secrets.values, isEmpty);
      expect(find.byKey(const Key('admin.url')), findsOneWidget);
      expect(transport.requests.last.path, ManageRoutes.unpair);
      if (offline) expect(find.textContaining('ألغِ الجهاز من جهاز المكتب'), findsOneWidget);
    });
  }

  testWidgets('settings logout keeps pairing and returns to bound-user sign-in', (tester) async {
    setSurface(tester, kPhone);
    final secrets = MemorySecretStore();
    final transport = FakeTransport(TransportKind.cloud, handler: (request) {
      switch ('${request.method} ${request.path}') {
        case 'POST /manage/pair':
          return ApiResponse(200, jsonEncode({
            'deviceToken': 'device-secret', 'deviceId': (request.body as Map)['deviceId'],
            'desktopSigningKey': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
            'user': {'globalId': 'u1', 'username': 'owner', 'displayName': 'Owner'},
            'company': {'name': 'Shop', 'currency': 'JOD', 'decimals': 3},
          }));
        case 'POST /manage/login':
          return const ApiResponse(200, '{"sessionToken":"session-secret","expiresAt":"2027-02-01T20:00:00.000Z","user":{"globalId":"u1","username":"owner","displayName":"Owner"}}');
        case 'GET /manage/snapshots':
          return const ApiResponse(200, '{"items":[]}');
        case 'POST /manage/logout':
          return const ApiResponse(204, '');
      }
      return const ApiResponse(404, '{"error":"not_found"}');
    });
    final session = AdminSession(secrets, clientFactory: (url, credentials) => CloudManageClient(
      transport: transport, headers: const ApiHeaderBuilder(appVersion: '0.1.0'), credentials: credentials));
    await session.pair(PairingOffer.manual(url: 'https://cloud.example', code: 'ABCDEFGH'),
      confirmKey: (_) async => true,
    );
    await session.login('owner', 'password');
    await tester.pumpWidget(PicPosAdminApp(settings: PicPosAppSettings(), session: session));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المزيد'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الإعدادات').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Owner'), findsWidgets);
    expect(find.textContaining('https://cloud.example'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings.logout')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تسجيل الخروج').last);
    await tester.pumpAndSettle();
    expect(secrets.values['admin.deviceToken'], 'device-secret');
    expect(secrets.values['admin.sessionToken'], isNull);
    expect(session.paired, isTrue);
    expect(find.byKey(const Key('admin.login')), findsOneWidget);
    expect(find.textContaining('Owner'), findsWidgets);
    expect(transport.requests.last.path, ManageRoutes.logout);
  });

  testWidgets('revoked session wipes secrets and returns to onboarding', (tester) async {
    final secrets = MemorySecretStore();
    final transport = FakeTransport(
      TransportKind.cloud,
      handler: (request) {
        switch ('${request.method} ${request.path}') {
          case 'POST /manage/pair':
            return ApiResponse(
              200,
              jsonEncode({
                'deviceToken': 'device-secret',
                'deviceId': (request.body as Map)['deviceId'],
                'desktopSigningKey':
                    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
                'company': {'name': 'Shop', 'currency': 'JOD', 'decimals': 3},
              }),
            );
          case 'POST /manage/login':
            return const ApiResponse(
              200,
              '{"sessionToken":"session-secret","expiresAt":"2027-02-01T20:00:00.000Z","user":{"globalId":"u1","username":"owner"}}',
            );
          case 'GET /manage/snapshots':
            return const ApiResponse(401, '{"error":"device_revoked"}');
        }
        return const ApiResponse(404, '{"error":"not_found"}');
      },
    );
    final session = AdminSession(
      secrets,
      clientFactory: (url, credentials) => CloudManageClient(
        transport: transport,
        headers: const ApiHeaderBuilder(appVersion: '0.1.0'),
        credentials: credentials,
      ),
    );
    await session.pair(
      PairingOffer.manual(url: 'https://cloud.example', code: 'ABCDEFGH'),
      confirmKey: (_) async => true,
    );
    setSurface(tester, kPhone);
    await tester.pumpWidget(PicPosAdminApp(settings: PicPosAppSettings(), session: session));
    await tester.pumpAndSettle();
    await expectLater(
      session.login('owner', 'mobile-password'),
      throwsA(isA<ApiError>()),
    );
    await tester.pumpAndSettle();
    expect(secrets.values, isEmpty);
    expect(session.paired, isFalse);
    expect(find.byKey(const Key('admin.url')), findsOneWidget);
  });

  group('M-5 manual pairing asks the user to confirm the signing key fingerprint', () {
    Future<(AdminSession, MemorySecretStore, FakeTransport, String)> manualSession() async {
      final signer = await PayloadSigner.fromSeed(List<int>.filled(32, 5));
      final key = await signer.publicKeyBase64();
      final secrets = MemorySecretStore();
      final transport = FakeTransport(TransportKind.cloud, handler: (request) {
        switch ('${request.method} ${request.path}') {
          case 'POST /manage/pair':
            return ApiResponse(200, jsonEncode({
              'deviceToken': 'device-secret',
              'deviceId': (request.body as Map)['deviceId'],
              'desktopSigningKey': key,
              'company': {'name': 'Shop', 'currency': 'JOD', 'decimals': 3},
            }));
          case 'POST /manage/unpair':
            return const ApiResponse(204, '');
        }
        return const ApiResponse(404, '{"error":"not_found"}');
      });
      final session = AdminSession(secrets, clientFactory: (url, credentials) => CloudManageClient(
          transport: transport, headers: const ApiHeaderBuilder(appVersion: '0.1.0'), credentials: credentials));
      return (session, secrets, transport, key);
    }

    final manual = PairingOffer.manual(url: 'https://cloud.example', code: 'ABCDEFGH');

    test('the fingerprint is 8 groups of 4 hex digits, deterministic and key-specific', () async {
      final a = await signingKeyFingerprint('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=');
      final b = await signingKeyFingerprint('AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=');
      expect(a, matches(RegExp(r'^([0-9A-F]{4} ){7}[0-9A-F]{4}$')));
      expect(a, await signingKeyFingerprint('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='));
      expect(a, isNot(b));
      await expectLater(signingKeyFingerprint('AAAA'), throwsFormatException);
    });

    test('confirmed: callback sees the fingerprint of the cloud key, then the pairing is saved', () async {
      final (session, secrets, _, key) = await manualSession();
      String? shown;
      await session.pair(manual, confirmKey: (fp) async {
        shown = fp;
        expect(secrets.values, isEmpty, reason: 'nothing is stored before the user confirms');
        return true;
      });
      expect(shown, await signingKeyFingerprint(key));
      expect(secrets.values['admin.signingKey'], key);
      expect(session.paired, isTrue);
    });

    for (final decline in [true, false]) {
      test(decline ? 'declined: nothing saved, device unpaired' : 'no confirmation callback: refused', () async {
        final (session, secrets, transport, _) = await manualSession();
        await expectLater(
          session.pair(manual, confirmKey: decline ? (_) async => false : null),
          throwsA(isA<FormatException>().having((e) => e.message, 'message', 'signing_key_not_confirmed')),
        );
        expect(secrets.values, isEmpty);
        expect(session.paired, isFalse);
        expect(session.verifier, isNull);
        expect(transport.requests.map((r) => r.path), contains('/manage/unpair'));
      });
    }

    test('QR offer already carries the desktop key: no confirmation asked', () async {
      final (session, _, _, key) = await manualSession();
      var asked = false;
      await session.pair(
        PairingOffer(cloudUrl: Uri.parse('https://cloud.example'), code: 'ABCDEFGH', desktopSigningKey: key),
        confirmKey: (_) async => asked = true,
      );
      expect(asked, isFalse);
      expect(session.paired, isTrue);
    });

    testWidgets('manual entry shows the fingerprint dialog; rejecting cancels the pairing', (tester) async {
      setSurface(tester, kPhone);
      final (session, secrets, _, key) = await manualSession();
      await tester.pumpWidget(PicPosAdminApp(settings: PicPosAppSettings(), session: session));
      await tester.enterText(find.byKey(const Key('admin.url')), 'https://cloud.example');
      await tester.enterText(find.byKey(const Key('admin.code')), 'ABCDEFGH');
      await tester.ensureVisible(find.byKey(const Key('admin.pair')));
      await tester.tap(find.byKey(const Key('admin.pair')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // busy bar animates: cannot settle
      expect(find.byKey(const Key('admin.keyConfirm')), findsOneWidget);
      expect(find.text(await signingKeyFingerprint(key)), findsOneWidget);
      expect(secrets.values, isEmpty);
      await tester.tap(find.byKey(const Key('admin.keyReject')));
      await tester.pumpAndSettle();
      expect(session.paired, isFalse);
      expect(secrets.values, isEmpty);
      expect(find.byKey(const Key('admin.error')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('admin.pair')));
      await tester.tap(find.byKey(const Key('admin.pair')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('admin.keyAccept')));
      await tester.pumpAndSettle();
      expect(session.paired, isTrue);
      expect(secrets.values['admin.signingKey'], key);
    });
  });
}
