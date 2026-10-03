@Tags(['postgres'])
library;

import 'package:picpos_cloud/picpos_cloud.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// Desktop Settings › Linked devices: `GET /desktop/devices` lists the rep
/// devices of the link's company, `POST /desktop/devices/<id>/revoke` revokes
/// one of them (same logic as the admin revoke, audited).
void main() {
  late Harness h;
  late Map<String, String> desk;

  Future<Map<String, String>> link(String companyGid) async {
    final (st, b) = await h.call('POST', '/admin/desktop-links',
        headers: {'x-admin-key': Harness.adminKey}, body: {'companyGlobalId': companyGid, 'name': 'HQ'});
    expect(st, 201, reason: '$b');
    return {'authorization': 'Bearer ${b['linkSecret']}', 'x-desktop-link': b['linkId'] as String};
  }

  setUp(() async {
    h = await Harness.start();
    desk = await link(Demo.companyGid);
  });
  tearDown(() async => h.stop());

  Future<List<Map<String, dynamic>>> devices(Map<String, String> headers) async {
    final (st, b) = await h.call('GET', '/desktop/devices', headers: headers);
    expect(st, 200, reason: '$b');
    return (b['devices'] as List).cast<Map<String, dynamic>>();
  }

  test('needs the desktop link credential', () async {
    expect((await h.call('GET', '/desktop/devices')).$1, 401);
    expect((await h.call('POST', '/desktop/devices/x/revoke')).$1, 401);
    final (bad, _) = await h.call('GET', '/desktop/devices', headers: {...desk, 'authorization': 'Bearer nope'});
    expect(bad, 401);
  });

  test('lists the company rep devices with employee and last seen', () async {
    expect(await devices(desk), isEmpty);
    final d1 = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
    final list = await devices(desk);
    expect(list, hasLength(1));
    final row = list.single;
    expect(row['deviceId'], d1.deviceId);
    expect(row['deviceName'], 'test');
    expect(row['employeeGlobalId'], Demo.rep1Gid);
    expect(row['employeeName'], 'مندوب ١');
    expect(row['pairedAt'], isA<int>());
    expect(row['lastSeenAt'], isA<int>());
    expect(row['revoked'], isFalse);
    expect(row['revokedAt'], isNull);
  });

  test('revoke blocks the device, marks it revoked and writes an audit row', () async {
    final d1 = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
    final d2 = await h.repDevice(Demo.rep2Gid, Demo.rep2Pin);
    final (st, b) = await h.call('POST', '/desktop/devices/${d1.deviceId}/revoke', headers: desk);
    expect(st, 200, reason: '$b');
    expect(b['revoked'], d1.deviceId);

    final (bs, bb) = await h.call('GET', '/mobile/bootstrap', headers: d1.headers);
    expect(bs, 401);
    expect(bb['error'], 'device_revoked');
    expect((await h.call('GET', '/mobile/bootstrap', headers: d2.headers)).$1, 200);

    final list = await devices(desk);
    expect(list.first['deviceId'], d2.deviceId, reason: 'active devices first');
    final revoked = list.firstWhere((x) => x['deviceId'] == d1.deviceId);
    expect(revoked['revoked'], isTrue);
    expect(revoked['revokedAt'], isA<int>());

    final audit = await h.db.query(
        "SELECT detail FROM audit_log WHERE action='device_revoked' AND entity='device' ORDER BY id DESC LIMIT 1");
    expect(audit, isNotEmpty);
    expect(audit.first[0], 'desktop:${desk['x-desktop-link']}');
  });

  test('unknown device is 404', () async {
    final (st, b) = await h.call('POST', '/desktop/devices/nope/revoke', headers: desk);
    expect(st, 404);
    expect(b['error'], 'unknown_device');
  });

  test('another company link neither sees nor revokes the devices', () async {
    const otherGid = '00000000-0000-4000-8000-0000000000f9';
    await h.db.query(
        "INSERT INTO companies (global_id, name, currency, default_tax_rate, integrity_secret) "
        "VALUES (@g, 'Other', 'JOD', 0, 'x')",
        {'g': otherGid});
    final other = await link(otherGid);
    final d1 = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);

    expect(await devices(other), isEmpty);
    final (st, b) = await h.call('POST', '/desktop/devices/${d1.deviceId}/revoke', headers: other);
    expect(st, 404);
    expect(b['error'], 'unknown_device');
    expect((await h.call('GET', '/mobile/bootstrap', headers: d1.headers)).$1, 200);
    expect((await devices(desk)).single['revoked'], isFalse);
  });
}
