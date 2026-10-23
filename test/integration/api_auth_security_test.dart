// Security regression tests for the embedded API auth surface.
//
// A-SEC-1 (C-3): GET /api/health must NOT leak the bearer token to any caller.
// A passive peer on the LAN could otherwise read `apiToken` and authenticate as
// a trusted device. The token is now delivered ONLY while the operator has
// opened a short device-pairing window; steady-state health omits it.
//
// A-SEC-2 (H-3): the auth middleware must FAIL CLOSED. A null active token used
// to pass every /api/* request through unauthenticated — turning a
// mis-started/never-generated token into a wide-open server.
//
// Runs against SQLite in-memory (fast).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_handler.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';

void main() {
  group('A-SEC-1 /api/health only leaks the token during a pairing window', () {
    late AppDatabase db;
    late ApiHandler handler;

    setUp(() {
      db = AppDatabase.forTesting();
      handler = ApiHandler(db);
      ApiAuthMiddleware.setToken('unit-test-token');
      ApiAuthMiddleware.closePairingWindow();
    });
    tearDown(() async {
      ApiAuthMiddleware.closePairingWindow();
      ApiAuthMiddleware.clearToken();
      await db.close();
    });

    Future<Map<String, dynamic>> health() async {
      final response = await handler
          .buildRouter()
          .call(shelf.Request('GET', Uri.parse('http://localhost/api/health')));
      expect(response.statusCode, 200);
      return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    }

    test('steady state (no pairing window) omits apiToken', () async {
      expect((await health()).containsKey('apiToken'), isFalse,
          reason: 'the bearer token must not be handed to arbitrary callers');
    });

    test('open pairing window exposes apiToken for handshake', () async {
      ApiAuthMiddleware.openPairingWindow(const Duration(minutes: 5));
      final body = await health();
      expect(body['apiToken'], 'unit-test-token');
    });

    test('expired pairing window omits apiToken again', () async {
      ApiAuthMiddleware.openPairingWindow(Duration.zero);
      expect((await health()).containsKey('apiToken'), isFalse,
          reason: 'a lapsed window must re-close the token');
    });
  });

  group('A-SEC-2 auth middleware fails closed with no token', () {
    setUp(() => ApiAuthMiddleware.clearToken());
    tearDown(() => ApiAuthMiddleware.clearToken());

    Future<shelf.Response> run(String path, {String? auth}) {
      final handler = ApiAuthMiddleware.createMiddleware()(
          (req) async => shelf.Response.ok('inner'));
      return Future.value(handler(shelf.Request(
        'GET',
        Uri.parse('http://localhost$path'),
        headers: {'authorization': ?auth},
      )));
    }

    test('no token configured rejects /api/* with 403', () async {
      final resp = await run('/api/products');
      expect(resp.statusCode, 403,
          reason: 'a server with no token must not pass /api/* through open');
    });

    test('exempt paths stay reachable even with no token', () async {
      final resp = await run('/api/health');
      expect(resp.statusCode, 200,
          reason: 'health must remain reachable for the pairing handshake');
    });

    test('valid token + correct Bearer passes', () async {
      ApiAuthMiddleware.setToken('tok123');
      final resp = await run('/api/products', auth: 'Bearer tok123');
      expect(resp.statusCode, 200);
    });
  });
}
