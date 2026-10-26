/// Printer links: Bluetooth Classic SPP (`print_bluetooth_thermal`, copied
/// from mobile/lib/printing/printer_transport.dart) and network ESC/POS over
/// raw TCP (port 9100, new for M-B).
library;

import 'dart:async';
import 'dart:io';

import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'bluetooth_permission.dart';

enum PrinterKind { bluetooth, network }

class PrinterDevice {
  const PrinterDevice(this.name, this.address);
  final String name;

  /// Bluetooth MAC, or `host[:port]` for network printers.
  final String address;
}

/// Why a print did not reach the paper (the job stays queued).
class PrinterException implements Exception {
  PrinterException(this.code, [this.cause]);

  /// `noPrinter` | `bluetoothOff` | `permission` | `permissionBlocked` | `badAddress` |
  /// `connectFailed` | `writeFailed` | `timeout`.
  final String code;
  final Object? cause;
  @override
  String toString() => 'PrinterException($code)';
}

abstract class PrinterTransport {
  PrinterKind get kind;
  Future<List<PrinterDevice>> pairedDevices();

  /// Sends [bytes] to the printer at [address]; throws [PrinterException].
  Future<void> send(String address, List<int> bytes);
}

class BluetoothThermalTransport implements PrinterTransport {
  /// [permissions] (WH-015): asks for the Android 12+ runtime permission and
  /// waits for the answer. Without it the plugin's own check is used.
  BluetoothThermalTransport({this.permissions});
  final BluetoothPermissionGate? permissions;

  @override
  PrinterKind get kind => PrinterKind.bluetooth;

  Future<void> _ensurePermission() async {
    final gate = permissions;
    if (gate != null) return ensureBluetoothAccess(gate);
    if (!await PrintBluetoothThermal.isPermissionBluetoothGranted) throw PrinterException('permission');
  }

  @override
  Future<List<PrinterDevice>> pairedDevices() async {
    await _ensurePermission();
    if (!await PrintBluetoothThermal.bluetoothEnabled) throw PrinterException('bluetoothOff');
    return [for (final d in await PrintBluetoothThermal.pairedBluetooths) PrinterDevice(d.name, d.macAdress)];
  }

  @override
  Future<void> send(String address, List<int> bytes) async {
    if (permissions != null) await _ensurePermission();
    if (!await PrintBluetoothThermal.bluetoothEnabled) throw PrinterException('bluetoothOff');
    if (!await PrintBluetoothThermal.connectionStatus) {
      if (!await PrintBluetoothThermal.connect(macPrinterAddress: address)) throw PrinterException('connectFailed');
    }
    try {
      // Chunks keep the RFCOMM writes small for printers with tiny buffers.
      const chunk = 4096;
      for (var i = 0; i < bytes.length; i += chunk) {
        final end = i + chunk < bytes.length ? i + chunk : bytes.length;
        if (!await PrintBluetoothThermal.writeBytes(bytes.sublist(i, end))) throw PrinterException('writeFailed');
      }
    } finally {
      await PrintBluetoothThermal.disconnect;
    }
  }
}

typedef SocketConnector = Future<Socket> Function(String host, int port, {Duration? timeout});

/// Raw TCP ("JetDirect", port 9100) ESC/POS printer on the shop LAN.
class NetworkPrinterTransport implements PrinterTransport {
  NetworkPrinterTransport({
    this.connectTimeout = const Duration(seconds: 5),
    this.writeTimeout = const Duration(seconds: 20),
    SocketConnector? connect,
  }) : _connect = connect ?? Socket.connect;

  static const defaultPort = 9100;
  final Duration connectTimeout;
  final Duration writeTimeout;
  final SocketConnector _connect;

  @override
  PrinterKind get kind => PrinterKind.network;

  /// Network printers are entered by IP:port (no discovery in release 1).
  @override
  Future<List<PrinterDevice>> pairedDevices() async => const [];

  /// Parses `host`, `host:port`, `[v6]:port`. Throws `badAddress`.
  static (String, int) parseAddress(String address) {
    final a = address.trim();
    if (a.isEmpty) throw PrinterException('badAddress');
    final v6 = RegExp(r'^\[([^\]]+)\](?::(\d+))?$').firstMatch(a);
    if (v6 != null) return (v6[1]!, _port(v6[2]));
    final parts = a.split(':');
    if (parts.length > 2 || parts.first.isEmpty) throw PrinterException('badAddress');
    return (parts.first, _port(parts.length == 2 ? parts[1] : null));
  }

  static int _port(String? p) {
    if (p == null) return defaultPort;
    final n = int.tryParse(p);
    if (n == null || n < 1 || n > 65535) throw PrinterException('badAddress');
    return n;
  }

  @override
  Future<void> send(String address, List<int> bytes) async {
    final (host, port) = parseAddress(address);
    Socket socket;
    try {
      socket = await _connect(host, port, timeout: connectTimeout);
    } on SocketException catch (e) {
      throw PrinterException('connectFailed', e);
    } on TimeoutException catch (e) {
      throw PrinterException('timeout', e);
    }
    try {
      socket.add(bytes);
      await socket.flush().timeout(writeTimeout);
      await socket.close().timeout(writeTimeout);
    } on TimeoutException catch (e) {
      throw PrinterException('timeout', e);
    } on SocketException catch (e) {
      throw PrinterException('writeFailed', e);
    } finally {
      socket.destroy();
    }
  }
}
