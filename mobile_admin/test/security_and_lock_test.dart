import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_admin/admin_session.dart';
import 'package:picpos_admin/app.dart';
import 'package:picpos_admin/app_lock.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_api_client/testing.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_ui/picpos_ui.dart';

import 'support.dart';

const _desktopKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';

CloudManageClient _clientFactory(
  FakeTransport transport,
  Uri _,
  ApiCredentials credentials,
) => CloudManageClient(
  transport: transport,
  headers: const ApiHeaderBuilder(appVersion: '0.1.0'),
  credentials: credentials,
);

Future<AdminSession> _pairedSession(
  MemorySecretStore secrets,
  FakeTransport transport,
) async {
  final session = AdminSession(
    secrets,
    clientFactory: (url, credentials) =>
        _clientFactory(transport, url, credentials),
  );
  await session.pair(
    PairingOffer.manual(url: 'https://cloud.example', code: 'ABCDEFGH'),
    confirmKey: (_) async => true,
  );
  return session;
}

ApiResponse _pairResponse(ApiRequest request) => ApiResponse(
  200,
  jsonEncode({
    'deviceToken': 'device-secret',
    'deviceId': (request.body as Map)['deviceId'],
    'desktopSigningKey': _desktopKey,
    'company': {'name': 'Shop', 'currency': 'JOD', 'decimals': 3},
  }),
);

void main() {
  setUpAll(loadTestFonts);

  test(
    'expired restored session clears local auth but retains pairing',
    () async {
      var unauthorized = false;
      final transport = FakeTransport(
        TransportKind.cloud,
        handler: (request) {
          switch ('${request.method} ${request.path}') {
            case 'POST /manage/pair':
              return _pairResponse(request);
            case 'POST /manage/login':
              return const ApiResponse(
                200,
                '{"sessionToken":"session-secret","expiresAt":"2027-02-01T20:00:00.000Z","user":{"globalId":"u1","username":"owner"}}',
              );
            case 'GET /manage/snapshots':
              return unauthorized
                  ? const ApiResponse(401, '{"error":"unauthorized"}')
                  : const ApiResponse(200, '{"items":[]}');
          }
          return const ApiResponse(404, '{"error":"not_found"}');
        },
      );
      final secrets = MemorySecretStore();
      final first = await _pairedSession(secrets, transport);
      await first.login('owner', 'password');
      expect(secrets.values['admin.sessionToken'], 'session-secret');

      unauthorized = true;
      final restored = AdminSession(
        secrets,
        clientFactory: (url, credentials) =>
            _clientFactory(transport, url, credentials),
      );
      await restored.restore();
      expect(restored.loggedIn, isTrue);

      await expectLater(
        restored.refresh(),
        throwsA(
          isA<ApiError>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.unauthorized,
          ),
        ),
      );
      expect(restored.paired, isTrue);
      expect(restored.loggedIn, isFalse);
      expect(restored.client!.credentials.deviceToken, 'device-secret');
      expect(restored.client!.credentials.sessionToken, isNull);
      expect(restored.snapshots, isNull);
      expect(secrets.values['admin.deviceToken'], 'device-secret');
      expect(secrets.values['admin.sessionToken'], isNull);
    },
  );

  test(
    'unauthorized refresh notifies and clears snapshots without unpairing',
    () async {
      var unauthorized = false;
      final transport = FakeTransport(
        TransportKind.cloud,
        handler: (request) {
          switch ('${request.method} ${request.path}') {
            case 'POST /manage/pair':
              return _pairResponse(request);
            case 'POST /manage/login':
              return const ApiResponse(
                200,
                '{"sessionToken":"session-secret","expiresAt":"2027-02-01T20:00:00.000Z","user":{"globalId":"u1","username":"owner"}}',
              );
            case 'GET /manage/snapshots':
              return unauthorized
                  ? const ApiResponse(401, '{"error":"session_expired"}')
                  : const ApiResponse(200, '{"items":[]}');
          }
          return const ApiResponse(404, '{"error":"not_found"}');
        },
      );
      final secrets = MemorySecretStore();
      final session = await _pairedSession(secrets, transport);
      await session.login('owner', 'password');
      session.snapshots = const VerifiedSnapshots(items: [], rejected: 0);
      var notifications = 0;
      session.addListener(() => notifications++);
      unauthorized = true;

      await expectLater(session.refresh(), throwsA(isA<ApiError>()));
      expect(notifications, greaterThan(0));
      expect(session.paired, isTrue);
      expect(session.loggedIn, isFalse);
      expect(session.snapshots, isNull);
      expect(secrets.values['admin.deviceToken'], 'device-secret');
      expect(secrets.values['admin.sessionToken'], isNull);
    },
  );

  testWidgets('optional TOTP is propagated and can be corrected on retry', (
    tester,
  ) async {
    setSurface(tester, kPhone);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    var loginAttempts = 0;
    final transport = FakeTransport(
      TransportKind.cloud,
      handler: (request) {
        switch ('${request.method} ${request.path}') {
          case 'POST /manage/pair':
            return _pairResponse(request);
          case 'POST /manage/login':
            loginAttempts++;
            if (loginAttempts == 1) {
              return const ApiResponse(401, '{"error":"invalid_credentials"}');
            }
            return const ApiResponse(
              200,
              '{"sessionToken":"session-secret","expiresAt":"2027-02-01T20:00:00.000Z","user":{"globalId":"u1","username":"owner"}}',
            );
          case 'GET /manage/snapshots':
            return const ApiResponse(200, '{"items":[]}');
        }
        return const ApiResponse(404, '{"error":"not_found"}');
      },
    );
    final session = await _pairedSession(MemorySecretStore(), transport);
    await tester.pumpWidget(
      PicPosAdminApp(settings: PicPosAppSettings(), session: session),
    );
    await tester.enterText(find.byKey(const Key('admin.username')), 'owner');
    await tester.enterText(find.byKey(const Key('admin.password')), 'password');
    await tester.enterText(find.byKey(const Key('admin.totp')), '١٢٣٤٥٦');
    await tester.tap(find.byKey(const Key('admin.login')));
    await tester.pumpAndSettle();
    expect((transport.requests[1].body as Map)['totp'], '123456');
    expect(find.byKey(const Key('admin.login')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('admin.totp')), '654321');
    await tester.tap(find.byKey(const Key('admin.login')));
    await tester.pumpAndSettle();
    expect((transport.requests[2].body as Map)['totp'], '654321');
    expect(find.byKey(const Key('admin.appPinSetup')), findsOneWidget);
  });

  test(
    'signing-key mismatch attempts remote unpair before saving nothing',
    () async {
      final requests = <String>[];
      final transport = FakeTransport(
        TransportKind.cloud,
        handler: (request) {
          requests.add('${request.method} ${request.path}');
          switch ('${request.method} ${request.path}') {
            case 'POST /manage/pair':
              return _pairResponse(request);
            case 'POST /manage/unpair':
              return const ApiResponse(204, '');
          }
          return const ApiResponse(404, '{"error":"not_found"}');
        },
      );
      final secrets = MemorySecretStore();
      final session = AdminSession(
        secrets,
        clientFactory: (url, credentials) =>
            _clientFactory(transport, url, credentials),
      );
      final wrongKey = base64.encode(List<int>.filled(32, 1));

      await expectLater(
        session.pair(
          PairingOffer(
            cloudUrl: Uri.parse('https://cloud.example'),
            code: 'ABCDEFGH',
            desktopSigningKey: wrongKey,
          ),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(requests, ['POST /manage/pair', 'POST /manage/unpair']);
      expect(session.paired, isFalse);
      expect(secrets.values, isEmpty);
    },
  );

  Future<void> pumpLock(
    WidgetTester tester,
    MemorySecretStore secrets, {
    Duration idle = kAdminIdleLockDuration,
  }) async {
    final session = AdminSession(secrets);
    await tester.pumpWidget(
      PicPosMaterialApp(
        settings: PicPosAppSettings(),
        title: (_) => 'test',
        home: AppLockGate(
          session: session,
          idleDuration: idle,
          child: const Center(child: Text('authenticated shell')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'first access sets a 4–6 digit PIN and wrong PIN does not unlock',
    (tester) async {
      setSurface(tester, kPhone);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      final secrets = MemorySecretStore();
      await pumpLock(tester, secrets);
      expect(find.byKey(const Key('admin.appPinSetup')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('admin.appPinSetup')),
        '١٢٣٤',
      );
      await tester.enterText(
        find.byKey(const Key('admin.appPinConfirm')),
        '١٢٣٤',
      );
      await tester.tap(find.byKey(const Key('admin.appPinSave')));
      await tester.pumpAndSettle();
      expect(find.text('authenticated shell'), findsOneWidget);
      expect(secrets.values[AdminSession.localPinKey], startsWith('pbkdf2\$'));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byKey(const Key('admin.appPinUnlock')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('admin.appPinUnlock')),
        '0000',
      );
      await tester.tap(find.byKey(const Key('admin.appPinUnlockSubmit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin.appPinUnlock')), findsOneWidget);
      expect(find.text('رمز قفل التطبيق غير صحيح'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('admin.appPinUnlock')),
        '١٢٣٤',
      );
      await tester.tap(find.byKey(const Key('admin.appPinUnlockSubmit')));
      await tester.pumpAndSettle();
      expect(find.text('authenticated shell'), findsOneWidget);
    },
  );

  testWidgets('five-minute idle timeout locks the authenticated shell', (
    tester,
  ) async {
    setSurface(tester, kPhone);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    final secrets = MemorySecretStore();
    await pumpLock(tester, secrets);
    await tester.enterText(find.byKey(const Key('admin.appPinSetup')), '1234');
    await tester.enterText(
      find.byKey(const Key('admin.appPinConfirm')),
      '1234',
    );
    await tester.tap(find.byKey(const Key('admin.appPinSave')));
    await tester.pumpAndSettle();
    expect(find.text('authenticated shell'), findsOneWidget);

    await tester.pump(kAdminIdleLockDuration);
    expect(find.byKey(const Key('admin.appPinUnlock')), findsOneWidget);
    expect(find.text('authenticated shell'), findsNothing);
  });

  testWidgets('re-open with a stored PIN starts locked', (tester) async {
    setSurface(tester, kPhone);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    final secrets = MemorySecretStore();
    await pumpLock(tester, secrets);
    await tester.enterText(find.byKey(const Key('admin.appPinSetup')), '1234');
    await tester.enterText(
      find.byKey(const Key('admin.appPinConfirm')),
      '1234',
    );
    await tester.tap(find.byKey(const Key('admin.appPinSave')));
    await tester.pumpAndSettle();
    expect(find.text('authenticated shell'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await pumpLock(tester, secrets);
    expect(find.byKey(const Key('admin.appPinUnlock')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('admin.appPinUnlock')), '1234');
    await tester.tap(find.byKey(const Key('admin.appPinUnlockSubmit')));
    await tester.pumpAndSettle();
    expect(find.text('authenticated shell'), findsOneWidget);
  });
}
