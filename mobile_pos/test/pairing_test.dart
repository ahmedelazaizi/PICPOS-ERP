// Cashier pairing + sign-in against a fake desktop transport: kind `pos`,
// pinned payload, honest errors, per-device token, role-aware refusal,
// revocation wipe. The REAL host is exercised by the desktop test
// test/security/pos_device_pairing_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_api_client/testing.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_pos/app.dart';
import 'package:picpos_pos/l10n/strings.dart';
import 'package:picpos_pos/screens/login_screen.dart';
import 'package:picpos_pos/screens/onboarding_screen.dart';
import 'package:picpos_pos/session/pos_session.dart';
import 'package:picpos_pos/shell/pos_shell.dart';
import 'package:picpos_ui/picpos_ui.dart';

import 'support.dart';

const _fp = 'ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12';

PairingPayload _payload({
  PairingKind kind = PairingKind.pos,
  DateTime? exp,
  String code = 'ABCD2345',
}) =>
    PairingPayload(
      version: 2,
      kind: kind,
      url: Uri.parse('https://192.168.1.10:8443'),
      code: code,
      fingerprint: _fp,
      expiresAt: exp,
      branchId: 3,
    );

class _Host {
  _Host({this.pairStatus = 200});
  bool tls = true;
  int pairStatus;
  bool revoked = false;
  ApiResponse? loginResponse;
  final List<ApiRequest> requests = [];
  final List<String> fingerprints = [];

  ApiResponse handle(ApiRequest r) {
    requests.add(r);
    if (revoked && r.path != '/api/m1/info') {
      throw const ApiError(kind: ApiErrorKind.deviceRevoked, status: 401, code: 'device_revoked');
    }
    switch (r.path) {
      case '/api/m1/info':
        return ApiResponse(200, '{"serverId":"s","apiLevel":1,"tls":$tls}');
      case '/api/pair':
        return pairStatus == 200
            ? const ApiResponse(200, '{"token":"DEVTOKEN","deviceId":"x","branchId":3,"branchCode":"B3","terminalCode":"B3-T01"}')
            : ApiResponse(pairStatus, '{"error":"bad"}');
      case '/api/auth/session':
        return loginResponse ?? const ApiResponse(200, '{"token":"SESS","userId":9,"expiresInMs":1000}');
    }
    return const ApiResponse(200, '{}');
  }

  PosClientFactory get factory => (uri, fp, creds) {
        fingerprints.add(fp);
        final t = FakeTransport(TransportKind.lan, baseUri: uri, handler: handle);
        return DeviceLanClient(
            transport: t, headers: const ApiHeaderBuilder(appVersion: 't'), kind: PosSession.kind, credentials: creds);
      };
}

void main() {
  setUpAll(loadTestFonts);

  group('PosSession', () {
    late MemorySecretStore secrets;
    late _Host host;
    late PosSession session;
    setUp(() {
      secrets = MemorySecretStore();
      host = _Host();
      session = PosSession(secrets, clientFactory: host.factory, now: () => DateTime(2026, 10, 26, 12));
    });

    test('pair keeps the per-device token, the pin, the branch and the terminal', () async {
      await session.pair(_payload());
      expect(session.paired, isTrue);
      expect(session.branchId, 3);
      expect(session.terminalCode, 'B3-T01');
      expect(host.fingerprints, everyElement(_fp));
      final pairReq = host.requests.firstWhere((r) => r.path == '/api/pair');
      expect(pairReq.body, containsPair('deviceKind', 'pos'));
      expect(pairReq.headers.containsKey('authorization'), isFalse);
      expect(await secrets.read('pos.deviceToken'), 'DEVTOKEN');
      expect(await secrets.read('pos.fingerprint'), _fp);
      expect(await secrets.read('pos.branchId'), '3');
      // a fresh process restores the pairing
      final again = PosSession(secrets, clientFactory: host.factory);
      await again.restore();
      expect(again.paired, isTrue);
      expect(again.client!.credentials.deviceToken, 'DEVTOKEN');
    });

    test('a code for another kind, an expired payload and a host without TLS '
        'are refused and nothing is stored', () async {
      await expectLater(session.pair(_payload(kind: PairingKind.warehouse)),
          throwsA(isA<PosPairingError>().having((e) => e.code, 'code', 'wrong_kind')));
      await expectLater(session.pair(_payload(exp: DateTime(2026, 10, 26, 11))),
          throwsA(isA<PosPairingError>().having((e) => e.code, 'code', 'expired')));
      host.tls = false;
      await expectLater(session.pair(_payload()),
          throwsA(isA<PosPairingError>().having((e) => e.code, 'code', 'no_tls')));
      expect(session.paired, isFalse);
      expect(await secrets.read('pos.deviceToken'), isNull);
    });

    test('a wrong / used code (401) is an honest invalid_code and stores nothing', () async {
      host.pairStatus = 401;
      await expectLater(session.pair(_payload()),
          throwsA(isA<PosPairingError>().having((e) => e.code, 'code', 'invalid_code')));
      expect(await secrets.read('pos.deviceToken'), isNull);
    });

    test('sign-in is the desktop\'s decision: pos_access_denied leaves the tablet '
        'signed out (no half-signed-in state) but paired', () async {
      await session.pair(_payload());
      host.loginResponse = const ApiResponse(403, '{"error":"pos_access_denied","code":"pos_access_denied"}');
      Object? error;
      try {
        await session.login('clerk', 'pw');
      } on Object catch (e) {
        error = e;
      }
      expect(posErrorCode(error!), 'pos_access_denied');
      expect(session.loggedIn, isFalse);
      expect(session.paired, isTrue);
      expect(await secrets.read('pos.sessionToken'), isNull);
    });

    test('sign-in then sign-out keeps the device pairing', () async {
      await session.pair(_payload());
      await session.login(' cashier ', 'pw');
      expect(session.loggedIn, isTrue);
      expect(host.requests.last.headers['authorization'], 'Bearer DEVTOKEN');
      await session.signOut();
      expect(session.loggedIn, isFalse);
      expect(session.paired, isTrue);
    });

    test('revocation by the office wipes the app and leaves a notice', () async {
      var wiped = 0;
      session = PosSession(secrets, clientFactory: host.factory, onWipe: () async => wiped++);
      await session.pair(_payload());
      await session.login('cashier', 'pw');
      host.revoked = true;
      await session.verifyStillPaired();
      expect(session.paired, isFalse);
      expect(session.loggedIn, isFalse);
      expect(session.unpairNotice, isNotNull);
      expect(wiped, 1);
      for (final k in ['url', 'fingerprint', 'deviceId', 'deviceToken', 'branchId', 'terminalCode', 'sessionToken']) {
        expect(await secrets.read('pos.$k'), isNull, reason: k);
      }
    });

    test('offline verification leaves the pairing untouched', () async {
      await session.pair(_payload());
      session.client = DeviceLanClient(
        transport: FakeTransport(TransportKind.lan)
          ..failWith = const ApiError(kind: ApiErrorKind.network, code: 'network'),
        headers: const ApiHeaderBuilder(appVersion: 't'),
        kind: 'pos',
        credentials: session.client!.credentials,
      );
      await session.verifyStillPaired();
      expect(session.paired, isTrue);
    });
  });

  group('screens', () {
    for (final lang in ['ar', 'en']) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        testWidgets('manual pairing → sign-in → shell ($lang ${mode.name})', (tester) async {
          setSurface(tester, kPhone);
          final host = _Host();
          final session = PosSession(MemorySecretStore(), clientFactory: host.factory);
          await tester.pumpWidget(PicPosPosApp(
              settings: PicPosAppSettings(locale: Locale(lang), themeMode: mode), session: session));
          await tester.pumpAndSettle();
          expect(find.byType(OnboardingScreen), findsOneWidget);
          expect(Directionality.of(tester.element(find.byType(OnboardingScreen))),
              lang == 'ar' ? TextDirection.rtl : TextDirection.ltr);

          await tester.enterText(find.byKey(const Key('onboarding.address')), '192.168.1.10:8443');
          await tester.enterText(find.byKey(const Key('onboarding.code')), 'abcd2345');
          await tester.enterText(find.byKey(const Key('onboarding.fingerprint')), _fp);
          await tester.ensureVisible(find.byKey(const Key('onboarding.pair')));
          await tester.tap(find.byKey(const Key('onboarding.pair')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(LoginScreen), findsOneWidget);
          expect(host.requests.firstWhere((r) => r.path == '/api/pair').body,
              containsPair('pairingCode', 'ABCD2345'));

          await tester.enterText(find.byKey(const Key('login.user')), 'cashier');
          await tester.enterText(find.byKey(const Key('login.password')), 'pw');
          await tester.tap(find.byKey(const Key('login.submit')));
          await tester.pumpAndSettle();
          expect(find.byType(PosShell), findsOneWidget);
        });
      }
    }

    testWidgets('missing fingerprint and a bad code show honest messages', (tester) async {
      setSurface(tester, kPhone);
      final host = _Host(pairStatus: 401);
      final session = PosSession(MemorySecretStore(), clientFactory: host.factory);
      await tester.pumpWidget(PicPosPosApp(settings: PicPosAppSettings(), session: session));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('onboarding.address')), '192.168.1.10');
      await tester.enterText(find.byKey(const Key('onboarding.code')), 'ABCD2345');
      await tester.ensureVisible(find.byKey(const Key('onboarding.pair')));
      await tester.tap(find.byKey(const Key('onboarding.pair')));
      await tester.pumpAndSettle();
      expect(find.text(S.table.lookup('err_no_fingerprint', ar: true)), findsOneWidget);
      expect(host.requests, isEmpty, reason: 'nothing is sent without a pin');

      await tester.enterText(find.byKey(const Key('onboarding.fingerprint')), _fp);
      await tester.tap(find.byKey(const Key('onboarding.pair')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('onboarding.error')), findsOneWidget);
      expect(find.text(S.table.lookup('err_invalid_code', ar: true)), findsOneWidget);
      expect(session.paired, isFalse);
    });

    testWidgets('QR scan pairs through the injected scanner (no camera needed)', (tester) async {
      setSurface(tester, kPhone);
      final host = _Host();
      final session = PosSession(MemorySecretStore(), clientFactory: host.factory);
      final qrJson = '{"v":2,"kind":"pos","url":"https://192.168.1.10:8443","code":"ABCD2345",'
          '"exp":${DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch},"fp":"$_fp","branchId":3}';
      await tester.pumpWidget(PicPosMaterialApp(
        settings: PicPosAppSettings(),
        title: (l) => 'PicPos',
        home: OnboardingScreen(session: session, scanner: (context, {bool qr = true}) async => qrJson),
      ));
      await tester.tap(find.byKey(const Key('onboarding.scan')));
      await tester.pumpAndSettle();
      expect(session.paired, isTrue);
      expect(session.branchId, 3);
    });

    testWidgets('a revoked tablet that restarts shows the unpaired notice on the pairing screen', (tester) async {
      setSurface(tester, kPhone);
      final host = _Host();
      final secrets = MemorySecretStore();
      final paired = PosSession(secrets, clientFactory: host.factory);
      await paired.pair(_payload());
      final restarted = PosSession(secrets, clientFactory: host.factory);
      await restarted.restore();
      host.revoked = true;
      await tester.pumpWidget(PicPosPosApp(settings: PicPosAppSettings(), session: restarted));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byKey(const Key('onboarding.unpaired')), findsOneWidget);
    });
  });
}

