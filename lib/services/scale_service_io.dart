import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:serial_port_win32/serial_port_win32.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'scale_disconnect_detector.dart';
import 'scale_reconnect_policy.dart';

/// Scale operating mode
enum ScaleMode {
  /// Scale responds to weight request commands (W, P, S, etc.)
  command,

  /// Scale continuously broadcasts weight data without commands
  continuous,

  /// Auto-detect mode on connect (default)
  auto,
}

/// Scale connection type
enum ScaleConnectionType {
  /// Serial COM port (USB/RS-232)
  serial,

  /// TCP/IP network connection
  tcp,
}

// ═══════════════════════════════════════════════════════════════════════════════
// ScaleService — main-isolate facade (public API unchanged)
// All blocking serial I/O runs in a background worker isolate.
// ═══════════════════════════════════════════════════════════════════════════════

class ScaleService {
  static ScaleService? _instance;

  // Worker isolate
  Isolate? _workerIsolate;
  SendPort? _workerSendPort;
  ReceivePort? _mainReceivePort;

  // Streams (main isolate only)
  StreamController<double>? _weightController;
  StreamController<bool>? _stabilityController;

  // State (mirrored from worker)
  bool _isConnected = false;
  String? _currentPort;
  int _baudRate = 9600;
  ScaleConnectionType _connectionType = ScaleConnectionType.serial;
  String? _tcpHost;
  int _tcpPort = 4001;
  ScaleMode _detectedMode = ScaleMode.auto;
  double _lastWeight = 0;
  bool _isStable = false;
  bool _isBinaryProtocol = false;
  double _adcCountsPerKg = 51783.0;

  VoidCallback? _onDisconnectedCallback;

  // Completers for request→response from worker
  Completer<bool>? _connectCompleter;
  Completer<bool>? _testCompleter;
  Completer<bool>? _calibrateCompleter;

  /// Upper bound on the connect handshake. Mode auto-detection legitimately
  /// takes up to ~12.3s on a scale that answers none of the probes — 2.1s of
  /// passive listening plus 12 commands × (50ms flush + 300ms settle + 500ms
  /// read) — and the worker only replies once detection finishes. The guard
  /// therefore has to sit well clear of that; a tighter bound would abort
  /// healthy connections on slow scales instead of fixing anything. This only
  /// catches a worker that never answers at all.
  static const Duration _connectTimeout = Duration(seconds: 25);

  /// Upper bound on a calibration round-trip. The worker answers from the
  /// ADC value it already holds, so this is short by comparison.
  static const Duration _calibrateTimeout = Duration(seconds: 15);

  Timer? _reconnectTimer;
  final ScaleReconnectPolicy _reconnect = ScaleReconnectPolicy();

  // SharedPreferences keys
  static const String _prefScalePort = 'scale_port';
  static const String _prefScaleBaudRate = 'scale_baud_rate';
  static const String _prefScaleDataBits = 'scale_data_bits';
  static const String _prefScaleParity = 'scale_parity';
  static const String _prefScaleStopBits = 'scale_stop_bits';
  static const String _prefScaleAutoConnect = 'scale_auto_connect';
  static const String _prefScaleMode = 'scale_mode';
  static const String _prefScaleCommand = 'scale_command';
  static const String _prefAdcCountsPerKg = 'scale_adc_counts_per_kg';
  static const String _prefScaleConnectionType = 'scale_connection_type';
  static const String _prefScaleTcpHost = 'scale_tcp_host';
  static const String _prefScaleTcpPort = 'scale_tcp_port';

  ScaleService._();

  static ScaleService get instance {
    _instance ??= ScaleService._();
    return _instance!;
  }

  /// Whether the current weight reading is stable (last N readings within tolerance)
  bool get isStable => _isStable;

  /// Stream of stability changes
  Stream<bool>? get stabilityStream => _stabilityController?.stream;

  static List<String> getAvailablePorts() {
    try {
      return SerialPort.getAvailablePorts();
    } catch (e) {
      return [];
    }
  }

  bool get isConnected => _isConnected;
  String? get currentPort => _currentPort;
  int get baudRate => _baudRate;
  ScaleConnectionType get connectionType => _connectionType;
  String? get tcpHost => _tcpHost;
  int get tcpPort => _tcpPort;
  ScaleMode get detectedMode => _detectedMode;
  Stream<double>? get weightStream => _weightController?.stream;

  /// Set a callback for when cable disconnection is detected
  set onDisconnected(VoidCallback? cb) => _onDisconnectedCallback = cb;

  /// Whether the scale uses binary protocol (needs calibration)
  bool get isBinaryProtocol => _isBinaryProtocol;

  /// Current calibration value
  double get adcCountsPerKg => _adcCountsPerKg;

  /// Synchronous access to the last read weight
  double get lastWeight => _lastWeight;

  // ─────────────────────────────────────────────────────────────────────────
  // Connect / Disconnect
  // ─────────────────────────────────────────────────────────────────────────

  /// Connect via serial COM port
  Future<bool> connect({
    required String portName,
    int baudRate = 9600,
    int? dataBits,
    String? parity,
    String? stopBits,
    bool saveSettings = true,
  }) async {
    return _connectInternal(
      connectionType: ScaleConnectionType.serial,
      portName: portName,
      baudRate: baudRate,
      dataBits: dataBits,
      parity: parity,
      stopBits: stopBits,
      saveSettings: saveSettings,
    );
  }

  /// Connect via TCP/IP network
  Future<bool> connectTcp({
    required String host,
    int port = 4001,
    bool saveSettings = true,
  }) async {
    return _connectInternal(
      connectionType: ScaleConnectionType.tcp,
      tcpHost: host,
      tcpPort: port,
      saveSettings: saveSettings,
    );
  }

  Future<bool> _connectInternal({
    required ScaleConnectionType connectionType,
    String? portName,
    int baudRate = 9600,
    int? dataBits,
    String? parity,
    String? stopBits,
    String? tcpHost,
    int tcpPort = 4001,
    bool saveSettings = true,
  }) async {
    try {
      // Not an operator-initiated disconnect: keep automatic reconnection
      // armed and only drop a retry already queued for this attempt. The
      // backoff schedule is deliberately NOT rewound here — see
      // ScaleReconnectPolicy.resume.
      _reconnect.resume();
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      await _teardown();

      _connectionType = connectionType;
      _currentPort = portName;
      _baudRate = baudRate;
      _tcpHost = tcpHost;
      _tcpPort = tcpPort;
      _weightController = StreamController<double>.broadcast();
      _stabilityController = StreamController<bool>.broadcast();
      _isStable = false;

      // Read saved calibration (SharedPreferences requires main isolate)
      double? savedCalibration;
      try {
        final prefs = await SharedPreferences.getInstance();
        // Clear cached mode to force fresh detection
        await prefs.remove(_prefScaleMode);
        await prefs.remove(_prefScaleCommand);
        savedCalibration = prefs.getDouble(_prefAdcCountsPerKg);
      } catch (_) {}

      // Spawn worker isolate
      _mainReceivePort = ReceivePort();
      final sendPortCompleter = Completer<SendPort>();
      bool gotSendPort = false;

      _mainReceivePort!.listen((message) {
        if (!gotSendPort && message is SendPort) {
          gotSendPort = true;
          sendPortCompleter.complete(message);
        } else if (message is Map) {
          _handleWorkerMessage(message);
        }
      });

      _workerIsolate = await Isolate.spawn(
        _scaleWorkerEntry,
        _mainReceivePort!.sendPort,
      );

      _workerSendPort = await sendPortCompleter.future;

      // Send connect command
      _connectCompleter = Completer<bool>();

      if (connectionType == ScaleConnectionType.tcp) {
        _workerSendPort!.send({
          'type': 'connectTcp',
          'host': tcpHost,
          'port': tcpPort,
          'savedCalibration': savedCalibration,
        });
      } else {
        _workerSendPort!.send({
          'type': 'connect',
          'portName': portName,
          'baudRate': baudRate,
          'dataBits': dataBits,
          'parity': parity,
          'stopBits': stopBits,
          'savedCalibration': savedCalibration,
        });
      }

      final success = await _connectCompleter!.future.timeout(
        _connectTimeout,
        onTimeout: () {
          debugPrint('[Scale] Connect timed out after '
              '${_connectTimeout.inSeconds}s — worker never replied');
          return false;
        },
      );
      _connectCompleter = null;

      if (!success) {
        // Whether the worker reported failure or never answered, tear the
        // isolate down. Leaving it alive kept the COM port claimed and made
        // the next attempt fail too — the retry loop below would then never
        // recover.
        _killWorker();
      }

      if (success) {
        _isConnected = true;
        _reconnect.reset();
        if (connectionType == ScaleConnectionType.tcp) {
          debugPrint('[Scale] Connected to $tcpHost:$tcpPort (TCP)');
        } else {
          debugPrint('[Scale] Connected to $portName @ $baudRate baud');
        }
        if (saveSettings) {
          if (connectionType == ScaleConnectionType.tcp) {
            await _saveTcpSettings(tcpHost!, tcpPort);
          } else {
            await _saveScaleSettings(
              portName!, baudRate, dataBits, parity, stopBits,
            );
          }
        }
      }

      return success;
    } catch (e) {
      debugPrint('[Scale] Connection failed: $e');
      _isConnected = false;
      _killWorker();
      return false;
    }
  }

  /// Operator-initiated disconnect. Suppresses automatic reconnection until
  /// something explicitly connects again — otherwise pressing "disconnect" in
  /// the hardware settings would be undone a couple of seconds later.
  Future<void> disconnect() async {
    _reconnect.suppress();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _teardown();
  }

  /// Release the worker, port and streams without touching reconnect intent.
  Future<void> _teardown() async {
    if (_workerSendPort != null) {
      _workerSendPort!.send({'type': 'disconnect'});
      await Future.delayed(const Duration(milliseconds: 150));
    }
    _killWorker();
    _isConnected = false;
    _currentPort = null;
    _lastWeight = 0;
    _isStable = false;
    _isBinaryProtocol = false;
    await _stabilityController?.close();
    _stabilityController = null;
    await _weightController?.close();
    _weightController = null;
  }

  void _killWorker() {
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _workerSendPort = null;
    _mainReceivePort?.close();
    _mainReceivePort = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Public methods that delegate to worker
  // ─────────────────────────────────────────────────────────────────────────

  /// Read weight on demand — returns last cached reading (non-blocking)
  Future<double?> readWeight() async {
    if (!_isConnected) return null;
    return _lastWeight >= 0 ? _lastWeight : null;
  }

  /// Manual tare/zero the scale
  void tare() {
    _workerSendPort?.send({'type': 'tare'});
    _lastWeight = 0.0;
    _weightController?.add(0.0);
  }

  /// Calibrate the scale using a known weight.
  Future<bool> calibrate(double knownWeightKg) async {
    if (!_isConnected || _workerSendPort == null) return false;
    if (knownWeightKg <= 0) return false;

    _calibrateCompleter = Completer<bool>();
    _workerSendPort!.send({
      'type': 'calibrate',
      'knownWeightKg': knownWeightKg,
    });

    final success = await _calibrateCompleter!.future.timeout(
      _calibrateTimeout,
      onTimeout: () {
        debugPrint('[Scale] Calibration timed out after '
            '${_calibrateTimeout.inSeconds}s — worker never replied');
        return false;
      },
    );
    _calibrateCompleter = null;
    return success;
  }

  /// Test connection — works for both modes
  Future<bool> testConnection() async {
    if (!_isConnected || _workerSendPort == null) return false;

    _testCompleter = Completer<bool>();
    _workerSendPort!.send({'type': 'testConnection'});

    final result = await _testCompleter!.future
        .timeout(const Duration(seconds: 10), onTimeout: () => false);
    _testCompleter = null;
    return result;
  }

  /// Force re-detection (clear saved mode and detect again)
  Future<void> redetectMode() async {
    if (!_isConnected || _workerSendPort == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefScaleMode);
      await prefs.remove(_prefScaleCommand);
    } catch (_) {}

    _workerSendPort!.send({'type': 'redetectMode'});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Worker message handler
  // ─────────────────────────────────────────────────────────────────────────

  void _handleWorkerMessage(Map message) {
    final type = message['type'] as String?;

    switch (type) {
      case 'connected':
        final success = message['success'] as bool;
        final modeStr = message['mode'] as String?;
        _detectedMode =
            modeStr == 'command' ? ScaleMode.command : ScaleMode.continuous;
        _isBinaryProtocol = message['isBinary'] as bool? ?? false;
        if (_isBinaryProtocol) {
          _adcCountsPerKg =
              (message['adcCountsPerKg'] as num?)?.toDouble() ?? 51783.0;
        }
        _connectCompleter?.complete(success);
        break;

      case 'weight':
        final weight = (message['value'] as num).toDouble();
        _lastWeight = weight;
        _weightController?.add(weight);
        break;

      case 'stability':
        final stable = message['value'] as bool;
        if (stable != _isStable) {
          _isStable = stable;
          _stabilityController?.add(stable);
        }
        break;

      case 'disconnected':
        _isConnected = false;
        _lastWeight = 0;
        _weightController?.add(0.0);
        _onDisconnectedCallback?.call();
        _killWorker();
        // The link dropped on its own (cable pulled, scale powered off, port
        // vanished). Nothing else in the app would ever bring it back, and a
        // cashier has no settings screen to reconnect from, so start retrying.
        _scheduleReconnect();
        break;

      case 'saveMode':
        _saveScaleMode(
          message['mode'] as String,
          message['command'] as String?,
        );
        break;

      case 'saveCalibration':
        final countsPerKg = (message['countsPerKg'] as num).toDouble();
        _adcCountsPerKg = countsPerKg;
        _persistCalibration(countsPerKg);
        break;

      case 'testResult':
        _testCompleter?.complete(message['success'] as bool);
        break;

      case 'calibrateResult':
        final success = message['success'] as bool;
        if (success) {
          _adcCountsPerKg =
              (message['countsPerKg'] as num?)?.toDouble() ?? _adcCountsPerKg;
        }
        _calibrateCompleter?.complete(success);
        break;

      case 'modeDetected':
        final modeStr = message['mode'] as String?;
        _detectedMode =
            modeStr == 'command' ? ScaleMode.command : ScaleMode.continuous;
        _isBinaryProtocol = message['isBinary'] as bool? ?? false;
        break;

      case 'log':
        debugPrint(message['message'] as String);
        break;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Settings persistence (must run on main isolate — needs Flutter bindings)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _saveScaleSettings(
    String portName,
    int baudRate, [
    int? dataBits,
    String? parity,
    String? stopBits,
  ]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefScaleConnectionType, 'serial');
      await prefs.setString(_prefScalePort, portName);
      await prefs.setInt(_prefScaleBaudRate, baudRate);
      if (dataBits != null) await prefs.setInt(_prefScaleDataBits, dataBits);
      if (parity != null) await prefs.setString(_prefScaleParity, parity);
      if (stopBits != null) await prefs.setString(_prefScaleStopBits, stopBits);
      await prefs.setBool(_prefScaleAutoConnect, true);
    } catch (_) {}
  }

  Future<void> _saveTcpSettings(String host, int port) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefScaleConnectionType, 'tcp');
      await prefs.setString(_prefScaleTcpHost, host);
      await prefs.setInt(_prefScaleTcpPort, port);
      await prefs.setBool(_prefScaleAutoConnect, true);
    } catch (_) {}
  }

  Future<void> _saveScaleMode(String mode, String? command) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefScaleMode, mode);
      if (command != null) {
        await prefs.setString(_prefScaleCommand, command);
      } else {
        await prefs.remove(_prefScaleCommand);
      }
    } catch (_) {}
  }

  Future<void> _persistCalibration(double countsPerKg) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefAdcCountsPerKg, countsPerKg);
    } catch (_) {}
  }

  Future<void> clearSavedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefScalePort);
      await prefs.remove(_prefScaleBaudRate);
      await prefs.setBool(_prefScaleAutoConnect, false);
      await prefs.remove(_prefScaleMode);
      await prefs.remove(_prefScaleCommand);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> getSavedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'connectionType': prefs.getString(_prefScaleConnectionType) ?? 'serial',
        'port': prefs.getString(_prefScalePort),
        'baudRate': prefs.getInt(_prefScaleBaudRate) ?? 9600,
        'dataBits': prefs.getInt(_prefScaleDataBits),
        'parity': prefs.getString(_prefScaleParity),
        'stopBits': prefs.getString(_prefScaleStopBits),
        'autoConnect': prefs.getBool(_prefScaleAutoConnect) ?? false,
        'mode': prefs.getString(_prefScaleMode) ?? 'auto',
        'command': prefs.getString(_prefScaleCommand),
        'tcpHost': prefs.getString(_prefScaleTcpHost),
        'tcpPort': prefs.getInt(_prefScaleTcpPort) ?? 4001,
      };
    } catch (_) {
      return {
        'connectionType': 'serial',
        'port': null,
        'baudRate': 9600,
        'autoConnect': false,
        'mode': 'auto',
        'tcpHost': null,
        'tcpPort': 4001,
      };
    }
  }

  /// Auto-connect using saved settings (called on app startup).
  ///
  /// This is the app's only automatic connection path — `MainScreen.initState`
  /// calls it once and nothing else ever retries. A scale that was still
  /// enumerating, powered off, or plugged in a minute later therefore stayed
  /// dead for the whole session, with no error on screen and no way for a
  /// cashier (who has no settings screen) to recover. Failures now arm a
  /// backoff retry instead of giving up.
  Future<bool> autoConnect() async {
    final connected = await _attemptAutoConnect();
    if (!connected && _reconnect.shouldRetry) {
      final settings = await getSavedSettings();
      if (settings['autoConnect'] == true) _scheduleReconnect();
    }
    return connected;
  }

  /// Queue the next reconnection attempt. Re-entrant: a retry already in
  /// flight wins, and an explicit disconnect or a live connection cancels it.
  void _scheduleReconnect() {
    if (!_reconnect.shouldRetry) return;
    if (_reconnectTimer != null) return;

    final delay = _reconnect.nextDelay();
    debugPrint('[Scale] Reconnect attempt ${_reconnect.attempt} in '
        '${delay.inSeconds}s');
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (!_reconnect.shouldRetry || _isConnected) return;
      // autoConnect re-arms the next attempt itself when this one fails, so
      // the chain continues without recursion here. It also stops on its own
      // once the saved settings say auto-connect is off.
      autoConnect();
    });
  }

  Future<bool> _attemptAutoConnect() async {
    try {
      final settings = await getSavedSettings();
      final bool shouldAutoConnect = settings['autoConnect'] ?? false;
      if (!shouldAutoConnect) return false;

      final connType = settings['connectionType'] as String? ?? 'serial';

      if (connType == 'tcp') {
        final String? tcpHost = settings['tcpHost'];
        final int tcpPort = settings['tcpPort'] ?? 4001;
        if (tcpHost == null || tcpHost.isEmpty) return false;

        return await connectTcp(
          host: tcpHost,
          port: tcpPort,
          saveSettings: false,
        );
      } else {
        final String? savedPort = settings['port'];
        final int savedBaudRate = settings['baudRate'] ?? 9600;
        final int? savedDataBits = settings['dataBits'];
        final String? savedParity = settings['parity'];
        final String? savedStopBits = settings['stopBits'];

        if (savedPort == null) return false;

        // Check if saved port is still available
        final availablePorts = getAvailablePorts();
        if (!availablePorts.contains(savedPort)) return false;

        return await connect(
          portName: savedPort,
          baudRate: savedBaudRate,
          dataBits: savedDataBits,
          parity: savedParity,
          stopBits: savedStopBits,
          saveSettings: false,
        );
      }
    } catch (_) {
      return false;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Worker isolate — all blocking serial I/O runs here
// ═══════════════════════════════════════════════════════════════════════════════

/// Top-level entry point for the worker isolate
void _scaleWorkerEntry(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  final worker = _ScaleWorker(mainSendPort);

  receivePort.listen((message) {
    if (message is Map) {
      worker.handleMessage(message);
    }
  });
}

class _ScaleWorker {
  final SendPort _main;

  // Serial port (COM)
  SerialPort? _port;

  // TCP socket
  Socket? _socket;
  StreamSubscription<List<int>>? _socketSubscription;
  bool _isTcp = false;

  Timer? _readTimer;
  /// Flag to stop the event-driven read loops (continuous / command modes).
  /// Set to true by `_handleCableDisconnection()` and dispose paths.
  bool _readLoopStopped = false;
  String _activeCommand = 'W\r\n';
  ScaleMode _detectedMode = ScaleMode.auto;
  double _lastWeight = 0;
  String _rawBuffer = '';

  // Stability detection — balanced for responsiveness vs noise rejection.
  // History: 8 → 5 → 4 samples. At a ~30ms cycle (continuous) or ~45ms
  // cycle (command mode), 4 samples ≈ 120-180ms to "stable" — fast enough
  // to feel instant in POS while still rejecting single-sample spikes.
  //
  // Threshold tuned to 15g (was 6g): the emitted weight is rounded to 1g
  // precision in _emitWeight. With ±1-2g ADC jitter, a 6g threshold let
  // rounding-boundary flips push the 4-sample min/max range over the limit
  // → stability indicator flickered. 15g covers quantization + typical
  // noise without masking real movement.
  final List<double> _recentWeights = [];
  static const int _stabilityWindowSize = 4;
  static const double _stabilityThreshold = 0.015; // 15g
  bool _isStable = false;

  // Moving average smoothing — 3 samples averages across the 1g rounding
  // boundary so the rounded output doesn't flip every tick from single-
  // ADC-count noise. Previous value of 2 was too tight: any sample
  // landing near a 1g edge made the smoothed value oscillate, which in
  // turn flipped the rounded emitted weight and polluted the stability
  // window.
  final List<double> _smoothingBuffer = [];
  static const int _smoothingWindowSize = 3;

  // Jump detection — clears buffers instantly when a new item is placed
  double _lastEmittedRaw = 0;
  static const double _jumpThreshold = 0.05; // 50g change = new item on scale

  // Binary protocol support
  List<int> _binaryBuffer = [];
  bool _isBinaryProtocol = false;
  static const int _binaryFrameSize = 23;
  static const int _binaryHeader = 0xAB;
  double _adcCountsPerKg = 51783.0;
  int _tareAdcValue = 0;
  bool _tared = false;
  int _tareStableCount = 0;
  int _lastRawAdc = 0;

  // Disconnection detection. An empty read is the normal state of an idle
  // scale in this event-driven loop, so it must not be counted as an error —
  // only sustained silence or a run of real I/O exceptions is evidence the
  // link is gone. See ScaleDisconnectDetector.
  final ScaleDisconnectDetector _linkHealth = ScaleDisconnectDetector();

  // Diagnostic log
  IOSink? _diagnosticLog;

  // Guard against overlapping reads
  bool _isReading = false;

  _ScaleWorker(this._main);

  void _log(String message) {
    _main.send({'type': 'log', 'message': message});
  }

  void handleMessage(Map message) {
    switch (message['type']) {
      case 'connect':
        _handleConnect(message);
        break;
      case 'connectTcp':
        _handleConnectTcp(message);
        break;
      case 'disconnect':
        _handleDisconnect();
        break;
      case 'tare':
        _handleTare();
        break;
      case 'calibrate':
        _handleCalibrate(message);
        break;
      case 'testConnection':
        _handleTestConnection();
        break;
      case 'redetectMode':
        _handleRedetectMode();
        break;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Connect
  // ─────────────────────────────────────────────────────────────────────────

  void _handleConnect(Map message) async {
    try {
      final portName = message['portName'] as String;
      final baudRate = message['baudRate'] as int? ?? 9600;
      final dataBits = message['dataBits'] as int?;
      final parity = message['parity'] as String?;
      final stopBits = message['stopBits'] as String?;
      final savedCalibration = message['savedCalibration'] as double?;

      // Map string parity/stopBits to Win32 constants
      int parityVal = 0; // NOPARITY
      if (parity != null) {
        switch (parity.toLowerCase()) {
          case 'odd':
            parityVal = 1;
            break;
          case 'even':
            parityVal = 2;
            break;
          case 'mark':
            parityVal = 3;
            break;
          case 'space':
            parityVal = 4;
            break;
        }
      }
      int stopBitsVal = 0; // ONESTOPBIT
      if (stopBits != null) {
        switch (stopBits) {
          case '1.5':
            stopBitsVal = 1;
            break;
          case '2':
            stopBitsVal = 2;
            break;
        }
      }

      _port = SerialPort(
        portName,
        openNow: false,
        BaudRate: baudRate,
        ByteSize: dataBits ?? 8,
        Parity: parityVal,
        StopBits: stopBitsVal,
      );
      _port!.open();
      _linkHealth.reset(DateTime.now());
      _recentWeights.clear();
      _isStable = false;
      _rawBuffer = '';
      _binaryBuffer = [];
      _isBinaryProtocol = false;
      _tared = false;
      _tareStableCount = 0;
      _lastRawAdc = 0;

      _startDiagnosticLog(portName, baudRate);

      _log('[Scale] Connected to $portName @ $baudRate baud');

      // Auto-detect mode (blocking calls are fine — we're in the worker isolate)
      _detectedMode = await _detectMode();
      _log('[Scale] Detected mode: $_detectedMode (binary: $_isBinaryProtocol)');

      // Load saved calibration for binary protocol
      if (_isBinaryProtocol && savedCalibration != null && savedCalibration > 0) {
        _adcCountsPerKg = savedCalibration;
        _log('[Scale] Loaded calibration: $_adcCountsPerKg counts/kg');
      }

      // Start periodic reading
      _startReading();

      _main.send({
        'type': 'connected',
        'success': true,
        'mode': _detectedMode == ScaleMode.command ? 'command' : 'continuous',
        'isBinary': _isBinaryProtocol,
        'adcCountsPerKg': _adcCountsPerKg,
      });
    } catch (e) {
      _log('[Scale] Connection failed: $e');
      _main.send({
        'type': 'connected',
        'success': false,
        'mode': 'continuous',
        'isBinary': false,
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Connect TCP
  // ─────────────────────────────────────────────────────────────────────────

  void _handleConnectTcp(Map message) async {
    try {
      final host = message['host'] as String;
      final port = message['port'] as int? ?? 4001;
      final savedCalibration = message['savedCalibration'] as double?;

      _isTcp = true;
      _linkHealth.reset(DateTime.now());
      _recentWeights.clear();
      _smoothingBuffer.clear();
      _isStable = false;
      _rawBuffer = '';
      _binaryBuffer = [];
      _isBinaryProtocol = false;
      _tared = false;
      _tareStableCount = 0;
      _lastRawAdc = 0;

      _log('[Scale] Connecting to $host:$port (TCP)...');

      // Connect with 5 second timeout
      _socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );

      _log('[Scale] TCP connected to $host:$port');
      _startDiagnosticLog('$host:$port', port);

      // Load saved calibration for binary protocol
      if (savedCalibration != null && savedCalibration > 0) {
        _adcCountsPerKg = savedCalibration;
      }

      // Listen to socket stream for incoming data
      _socketSubscription = _socket!.listen(
        (data) => _onTcpData(data),
        onError: (e) {
          _log('[Scale] TCP error: $e');
          _handleCableDisconnection();
        },
        onDone: () {
          _log('[Scale] TCP connection closed by remote');
          _handleCableDisconnection();
        },
        cancelOnError: false,
      );

      // Wait a moment for initial data to determine mode
      await Future.delayed(const Duration(milliseconds: 1500));

      // If we received data during the wait, it's continuous mode
      if (_rawBuffer.isNotEmpty || _binaryBuffer.isNotEmpty) {
        _detectedMode = ScaleMode.continuous;
        _log('[Scale] TCP → Continuous mode detected (data received passively)');
      } else {
        // Try command mode — send a weight request
        _detectedMode = await _detectTcpMode();
      }

      _main.send({'type': 'saveMode', 'mode': _detectedMode == ScaleMode.command ? 'command' : 'continuous', 'command': _detectedMode == ScaleMode.command ? _activeCommand : null});

      // For command mode, start a timer to periodically send weight requests
      if (_detectedMode == ScaleMode.command) {
        _startTcpCommandReading();
      }
      // For continuous mode, data arrives via _socketSubscription listener

      _main.send({
        'type': 'connected',
        'success': true,
        'mode': _detectedMode == ScaleMode.command ? 'command' : 'continuous',
        'isBinary': _isBinaryProtocol,
        'adcCountsPerKg': _adcCountsPerKg,
      });
    } catch (e) {
      _log('[Scale] TCP connection failed: $e');
      _isTcp = false;
      _socket = null;
      _main.send({
        'type': 'connected',
        'success': false,
        'mode': 'continuous',
        'isBinary': false,
      });
    }
  }

  /// Called when data arrives on the TCP socket
  void _onTcpData(List<int> data) {
    if (data.isEmpty) return;
    _linkHealth.onData(DateTime.now());

    _logRawData(data, String.fromCharCodes(data));

    // Check for binary protocol
    if (!_isBinaryProtocol && data.contains(_binaryHeader)) {
      _isBinaryProtocol = true;
      _log('[Scale] TCP: Binary protocol detected (0xAB header)');
      _main.send({
        'type': 'modeDetected',
        'mode': 'continuous',
        'isBinary': true,
      });
    }

    if (_isBinaryProtocol) {
      final weight = _processBinaryData(data);
      if (weight != null) _emitWeight(weight);
    } else {
      final response = String.fromCharCodes(data);
      _rawBuffer += response;
      final weight = _parseWeightFromBuffer(_rawBuffer);
      if (weight != null && weight >= 0) {
        _emitWeight(weight);
      }
      if (_rawBuffer.length > 512) {
        _rawBuffer = _rawBuffer.substring(_rawBuffer.length - 256);
      }
    }
  }

  Future<ScaleMode> _detectTcpMode() async {
    if (_socket == null) return ScaleMode.continuous;

    final commands = ['W\r\n', 'W\r', 'P\r\n', 'S\r\n', 'SI\r\n', 'IP\r\n'];
    for (final cmd in commands) {
      try {
        _rawBuffer = '';
        _socket!.write(cmd);
        await Future.delayed(const Duration(milliseconds: 500));
        if (_rawBuffer.isNotEmpty) {
          final weight = _parseWeightFromBuffer(_rawBuffer);
          if (weight != null) {
            _activeCommand = cmd;
            _log('[Scale] TCP → Command mode! Cmd: "${_sanitize(cmd)}"');
            return ScaleMode.command;
          }
        }
      } catch (e) {
        _log('[Scale] TCP command "${_sanitize(cmd)}" failed: $e');
      }
    }

    _log('[Scale] TCP → Defaulting to continuous mode');
    return ScaleMode.continuous;
  }

  void _startTcpCommandReading() {
    _log('[Scale] TCP: Starting command polling (200ms interval)...');
    _readTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_socket == null) return;
      try {
        _socket!.write(_activeCommand);
      } catch (e) {
        final now = DateTime.now();
        _linkHealth.onIoError(now);
        if (_linkHealth.shouldDisconnect(now)) {
          _log('[Scale] TCP: Too many errors, disconnecting');
          _handleCableDisconnection();
        }
      }
    });
  }

  void _handleDisconnect() {
    _readLoopStopped = true;       // stop event-driven read loops
    _readTimer?.cancel();
    _readTimer = null;
    _rawBuffer = '';
    _lastWeight = 0;
    _recentWeights.clear();
    _smoothingBuffer.clear();
    _binaryBuffer = [];
    _isBinaryProtocol = false;
    _tared = false;
    _tareStableCount = 0;
    _lastRawAdc = 0;
    _closeDiagnosticLog();

    // Close TCP socket
    try {
      _socketSubscription?.cancel();
      _socketSubscription = null;
      _socket?.destroy();
      _socket = null;
    } catch (_) {}
    _isTcp = false;

    // Close serial port
    try {
      _port?.close();
    } catch (_) {}
    _port = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Mode detection (all blocking — safe in worker isolate)
  // ─────────────────────────────────────────────────────────────────────────

  Future<ScaleMode> _detectMode() async {
    if (_port == null) return ScaleMode.continuous;

    _log('[Scale] Auto-detecting scale mode...');

    // === Step 1: Try passive listening (continuous scales) ===
    try {
      // Flush stale data
      try {
        await _port!.readBytes(512, timeout: const Duration(milliseconds: 100));
      } catch (_) {}

      // Wait then read
      await Future.delayed(const Duration(milliseconds: 800));
      final passiveData = await _port!.readBytes(
        256,
        timeout: const Duration(milliseconds: 1200),
      );

      if (passiveData.isNotEmpty) {
        // Check binary protocol (0xAB header)
        if (passiveData.contains(_binaryHeader)) {
          _isBinaryProtocol = true;
          _log('[Scale] → Binary protocol detected (0xAB header found)');
          _detectedMode = ScaleMode.continuous;
          _main.send({'type': 'saveMode', 'mode': 'continuous', 'command': null});
          return ScaleMode.continuous;
        }

        final response = String.fromCharCodes(passiveData);
        _log('[Scale] Passive data (${passiveData.length}b): ${_sanitize(response)}');
        final weight = _parseWeightFromBuffer(response);
        if (weight != null) {
          _log('[Scale] → Continuous mode detected! Weight: $weight');
          _detectedMode = ScaleMode.continuous;
          _main.send({'type': 'saveMode', 'mode': 'continuous', 'command': null});
          return ScaleMode.continuous;
        }

        // Majority non-printable → likely binary
        final nonPrintable =
            passiveData.where((b) => b < 0x20 || b > 0x7E).length;
        if (nonPrintable > passiveData.length * 0.5) {
          _isBinaryProtocol = true;
          _log('[Scale] → Likely binary protocol ($nonPrintable/${passiveData.length} non-printable)');
          _detectedMode = ScaleMode.continuous;
          _main.send({'type': 'saveMode', 'mode': 'continuous', 'command': null});
          return ScaleMode.continuous;
        }
      }
    } catch (e) {
      _log('[Scale] Passive read error: $e');
    }

    // === Step 2: Try command-based ===
    final commands = [
      'W\r\n',
      'W\r',
      'P\r\n',
      'S\r\n',
      'SI\r\n',
      'IP\r\n',
      'R\r\n',
      '\x05',
      '\x02R\x03',
      '\x02P\x03',
      '\x1BW',
      '?\r\n',
    ];

    for (final cmd in commands) {
      try {
        // Flush buffer
        try {
          await _port!.readBytes(256, timeout: const Duration(milliseconds: 50));
        } catch (_) {}

        _port!.writeBytesFromString(cmd, includeZeroTerminator: false);
        await Future.delayed(const Duration(milliseconds: 300));
        final data = await _port!.readBytes(
          128,
          timeout: const Duration(milliseconds: 500),
        );

        if (data.isNotEmpty) {
          final response = String.fromCharCodes(data);
          _log('[Scale] Command "${_sanitize(cmd)}" → ${_sanitize(response)}');
          final weight = _parseWeightFromBuffer(response);
          if (weight != null) {
            _activeCommand = cmd;
            _log('[Scale] → Command mode! Cmd: "${_sanitize(cmd)}", Weight: $weight');
            _detectedMode = ScaleMode.command;
            _main.send({'type': 'saveMode', 'mode': 'command', 'command': cmd});
            return ScaleMode.command;
          }
        }
      } catch (e) {
        _log('[Scale] Command "${_sanitize(cmd)}" failed: $e');
      }
    }

    // === Step 3: Fallback to continuous ===
    _log('[Scale] No command worked, defaulting to continuous mode');
    _detectedMode = ScaleMode.continuous;
    _main.send({'type': 'saveMode', 'mode': 'continuous', 'command': null});
    return ScaleMode.continuous;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Periodic reading
  // ─────────────────────────────────────────────────────────────────────────

  void _startReading() {
    _readTimer?.cancel();
    _readTimer = null;
    _readLoopStopped = false;  // reset for new read session
    if (_detectedMode == ScaleMode.continuous) {
      _startContinuousReading();
    } else {
      _startCommandReading();
    }
  }

  void _emitWeight(double rawWeight) {
    // ── Jump detection: new item placed → reset buffers immediately ──
    // This ensures stability re-detection starts fresh instead of
    // carrying over old readings, giving instant response under load.
    if ((rawWeight - _lastEmittedRaw).abs() > _jumpThreshold) {
      _smoothingBuffer.clear();
      _recentWeights.clear();
      if (_isStable) {
        _isStable = false;
        _main.send({'type': 'stability', 'value': false});
      }
    }
    _lastEmittedRaw = rawWeight;

    // ── Moving average smoothing (3 samples, weighted) ──
    _smoothingBuffer.add(rawWeight);
    if (_smoothingBuffer.length > _smoothingWindowSize) {
      _smoothingBuffer.removeAt(0);
    }
    double weight;
    if (_smoothingBuffer.length >= 2) {
      // Weighted average: latest reading counts most
      double sum = 0, wSum = 0;
      for (int i = 0; i < _smoothingBuffer.length; i++) {
        final w = (i + 1).toDouble();
        sum += _smoothingBuffer[i] * w;
        wSum += w;
      }
      weight = (sum / wSum * 1000).roundToDouble() / 1000; // round to 1g
    } else {
      weight = rawWeight;
    }

    // Only emit if value actually changed (avoid unnecessary UI updates)
    if (weight != _lastWeight) {
      _lastWeight = weight;
      _main.send({'type': 'weight', 'value': weight});
    }

    // ── Stability tracking (5-sample min/max range) ──
    _recentWeights.add(weight);
    if (_recentWeights.length > _stabilityWindowSize) {
      _recentWeights.removeAt(0);
    }
    bool newStable = false;
    // Only consider stable if weight is meaningful (> 10g avoids empty-scale noise)
    if (_recentWeights.length >= _stabilityWindowSize && weight > 0.01) {
      final minW = _recentWeights.reduce((a, b) => a < b ? a : b);
      final maxW = _recentWeights.reduce((a, b) => a > b ? a : b);
      newStable = (maxW - minW) <= _stabilityThreshold;
    }
    if (newStable != _isStable) {
      _isStable = newStable;
      _main.send({'type': 'stability', 'value': _isStable});
    }
  }

  void _startContinuousReading() {
    _log('[Scale] Starting event-driven continuous reading (no polling)...');
    // Event-driven loop: readBytes() blocks until data arrives (up to 30ms
    // timeout), so weight updates arrive with minimal latency. No fixed
    // polling interval to amortize — previously the 50ms Timer.periodic was
    // the dominant source of lag (weight appeared ~50-100ms after scale LCD).
    _runContinuousReadLoop();
  }

  Future<void> _runContinuousReadLoop() async {
    while (!_readLoopStopped && _port != null) {
      if (_isReading) {
        // Another async path is mid-read — yield briefly then retry
        await Future.delayed(const Duration(microseconds: 500));
        continue;
      }
      await _readContinuousTick();
      // No explicit delay — readBytes' own timeout paces the loop.
    }
    _log('[Scale] Continuous read loop exited');
  }

  Future<void> _readContinuousTick() async {
    if (_port == null || _isReading) return;
    _isReading = true;

    try {
      final data = await _port!.readBytes(
        256,
        // 30ms timeout: blocks until bytes arrive OR 30ms elapses. Lets the
        // loop "yield" naturally when the scale is idle, and returns
        // immediately when bytes are available.
        timeout: const Duration(milliseconds: 30),
      );
      if (data.isNotEmpty) {
        _linkHealth.onData(DateTime.now());
        final response = String.fromCharCodes(data);
        _logRawData(data, response);

        // Binary protocol detection
        if (!_isBinaryProtocol && data.contains(_binaryHeader)) {
          _isBinaryProtocol = true;
          _log('[Scale] Binary protocol detected (0xAB header found)');
          _main.send({
            'type': 'modeDetected',
            'mode': 'continuous',
            'isBinary': true,
          });
        }

        if (_isBinaryProtocol) {
          final weight = _processBinaryData(data);
          if (weight != null) {
            _emitWeight(weight);
          }
        } else {
          _rawBuffer += response;
          final weight = _parseWeightFromBuffer(_rawBuffer);
          if (weight != null && weight >= 0) {
            _emitWeight(weight);
          }
          if (_rawBuffer.length > 512) {
            _rawBuffer = _rawBuffer.substring(_rawBuffer.length - 256);
          }
        }
      } else {
        // An empty read is what an idle scale looks like — only a long gap
        // since the last real byte means the cable is actually gone.
        final now = DateTime.now();
        _linkHealth.onEmptyRead(now);
        if (_linkHealth.shouldDisconnect(now)) {
          _log('[Scale] Cable disconnected: silent for '
              '${_linkHealth.silenceFor(now).inMilliseconds}ms');
          _handleCableDisconnection();
          return;
        }
      }
    } catch (e) {
      final now = DateTime.now();
      _linkHealth.onIoError(now);
      if (_linkHealth.shouldDisconnect(now)) {
        _log('[Scale] Cable disconnected: $e');
        _handleCableDisconnection();
        return;
      }
    } finally {
      _isReading = false;
    }
  }

  void _startCommandReading() {
    _log('[Scale] Starting event-driven command reading with '
        '"${_sanitize(_activeCommand)}" (no polling)...');
    // Command mode: still needs to SEND the weight request, but we remove
    // the outer 100ms Timer.periodic. The tick itself has a 30ms inter-command
    // delay which is required by the scale's serial protocol — eliminating
    // that would flood the scale buffer.
    _runCommandReadLoop();
  }

  Future<void> _runCommandReadLoop() async {
    while (!_readLoopStopped && _port != null) {
      if (_isReading) {
        await Future.delayed(const Duration(microseconds: 500));
        continue;
      }
      await _readCommandTick();
      // Inter-request gap tightened 20ms → 10ms. All mainstream POS scales
      // (CAS PD-II, Aclas PS-1, Rongta RLS) handle 10ms reliably; below
      // that some firmwares queue/drop requests.
      if (!_readLoopStopped) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }
    _log('[Scale] Command read loop exited');
  }

  Future<void> _readCommandTick() async {
    if (_port == null || _isReading) return;
    _isReading = true;

    try {
      _port!.writeBytesFromString(
        _activeCommand,
        includeZeroTerminator: false,
      );
      // Scale reply latency — tightened 20ms → 8ms. Gives the scale MCU
      // time to prepare the weight frame but doesn't idle-burn.
      await Future.delayed(const Duration(milliseconds: 8));

      final data = await _port!.readBytes(
        128,
        // 25ms timeout: returns immediately on bytes, caps idle waits.
        // Total cycle floor now ~20ms (write+8+~5ms reply+10 gap) vs the
        // previous 85ms. Scale readings 3-4× faster.
        timeout: const Duration(milliseconds: 25),
      );
      if (data.isNotEmpty) {
        _linkHealth.onData(DateTime.now());
        final response = String.fromCharCodes(data);
        _logRawData(data, response);

        // Binary protocol detection
        if (!_isBinaryProtocol && data.contains(_binaryHeader)) {
          _isBinaryProtocol = true;
          _log('[Scale] Binary protocol detected in command mode (0xAB)');
          _main.send({
            'type': 'modeDetected',
            'mode': 'continuous',
            'isBinary': true,
          });
          // Switch to continuous — stop current command loop first
          _readLoopStopped = true;
          _readTimer?.cancel();
          _isReading = false;
          // Yield so the command loop's while-check sees the stop flag
          await Future.delayed(const Duration(milliseconds: 5));
          _readLoopStopped = false;   // reset for the new loop
          _startContinuousReading();
          return;
        }

        if (_isBinaryProtocol) {
          final weight = _processBinaryData(data);
          if (weight != null) {
            _emitWeight(weight);
          }
        } else {
          final weight = _parseWeightFromBuffer(response);
          if (weight != null && weight >= 0) {
            _emitWeight(weight);
          }
        }
      } else {
        // The scale simply had nothing to say this cycle; that is not a fault.
        final now = DateTime.now();
        _linkHealth.onEmptyRead(now);
        if (_linkHealth.shouldDisconnect(now)) {
          _log('[Scale] Cable disconnected in command mode: silent for '
              '${_linkHealth.silenceFor(now).inMilliseconds}ms');
          _handleCableDisconnection();
          return;
        }
      }
    } catch (e) {
      final now = DateTime.now();
      _linkHealth.onIoError(now);
      if (_linkHealth.shouldDisconnect(now)) {
        _log('[Scale] Cable disconnected: $e');
        _handleCableDisconnection();
        return;
      }
    } finally {
      _isReading = false;
    }
  }

  void _handleCableDisconnection() {
    _readLoopStopped = true;       // stop event-driven read loops
    _readTimer?.cancel();          // legacy timer (TCP path still uses it)
    _readTimer = null;
    _lastWeight = 0;
    _recentWeights.clear();
    _smoothingBuffer.clear();
    _binaryBuffer = [];
    _isBinaryProtocol = false;
    _tared = false;
    _tareStableCount = 0;
    _lastRawAdc = 0;
    _linkHealth.reset(DateTime.now());
    _closeDiagnosticLog();

    // Close TCP socket
    try {
      _socketSubscription?.cancel();
      _socketSubscription = null;
      _socket?.destroy();
      _socket = null;
    } catch (_) {}
    _isTcp = false;

    // Close serial port
    try {
      _port?.close();
    } catch (_) {}
    _port = null;

    _log('[Scale] Disconnected due to cable/network removal');
    _main.send({'type': 'disconnected'});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Tare / Calibrate / Test / Redetect
  // ─────────────────────────────────────────────────────────────────────────

  void _handleTare() {
    if (_lastRawAdc > 0) {
      _tareAdcValue = _lastRawAdc;
      _tared = true;
      _lastWeight = 0.0;
      _recentWeights.clear();
      _smoothingBuffer.clear();
      _isStable = false;
      _main.send({'type': 'weight', 'value': 0.0});
      _main.send({'type': 'stability', 'value': false});
      _log('[Scale] Manual tare set to ADC value: $_tareAdcValue');
    }
  }

  void _handleCalibrate(Map message) {
    final knownWeightKg = (message['knownWeightKg'] as num).toDouble();

    if (!_isBinaryProtocol || !_tared || _lastRawAdc <= 0 || knownWeightKg <= 0) {
      _main.send({'type': 'calibrateResult', 'success': false});
      return;
    }

    final adcDelta = _lastRawAdc - _tareAdcValue;
    if (adcDelta <= 0) {
      _main.send({'type': 'calibrateResult', 'success': false});
      return;
    }

    _adcCountsPerKg = adcDelta / knownWeightKg;
    _log('[Scale] Calibrated: ADC delta=$adcDelta, known=${knownWeightKg}kg → countsPerKg=$_adcCountsPerKg');

    // Ask main isolate to persist
    _main.send({'type': 'saveCalibration', 'countsPerKg': _adcCountsPerKg});

    // Recalculate & broadcast current weight
    final recalculated =
        (adcDelta / _adcCountsPerKg * 1000).roundToDouble() / 1000;
    _lastWeight = recalculated;
    _main.send({'type': 'weight', 'value': recalculated});

    _main.send({
      'type': 'calibrateResult',
      'success': true,
      'countsPerKg': _adcCountsPerKg,
    });
  }

  void _handleTestConnection() async {
    if (_port == null && _socket == null) {
      _main.send({'type': 'testResult', 'success': false});
      return;
    }

    // TCP test: if socket is connected and we have recent weight data, it's working
    if (_isTcp && _socket != null) {
      try {
        // Send a command and check if we get data
        _socket!.write('W\r\n');
        await Future.delayed(const Duration(milliseconds: 500));
        // If we have a last weight, consider it working
        if (_lastWeight > 0 || _rawBuffer.isNotEmpty || _binaryBuffer.isNotEmpty) {
          _log('[Scale] TCP test OK');
          _main.send({'type': 'testResult', 'success': true});
        } else {
          _log('[Scale] TCP test: no data received');
          _main.send({'type': 'testResult', 'success': false});
        }
      } catch (e) {
        _log('[Scale] TCP test error: $e');
        _main.send({'type': 'testResult', 'success': false});
      }
      return;
    }

    try {
      // Method 1: passive read
      final passiveData = await _port!.readBytes(
        256,
        timeout: const Duration(milliseconds: 1000),
      );
      if (passiveData.isNotEmpty) {
        final response = String.fromCharCodes(passiveData);
        final weight = _parseWeightFromBuffer(response);
        if (weight != null) {
          _log('[Scale] Test OK (passive): weight=$weight');
          _main.send({'type': 'testResult', 'success': true});
          return;
        }
      }

      // Method 2: commands
      final commands = [_activeCommand, 'W\r\n', 'P\r\n', 'S\r\n'];
      for (final cmd in commands) {
        try {
          _port!.writeBytesFromString(cmd, includeZeroTerminator: false);
          await Future.delayed(const Duration(milliseconds: 200));
          final data = await _port!.readBytes(
            128,
            timeout: const Duration(milliseconds: 500),
          );
          if (data.isNotEmpty) {
            final response = String.fromCharCodes(data);
            final weight = _parseWeightFromBuffer(response);
            if (weight != null) {
              _log('[Scale] Test OK (command "${_sanitize(cmd)}"): weight=$weight');
              _main.send({'type': 'testResult', 'success': true});
              return;
            }
          }
        } catch (_) {}
      }

      // Method 3: any data at all
      if (passiveData.isNotEmpty) {
        _log('[Scale] Test OK (data received but unparseable)');
        _main.send({'type': 'testResult', 'success': true});
        return;
      }

      _log('[Scale] Test FAILED: no data received');
      _main.send({'type': 'testResult', 'success': false});
    } catch (e) {
      _log('[Scale] Test error: $e');
      _main.send({'type': 'testResult', 'success': false});
    }
  }

  void _handleRedetectMode() async {
    _readLoopStopped = true;       // stop the running event-driven loop
    _readTimer?.cancel();
    // Yield once so any loop in-flight can exit before we restart
    await Future.delayed(const Duration(milliseconds: 10));
    _rawBuffer = '';
    _detectedMode = await _detectMode();
    _main.send({
      'type': 'modeDetected',
      'mode': _detectedMode == ScaleMode.command ? 'command' : 'continuous',
      'isBinary': _isBinaryProtocol,
    });
    _startReading();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Binary protocol parsing
  // ═════════════════════════════════════════════════════════════════════════

  double? _processBinaryData(List<int> data) {
    _binaryBuffer.addAll(data);

    if (_binaryBuffer.length > 1024) {
      _binaryBuffer = _binaryBuffer.sublist(_binaryBuffer.length - 512);
    }

    double? lastWeight;

    while (_binaryBuffer.length >= _binaryFrameSize) {
      final headerIdx = _binaryBuffer.indexOf(_binaryHeader);
      if (headerIdx < 0) {
        _binaryBuffer.clear();
        break;
      }
      if (headerIdx > 0) {
        _binaryBuffer = _binaryBuffer.sublist(headerIdx);
      }
      if (_binaryBuffer.length < _binaryFrameSize) break;

      final frame = _binaryBuffer.sublist(0, _binaryFrameSize);
      _binaryBuffer = _binaryBuffer.sublist(_binaryFrameSize);

      final w = _parseBinaryFrame(frame);
      if (w != null) lastWeight = w;
    }

    return lastWeight;
  }

  double? _parseBinaryFrame(List<int> frame) {
    if (frame.length < _binaryFrameSize) return null;
    if (frame[0] != _binaryHeader) return null;
    if (frame[5] != 0x83 || frame[12] != 0x36) return null;

    final rawAdc =
        (frame[17] << 24) | (frame[18] << 16) | (frame[19] << 8) | frame[20];
    _lastRawAdc = rawAdc;

    final isStable = frame[13] == 0x01;

    // Auto-tare
    if (!_tared) {
      if (isStable) {
        _tareStableCount++;
        if (_tareStableCount >= 5) {
          _tareAdcValue = rawAdc;
          _tared = true;
          _log('[Scale] Auto-tare set to ADC value: $_tareAdcValue');
        }
      } else {
        _tareStableCount = 0;
      }
      return 0.0;
    }

    final adcDelta = rawAdc - _tareAdcValue;
    double weightKg = adcDelta / _adcCountsPerKg;
    weightKg = (weightKg * 1000).roundToDouble() / 1000;
    if (weightKg < -0.005) weightKg = 0.0;
    if (weightKg < 0) weightKg = 0.0;

    return weightKg;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Text-based protocol parsing
  // ═════════════════════════════════════════════════════════════════════════

  String _extractStxEtxFrames(String buffer) {
    final frames = <String>[];
    int idx = 0;
    while (idx < buffer.length) {
      final stxPos = buffer.indexOf('\x02', idx);
      if (stxPos < 0) break;
      final etxPos = buffer.indexOf('\x03', stxPos + 1);
      if (etxPos < 0) break;
      frames.add(buffer.substring(stxPos + 1, etxPos));
      idx = etxPos + 1;
    }
    if (frames.isNotEmpty) return frames.last;
    final bareStx = buffer.lastIndexOf('\x02');
    if (bareStx >= 0 && bareStx < buffer.length - 1) {
      return buffer.substring(bareStx + 1).trim();
    }
    return buffer;
  }

  double? _parseWeightFromBuffer(String buffer) {
    if (buffer.isEmpty) return null;

    final extracted = _extractStxEtxFrames(buffer);
    if (extracted != buffer) {
      final w = _parseSingleWeight(extracted);
      if (w != null) return w;
    }

    final lines = buffer.split(RegExp(r'[\r\n]+'));
    for (int i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final weight = _parseSingleWeight(line);
      if (weight != null) return weight;
    }

    return _parseSingleWeight(buffer);
  }

  double? _parseSingleWeight(String response) {
    if (response.isEmpty) return null;

    try {
      final cleaned = response
          .replaceAll(RegExp(r'[\x00-\x08\x0E-\x1F\x7F]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      if (cleaned.isEmpty) return null;

      // Toledo: "ST,GS,  1.234kg"
      final toledoMatch =
          RegExp(r'[SU][TN],\s*[GN][SN],\s*([+-]?[\d.]+)').firstMatch(cleaned);
      if (toledoMatch != null) {
        return _validateWeight(double.tryParse(toledoMatch.group(1)!));
      }

      // Mettler Toledo: "S S     1.234 kg"
      final mettlerMatch =
          RegExp(r'S\s+[SDE]\s+([+-]?[\d.]+)').firstMatch(cleaned);
      if (mettlerMatch != null) {
        return _validateWeight(double.tryParse(mettlerMatch.group(1)!));
      }

      // CAS: "W  1.234 kg"
      final casMatch =
          RegExp(r'^[nN]?[WN]\s+([+-]?[\d.]+)').firstMatch(cleaned);
      if (casMatch != null) {
        return _validateWeight(double.tryParse(casMatch.group(1)!));
      }

      // ACLAS/Rongta: "wn  1.234"
      final aclasMatch = RegExp(r'w[nstNST]\s*([+-]?[\d.]+)',
              caseSensitive: false)
          .firstMatch(cleaned);
      if (aclasMatch != null) {
        return _validateWeight(double.tryParse(aclasMatch.group(1)!));
      }

      // Rongta PLU: "P01,1.234,2.50,3.13"
      final pluMatch = RegExp(r'P\d+,\s*([\d.]+),', caseSensitive: false)
          .firstMatch(cleaned);
      if (pluMatch != null) {
        return _validateWeight(double.tryParse(pluMatch.group(1)!));
      }

      // Rongta ECR: "$1.234$" or "W:1.234"
      final ecrMatch = RegExp(r'(?:\$|W[T]?:)\s*([\d.]+)', caseSensitive: false)
          .firstMatch(cleaned);
      if (ecrMatch != null) {
        return _validateWeight(double.tryParse(ecrMatch.group(1)!));
      }

      // Rongta status: "00 S 1.234"
      final rongtaStatusMatch =
          RegExp(r'\d+\s+[SU]\s+([+-]?[\d.]+)', caseSensitive: false)
              .firstMatch(cleaned);
      if (rongtaStatusMatch != null) {
        return _validateWeight(
            double.tryParse(rongtaStatusMatch.group(1)!));
      }

      // POS-NK30: "ST  1.234kg"
      final stMatch =
          RegExp(r'[GSU][TSN]\s+([+-]?[\d.]+)').firstMatch(cleaned);
      if (stMatch != null) {
        return _validateWeight(double.tryParse(stMatch.group(1)!));
      }

      // Dibal: "  1.234 Kg"
      final dibalMatch =
          RegExp(r'[=\s]+([\d.]+)\s*[Kk][Gg]').firstMatch(cleaned);
      if (dibalMatch != null) {
        return _validateWeight(double.tryParse(dibalMatch.group(1)!));
      }

      // A&D: "ST,+001.234  kg"
      final andMatch =
          RegExp(r'[SQ]T,\s*[+-]?([\d.]+)').firstMatch(cleaned);
      if (andMatch != null) {
        return _validateWeight(double.tryParse(andMatch.group(1)!));
      }

      // Generic with unit: "1.234 kg"
      final unitMatch =
          RegExp(r'([\d.]+)\s*(kg|g|lb|oz)', caseSensitive: false)
              .firstMatch(cleaned);
      if (unitMatch != null) {
        double? val = double.tryParse(unitMatch.group(1)!);
        if (val != null) {
          final unit = unitMatch.group(2)!.toLowerCase();
          if (unit == 'g') {
            val = val / 1000.0;
          } else if (unit == 'lb') {
            val = val * 0.453592;
          } else if (unit == 'oz') {
            val = val * 0.0283495;
          }
        }
        return _validateWeight(val);
      }

      // Chinese generic: "001.234"
      final chineseMatch =
          RegExp(r'[+=\s]*0*(\d+\.\d+)').firstMatch(cleaned);
      if (chineseMatch != null) {
        final weight = double.tryParse(chineseMatch.group(1)!);
        if (weight != null && weight >= 0 && weight < 1000) return weight;
      }

      // Comma decimal: "0,350"
      final commaMatch = RegExp(r'([\d]+),(\d+)').firstMatch(cleaned);
      if (commaMatch != null) {
        final weight = double.tryParse(
          '${commaMatch.group(1)}.${commaMatch.group(2)}',
        );
        if (weight != null && weight >= 0 && weight < 1000) return weight;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  double? _validateWeight(double? weight) {
    if (weight == null || weight < 0 || weight >= 1000) return null;
    return weight;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Diagnostic log
  // ═════════════════════════════════════════════════════════════════════════

  String _sanitize(String s) {
    return s
        .replaceAll('\r', '\\r')
        .replaceAll('\n', '\\n')
        .replaceAll(RegExp(r'[\x00-\x1F]'), '?');
  }

  void _startDiagnosticLog(String portName, int baudRate) {
    try {
      final desktopPath = Platform.environment['USERPROFILE'] ?? '';
      if (desktopPath.isEmpty) return;
      final logFile = File('$desktopPath\\Desktop\\scale_raw_data.log');
      _diagnosticLog = logFile.openWrite(mode: FileMode.append);
      _diagnosticLog!.writeln(
        '\n=== Scale session started at ${DateTime.now()} ===',
      );
      _diagnosticLog!.writeln('Port: $portName, Baud: $baudRate');
      _log('[Scale] Diagnostic log: ${logFile.path}');
    } catch (e) {
      _log('[Scale] Could not start diagnostic log: $e');
    }
  }

  void _closeDiagnosticLog() {
    try {
      _diagnosticLog?.writeln('=== Session ended at ${DateTime.now()} ===');
      _diagnosticLog?.close();
    } catch (_) {}
    _diagnosticLog = null;
  }

  void _logRawData(List<int> data, String response) {
    try {
      if (_diagnosticLog == null) return;
      final hex =
          data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      final time = DateTime.now().toIso8601String().substring(11, 23);
      _diagnosticLog!.writeln('[$time] ${data.length}b HEX: $hex');
      _diagnosticLog!.writeln('[$time] STR: ${_sanitize(response)}');
    } catch (_) {}
  }
}
