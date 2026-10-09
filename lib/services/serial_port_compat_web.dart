// ignore_for_file: non_constant_identifier_names
// نسخة الويب من SerialPort (serial_port_win32 تعتمد dart:ffi فلا تُترجم للويب).
// نفس التوقيعات التي يستعملها المشروع؛ كل عملية فعلية ترمي UnsupportedError.
import 'dart:typed_data';

class SerialPort {
  SerialPort(
    this.portName, {
    bool openNow = true,
    this.BaudRate = 115200,
    this.Parity = 0,
    this.StopBits = 0,
    this.ByteSize = 8,
    int ReadIntervalTimeout = 0,
  }) {
    if (openNow) open();
  }

  final String portName;
  int BaudRate;
  int Parity;
  int StopBits;
  int ByteSize;
  bool isOpened = false;

  static List<String> getAvailablePorts() => const [];

  Future<void> open() async => throw UnsupportedError(
      'Serial ports are not available on web');

  void close() {}

  Future<bool> writeBytesFromUint8List(Uint8List uint8list,
          {int timeout = 500}) async =>
      throw UnsupportedError('Serial ports are not available on web');

  Future<bool> writeBytesFromString(String buffer,
          {int timeout = 500, required bool includeZeroTerminator}) async =>
      throw UnsupportedError('Serial ports are not available on web');

  Future<Uint8List> readBytes(int bytesSize,
          {required Duration? timeout,
          Duration dataPollingInterval = const Duration(microseconds: 500)}) async =>
      throw UnsupportedError('Serial ports are not available on web');
}