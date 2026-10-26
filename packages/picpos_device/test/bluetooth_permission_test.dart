// WH-015: the Android 12+ Bluetooth permission flow of the printing port,
// with a fake gate (no device needed).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_device/picpos_device.dart';

class _Gate implements BluetoothPermissionGate {
  _Gate(this.current, {this.afterRequest});
  BluetoothAccess current;
  final BluetoothAccess? afterRequest;
  int requests = 0;
  @override
  Future<BluetoothAccess> status() async => current;
  @override
  Future<BluetoothAccess> request() async {
    requests++;
    return current = afterRequest ?? current;
  }
}

Matcher refusedWith(String code) => throwsA(isA<PrinterException>().having((e) => e.code, 'code', code));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('already granted: no prompt', () async {
    final g = _Gate(BluetoothAccess.granted);
    await ensureBluetoothAccess(g);
    expect(g.requests, 0);
  });

  test('missing, then granted by the user: asked once and allowed', () async {
    final g = _Gate(BluetoothAccess.denied, afterRequest: BluetoothAccess.granted);
    await ensureBluetoothAccess(g);
    expect(g.requests, 1);
  });

  test('refused at the prompt: permission (can be asked again)', () async {
    final g = _Gate(BluetoothAccess.denied);
    await expectLater(ensureBluetoothAccess(g), refusedWith('permission'));
    expect(g.requests, 1);
  });

  test('"don\'t ask again": permissionBlocked, so the app can point to the settings', () async {
    final g = _Gate(BluetoothAccess.denied, afterRequest: BluetoothAccess.blocked);
    await expectLater(ensureBluetoothAccess(g), refusedWith('permissionBlocked'));
  });

  test('the transport refuses to list or send without the permission, before touching Bluetooth', () async {
    final t = BluetoothThermalTransport(permissions: _Gate(BluetoothAccess.denied));
    await expectLater(t.pairedDevices(), refusedWith('permission'));
    await expectLater(t.send('AA:BB', [1]), refusedWith('permission'));
    final blocked = BluetoothThermalTransport(permissions: _Gate(BluetoothAccess.blocked));
    await expectLater(blocked.pairedDevices(), refusedWith('permissionBlocked'));
  });

  group('method channel gate', () {
    const name = 'test/bt_permission';
    void answer(Object? Function(String method) f) => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(name), (c) async => f(c.method));

    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(name), null));

    test('maps the native answers', () async {
      final g = MethodChannelBluetoothPermissionGate(name);
      answer((m) => 'granted');
      expect(await g.status(), BluetoothAccess.granted);
      answer((m) => 'blocked');
      expect(await g.request(), BluetoothAccess.blocked);
      answer((m) => 'denied');
      expect(await g.request(), BluetoothAccess.denied);
      answer((m) => null);
      expect(await g.status(), BluetoothAccess.denied, reason: 'an unknown answer is never read as a grant');
    });

    test('no native side (not Android): nothing to ask', () async {
      expect(await MethodChannelBluetoothPermissionGate('test/none').status(), BluetoothAccess.granted);
    });
  });
}