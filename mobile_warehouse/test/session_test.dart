// Pairing / sign-in / scope / revocation / PIN, against a scripted desktop.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_warehouse/session/wh_session.dart';

import 'fakes.dart';

void main() {
  late FakeDesktop desktop;
  late MemorySecretStore secrets;
  late WhSession session;
  var wiped = 0;

  setUp(() {
    desktop = FakeDesktop();
    secrets = MemorySecretStore();
    wiped = 0;
    session = desktop.session(secrets, onWipe: () async => wiped++);
  });

  PairingPayload payload([String? raw]) => PairingPayload.parse(raw ?? desktop.qr());

  test('pairs, pins the payload fingerprint, stores credentials and branch', () async {
    await session.pair(payload());
    expect(session.paired, isTrue);
    expect(session.branchId, 3);
    expect(desktop.lastFingerprint, kFingerprint, reason: 'the client must be built with the QR fingerprint');
    expect(desktop.lastBase, Uri.parse('https://192.168.1.5:8443'));
    expect(await secrets.read('wh.deviceToken'), 'DEVTOKEN');
    expect(await secrets.read('wh.fingerprint'), kFingerprint);
    expect(session.loggedIn, isFalse, reason: 'pairing grants no user session');
  });

  test('refuses payloads for another kind, expired payloads and hosts without TLS - saving nothing', () async {
    await expectLater(session.pair(payload(desktop.qr(kind: 'pos'))), throwsA(isA<PairingFormatError>().having((e) => e.code, 'code', 'wrong_kind')));
    final past = DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch;
    await expectLater(session.pair(payload(desktop.qr(exp: past))), throwsA(isA<PairingFormatError>().having((e) => e.code, 'code', 'expired')));
    desktop.tls = false;
    await expectLater(session.pair(payload()), throwsA(isA<PairingFormatError>().having((e) => e.code, 'code', 'no_tls')));
    expect(session.paired, isFalse);
    expect(await secrets.read('wh.deviceToken'), isNull);
  });

  test('a wrong/expired one-time code does not pair', () async {
    desktop.codeValid = false;
    await expectLater(session.pair(payload()), throwsA(isA<ApiError>()));
    expect(session.paired, isFalse);
    expect(await secrets.read('wh.deviceId'), isNull);
  });

  test('login loads the scope; supervisor-level comes from the server permissions only', () async {
    await session.pair(payload());
    await session.login('ali', 'pw');
    expect(session.loggedIn, isTrue);
    expect(session.info!.displayName, 'Ali Hassan');
    expect(session.info!.isSupervisorLevel, isFalse);
    expect(session.info!.warehouses.single.name, 'Main store');
    desktop.supervisor = true;
    await session.refresh();
    expect(session.info!.isSupervisorLevel, isTrue);
  });

  test('wrong password: not signed in; paired stays', () async {
    await session.pair(payload());
    desktop.validPassword = false;
    await expectLater(session.login('ali', 'bad'), throwsA(isA<ApiError>()));
    expect(session.loggedIn, isFalse);
    expect(session.paired, isTrue);
  });

  test('a user without warehouse access is signed straight out again', () async {
    await session.pair(payload());
    desktop.userAllowed = false;
    await expectLater(session.login('cashier', 'pw'), throwsA(isA<ApiError>()));
    expect(session.loggedIn, isFalse);
    expect(await secrets.read('wh.sessionToken'), isNull);
    expect(errorCode(const ApiError(kind: ApiErrorKind.forbidden, code: 'permission_denied', status: 403)), 'permission_denied');
  });

  test('revocation by the desktop wipes secrets, PIN and the local store on the next call', () async {
    await session.pair(payload());
    await session.login('ali', 'pw');
    await session.setLocalPin('1234');
    desktop.revoked = true;
    await expectLater(session.refresh(), throwsA(isA<ApiError>()));
    expect(session.paired, isFalse);
    expect(await secrets.read('wh.deviceToken'), isNull);
    expect(await secrets.read('wh.localPinVerifier'), isNull);
    expect(wiped, 1);
  });

  test('restore() brings back the pairing and the session token after a restart', () async {
    await session.pair(payload());
    await session.login('ali', 'pw');
    final again = desktop.session(secrets);
    await again.restore();
    expect(again.paired, isTrue);
    expect(again.loggedIn, isTrue);
    expect(again.branchId, 3);
    expect(again.info, isNull, reason: 'permissions are never cached: they come from the desktop');
  });

  test('signOut keeps the pairing but drops the session', () async {
    await session.pair(payload());
    await session.login('ali', 'pw');
    await session.signOut();
    expect(session.paired, isTrue);
    expect(session.loggedIn, isFalse);
    expect(session.info, isNull);
  });

  test('local PIN: 4-6 digits, stored hashed, verified, Arabic digits accepted', () async {
    await expectLater(session.setLocalPin('12'), throwsFormatException);
    await session.setLocalPin('٤٣٢١');
    expect(await secrets.read('wh.localPinVerifier'), startsWith('pbkdf2\$'));
    expect(await session.verifyLocalPin('4321'), isTrue);
    expect(await session.verifyLocalPin('0000'), isFalse);
  });
}
