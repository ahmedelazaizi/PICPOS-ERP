import 'dart:io';
import 'package:flutter/foundation.dart';
import 'cash_drawer_service.dart';

/// Factory function for creating IO-specific cash drawer service
CashDrawerService createCashDrawerService() => CashDrawerServiceIO();

/// Desktop (Windows/macOS/Linux) implementation of cash drawer service
class CashDrawerServiceIO implements CashDrawerService {
  /// ESC/POS command to open cash drawer
  /// Standard pulse command: ESC p m t1 t2
  /// ESC = 0x1B, p = 0x70, m = drawer pin (0 or 1), t1/t2 = pulse timing
  /// Send BOTH pin 0 and pin 1 commands to cover all drawer configurations
  static final Uint8List _openDrawerCommand = Uint8List.fromList([
    0x1B, 0x70, 0x00, 0x19, 0xFA, // ESC p 0 25 250 - open drawer pin 1 (connector 1)
    0x1B, 0x70, 0x01, 0x19, 0xFA, // ESC p 1 25 250 - open drawer pin 2 (connector 2)
  ]);

  @override
  bool get isAvailable =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  Future<bool> openDrawer({String? printerName}) async {
    if (!isAvailable) return false;

    try {
      if (Platform.isWindows) {
        return await _openDrawerWindows(printerName);
      } else if (Platform.isLinux || Platform.isMacOS) {
        return await _openDrawerUnix(printerName);
      }
      return false;
    } catch (e) {
      debugPrint('Error opening cash drawer: $e');
      return false;
    }
  }

  /// Open drawer on Windows using Windows Print Spooler API (winspool.drv)
  /// This sends raw ESC/POS bytes directly through the printer spooler,
  /// which works with any locally installed printer without network sharing.
  Future<bool> _openDrawerWindows(String? printerName) async {
    try {
      // Get default printer if not specified
      final printer = printerName ?? await _getDefaultPrinter();
      if (printer == null) {
        debugPrint('CashDrawer: No printer found for cash drawer');
        return false;
      }

      debugPrint('CashDrawer: Opening drawer on printer: $printer');

      // Create temp file with ESC/POS command
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}\\drawer_cmd.bin');
      await tempFile.writeAsBytes(_openDrawerCommand);

      // Primary Method: Use Windows Print Spooler API via PowerShell
      // This sends raw bytes directly to the printer spooler (winspool.drv)
      // Works with ANY locally installed printer - no sharing required
      final escapedPath = tempFile.path.replaceAll("'", "''");
      final escapedPrinter = printer.replaceAll("'", "''");

      final psResult = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        '''
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class RawPrinterHelper {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DOCINFOW {
        [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
        [MarshalAs(UnmanagedType.LPWStr)] public string pDataType;
    }

    [DllImport("winspool.drv", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool OpenPrinter(string pPrinterName, out IntPtr phPrinter, IntPtr pDefault);

    [DllImport("winspool.drv", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool StartDocPrinter(IntPtr hPrinter, int Level, ref DOCINFOW pDocInfo);

    [DllImport("winspool.drv", SetLastError = true)]
    public static extern bool StartPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", SetLastError = true)]
    public static extern bool WritePrinter(IntPtr hPrinter, byte[] pBuf, int cbBuf, out int pcWritten);

    [DllImport("winspool.drv", SetLastError = true)]
    public static extern bool EndPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", SetLastError = true)]
    public static extern bool EndDocPrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", SetLastError = true)]
    public static extern bool ClosePrinter(IntPtr hPrinter);

    public static bool SendBytesToPrinter(string printerName, byte[] bytes) {
        IntPtr hPrinter;
        if (!OpenPrinter(printerName, out hPrinter, IntPtr.Zero)) return false;

        var di = new DOCINFOW();
        di.pDocName = "CashDrawerOpen";
        di.pDataType = "RAW";

        if (!StartDocPrinter(hPrinter, 1, ref di)) { ClosePrinter(hPrinter); return false; }
        if (!StartPagePrinter(hPrinter)) { EndDocPrinter(hPrinter); ClosePrinter(hPrinter); return false; }

        int written;
        bool ok = WritePrinter(hPrinter, bytes, bytes.Length, out written);

        EndPagePrinter(hPrinter);
        EndDocPrinter(hPrinter);
        ClosePrinter(hPrinter);

        return ok;
    }
}
"@

\$bytes = [System.IO.File]::ReadAllBytes('$escapedPath')
\$result = [RawPrinterHelper]::SendBytesToPrinter('$escapedPrinter', \$bytes)
if (\$result) { exit 0 } else { exit 1 }
''',
      ]);

      debugPrint(
        'CashDrawer: Spooler API result: exitCode=${psResult.exitCode}, stderr=${psResult.stderr}',
      );

      if (psResult.exitCode == 0) {
        // Cleanup
        if (await tempFile.exists()) await tempFile.delete();
        debugPrint('CashDrawer: SUCCESS via Spooler API');
        return true;
      }

      // Fallback Method 1: Try copy /b to network share (requires printer sharing)
      var result = await Process.run('cmd', [
        '/c',
        'copy',
        '/b',
        tempFile.path,
        '\\\\localhost\\$printer',
      ]);
      debugPrint(
        'CashDrawer: Fallback 1 (network share) result: ${result.exitCode}',
      );

      if (result.exitCode != 0) {
        // Fallback Method 2: Try print command
        result = await Process.run('print', [
          '/d:\\\\localhost\\$printer',
          tempFile.path,
        ]);
        debugPrint(
          'CashDrawer: Fallback 2 (print cmd) result: ${result.exitCode}',
        );
      }

      // Cleanup
      if (await tempFile.exists()) await tempFile.delete();

      final success = result.exitCode == 0;
      debugPrint('CashDrawer: Final result - success: $success');
      return success;
    } catch (e) {
      debugPrint('CashDrawer: Windows drawer error: $e');
      return false;
    }
  }

  /// Open drawer on Unix systems (Linux/macOS)
  Future<bool> _openDrawerUnix(String? printerName) async {
    try {
      // Try common printer device paths
      final devicePaths = [
        '/dev/usb/lp0',
        '/dev/usb/lp1',
        '/dev/lp0',
        ?printerName,
      ];

      for (final devicePath in devicePaths) {
        try {
          final file = File(devicePath);
          if (await file.exists()) {
            await file.writeAsBytes(_openDrawerCommand, mode: FileMode.append);
            return true;
          }
        } catch (_) {
          continue;
        }
      }

      // Fallback: use lpr command
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/drawer_cmd.bin');
      await tempFile.writeAsBytes(_openDrawerCommand);

      final result = await Process.run('lpr', [
        '-o',
        'raw',
        if (printerName != null) ...['-P', printerName],
        tempFile.path,
      ]);

      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      return result.exitCode == 0;
    } catch (e) {
      debugPrint('Unix drawer error: $e');
      return false;
    }
  }

  /// Get default printer name on Windows
  Future<String?> _getDefaultPrinter() async {
    try {
      final result = await Process.run('powershell', [
        '-Command',
        '(Get-WmiObject -Query "SELECT * FROM Win32_Printer WHERE Default=TRUE").Name',
      ]);

      if (result.exitCode == 0) {
        final printer = result.stdout.toString().trim();
        if (printer.isNotEmpty) return printer;
      }
    } catch (e) {
      debugPrint('Error getting default printer: $e');
    }
    return null;
  }
}
