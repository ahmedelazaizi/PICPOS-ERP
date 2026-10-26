import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';

/// Opens the camera and returns the first QR read (the pairing JSON, kept
/// verbatim), or null if cancelled. Replaced by a fake in tests/emulators
/// without a camera: manual entry always works.
Future<String?> scanWithCamera(BuildContext context, {bool qr = true}) =>
    Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const CameraScanPage()));

class CameraScanPage extends StatefulWidget {
  const CameraScanPage({super.key});

  @override
  State<CameraScanPage> createState() => _CameraScanPageState();
}

class _CameraScanPageState extends State<CameraScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (raw == null || raw.isEmpty) return;
    _done = true;
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t('scanQr'))),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(PicPosSpacing.lg),
              child: Text(t('cameraUnavailable'), textAlign: TextAlign.center),
            ),
          ),
        ),
        Positioned(
          left: PicPosSpacing.lg,
          right: PicPosSpacing.lg,
          bottom: PicPosSpacing.lg,
          child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: Text(t('cancel'))),
        ),
      ]),
    );
  }
}
