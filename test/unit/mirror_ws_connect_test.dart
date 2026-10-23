// Spec 129 F1 / FR-101+FR-102 — verifies the WS connect URI for mirror mode.
//
// The pure-function helper [WebSocketSyncClient.buildConnectUri] is the
// surface we can unit-test cleanly (no SharedPreferences, no DeviceIdentity
// service, no real WebSocket). The integration test for catch-up after
// disconnect lives in test/integration/ — see quickstart.md §3 cell 11 for
// the manual smoke equivalent.
//
// What we assert:
//   • Mirror mode: query string contains `mode=mirror` and NEVER `branch_id`.
//   • Mirror mode with device_id: `device_id=<id>` is appended.
//   • Mirror mode without device_id (warmup failed / pre-warmup): omits
//     device_id; URL still functions.
//   • Client mode: `branch_id=<n>` appended, no `mode` param (backward-compat).
//   • Client mode without branch_id: base URI returned unchanged.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/websocket_sync_client.dart';

void main() {
  final base = Uri.parse('ws://hq.local:8080/ws');

  group('WebSocketSyncClient.buildConnectUri — mirror mode (Spec 129 F1)', () {
    test('mirror with device_id → mode=mirror + device_id, NO branch_id', () {
      final uri = WebSocketSyncClient.buildConnectUri(
        base: base,
        isMirror: true,
        clientBranchId: null,
        mirrorDeviceId: '0190c4e8-7c6d-7a2e-b9a3-4f6b8c0d1e2f',
      );
      expect(uri.queryParameters['mode'], 'mirror');
      expect(uri.queryParameters['device_id'], '0190c4e8-7c6d-7a2e-b9a3-4f6b8c0d1e2f');
      expect(uri.queryParameters.containsKey('branch_id'), isFalse,
          reason: 'Mirror subscribes to ALL branches (FR-102) — no branch_id.');
    });

    test('mirror without device_id → mode=mirror only (degraded path)', () {
      final uri = WebSocketSyncClient.buildConnectUri(
        base: base,
        isMirror: true,
        clientBranchId: null,
        mirrorDeviceId: null,
      );
      expect(uri.queryParameters['mode'], 'mirror');
      expect(uri.queryParameters.containsKey('device_id'), isFalse,
          reason: 'Missing device_id is logged as device=unknown but not fatal.');
      expect(uri.queryParameters.containsKey('branch_id'), isFalse);
    });

    test('mirror with empty device_id treated as missing', () {
      final uri = WebSocketSyncClient.buildConnectUri(
        base: base,
        isMirror: true,
        clientBranchId: null,
        mirrorDeviceId: '',
      );
      expect(uri.queryParameters['mode'], 'mirror');
      expect(uri.queryParameters.containsKey('device_id'), isFalse);
    });

    test('mirror ignores any clientBranchId leaking from a prior client session', () {
      // Defensive: if SharedPreferences still has a stale client_branch_id
      // from when this device was paired as a client, the mirror branch must
      // ignore it. The _doConnect code path nulls _clientBranchId for mirrors
      // before calling this helper, but we double-check the helper itself.
      final uri = WebSocketSyncClient.buildConnectUri(
        base: base,
        isMirror: true,
        clientBranchId: 42,
        mirrorDeviceId: 'dev-abc',
      );
      expect(uri.queryParameters['mode'], 'mirror');
      expect(uri.queryParameters['device_id'], 'dev-abc');
      expect(uri.queryParameters.containsKey('branch_id'), isFalse);
    });
  });

  group('WebSocketSyncClient.buildConnectUri — client mode (backward-compat)', () {
    test('client with branch_id → branch_id appended, no mode param', () {
      final uri = WebSocketSyncClient.buildConnectUri(
        base: base,
        isMirror: false,
        clientBranchId: 7,
        mirrorDeviceId: null,
      );
      expect(uri.queryParameters['branch_id'], '7');
      expect(uri.queryParameters.containsKey('mode'), isFalse,
          reason: 'Pre-129 clients do not send mode; server defaults to client.');
      expect(uri.queryParameters.containsKey('device_id'), isFalse);
    });

    test('client without branch_id → base URI unchanged', () {
      final uri = WebSocketSyncClient.buildConnectUri(
        base: base,
        isMirror: false,
        clientBranchId: null,
        mirrorDeviceId: null,
      );
      expect(uri, equals(base));
    });

    test('client passes mirrorDeviceId but isMirror=false → ignored', () {
      // The flag governs which branch of the if/else runs; deviceId is
      // mirror-only metadata.
      final uri = WebSocketSyncClient.buildConnectUri(
        base: base,
        isMirror: false,
        clientBranchId: 3,
        mirrorDeviceId: 'should-be-ignored',
      );
      expect(uri.queryParameters['branch_id'], '3');
      expect(uri.queryParameters.containsKey('device_id'), isFalse);
      expect(uri.queryParameters.containsKey('mode'), isFalse);
    });
  });

  group('buildConnectUri — host + scheme preservation', () {
    test('preserves host, port, path when adding query params (mirror)', () {
      final uri = WebSocketSyncClient.buildConnectUri(
        base: Uri.parse('wss://my.server.example:9443/api/ws'),
        isMirror: true,
        clientBranchId: null,
        mirrorDeviceId: 'd1',
      );
      expect(uri.scheme, 'wss');
      expect(uri.host, 'my.server.example');
      expect(uri.port, 9443);
      expect(uri.path, '/api/ws');
      expect(uri.queryParameters['mode'], 'mirror');
      expect(uri.queryParameters['device_id'], 'd1');
    });
  });
}
