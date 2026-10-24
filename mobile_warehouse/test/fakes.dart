import 'dart:convert';

import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_api_client/testing.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_warehouse/session/wh_session.dart';

final kFingerprint = 'ab' * 32;

/// A scripted office computer behind a [FakeTransport]. Flip the fields to
/// simulate TLS-less hosts, revoked devices, users without access, etc.
class FakeDesktop {
  bool tls = true;
  bool revoked = false;
  bool codeValid = true;
  bool userAllowed = true;
  bool validPassword = true;
  bool supervisor = false;
  List<Map<String, Object?>> warehouses = const [
    {'id': 1, 'name': 'Main store'}
  ];
  final transports = <FakeTransport>[];
  Uri? lastBase;
  String? lastFingerprint;

  ApiResponse handle(ApiRequest r) {
    if (r.path == '/api/m1/info') {
      return ApiResponse(200, jsonEncode({'serverId': 's1', 'apiLevel': 1, 'tls': tls, 'companyName': 'Co'}));
    }
    if (revoked && r.path != '/api/pair') return const ApiResponse(401, '{"error":"device_revoked"}');
    switch (r.path) {
      case '/api/pair':
        return codeValid
            ? const ApiResponse(200, '{"token":"DEVTOKEN","deviceId":"x","branchId":3}')
            : const ApiResponse(401, '{"error":"رمز الإقران غير صحيح أو منتهي"}');
      case '/api/auth/session':
        return validPassword
            ? const ApiResponse(200, '{"token":"SESS","userId":7,"expiresInMs":3600000}')
            : const ApiResponse(401, '{"error":"Invalid credentials"}');
      case '/api/m1/wh/session':
        if (!userAllowed) return const ApiResponse(403, '{"error":"User #7 lacks permission: warehouse_mobile_access"}');
        return ApiResponse(
            200,
            jsonEncode({
              'user': {'id': 7, 'username': 'ali', 'displayName': 'Ali Hassan', 'roleName': 'x'},
              'device': {'id': 'x', 'kind': 'warehouse', 'branchId': 3, 'branchName': 'Cairo'},
              'permissions': [
                'warehouse_mobile_access',
                'inventory_view',
                if (supervisor) 'inventory_transfer',
              ],
              'warehouses': warehouses,
            }));
      case '/api/m1/wh/items':
        if (r.query['barcode'] == '6221234567890' || r.query['q'] == 'Milk') {
          return const ApiResponse(
              200,
              '{"items":[{"id":1,"code":"P-1","barcode":"6221234567890","name":"Milk 1L","stock":'
              '[{"warehouseId":1,"warehouse":"Main store","quantity":"12.0","reserved":"2.0"}]}],"warehouses":[]}');
        }
        return const ApiResponse(200, '{"items":[],"warehouses":[]}');
    }
    return const ApiResponse(404, '{"error":"nf"}');
  }

  WarehouseLanClient _client(Uri base, String fp, ApiCredentials creds) {
    lastBase = base;
    lastFingerprint = fp;
    final t = FakeTransport(TransportKind.lan, baseUri: base, handler: handle);
    transports.add(t);
    return WarehouseLanClient(transport: t, headers: const ApiHeaderBuilder(appVersion: 't'), credentials: creds);
  }

  WhSession session(SecretStore secrets, {Future<void> Function()? onWipe, DateTime Function()? now}) =>
      WhSession(secrets, clientFactory: _client, onWipe: onWipe, now: now);

  String qr({String kind = 'warehouse', int? exp, String? fp}) => jsonEncode({
        'v': 2,
        'kind': kind,
        'url': 'https://192.168.1.5:8443',
        'code': 'PAIR1234',
        'exp': exp,
        'fp': fp ?? kFingerprint,
        'branchId': 3,
      });
}
