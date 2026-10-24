// G-6 (plan 2026-10-23, §B.4): issuing a pairing code, revoking a device and
// listing paired devices need `devices_pair_manage`, enforced in the SERVICE
// layer - these tests call the service directly, with no UI in between.
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/role_grant_matrix.dart';
import 'package:picpos_erp/core/permissions/warehouse_permission_codes.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/lan_pairing_service.dart';
import 'package:picpos_erp/services/role_grant_preflight_service.dart';

const _secret = 'per-install-secret-with-at-least-32-bytes';

LanPairingService _service({AppDatabase? db, required Set<int> allowed, List<String>? asked}) =>
    LanPairingService.forTesting(
      installSecret: _secret,
      db: db,
      makeCode: () => 'PAIR1234',
      hasPermission: (userId, code) async {
        asked?.add('$userId:$code');
        return code == WarehousePermissionCodes.devicesPairManage && allowed.contains(userId);
      },
    );

void main() {
  group('service-layer enforcement (stubbed permission lookup)', () {
    test('a user without the code cannot issue a pairing code', () async {
      final asked = <String>[];
      final svc = _service(allowed: {7}, asked: asked);
      await expectLater(
        svc.issuePairingCode(serverHost: 'h', port: 1, actorUserId: 8),
        throwsA(isA<PermissionDeniedException>().having((e) => e.code, 'code', 'devices_pair_manage')),
      );
      expect(asked, ['8:devices_pair_manage']);
    });

    test('no actor (null / 0) is denied for issue, revoke and list', () async {
      final svc = _service(allowed: {1});
      for (final actor in <int?>[null, 0]) {
        await expectLater(svc.issuePairingCode(serverHost: 'h', port: 1, actorUserId: actor),
            throwsA(isA<PermissionDeniedException>()));
        await expectLater(svc.revoke('dev', actorUserId: actor), throwsA(isA<PermissionDeniedException>()));
        await expectLater(svc.listDevicesFor(actor), throwsA(isA<PermissionDeniedException>()));
      }
    });

    test('a user without the code cannot revoke; the holder can, and the token dies at once', () async {
      final svc = _service(allowed: {7});
      final offer = await svc.issuePairingCode(serverHost: 'h', port: 1, actorUserId: 7);
      final paired = await svc.pair(
          LanPairingRequest(code: offer.code, deviceId: 'dev-1', deviceName: 'x', ip: '10.0.0.2'));
      expect(paired.status, LanPairingStatus.success);

      await expectLater(svc.revoke('dev-1', actorUserId: 8), throwsA(isA<PermissionDeniedException>()));
      expect(await svc.verifyDeviceToken(token: paired.token!, deviceId: 'dev-1'), isTrue);

      await svc.revoke('dev-1', actorUserId: 7);
      expect(await svc.verifyDeviceToken(token: paired.token!, deviceId: 'dev-1'), isFalse,
          reason: 'revocation must kill the device token on the very next request');
    });

    test('the holder may issue for every kind; unknown kinds are refused', () async {
      final svc = _service(allowed: {7});
      for (final kind in <String?>[null, 'admin', 'pos']) {
        final offer = await svc.issuePairingCode(serverHost: 'h', port: 1, actorUserId: 7, deviceKind: kind);
        expect(offer.code, 'PAIR1234');
      }
      await expectLater(
          svc.issuePairingCode(serverHost: 'h', port: 1, actorUserId: 7, deviceKind: 'toaster'),
          throwsArgumentError);
    });

    test('QR v2 payload: kind, https url, expiry, fingerprint, branch - and no install secret', () async {
      final svc = _service(allowed: {7});
      final offer = await svc.issuePairingCode(
        serverHost: '192.168.1.5',
        port: 8443,
        serverFingerprint: 'ab' * 32,
        actorUserId: 7,
        deviceKind: 'warehouse',
        branchId: 3,
      );
      final json = jsonDecode(offer.qrPayload) as Map<String, dynamic>;
      expect(json['v'], 2);
      expect(json['kind'], 'warehouse');
      expect(json['url'], 'https://192.168.1.5:8443');
      expect(json['code'], 'PAIR1234');
      expect(json['fp'], 'ab' * 32);
      expect(json['branchId'], 3);
      expect(json['exp'], isA<int>());
      expect(offer.qrPayload.contains(_secret), isFalse);
      expect(offer.qrPayload.toLowerCase().contains('token'), isFalse);
    });
  });

  group('database-backed permission + audit', () {
    late AppDatabase db;
    late int clerk, admin, inactive;

    Future<int> user(String name, int roleId, {bool active = true}) => db.into(db.users).insert(
          UsersCompanion.insert(
            username: name,
            passwordHash: 'x',
            displayName: name,
            roleId: Value(roleId),
            isActive: Value(active),
          ),
        );

    setUp(() async {
      db = AppDatabase.forTesting();
      await db.ensureLanPairingSchema();
      await RoleGrantPreflightService(db).grantMissingDefaults();
      Future<int> role(String n) async =>
          (await (db.select(db.roles)..where((r) => r.name.equals(n))).getSingle()).id;
      clerk = await user('clerk_u', await role(kWarehouseClerkRole));
      admin = await user('admin_u', await role('مدير النظام'));
      inactive = await user('gone_u', await role('مدير النظام'), active: false);
    });
    tearDown(() => db.close());

    test('system admin may; warehouse clerk and deactivated admin may not; all audited', () async {
      final svc = LanPairingService.forTesting(
        installSecret: _secret,
        db: db,
        makeCode: () => 'PAIR1234',
        hasPermission: db.userHasPermission, // the production lookup
      );
      final offer = await svc.issuePairingCode(
        serverHost: 'h',
        port: 1,
        serverFingerprint: 'cd' * 32,
        actorUserId: admin,
        deviceKind: 'warehouse',
        branchId: 1,
      );
      expect(offer.code, 'PAIR1234');
      await expectLater(svc.issuePairingCode(serverHost: 'h', port: 1, actorUserId: clerk),
          throwsA(isA<PermissionDeniedException>()));
      await expectLater(svc.issuePairingCode(serverHost: 'h', port: 1, actorUserId: inactive),
          throwsA(isA<PermissionDeniedException>()));

      final logs = await db.select(db.activityLogs).get();
      expect(logs.map((l) => l.action), containsAll(['device_pairing_issue', 'device_pairing_denied']));
      final issued = logs.firstWhere((l) => l.action == 'device_pairing_issue');
      expect(issued.userId, admin);
      expect(issued.description, allOf(contains('kind=warehouse'), contains('branch=1')));
    });
  });
}
