import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/strings.dart';

/// Opens the camera and returns the first barcode read, or null.
typedef CameraScan = Future<String?> Function(BuildContext context);

/// Cleans what a scanner delivered: keyboard-wedge (HID) scanners may add a
/// CR/LF/TAB suffix or an AIM/GS1 symbology prefix (`]C1`, `]E0`, …) and
/// group separators; camera reads may carry whitespace.
String normalizeBarcode(String raw) {
  var s = raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
  if (RegExp(r'^\][A-Za-z][0-9A-Za-z]').hasMatch(s)) s = s.substring(3);
  return s;
}

Future<String?> openCameraScanner(BuildContext context) =>
    Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const CameraScanPage()));

/// Full-screen camera reader (retail 1-D codes + QR) with a torch toggle.
class CameraScanPage extends StatefulWidget {
  const CameraScanPage({super.key});
  @override
  State<CameraScanPage> createState() => _CameraScanPageState();
}

class _CameraScanPageState extends State<CameraScanPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.itf2of5,
      BarcodeFormat.qrCode,
    ],
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue == null ? '' : normalizeBarcode(b.rawValue!);
      if (v.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(v);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('cameraScan')),
        actions: [
          IconButton(
            tooltip: s.t('torch'),
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: _controller.toggleTorch,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(s.t('cameraUnavailable'), textAlign: TextAlign.center),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 280,
                height: 160,
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
