import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';

/// Opens the camera and returns the first code read (normalised with the same
/// rules the desktop applies to stored barcodes), or null if cancelled.
/// [qr] restricts the formats to QR (pairing); otherwise all barcodes.
Future<String?> scanWithCamera(BuildContext context, {bool qr = false}) =>
    Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => CameraScanPage(qrOnly: qr)));

class CameraScanPage extends StatefulWidget {
  const CameraScanPage({super.key, this.qrOnly = false});
  final bool qrOnly;

  @override
  State<CameraScanPage> createState() => _CameraScanPageState();
}

class _CameraScanPageState extends State<CameraScanPage> {
  late final MobileScannerController _controller = MobileScannerController(
    formats: widget.qrOnly ? const [BarcodeFormat.qrCode] : const [BarcodeFormat.all],
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
    // A QR payload is JSON: it must not be mangled by barcode normalisation.
    Navigator.of(context).pop(widget.qrOnly ? raw : normalizeScan(raw));
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t(widget.qrOnly ? 'scanQr' : 'scanCamera'))),
      body: Stack(children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
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
