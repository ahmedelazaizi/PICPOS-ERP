// ═══════════════════════════════════════════════════════════════════════════
// CFD USB TRANSPORT — USB Virtual COM port transport for VFD displays
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'cfd_transport.dart';
import 'cfd_serial_transport.dart';

/// USB transport for VFD displays connected via USB (Virtual COM Port).
///
/// This is a thin wrapper around [CfdSerialTransport].
/// USB VFD displays create a virtual COM port when plugged in, so the
/// communication protocol is identical to RS-232 Serial.
///
/// The main differences from serial are:
/// 1. Port names often contain "USB" in their description
/// 2. Different default baud rates (often 9600)
/// 3. USB provides power, no external power supply needed
class CfdUsbTransport implements CfdTransport {
  final _serialTransport = CfdSerialTransport();

  @override
  CfdConnectionType get type => CfdConnectionType.usb;

  @override
  bool get isConnected => _serialTransport.isConnected;

  @override
  String get statusText {
    if (_serialTransport.isConnected) {
      return 'متصل (USB ${_serialTransport.statusText.replaceAll('متصل ', '')})';
    }
    return 'غير متصل';
  }

  /// Get available USB COM ports.
  /// Filters ports that are likely USB (heuristic: not COM1/COM2 which are
  /// typically built-in RS-232).
  static List<String> getAvailablePorts() {
    final allPorts = CfdSerialTransport.getAvailablePorts();
    // USB virtual COM ports are typically COM3 and above
    return allPorts.where((p) {
      final num = int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), ''));
      return num != null && num >= 3;
    }).toList();
  }

  /// Supported baud rates (same as serial)
  static List<int> get supportedBaudRates =>
      CfdSerialTransport.supportedBaudRates;

  @override
  Future<bool> connect(Map<String, dynamic> config) async {
    debugPrint('[CFD:USB] Connecting via virtual COM...');
    return _serialTransport.connect(config);
  }

  @override
  void sendCartUpdate(CfdCartData cartData) =>
      _serialTransport.sendCartUpdate(cartData);

  @override
  void sendIdle() => _serialTransport.sendIdle();

  @override
  Future<void> disconnect() async {
    debugPrint('[CFD:USB] Disconnecting...');
    return _serialTransport.disconnect();
  }

  /// Test USB port connection
  static Future<bool> testPort(String portName, int baudRate) =>
      CfdSerialTransport.testPort(portName, baudRate);
}
