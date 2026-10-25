import 'package:flutter/material.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';
import '../printing/label_printer.dart';
import '../session/wh_session.dart' show errorCode;
import '../sync/wh_ops.dart';
import '../widgets/wh_widgets.dart';

/// W5: item and bin labels. The label data comes from the office; the label
/// is rendered on the phone and sent to the printer chosen in Settings. With
/// no printer the screen says so - it never pretends to have printed.
class LabelsPage extends StatefulWidget {
  const LabelsPage({super.key, required this.ops, this.openSettings});
  final WhOps ops;
  final VoidCallback? openSettings;
  @override
  State<LabelsPage> createState() => _LabelsPageState();
}

class _LabelsPageState extends State<LabelsPage> {
  String _kind = 'item';
  WhLabelData? _label;
  LabelPrintResult? _result;
  int _copies = 1;
  String? _error;

  Future<void> _scanned(String code) async {
    setState(() {
      _error = null;
      _result = null;
    });
    try {
      final l = await widget.ops.online((c) => c.label(_kind, code));
      if (mounted) setState(() => _label = l);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _label = null;
          _error = errorCode(e);
        });
      }
    }
  }

  Future<void> _print() async {
    final lang = Localizations.localeOf(context).languageCode;
    final r = await widget.ops.printer.printLabel(_label!, copies: _copies, locale: lang);
    if (mounted) setState(() => _result = r);
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final printer = widget.ops.printer;
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: Text(t('labelsTitle'))),
      body: ListView(padding: const EdgeInsets.all(PicPosSpacing.lg), children: [
        SegmentedButton<String>(
          key: const Key('label.kind'),
          segments: [ButtonSegment(value: 'item', label: Text(t('labelItem'))), ButtonSegment(value: 'location', label: Text(t('labelBin')))],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() {
            _kind = s.first;
            _label = null;
          }),
        ),
        const SizedBox(height: PicPosSpacing.md),
        ScanField(ops: widget.ops, onScan: _scanned),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: PicPosSpacing.md), child: Text(S.errorText(context, _error!), key: const Key('label.error'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (_label != null) ...[
          const SizedBox(height: PicPosSpacing.md),
          PicPosBlock(
            title: _label!.title,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_label!.subtitle.isNotEmpty) Text(_label!.subtitle, textDirection: TextDirection.ltr),
              Text(_label!.barcode, key: const Key('label.barcode'), textDirection: TextDirection.ltr, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: PicPosSpacing.sm),
              Row(children: [
                Text(t('copies')),
                IconButton(tooltip: t('less'), onPressed: _copies > 1 ? () => setState(() => _copies--) : null, icon: const Icon(Icons.remove)),
                Text('$_copies', key: const Key('label.copies')),
                IconButton(tooltip: t('more'), onPressed: _copies < 50 ? () => setState(() => _copies++) : null, icon: const Icon(Icons.add)),
              ]),
            ]),
          ),
          const SizedBox(height: PicPosSpacing.md),
          if (!printer.hasPrinter)
            Text(t('noPrinterConnected'), key: const Key('label.noPrinter'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          FilledButton.icon(
            key: const Key('label.print'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kBigTarget)),
            onPressed: _print,
            icon: const Icon(Icons.print_outlined),
            label: Text(t('printLabel')),
          ),
          if (r != null)
            Padding(
              padding: const EdgeInsets.only(top: PicPosSpacing.md),
              child: Text(
                switch (r.status) {
                  LabelPrintStatus.printed => t('printed'),
                  LabelPrintStatus.noPrinter => t('noPrinterConnected'),
                  LabelPrintStatus.queued => t('printQueued', {'why': r.error ?? ''}),
                },
                key: const Key('label.result'),
              ),
            ),
          if (!printer.hasPrinter && widget.openSettings != null)
            TextButton(onPressed: widget.openSettings, child: Text(t('choosePrinter'))),
        ],
      ]),
    );
  }
}
