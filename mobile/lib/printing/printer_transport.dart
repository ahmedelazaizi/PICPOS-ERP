/// Bluetooth Classic (SPP) link to an ESC/POS printer through the maintained
/// `print_bluetooth_thermal` plugin (Android: paired devices, RFCOMM socket).
/// Pairing itself happens in Android's Bluetooth settings; the app lists the
/// paired devices and remembers the chosen one.
library;

import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class PrinterDevice {
  const PrinterDevice(this.name, this.address);
  final String name;
  final String address;
}

/// Why a print did not reach the paper (shown to the rep, job is queued).
class PrinterException implements Exception {
  PrinterException(this.code);

  /// `noPrinter` | `bluetoothOff` | `permission` | `connectFailed` | `writeFailed` | `timeout`.
  final String code;
  @override
  String toString() => 'PrinterException($code)';
}

abstract class PrinterTransport {
  Future<List<PrinterDevice>> pairedDevices();

  /// Sends [bytes] to the printer at [address]; throws [PrinterException].
  Future<void> send(String address, List<int> bytes);
}

class BluetoothThermalTransport implements PrinterTransport {
  @override
  Future<List<PrinterDevice>> pairedDevices() async {
    if (!await PrintBluetoothThermal.isPermissionBluetoothGranted) throw PrinterException('permission');
    if (!await PrintBluetoothThermal.bluetoothEnabled) throw PrinterException('bluetoothOff');
    return [for (final d in await PrintBluetoothThermal.pairedBluetooths) PrinterDevice(d.name, d.macAdress)];
  }

  @override
  Future<void> send(String address, List<int> bytes) async {
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
