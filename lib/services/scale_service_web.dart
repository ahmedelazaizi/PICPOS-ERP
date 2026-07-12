import 'dart:async';

/// Scale mode enum (web stub)
enum ScaleMode { command, continuous, auto }

class ScaleService {
  static ScaleService? _instance;
  ScaleService._();

  static ScaleService get instance {
    _instance ??= ScaleService._();
    return _instance!;
  }

  static List<String> getAvailablePorts() => [];
  bool get isConnected => false;
  String? get currentPort => null;
  ScaleMode get detectedMode => ScaleMode.auto;
  Stream<double>? get weightStream => null;
  bool get isStable => false;
  Stream<bool>? get stabilityStream => null;
  double get lastWeight => 0;

  Future<bool> connect({
    required String portName,
    int baudRate = 9600,
    bool saveSettings = true,
  }) async => false;
  Future<void> disconnect() async {}
  Future<double?> readWeight() async => null;
  Future<bool> testConnection() async => false;
  Future<bool> autoConnect() async => false;
  Future<void> clearSavedSettings() async {}
  Future<Map<String, dynamic>> getSavedSettings() async => {
    'port': null,
    'baudRate': 9600,
    'autoConnect': false,
    'mode': 'auto',
  };
  Future<void> redetectMode() async {}
}
