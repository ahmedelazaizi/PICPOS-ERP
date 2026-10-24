// Plan 2026-10-23 W1: pairing a `warehouse` device. The code is bound to the
// kind and the branch (the phone cannot choose its branch), TLS is mandatory,
// a generic code cannot make a warehouse device (and vice versa), the device
// row records kind + branch, and revocation kills the token.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/lan_pairing_api_handler.dart';
import 'package:picpos_erp/services/api/lan_pairing_service.dart';

class _Conn implements HttpConnectionInfo {
  @override
  InternetAddress get remoteAddress => InternetAddress('10.0.0.9');
  @override
  int get remotePort => 1;
  @override
  int get localPort => 8080;
}

void main() {
  late AppDatabase db;
  late LanPairingService svc;
  late int branchA, branchB;
  var code = 'WH000001';

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.ensureLanPairingSchema();
    branchA = await db.into(db.branches).insert(BranchesCompanion.insert(name: 'A', code: const Value('AAA')));
    branchB = await db.into(db.branches).insert(BranchesCompanion.insert(name: 'B', code: const Value('BBB')));
    svc = LanPairingService.forTesting(
      installSecret: 'per-install-secret-with-at-least-32-bytes',
      db: db,
      makeCode: () => code,
    );
    LanPairingApiHandler.setService(svc);
  });
  tearDown(() async {
    LanPairingApiHandler.clearService();
    await db.close();
  });

  Future<PairingOffer> issueWh({int? branch, String? fp = 'ef'}) => svc.issuePairingCode(
        serverHost: 'h',
        port: 1,
        serverFingerprint: fp == null ? null : fp * 32,
        actorUserId: 1,
        deviceKind: 'warehouse',
        branchId: branch,
      );

  Future<LanPairingResult> pairWh(String c, {String id = 'wh-1', int? requestedBranch}) => svc.pair(
        LanPairingRequest(
            code: c, deviceId: id, deviceName: 'Phone', ip: '10.0.0.9', deviceKind: 'warehouse', branchId: requestedBranch),
      );

  test('a warehouse code needs a branch and a TLS fingerprint', () async {
    await expectLater(issueWh(branch: null), throwsArgumentError);
    await expectLater(issueWh(branch: branchA, fp: null), throwsStateError);
  });

  test('the branch comes from the offer; the phone cannot pick another one', () async {
    final offer = await issueWh(branch: branchA);
    final r = await pairWh(offer.code, requestedBranch: branchB);
    expect(r.status, LanPairingStatus.success);
    expect(r.branchId, branchA);
    final dev = await svc.deviceById('wh-1');
    expect(dev!.deviceKind, 'warehouse');
    expect(dev.branchId, branchA);
    expect(dev.terminalCode, isNull, reason: 'warehouse devices get no POS terminal code');
    expect(dev.revoked, isFalse);
  });

  test('a generic (or pos) code cannot create a warehouse device', () async {
    final generic = await svc.issuePairingCode(serverHost: 'h', port: 1, actorUserId: 1);
    expect((await pairWh(generic.code)).status, LanPairingStatus.kindMismatch);
    expect(await svc.deviceById('wh-1'), isNull);
    // ...and the code is not burnt by the failed attempt.
    final ok = await svc.pair(LanPairingRequest(
        code: generic.code, deviceId: 'adm-1', deviceName: 'A', ip: '10.0.0.9', deviceKind: 'admin'));
    expect(ok.status, LanPairingStatus.success);
  });

  test('a warehouse code cannot create a pos/admin device', () async {
    final offer = await issueWh(branch: branchA);
    final r = await svc.pair(LanPairingRequest(
        code: offer.code, deviceId: 'pos-1', deviceName: 'P', ip: '10.0.0.9', deviceKind: 'pos', branchId: branchA));
    expect(r.status, LanPairingStatus.kindMismatch);
    expect((await pairWh(offer.code)).status, LanPairingStatus.success);
  });

  test('inactive or unknown branch is refused', () async {
    final offer = await issueWh(branch: 9999);
    expect((await pairWh(offer.code)).status, LanPairingStatus.branchUnavailable);
  });

  test('HTTP /api/pair accepts the warehouse kind and returns the bound branch', () async {
    final offer = await issueWh(branch: branchA);
    final res = await LanPairingApiHandler.pair(Request('POST', Uri.parse('http://x/api/pair'),
        context: {'shelf.io.connection_info': _Conn()},
        body: jsonEncode({'pairingCode': offer.code, 'deviceId': 'wh-http', 'deviceKind': 'warehouse'})));
    expect(res.statusCode, 200);
    final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    expect(body['branchId'], branchA);
    expect(body['token'], isNotEmpty);
    // an unsupported kind is still a 400
    final bad = await LanPairingApiHandler.pair(Request('POST', Uri.parse('http://x/api/pair'),
        context: {'shelf.io.connection_info': _Conn()},
        body: jsonEncode({'pairingCode': 'X', 'deviceId': 'd', 'deviceKind': 'toaster'})));
    expect(bad.statusCode, 400);
    // mismatch maps to 401
    final g = await svc.issuePairingCode(serverHost: 'h', port: 1, actorUserId: 1);
    final mm = await LanPairingApiHandler.pair(Request('POST', Uri.parse('http://x/api/pair'),
        context: {'shelf.io.connection_info': _Conn()},
        body: jsonEncode({'pairingCode': g.code, 'deviceId': 'wh-x', 'deviceKind': 'warehouse'})));
    expect(mm.statusCode, 401);
  });

  test('revocation kills the warehouse token', () async {
    final offer = await issueWh(branch: branchA);
    final r = await pairWh(offer.code);
    expect(await svc.verifyDeviceToken(token: r.token!, deviceId: 'wh-1'), isTrue);
    await svc.revoke('wh-1', actorUserId: 1);
    expect(await svc.verifyDeviceToken(token: r.token!, deviceId: 'wh-1'), isFalse);
    expect((await svc.deviceById('wh-1'))!.revoked, isTrue);
  });
}
