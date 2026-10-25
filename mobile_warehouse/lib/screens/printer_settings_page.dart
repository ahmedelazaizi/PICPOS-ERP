import 'package:flutter/material.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';
import '../printing/label_printer.dart';
import '../sync/wh_ops.dart';

/// Choose where labels print: a paired Bluetooth printer or a network
/// (raw TCP 9100) one. States plainly when nothing is connected, or when the
/// platform refused Bluetooth (permission / switched off).
class PrinterSettingsPage extends StatefulWidget {
  const PrinterSettingsPage({super.key, required this.ops});
  final WhOps ops;
  @override
  State<PrinterSettingsPage> createState() => _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends State<PrinterSettingsPage> {
  List<PrinterDevice>? _devices;
  String? _problem;
  final _addr = TextEditingController();

  PrintService? get _service {
    final p = widget.ops.printer;
    return p is ServiceLabelPrinter ? p.service : null;
  }

  @override
  void dispose() {
    _addr.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final bt = _service?.transports[PrinterKind.bluetooth];
    if (bt == null) return;
    try {
      final d = await bt.pairedDevices();
      if (mounted) {
        setState(() {
          _devices = d;
          _problem = null;
        });
      }
    } on PrinterException catch (e) {
      if (mounted) setState(() => _problem = e.code);
    }
  }

  Future<void> _use(PrinterSettings s) async {
    await _service!.saveSettings(s);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final svc = _service;
    final cur = svc?.settings;
    return Scaffold(
      appBar: AppBar(title: Text(t('printerTitle'))),
      body: ListView(padding: const EdgeInsets.all(PicPosSpacing.lg), children: [
        if (svc == null)
          Text(t('printerUnsupported'), key: const Key('printer.unsupported'))
        else ...[
          Text(cur!.hasPrinter ? t('printerCurrent', {'name': cur.name ?? cur.address ?? ''}) : t('noPrinterConnected'), key: const Key('printer.status')),
          const SizedBox(height: PicPosSpacing.md),
          SegmentedButton<PaperWidth>(
            segments: const [ButtonSegment(value: PaperWidth.mm58, label: Text('58 mm')), ButtonSegment(value: PaperWidth.mm80, label: Text('80 mm'))],
            selected: {cur.paper},
            onSelectionChanged: (s) => _use(cur.copyWith(paper: s.first)),
          ),
          const SizedBox(height: PicPosSpacing.md),
          FilledButton.icon(
            key: const Key('printer.scan'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: _scan,
            icon: const Icon(Icons.bluetooth_searching),
            label: Text(t('findBluetooth')),
          ),
          if (_problem != null) Padding(padding: const EdgeInsets.only(top: PicPosSpacing.sm), child: Text(t('printer_$_problem'), key: const Key('printer.problem'))),
          for (final d in _devices ?? const <PrinterDevice>[])
            ListTile(
              title: Text(d.name),
              subtitle: Text(d.address, textDirection: TextDirection.ltr),
              onTap: () => _use(cur.copyWith(kind: PrinterKind.bluetooth, address: d.address, name: d.name)),
            ),
          const Divider(),
          TextField(key: const Key('printer.addr'), controller: _addr, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: t('networkPrinter'), hintText: '192.168.1.50:9100')),
          const SizedBox(height: PicPosSpacing.sm),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => _addr.text.trim().isEmpty ? null : _use(cur.copyWith(kind: PrinterKind.network, address: _addr.text.trim(), name: _addr.text.trim())),
            child: Text(t('useNetworkPrinter')),
          ),
        ],
      ]),
    );
  }
}
