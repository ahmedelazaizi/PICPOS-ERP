import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../presentation/pos/providers/cart_controller.dart';
import 'cfd/cfd_transport.dart';
import 'cfd/cfd_network_transport.dart';
import 'cfd/cfd_serial_transport.dart';
import 'cfd/cfd_usb_transport.dart';
import 'cfd/cfd_hdmi_transport.dart';

/// Service to manage Customer Facing Display (CFD) broadcasts.
///
/// Supports multiple connection types via the [CfdTransport] abstraction:
/// - Network (SSE) — for tablets/phones on the same network
/// - Serial (COM) — for VFD pole displays via RS-232
/// - USB — for VFD displays via USB Virtual COM port
/// - HDMI — for second monitor displays
class CfdService {
  CfdService._();
  static final instance = CfdService._();

  // Persistence keys
  static const _prefConnectionType = 'cfd_connection_type';
  static const _prefPort = 'cfd_port';
  static const _prefBaudRate = 'cfd_baud_rate';
  static const _prefMonitorIndex = 'cfd_monitor_index';
  static const _prefEnabled = 'cfd_enabled';
  static const _prefDisplayConfig = 'cfd_display_config';

  // Active transport
  CfdTransport? _activeTransport;
  CfdConnectionType _connectionType = CfdConnectionType.network;
  bool _enabled = false;

  // Saved configuration
  String? _savedPort; // COM port name
  int _savedBaudRate = 9600;
  int _savedMonitorIndex = 1;

  // Display content configuration
  CfdDisplayConfig _displayConfig = CfdDisplayConfig.defaultConfig;

  // Network transport is special — it's always available for SSE clients
  // even if another transport is the "primary" display
  final _networkTransport = CfdNetworkTransport();

  // Getters
  CfdConnectionType get connectionType => _connectionType;
  bool get enabled => _enabled;
  CfdTransport? get activeTransport => _activeTransport;
  bool get isConnected => _activeTransport?.isConnected ?? false;
  String get statusText =>
      _activeTransport?.statusText ?? 'غير مفعل';

  /// The network transport (always available for SSE API)
  CfdNetworkTransport get networkTransport => _networkTransport;

  // Saved config getters
  String? get savedPort => _savedPort;
  int get savedBaudRate => _savedBaudRate;
  int get savedMonitorIndex => _savedMonitorIndex;
  CfdDisplayConfig get displayConfig => _displayConfig;

  /// Load saved settings
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefEnabled) ?? false;
    final typeStr = prefs.getString(_prefConnectionType);
    if (typeStr != null) {
      _connectionType = CfdConnectionType.values.firstWhere(
        (t) => t.name == typeStr,
        orElse: () => CfdConnectionType.network,
      );
    }
    _savedPort = prefs.getString(_prefPort);
    _savedBaudRate = prefs.getInt(_prefBaudRate) ?? 9600;
    _savedMonitorIndex = prefs.getInt(_prefMonitorIndex) ?? 1;
    final configStr = prefs.getString(_prefDisplayConfig);
    if (configStr != null) {
      try {
        _displayConfig = CfdDisplayConfig.fromJson(
          json.decode(configStr) as Map<String, dynamic>,
        );
      } catch (_) {
        _displayConfig = CfdDisplayConfig.defaultConfig;
      }
    }
  }

  /// Save settings
  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, _enabled);
    await prefs.setString(_prefConnectionType, _connectionType.name);
    if (_savedPort != null) {
      await prefs.setString(_prefPort, _savedPort!);
    }
    await prefs.setInt(_prefBaudRate, _savedBaudRate);
    await prefs.setInt(_prefMonitorIndex, _savedMonitorIndex);
    await prefs.setString(
      _prefDisplayConfig,
      json.encode(_displayConfig.toJson()),
    );
  }

  /// Update display content configuration
  Future<void> setDisplayConfig(CfdDisplayConfig config) async {
    _displayConfig = config;
    await saveSettings();
  }

  /// Set connection type and configuration
  Future<void> setConnectionType(
    CfdConnectionType type, {
    String? port,
    int? baudRate,
    int? monitorIndex,
  }) async {
    _connectionType = type;
    if (port != null) _savedPort = port;
    if (baudRate != null) _savedBaudRate = baudRate;
    if (monitorIndex != null) _savedMonitorIndex = monitorIndex;
    await saveSettings();
  }

  /// Enable/disable the CFD
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    await saveSettings();

    if (enabled) {
      await connectTransport();
    } else {
      await disconnectTransport();
    }
  }

  /// Connect the configured transport
  Future<bool> connectTransport() async {
    await disconnectTransport();

    final transport = _createTransport(_connectionType);
    final config = _buildConfig();

    final success = await transport.connect(config);
    if (success) {
      _activeTransport = transport;
      debugPrint('[CFD] Connected via ${_connectionType.name}');
    } else {
      debugPrint('[CFD] Failed to connect via ${_connectionType.name}');
    }
    return success;
  }

  /// Disconnect the active transport
  Future<void> disconnectTransport() async {
    if (_activeTransport != null) {
      await _activeTransport!.disconnect();
      _activeTransport = null;
    }
  }

  /// Test connection with given config
  Future<bool> testConnection(
    CfdConnectionType type, {
    String? port,
    int? baudRate,
    int? monitorIndex,
  }) async {
    final transport = _createTransport(type);
    final config = <String, dynamic>{};
    if (port != null) config['port'] = port;
    if (baudRate != null) config['baudRate'] = baudRate;
    if (monitorIndex != null) config['monitorIndex'] = monitorIndex;

    final result = await transport.connect(config);
    if (result) {
      await transport.disconnect();
    }
    return result;
  }

  /// Broadcast cart state to all active transports
  void broadcastCart(CartState state) {
    final cartData = CfdCartData(
      items: state.items
          .map((i) => CfdCartItem(
                name: i.productName,
                quantity: i.quantity,
                price: i.effectivePrice,
                total: i.total,
              ))
          .toList(),
      subtotal: state.subtotal,
      discountPercent: state.discountPercent,
      taxAmount: state.totals.taxAmount,
      total: state.total,
      customerName: state.selectedCustomerName,
    );

    // Always broadcast to network transport (for SSE clients)
    _networkTransport.sendCartUpdate(cartData, _displayConfig);

    // Also broadcast to the active primary transport if different
    if (_activeTransport != null &&
        _activeTransport is! CfdNetworkTransport) {
      _activeTransport!.sendCartUpdate(cartData);
    }
  }

  /// Broadcast idle/welcome state
  void broadcastIdle() {
    _networkTransport.sendIdle(_displayConfig);
    if (_activeTransport != null &&
        _activeTransport is! CfdNetworkTransport) {
      _activeTransport!.sendIdle();
    }
  }

  /// Dispose all resources
  Future<void> dispose() async {
    await disconnectTransport();
    await _networkTransport.disconnect();
  }

  // ─── Private Helpers ──────────────────────────────────────────────────

  CfdTransport _createTransport(CfdConnectionType type) {
    switch (type) {
      case CfdConnectionType.network:
        return _networkTransport;
      case CfdConnectionType.serial:
        return CfdSerialTransport();
      case CfdConnectionType.usb:
        return CfdUsbTransport();
      case CfdConnectionType.hdmi:
        return CfdHdmiTransport();
    }
  }

  Map<String, dynamic> _buildConfig() {
    switch (_connectionType) {
      case CfdConnectionType.network:
        return {};
      case CfdConnectionType.serial:
      case CfdConnectionType.usb:
        return {
          'port': _savedPort,
          'baudRate': _savedBaudRate,
        };
      case CfdConnectionType.hdmi:
        return {
          'monitorIndex': _savedMonitorIndex,
        };
    }
  }

  // ─── Legacy API Compatibility ─────────────────────────────────────────

  /// Connect a new SSE client (used by API handler)
  Stream<String> connect() => _networkTransport.connectClient();
}
