import 'package:flutter/material.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';
import '../session/wh_session.dart' show errorCode;
import '../sync/wh_ops.dart';
import '../sync/wh_outbox.dart';
import '../widgets/wh_widgets.dart';

/// W4: blind counting. This screen never shows, and the server never sends, a
/// system quantity: the counter sees the goods to count and only his own
/// entries.
class CountTasksPage extends StatefulWidget {
  const CountTasksPage({super.key, required this.ops});
  final WhOps ops;
  @override
  State<CountTasksPage> createState() => _CountTasksPageState();
}

class _CountTasksPageState extends State<CountTasksPage> {
  List<WhCountTask>? _tasks;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final tasks = await widget.ops.online((c) => c.countTasks());
      if (mounted) setState(() => _tasks = tasks);
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorCode(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t('countTitle')), actions: [IconButton(tooltip: t('refresh'), onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(PicPosSpacing.lg), child: Text('${t('needsOffice')}\n${S.errorText(context, _error!)}', key: const Key('count.error'))))
          : _tasks == null
              ? const Center(child: CircularProgressIndicator())
              : _tasks!.isEmpty
                  ? EmptyState(icon: Icons.fact_check_outlined, title: t('countTitle'), message: t('countNone'))
                  : ListView(padding: const EdgeInsets.all(PicPosSpacing.lg), children: [
                      for (final task in _tasks!)
                        Card(
                          child: ListTile(
                            key: Key('task.${task.ref}'),
                            minVerticalPadding: PicPosSpacing.md,
                            title: Text(task.warehouse ?? '${task.warehouseId}'),
                            subtitle: Text(t('countItems', {'n': '${task.items.length}'})),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CountPage(ops: widget.ops, task: task)));
                              await _load();
                            },
                          ),
                        ),
                    ]),
    );
  }
}

class CountPage extends StatefulWidget {
  const CountPage({super.key, required this.ops, required this.task});
  final WhOps ops;
  final WhCountTask task;
  @override
  State<CountPage> createState() => _CountPageState();
}

class _CountPageState extends State<CountPage> {
  final _entered = <int, ({String id, String qty})>{};
  final _docId = newId('count');
  String? _note;
  bool _sent = false;

  Future<void> _count(WhCountItem item) async {
    final q = await askQuantity(context, title: item.name ?? '${item.productId}', initial: _entered[item.productId]?.qty ?? '');
    if (q == null || !mounted) return;
    setState(() => _entered[item.productId] = (id: _entered[item.productId]?.id ?? newId('entry'), qty: q));
  }

  Future<void> _scanned(String code) async {
    final item = widget.task.items.where((i) => i.barcode == code).firstOrNull;
    if (item == null) {
      setState(() => _note = S.of(context)('itemNotInCount'));
      return;
    }
    setState(() => _note = null);
    await _count(item);
  }

  Future<void> _send() async {
    final t = S.of(context);
    final ref = Uri.encodeComponent(widget.task.ref);
    final ob = widget.ops.outbox;
    final entriesOp = await ob.enqueue('count_entries', '${WhDocPaths.counts}/$ref/entries', {
      'globalId': _docId,
      'entries': [for (final e in _entered.entries) {'lineGlobalId': e.value.id, 'productId': e.key, 'quantity': e.value.qty}],
    });
    final submitOp = await ob.enqueue('count_submit', '${WhDocPaths.counts}/$ref/submit', {'globalId': _docId}, after: entriesOp);
    setState(() => _sent = true);
    final r = await ob.drainFor([entriesOp, submitOp]);
    if (!mounted) return;
    if (r.rejectedCode != null && r.rejectedIndex == 0) setState(() => _sent = false);
    showOutcome(context, r, sent: t('countSent'), saved: t('savedForLater'));
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final all = widget.task.items.every((i) => _entered.containsKey(i.productId));
    return Scaffold(
      appBar: AppBar(title: Text(widget.task.warehouse ?? t('countTitle'))),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.all(PicPosSpacing.lg), child: ScanField(ops: widget.ops, onScan: _scanned)),
        if (_note != null) Padding(padding: const EdgeInsets.symmetric(horizontal: PicPosSpacing.lg), child: Text(_note!, key: const Key('count.note'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(PicPosSpacing.lg), children: [
            for (final i in widget.task.items)
              Card(
                child: ListTile(
                  key: Key('count.item.${i.productId}'),
                  minVerticalPadding: PicPosSpacing.md,
                  title: Text(i.name ?? '${i.productId}'),
                  subtitle: Text(i.barcode ?? '', textDirection: TextDirection.ltr),
                  trailing: _entered.containsKey(i.productId)
                      ? Text(_entered[i.productId]!.qty, textDirection: TextDirection.ltr, style: Theme.of(context).textTheme.titleLarge)
                      : StatusPill(label: t('notCounted'), tone: PicPosTone.warning),
                  onTap: _sent ? null : () => _count(i),
                ),
              ),
          ]),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(PicPosSpacing.lg),
            child: FilledButton(
              key: const Key('count.send'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kBigTarget)),
              onPressed: all && !_sent ? _send : null,
              child: Text(t('submitCount')),
            ),
          ),
        ),
      ]),
    );
  }
}
