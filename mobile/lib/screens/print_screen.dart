import 'package:flutter/material.dart';

import '../data/local_store.dart';
import '../l10n/strings.dart';
import '../printing/print_service.dart';
import '../printing/printer_transport.dart';
import '../printing/receipt_model.dart';

/// Inherited access to the print service (absent in tests that do not print).
class PrintScope extends InheritedNotifier<PrintService> {
  const PrintScope({super.key, required PrintService service, required super.child}) : super(notifier: service);

  static PrintService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PrintScope>()?.notifier;
}

String printerError(S s, String? code) => s.t('prn_${code ?? 'renderFailed'}');

/// Printer settings, the retry queue and reprint from history.
class PrintCenterScreen extends StatefulWidget {
  const PrintCenterScreen({super.key});
  @override
  State<PrintCenterScreen> createState() => _PrintCenterScreenState();
}

class _PrintCenterScreenState extends State<PrintCenterScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = PrintScope.maybeOf(context)!;
    final st = p.settings;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('printing'))),
      body: SafeArea(
        child: FutureBuilder<List<OutboxEntry>>(
          future: p.history(),
          builder: (context, snap) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.print_outlined),
                        title: Text(st.hasPrinter ? (st.name ?? st.address!) : s.t('noPrinterSelected')),
                        subtitle: st.hasPrinter ? Text(st.address!, textDirection: TextDirection.ltr) : null,
                        trailing: TextButton(
                          key: const Key('choosePrinter'),
                          onPressed: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => const PrinterPickerScreen())),
                          child: Text(s.t('choosePrinter')),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(s.t('paperWidth'), style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 4),
                      SegmentedButton<PaperWidth>(
                        segments: [
                          ButtonSegment(value: PaperWidth.mm58, label: Text(s.t('mm58'))),
                          ButtonSegment(value: PaperWidth.mm80, label: Text(s.t('mm80'))),
                        ],
                        selected: {st.paper},
                        onSelectionChanged: (v) => p.saveSettings(st.copyWith(paper: v.first)),
                      ),
                      SwitchListTile(
                        key: const Key('printOnSave'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.t('printOnSave')),
                        value: st.printOnSave,
                        onChanged: (v) => p.saveSettings(st.copyWith(printOnSave: v)),
                      ),
                      OutlinedButton.icon(
                        key: const Key('testPrint'),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: Text(s.t('testPrint')),
                        onPressed: _busy || !st.hasPrinter
                            ? null
                            : () => _run(() async {
                                  final m = ScaffoldMessenger.of(context);
                                  try {
                                    await p.testPrint();
                                    m.showSnackBar(SnackBar(content: Text(s.t('printed'))));
                                  } on PrinterException catch (e) {
                                    m.showSnackBar(SnackBar(content: Text(printerError(s, e.code))));
                                  } catch (_) {
                                    m.showSnackBar(SnackBar(content: Text(printerError(s, null))));
                                  }
                                }),
                      ),
                    ],
                  ),
                ),
              ),
              if (p.queue.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: Text(s.t('printQueue'), style: Theme.of(context).textTheme.titleMedium)),
                  FilledButton.tonalIcon(
                    key: const Key('retryPrints'),
                    icon: const Icon(Icons.refresh),
                    label: Text(s.t('retryAll')),
                    onPressed: _busy ? null : () => _run(p.retryQueue),
                  ),
                ]),
                for (final j in p.queue)
                  ListTile(
                    leading: Icon(Icons.print_disabled_outlined, color: cs.error),
                    title: Text('${s.t('kind_${j.kind}')} ${j.number}'),
                    subtitle: Text('${printerError(s, j.lastError)} · ${j.attempts}×'),
                    trailing: IconButton(
                      tooltip: s.t('discard'),
                      icon: const Icon(Icons.close),
                      onPressed: () => p.discardJob(j.globalId),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              Text(s.t('printHistory'), style: Theme.of(context).textTheme.titleMedium),
              if ((snap.data ?? const []).isEmpty) Text(s.t('nothingPending')),
              for (final e in snap.data ?? const <OutboxEntry>[])
                ListTile(
                  key: Key('doc-${e.globalId}'),
                  title: Text('${s.t('kind_${e.kind}')} ${PrintService.numberOf(e)}'),
                  subtitle: Text(e.status == OutboxStatus.accepted ? s.t('accepted') : s.t(e.status.name)),
                  trailing: IconButton(
                    key: Key('reprint-${e.globalId}'),
                    tooltip: s.t('reprint'),
                    icon: const Icon(Icons.print),
                    onPressed: _busy ? null : () => _run(() => p.printEntry(e, reprint: true)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paired Bluetooth devices; tapping one makes it the default printer.
class PrinterPickerScreen extends StatefulWidget {
  const PrinterPickerScreen({super.key});
  @override
  State<PrinterPickerScreen> createState() => _PrinterPickerScreenState();
}

class _PrinterPickerScreenState extends State<PrinterPickerScreen> {
  Future<List<PrinterDevice>>? _devices;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _devices ??= PrintScope.maybeOf(context)!.discover();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = PrintScope.maybeOf(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('choosePrinter')),
        actions: [
          IconButton(
            tooltip: s.t('refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _devices = p.discover()),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<PrinterDevice>>(
          future: _devices,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            final err = snap.error;
            final list = snap.data ?? const <PrinterDevice>[];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(s.t('pairHint')),
                const SizedBox(height: 12),
                if (err != null)
                  Text(err is PrinterException ? printerError(s, err.code) : s.t('prn_connectFailed'),
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                if (err == null && list.isEmpty) Text(s.t('noPairedPrinters')),
                for (final d in list)
                  ListTile(
                    key: Key('printer-${d.address}'),
                    leading: const Icon(Icons.print_outlined),
                    title: Text(d.name.isEmpty ? d.address : d.name),
                    subtitle: Text(d.address, textDirection: TextDirection.ltr),
                    trailing: p.settings.address == d.address ? const Icon(Icons.check) : null,
                    onTap: () async {
                      await p.saveSettings(p.settings.copyWith(address: d.address, name: d.name));
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Snackbar text after a print attempt.
String printOutcomeText(S s, PrintOutcome o) => o.status == PrintStatus.printed
    ? '${s.t('printed')} — ${o.number}'
    : '${s.t('printQueued')} (${printerError(s, o.error)})';
