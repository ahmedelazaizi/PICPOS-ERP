import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:picpos_cloud/picpos_cloud.dart';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

/// Integration harness: each test gets its own Postgres schema in the docker
/// test database (`docker compose up -d postgres`, host port 55432).
/// Override with TEST_DB_HOST/TEST_DB_PORT/TEST_DB_NAME/TEST_DB_USER/TEST_DB_PASSWORD.
class Harness {
  Harness._(this.db, this.services, this.provider);
  final CloudDatabase db;
  final CloudServices services;
  final MockWhatsAppProvider provider;
  static const adminKey = 'test-admin';

  static Future<Harness> start() async {
    final env = Platform.environment;
    final schema = 't_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';
    final db = await CloudDatabase.open(
      host: env['TEST_DB_HOST'] ?? 'localhost',
      port: int.parse(env['TEST_DB_PORT'] ?? '55432'),
      database: env['TEST_DB_NAME'] ?? 'picpos_cloud',
      username: env['TEST_DB_USER'] ?? 'picpos',
      password: env['TEST_DB_PASSWORD'] ?? 'picpos_test_only',
      schema: schema,
      maxConnections: 4,
    );
    final provider = MockWhatsAppProvider();
    final services = await CloudServices.create(
      db: db,
      tokenSecret: 'test-secret-0123456789-0123456789-abc',
      adminKey: adminKey,
      provider: provider,
      pullOverlapMs: 0,
    );
    await seedDemo(db, pinIterations: 1000);
    return Harness._(db, services, provider);
  }

  Future<void> stop() async {
    await db.dropSchema();
    await db.close();
  }

  Future<(int, Map<String, dynamic>)> call(
    String method,
    String path, {
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    final res = await services.app.handler(Request(
      method,
      Uri.parse('http://localhost$path'),
      body: body == null ? null : jsonEncode(body),
      headers: headers,
    ));
    final text = await res.readAsString();
    return (res.statusCode, (jsonDecode(text) as Map).cast<String, dynamic>());
  }

  Future<String> pairingCode(String employeeGid) async {
    final (st, b) = await call('POST', '/admin/pairing-codes',
        headers: {'x-admin-key': adminKey},
        body: {'companyGlobalId': Demo.companyGid, 'employeeGlobalId': employeeGid});
    if (st != 201) throw StateError('pairing code: $st $b');
    return b['code'] as String;
  }

  /// Pairs a new device for [employeeGid] and logs in. Returns auth headers.
  Future<RepDevice> repDevice(String employeeGid, String pin) async {
    final deviceId = const Uuid().v4();
    final (st, b) = await call('POST', '/mobile/pair',
        body: {'code': await pairingCode(employeeGid), 'deviceId': deviceId, 'deviceName': 'test'});
    if (st != 200) throw StateError('pair: $st $b');
    final dh = {'authorization': 'Bearer ${b['deviceToken']}', 'x-device-id': deviceId};
    final (ls, lb) = await call('POST', '/mobile/login', headers: dh, body: {'pin': pin});
    if (ls != 200) throw StateError('login: $ls $lb');
    return RepDevice(deviceId, {...dh, 'x-session-token': lb['sessionToken'] as String});
  }
}

class RepDevice {
  RepDevice(this.deviceId, this.headers);
  final String deviceId;
  final Map<String, String> headers;
}
