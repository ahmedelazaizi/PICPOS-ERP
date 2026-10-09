// ═══════════════════════════════════════════════════════════════════════════
// CFD SERIAL TRANSPORT — Serial/COM port transport for VFD pole displays
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'package:flutter/foundation.dart';
import '../serial_port_compat.dart';
import '../../core/constants/app_constants.dart';
import 'cfd_transport.dart';

/// Serial transport for VFD pole displays via RS-232 COM port.
///
/// Uses ESC/POS protocol to communicate with 2-line, 20-character VFD displays.
/// Also used as the base for USB Virtual COM transport.
class CfdSerialTransport implements CfdTransport {
  SerialPort? _port;
  String? _portName;
  int _baudRate = 9600;
  bool _connected = false;

  /// Display dimensions (standard VFD pole display)
  static const int displayColumns = 20;
  static const int displayRows = 2;

  @override
  CfdConnectionType get type => CfdConnectionType.serial;

  @override
  bool get isConnected => _connected;

  @override
  String get statusText {
    if (_connected) return 'متصل ($_portName @ $_baudRate)';
    return 'غير متصل';
  }

  /// Get list of available COM ports
  static List<String> getAvailablePorts() {
    if (!Platform.isWindows) return [];
    try {
      return SerialPort.getAvailablePorts();
    } catch (e) {
      debugPrint('[CFD:Serial] Failed to list ports: $e');
      return [];
    }
  }

  /// Common baud rates for VFD displays
  static const List<int> supportedBaudRates = [
    2400,
    4800,
    9600,
    19200,
    38400,
    57600,
    115200,
  ];

  @override
  Future<bool> connect(Map<String, dynamic> config) async {
    final portName = config['port'] as String?;
    final baudRate = config['baudRate'] as int? ?? 9600;

    if (portName == null || portName.isEmpty) {
      debugPrint('[CFD:Serial] No port specified');
      return false;
    }

    try {
      await disconnect(); // Close any existing connection

      _port = SerialPort(portName, openNow: false, BaudRate: baudRate);
      _port!.open();
      _portName = portName;
      _baudRate = baudRate;
      _connected = true;

      // Initialize display
      _initializeDisplay();

      debugPrint('[CFD:Serial] Connected to $portName @ $baudRate baud');
      return true;
    } catch (e) {
      debugPrint('[CFD:Serial] Failed to connect: $e');
      _connected = false;
      _port = null;
      return false;
    }
  }

  @override
  void sendCartUpdate(CfdCartData cartData) {
    if (!_connected || _port == null) return;

    try {
      // Clear display
      _clearDisplay();

      if (cartData.items.isEmpty) {
        sendIdle();
        return;
      }

      // Line 1: Last item name (truncated to 20 chars)
      final lastItem = cartData.items.last;
      final itemName = _truncateArabic(lastItem.name, displayColumns);

      // Line 2: Total amount (right-aligned)
      final totalStr = cartData.total.toStringAsFixed(AppConstants.decimalPlaces);
      final totalLine = 'الإجمالي: $totalStr'.padLeft(displayColumns);

      _moveCursor(0, 0);
      _writeText(itemName);
      _moveCursor(1, 0);
      _writeText(totalLine.substring(0, displayColumns.clamp(0, totalLine.length)));
    } catch (e) {
      debugPrint('[CFD:Serial] Failed to send cart update: $e');
    }
  }

  @override
  void sendIdle() {
    if (!_connected || _port == null) return;

    try {
      _clearDisplay();
      _moveCursor(0, 0);
      _writeText(_centerText('مرحباً بكم', displayColumns));
      _moveCursor(1, 0);
      _writeText(_centerText('Welcome', displayColumns));
    } catch (e) {
      debugPrint('[CFD:Serial] Failed to send idle: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    if (_port != null) {
      try {
        _port!.close();
      } catch (e) {
        debugPrint('[CFD:Serial] Error closing port: $e');
      }
      _port = null;
    }
    _connected = false;
    debugPrint('[CFD:Serial] Disconnected');
  }

  // ─── ESC/POS Commands ──────────────────────────────────────────────────

  /// Initialize the display (ESC @)
  void _initializeDisplay() {
    _sendBytes([0x1B, 0x40]); // ESC @
    sendIdle();
  }

  /// Clear the display
  void _clearDisplay() {
    _sendBytes([0x0C]); // Form feed — clears display on most VFDs
  }

  /// Move cursor to row, column (ESC C r c)
  void _moveCursor(int row, int col) {
    // Different VFDs use different cursor positioning commands.
    // ESC [ row ; col H is ANSI-style
    // For AEDEX-compatible: 1F 24 col row
    // For Epson-compatible: 1F 43 col row
    _sendBytes([0x1F, 0x24, col, row]);
  }

  /// Write text string to the display
  void _writeText(String text) {
    try {
      // Convert to bytes — VFDs typically use Code Page 864 (Arabic) or UTF-8
      // We use the default system encoding via the serial port
      _port?.writeBytesFromString(text, includeZeroTerminator: false);
    } catch (e) {
      debugPrint('[CFD:Serial] Write error: $e');
    }
  }

  /// Send raw bytes to the serial port
  void _sendBytes(List<int> bytes) {
    try {
      _port?.writeBytesFromString(String.fromCharCodes(bytes), includeZeroTerminator: false);
    } catch (e) {
      debugPrint('[CFD:Serial] Byte send error: $e');
    }
  }

  // ─── Text Helpers ──────────────────────────────────────────────────────

  /// Truncate text to fit display width
  String _truncateArabic(String text, int maxLength) {
    if (text.length <= maxLength) return text.padRight(maxLength);
    return '${text.substring(0, maxLength - 1)}~';
  }

  /// Center text within the display width
  String _centerText(String text, int width) {
    if (text.length >= width) return text.substring(0, width);
    final padding = (width - text.length) ~/ 2;
    return text.padLeft(text.length + padding).padRight(width);
  }

  /// Test connection to a port — returns true if port can be opened
  static Future<bool> testPort(String portName, int baudRate) async {
    try {
      final port = SerialPort(portName, openNow: false, BaudRate: baudRate);
      port.open();
      // Send ESC @ to initialize
      port.writeBytesFromString(String.fromCharCodes([0x1B, 0x40]), includeZeroTerminator: false);
      port.close();
      return true;
    } catch (e) {
      debugPrint('[CFD:Serial] Test failed for $portName: $e');
      return false;
    }
  }
}
