/// Android 12+ Bluetooth runtime permission for printing (WH-015).
///
/// Talking to an already-PAIRED printer needs only `BLUETOOTH_CONNECT`
/// (runtime, "Nearby devices"). No location permission is involved: the
/// manifest declares `BLUETOOTH_SCAN` with `neverForLocation`, and below
/// Android 12 the legacy permissions are install-time (maxSdkVersion 30).
/// The gate is an interface so the flow is testable with a fake.
library;

import 'package:flutter/services.dart';

import 'printer_transport.dart';

/// `granted` (or not needed on this Android) | `denied` (may be asked again) |
/// `blocked` ("don't ask again": only the phone settings can grant it).
enum BluetoothAccess { granted, denied, blocked }

abstract class BluetoothPermissionGate {
  Future<BluetoothAccess> status();

  /// Shows the system prompt when the permission can still be asked.
  Future<BluetoothAccess> request();
}

/// Platform side lives in the app's MainActivity (method channel [name]).
class MethodChannelBluetoothPermissionGate implements BluetoothPermissionGate {
  MethodChannelBluetoothPermissionGate([String name = 'com.picpos.warehouse/bluetooth_permission'])
      : _channel = MethodChannel(name);
  final MethodChannel _channel;

  Future<BluetoothAccess> _call(String method) async {
    try {
      return _parse(await _channel.invokeMethod<String>(method));
    } on PlatformException {
      return BluetoothAccess.denied;
    } on MissingPluginException {
      return BluetoothAccess.granted; // not Android / no native side: nothing to ask
    }
  }

  static BluetoothAccess _parse(String? s) => switch (s) {
        'granted' => BluetoothAccess.granted,
        'blocked' => BluetoothAccess.blocked,
        _ => BluetoothAccess.denied,
      };

  @override
  Future<BluetoothAccess> status() => _call('status');
  @override
  Future<BluetoothAccess> request() => _call('request');
}

/// Asks for the permission when it is missing. Throws [PrinterException]
/// `permission` (denied, can be asked again) or `permissionBlocked`.
Future<void> ensureBluetoothAccess(BluetoothPermissionGate gate) async {
  var access = await gate.status();
  if (access != BluetoothAccess.granted) access = await gate.request();
  switch (access) {
    case BluetoothAccess.granted:
      return;
    case BluetoothAccess.denied:
      throw PrinterException('permission');
    case BluetoothAccess.blocked:
      throw PrinterException('permissionBlocked');
  }
}