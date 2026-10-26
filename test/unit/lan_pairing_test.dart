import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';
import 'package:picpos_erp/services/api/api_handler.dart';
import 'package:picpos_erp/services/api/lan_pairing_api_handler.dart';
import 'package:picpos_erp/services/api/lan_pairing_service.dart';

class _PairingConnectionInfo implements HttpConnectionInfo {
  _PairingConnectionInfo(String address)
    : remoteAddress = InternetAddress(address);

  @override
  final InternetAddress remoteAddress;
  @override
  int get remotePort => 45678;
  @override
  int get localPort => 8080;
}

void main() {
  late DateTime now;
  late LanPairingService pairing;

  setUp(() async {
    now = DateTime(2026, 1, 1);
    pairing = LanPairingService.forTesting(
      installSecret: 'per-install-secret-with-at-least-32-bytes',
      now: () => now,
      makeCode: () => 'ABCD2345',
    );
  });

  test('pairing code is one-time and expires after ten minutes', () async {
    final offer = await pairing.issuePairingCode(actorUserId: 1, 
      serverHost: '192.168.1.2',
      port: 8080,
      serverFingerprint: 'fp',
    );
    expect((jsonDecode(offer.qrPayload) as Map)['pairingCode'], offer.code);
    final first = await pairing.pair(
      LanPairingRequest(
        code: offer.code,
        deviceId: 'device-a',
        deviceName: 'Cashier A',
        ip: '10.0.0.2',
      ),
    );
    expect(first.status, LanPairingStatus.success);
    final second = await pairing.pair(
      LanPairingRequest(
        code: offer.code,
        deviceId: 'device-b',
        deviceName: 'Cashier B',
        ip: '10.0.0.3',
      ),
    );
    expect(second.status, LanPairingStatus.invalidCode);

    final expired = await pairing.issuePairingCode(actorUserId: 1, serverHost: 'host', port: 8080);
    now = now.add(const Duration(minutes: 11));
    final expiredResult = await pairing.pair(
      LanPairingRequest(
        code: expired.code,
        deviceId: 'device-c',
        deviceName: 'Cashier C',
        ip: '10.0.0.4',
      ),
    );
    expect(expiredResult.status, LanPairingStatus.invalidCode);
  });

  test('existing pairing table upgrades additively and idempotently', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    await db.customStatement('DROP TABLE IF EXISTS lan_branch_terminal_codes');
    await db.customStatement('DROP TABLE lan_paired_devices');
    await db.customStatement('''
      CREATE TABLE lan_paired_devices (
        device_id TEXT PRIMARY KEY,
        name TEXT NOT NULL DEFAULT '',
        paired_at INTEGER,
        last_seen_at INTEGER,
        last_seen_ip TEXT,
        revoked INTEGER NOT NULL DEFAULT 0,
        legacy_seen INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.ensureLanPairingSchema();
    await db.ensureLanPairingSchema();

    final columns = await db
        .customSelect('PRAGMA table_info(lan_paired_devices)')
        .get();
    expect(
      columns.map((row) => row.data['name']),
      containsAll(['device_kind', 'branch_id', 'terminal_code']),
    );
    final registry = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE name = 'lan_branch_terminal_codes'",
        )
        .get();
    expect(registry, hasLength(1));
  });

  test('pairing attempts are limited to five per IP per ten minutes', () async {
    for (var i = 0; i < 5; i++) {
      await pairing.issuePairingCode(actorUserId: 1, serverHost: 'host', port: 8080);
      final result = await pairing.pair(
        LanPairingRequest(
          code: 'WRONG$i',
          deviceId: 'device-$i',
          deviceName: 'Cashier',
          ip: '10.0.0.5',
        ),
      );
      expect(result.status, LanPairingStatus.invalidCode);
    }
    await pairing.issuePairingCode(actorUserId: 1, serverHost: 'host', port: 8080);
    final limited = await pairing.pair(
      const LanPairingRequest(
        code: 'WRONG',
        deviceId: 'device-6',
        deviceName: 'Cashier',
        ip: '10.0.0.5',
      ),
    );
    expect(limited.status, LanPairingStatus.rateLimited);
  });

  test('derived token verifies and a revoked token is rejected', () async {
    final offer = await pairing.issuePairingCode(actorUserId: 1, serverHost: 'host', port: 8080);
    final result = await pairing.pair(
      LanPairingRequest(
        code: offer.code,
        deviceId: 'device-a',
        deviceName: 'Cashier A',
        ip: '10.0.0.2',
      ),
    );
    expect(
      await pairing.verifyDeviceToken(
        token: result.token!,
        deviceId: 'device-a',
      ),
      isTrue,
    );
    await pairing.revoke('device-a', actorUserId: 1);
    expect(
      await pairing.verifyDeviceToken(
        token: result.token!,
        deviceId: 'device-a',
      ),
      isFalse,
    );
  });

  group('legacy transition and API middleware', () {
    late AppDatabase db;
    late DateTime transitionNow;
    late LanPairingService dbPairing;

    setUp(() async {
      transitionNow = DateTime(2026, 1, 1);
      db = AppDatabase.forTesting();
      await db.ensureLanPairingSchema();
      dbPairing = LanPairingService.forTesting(
        db: db,
        installSecret: 'per-install-secret-with-at-least-32-bytes',
        now: () => transitionNow,
        makeCode: () => 'PAIR1234',
      );
      await dbPairing.initializeLegacyTransition();
      // These tests model a server upgraded from before `legacy_token_enabled`
      // existed (legacy ON, inside its window); a NEW server starts with the
      // shared bearer OFF (test/security/legacy_token_gate_test.dart).
      await dbPairing.setLegacyTokenEnabled(true, actorUserId: 1);
      ApiAuthMiddleware.setToken('legacy-token');
      ApiAuthMiddleware.setPairingService(dbPairing);
      LanPairingApiHandler.setService(dbPairing);
    });

    tearDown(() async {
      ApiAuthMiddleware.clearPairingService();
      LanPairingApiHandler.clearService();
      ApiAuthMiddleware.clearToken();
      await db.close();
    });

    Future<Response> run(Request request) {
      final handler = ApiAuthMiddleware.createMiddleware()(
        (request) async =>
            Response.ok(request.context['lanDeviceId'] ?? 'none'),
      );
      return Future.value(handler(request));
    }

    Future<int> addBranch(String name, {String? code, bool active = true}) => db
        .into(db.branches)
        .insert(
          BranchesCompanion.insert(
            name: name,
            code: Value(code),
            isActive: Value(active),
          ),
        );

    Future<Response> pairRequest({
      required String code,
      required String deviceId,
      String? deviceKind,
      int? branchId,
      bool includeBranchId = true,
      String ip = '10.0.0.20',
    }) => LanPairingApiHandler.pair(
      Request(
        'POST',
        Uri.parse('http://localhost/api/pair'),
        context: {'shelf.io.connection_info': _PairingConnectionInfo(ip)},
        body: jsonEncode({
          'pairingCode': code,
          'deviceId': deviceId,
          'deviceKind': ?deviceKind,
          if (includeBranchId && branchId != null) 'branchId': branchId,
        }),
      ),
    );

    test(
      'POS pairing returns and persists branch-scoped terminal codes',
      () async {
        final branchA = await addBranch('Branch A', code: 'CAI');
        final branchB = await addBranch('Branch B', code: 'ALX');
        final pairOnBranch = <String, dynamic>{};

        Future<Map<String, dynamic>> pairPos(String id, int branchId) async {
          final offer = await dbPairing.issuePairingCode(actorUserId: 1, 
            serverHost: 'host',
            port: 8080,
          );
          final response = await pairRequest(
            code: offer.code,
            deviceId: id,
            deviceKind: 'pos',
            branchId: branchId,
          );
          expect(response.statusCode, 200);
          return jsonDecode(await response.readAsString())
              as Map<String, dynamic>;
        }

        pairOnBranch.addAll(await pairPos('pos-a1', branchA));
        expect(pairOnBranch, containsPair('branchId', branchA));
        expect(pairOnBranch, containsPair('branchCode', 'CAI'));
        expect(pairOnBranch, containsPair('terminalCode', 'T01'));
        expect(pairOnBranch.keys.toSet(), {
          'token',
          'deviceId',
          'branchId',
          'branchCode',
          'terminalCode',
        });
        expect(
          await dbPairing.verifyDeviceToken(
            token: pairOnBranch['token'] as String,
            deviceId: 'pos-a1',
          ),
          isTrue,
        );
        await dbPairing.revoke('pos-a1', actorUserId: 1);

        final secondA = await pairPos('pos-a2', branchA);
        final firstB = await pairPos('pos-b1', branchB);
        expect(secondA['terminalCode'], 'T02');
        expect(firstB['terminalCode'], 'T01');
        expect(firstB['branchCode'], 'ALX');

        final devices = await dbPairing.listDevices();
        final persisted = devices.singleWhere(
          (device) => device.deviceId == 'pos-a1',
        );
        expect(persisted.deviceKind, 'pos');
        expect(persisted.branchId, branchA);
        expect(persisted.terminalCode, 'T01');
        expect(persisted.revoked, isTrue);
        expect(
          (await dbPairing.listDevices())
              .singleWhere((device) => device.deviceId == 'pos-a2')
              .terminalCode,
          'T02',
        );
      },
    );

    test('concurrent POS attempts consume one offer exactly once', () async {
      final branchId = await addBranch('Concurrent branch', code: 'CAI');
      final offer = await dbPairing.issuePairingCode(actorUserId: 1, serverHost: 'host', port: 8080);
      final outcomes = await Future.wait([
        dbPairing.pair(
          LanPairingRequest(
            code: offer.code,
            deviceId: 'concurrent-a',
            deviceName: 'Terminal A',
            ip: '10.0.0.40',
            deviceKind: 'pos',
            branchId: branchId,
          ),
        ),
        dbPairing.pair(
          LanPairingRequest(
            code: offer.code,
            deviceId: 'concurrent-b',
            deviceName: 'Terminal B',
            ip: '10.0.0.41',
            deviceKind: 'pos',
            branchId: branchId,
          ),
        ),
      ]);

      expect(
        outcomes.where((result) => result.status == LanPairingStatus.success),
        hasLength(1),
      );
      expect(
        outcomes.where(
          (result) => result.status == LanPairingStatus.invalidCode,
        ),
        hasLength(1),
      );
      expect(
        (await dbPairing.listDevices()).where((device) => device.isPaired),
        hasLength(1),
      );
      final allocations = await db
          .customSelect(
            'SELECT terminal_code FROM lan_branch_terminal_codes '
            'WHERE branch_id = ?',
            variables: [Variable<int>(branchId)],
          )
          .get();
      expect(allocations, hasLength(1));
    });

    test(
      'distinct in-flight offers allocate unique branch terminal codes',
      () async {
        final branchId = await addBranch('Overlapping branch', code: 'CAI');
        final firstOffer = await dbPairing.issuePairingCode(actorUserId: 1, 
          serverHost: 'host',
          port: 8080,
        );
        final firstAttempt = dbPairing.pair(
          LanPairingRequest(
            code: firstOffer.code,
            deviceId: 'offer-a-device',
            deviceName: 'Offer A',
            ip: '10.0.0.52',
            deviceKind: 'pos',
            branchId: branchId,
          ),
        );
        final secondOffer = await dbPairing.issuePairingCode(actorUserId: 1, 
          serverHost: 'host',
          port: 8080,
        );
        final secondAttempt = dbPairing.pair(
          LanPairingRequest(
            code: secondOffer.code,
            deviceId: 'offer-b-device',
            deviceName: 'Offer B',
            ip: '10.0.0.53',
            deviceKind: 'pos',
            branchId: branchId,
          ),
        );

        final results = await Future.wait([firstAttempt, secondAttempt]);
        expect(
          results.map((result) => result.status),
          everyElement(LanPairingStatus.success),
        );
        expect(results.map((result) => result.terminalCode).toSet(), {
          'T01',
          'T02',
        });
        final allocations = await db
            .customSelect(
              'SELECT terminal_code FROM lan_branch_terminal_codes '
              'WHERE branch_id = ?',
              variables: [Variable<int>(branchId)],
            )
            .get();
        expect(allocations, hasLength(2));
      },
    );

    test('successful pairing does not clear a newer pending offer', () async {
      final branchId = await addBranch('Replacement branch', code: 'CAI');
      final firstOffer = await dbPairing.issuePairingCode(actorUserId: 1, 
        serverHost: 'host',
        port: 8080,
      );
      final firstAttempt = dbPairing.pair(
        LanPairingRequest(
          code: firstOffer.code,
          deviceId: 'first-device',
          deviceName: 'First terminal',
          ip: '10.0.0.50',
          deviceKind: 'pos',
          branchId: branchId,
        ),
      );
      final replacement = await dbPairing.issuePairingCode(actorUserId: 1, 
        serverHost: 'host',
        port: 8080,
      );

      expect((await firstAttempt).status, LanPairingStatus.success);
      final secondResult = await dbPairing.pair(
        LanPairingRequest(
          code: replacement.code,
          deviceId: 'second-device',
          deviceName: 'Second terminal',
          ip: '10.0.0.51',
          deviceKind: 'pos',
          branchId: branchId,
        ),
      );
      expect(secondResult.status, LanPairingStatus.success);
    });

    test('POS branch validation failures leave the offer usable', () async {
      final activeBranch = await addBranch('Valid branch', code: 'CAI');
      final inactiveBranch = await addBranch(
        'Inactive branch',
        code: 'OFF',
        active: false,
      );
      final noCodeBranch = await addBranch('Missing code');
      final failures = [
        (branchId: null, includeBranchId: false, status: 400, id: 'missing'),
        (branchId: 0, includeBranchId: true, status: 400, id: 'non-positive'),
        (branchId: 999999, includeBranchId: true, status: 404, id: 'unknown'),
        (
          branchId: inactiveBranch,
          includeBranchId: true,
          status: 404,
          id: 'inactive',
        ),
        (
          branchId: noCodeBranch,
          includeBranchId: true,
          status: 409,
          id: 'no-code',
        ),
      ];

      for (final failure in failures) {
        final offer = await dbPairing.issuePairingCode(actorUserId: 1, 
          serverHost: 'host',
          port: 8080,
        );
        final rejected = await pairRequest(
          code: offer.code,
          deviceId: 'failed-${failure.id}',
          deviceKind: 'pos',
          branchId: failure.branchId,
          includeBranchId: failure.includeBranchId,
          ip: '10.0.0.${30 + failures.indexOf(failure)}',
        );
        expect(rejected.statusCode, failure.status, reason: failure.id);
        final errorBody =
            jsonDecode(await rejected.readAsString()) as Map<String, dynamic>;
        expect(errorBody['error'], isNotEmpty);

        final retry = await pairRequest(
          code: offer.code,
          deviceId: 'retry-${failure.id}',
          deviceKind: 'pos',
          branchId: activeBranch,
          ip: '10.0.0.${30 + failures.indexOf(failure)}',
        );
        expect(retry.statusCode, 200, reason: failure.id);
      }
    });

    test(
      'legacy token is accepted in-window and records an unpaired device',
      () async {
        final response = await run(
          Request(
            'GET',
            Uri.parse('http://localhost/api/settings'),
            headers: {
              'authorization': 'Bearer legacy-token',
              'x-device-id': 'legacy-device',
              'x-device-name': 'Old terminal',
            },
          ),
        );
        expect(response.statusCode, 200);
        expect(
          (await dbPairing.listUnpairedDevices()).single.deviceId,
          'legacy-device',
        );
      },
    );

    test('legacy token is rejected after the transition window', () async {
      transitionNow = transitionNow.add(const Duration(days: 31));
      final response = await run(
        Request(
          'GET',
          Uri.parse('http://localhost/api/settings'),
          headers: {'authorization': 'Bearer legacy-token'},
        ),
      );
      expect(response.statusCode, 403);
      expect(await response.readAsString(), contains('إقران'));
    });

    test(
      'API handler pipeline accepts paired and rejects unpaired token',
      () async {
        final offer = await dbPairing.issuePairingCode(actorUserId: 1, 
          serverHost: 'host',
          port: 8080,
        );
        final router = ApiHandler(db).buildRouter();
        final protected = ApiAuthMiddleware.createMiddleware()(router.call);
        final pairResponse = await protected(
          Request(
            'POST',
            Uri.parse('http://localhost/api/pair'),
            body: jsonEncode({
              'pairingCode': offer.code,
              'deviceId': 'paired-device',
              'deviceName': 'Paired terminal',
            }),
          ),
        );
        expect(pairResponse.statusCode, 200);
        final pairingBody =
            jsonDecode(await pairResponse.readAsString())
                as Map<String, dynamic>;
        expect(pairingBody.keys.toSet(), {'token', 'deviceId'});
        final token = pairingBody['token'] as String;
        final pairedResponse = await protected(
          Request(
            'GET',
            Uri.parse('http://localhost/api/settings'),
            headers: {
              'authorization': 'Bearer $token',
              'x-device-id': 'paired-device',
            },
          ),
        );
        expect(pairedResponse.statusCode, 200);
        final unpairedResponse = await protected(
          Request(
            'GET',
            Uri.parse('http://localhost/api/settings'),
            headers: {
              'authorization': 'Bearer $token',
              'x-device-id': 'other-device',
            },
          ),
        );
        expect(unpairedResponse.statusCode, 403);
      },
    );
  });
}
