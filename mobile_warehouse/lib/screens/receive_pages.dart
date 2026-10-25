import 'package:flutter/material.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';
import '../session/wh_session.dart' show errorCode;
import '../sync/wh_ops.dart';
import '../sync/wh_outbox.dart';
import '../widgets/wh_widgets.dart';

/// W2: open purchase orders of my warehouses. Needs the office (the list is
/// not cached: an old list could mislead a receiver), and says so.
class PoListPage extends StatefulWidget {
  const PoListPage({super.key, required this.ops});
  final WhOps ops;
  @override
  State<PoListPage> createState() => _PoListPageState();
}

class _PoListPageState extends State<PoListPage> {
  List<WhPurchaseOrder>? _orders;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final o = await widget.ops.online((c) => c.purchaseOrders());
      if (mounted) setState(() => _orders = o);
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorCode(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t('receiveTitle')), actions: [
        IconButton(key: const Key('po.refresh'), tooltip: t('refresh'), onPressed: _load, icon: const Icon(Icons.refresh)),
      ]),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(PicPosSpacing.lg), child: Text('${t('needsOffice')}\n${S.errorText(context, _error!)}', key: const Key('po.error'))))
          : _orders == null
              ? const Center(child: CircularProgressIndicator())
              : _orders!.isEmpty
                  ? EmptyState(icon: Icons.inventory_2_outlined, title: t('receiveTitle'), message: t('poNone'))
                  : ListView(padding: const EdgeInsets.all(PicPosSpacing.lg), children: [
                      for (final o in _orders!)
                        Card(
                          child: ListTile(
                            key: Key('po.${o.ref}'),
                            minVerticalPadding: PicPosSpacing.md,
                            title: Text(o.orderNumber, textDirection: TextDirection.ltr),
                            subtitle: Text(t('poLines', {'n': '${o.items.length}'})),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => PoReceivePage(ops: widget.ops, order: o))),
                          ),
                        ),
                    ]),
    );
  }
}

class _Draft {
  _Draft(this.item, this.qty, this.condition, {this.batch, this.expiry, this.bin}) : id = newId('line');
  final String id;
  final WhPoItem item;
  final String qty;
  final String condition;
  final String? batch;
  final String? expiry;
  final String? bin;
}

/// Scan-first receiving: scan an item of the order, enter the actual
/// quantity (keypad), batch/expiry when required, condition and bin; review;
/// send. Sending goes through the encrypted outbox, so it works offline and
/// replays with the same ids.
class PoReceivePage extends StatefulWidget {
  const PoReceivePage({super.key, required this.ops, required this.order});
  final WhOps ops;
  final WhPurchaseOrder order;
  @override
  State<PoReceivePage> createState() => _PoReceivePageState();
}

class _PoReceivePageState extends State<PoReceivePage> {
  final _drafts = <_Draft>[];
  final _receiptId = newId('receipt');
  String? _note;
  bool _sent = false;

  double _pending(WhPoItem i) => _drafts.where((d) => d.item.itemId == i.itemId).fold(0.0, (s, d) => s + (double.tryParse(d.qty) ?? 0));

  Future<void> _scanned(String code) async {
    final item = widget.order.items.where((i) => i.barcode == code).firstOrNull;
    if (item == null) {
      setState(() => _note = S.of(context)('itemNotInOrder'));
      return;
    }
    setState(() => _note = null);
    await _enter(item);
  }

  Future<void> _enter(WhPoItem item) async {
    final t = S.of(context);
    final qty = await askQuantity(context, title: item.name ?? t('item'));
    if (qty == null || !mounted) return;
    final d = await showDialog<_Draft>(context: context, builder: (_) => _LineDialog(item: item, qty: qty));
    if (d != null) setState(() => _drafts.add(d));
  }

  Future<void> _send() async {
    final t = S.of(context);
    final ob = widget.ops.outbox;
    final linesOp = await ob.enqueue('receipt_lines', '${WhDocPaths.po}/${Uri.encodeComponent(widget.order.ref)}/receipts', {
      'globalId': _receiptId,
      'lines': [
        for (final d in _drafts)
          WhReceiptLineInput(
            lineGlobalId: d.id,
            productId: d.item.productId,
            quantity: d.qty,
            condition: d.condition,
            batchNumber: d.batch,
            expiryDate: d.expiry,
            locationBarcode: d.bin,
            poItemId: d.item.itemId,
          ).toJson(),
      ],
    });
    final submitOp = await ob.enqueue('receipt_submit', '${WhDocPaths.receipts}/$_receiptId/submit', const {}, after: linesOp);
    setState(() => _sent = true);
    final r = await ob.drainFor([linesOp, submitOp]);
    if (!mounted) return;
    // "Sent" only when the office ACCEPTED both steps (W2.3c): a refusal shows
    // its reason. If the lines were refused nothing exists at the office, so
    // the receipt can be corrected and sent again under the same ids.
    if (r.rejectedCode != null) {
      if (r.rejectedIndex == 0) setState(() => _sent = false);
      return showRejected(context, 'receiptRejected', r.rejectedCode!);
    }
    showDone(context, r.accepted ? t('receiptSent') : t('receiptSaved'));
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.order.orderNumber, textDirection: TextDirection.ltr)),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.all(PicPosSpacing.lg), child: ScanField(ops: widget.ops, onScan: _scanned)),
        if (_note != null) Padding(padding: const EdgeInsets.symmetric(horizontal: PicPosSpacing.lg), child: Text(_note!, key: const Key('receive.note'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(PicPosSpacing.lg), children: [
            for (final i in widget.order.items)
              Card(
                child: ListTile(
                  key: Key('item.${i.productId}'),
                  minVerticalPadding: PicPosSpacing.md,
                  title: Text(i.name ?? '${i.productId}'),
                  subtitle: Text(i.barcode ?? '', textDirection: TextDirection.ltr),
                  trailing: Text(
                    t('progress', {'got': _fmt((double.tryParse(i.received) ?? 0) + _pending(i)), 'of': i.ordered}),
                    textDirection: TextDirection.ltr,
                    style: tt.titleMedium,
                  ),
                  onTap: _sent ? null : () => _enter(i),
                ),
              ),
            if (_drafts.isNotEmpty) ...[
              const SizedBox(height: PicPosSpacing.md),
              Text(t('thisReceipt'), style: tt.titleSmall),
              for (final d in _drafts)
                ListTile(
                  title: Text('${d.item.name} × ${ltr(d.qty)}'),
                  subtitle: Text([
                    if (d.condition == 'damaged') t('damaged'),
                    if (d.batch != null) ltr('${d.batch} ${d.expiry ?? ''}'),
                    if (d.bin != null) ltr(d.bin!),
                  ].join(' · ')),
                  trailing: _sent ? null : IconButton(tooltip: t('remove'), onPressed: () => setState(() => _drafts.remove(d)), icon: const Icon(Icons.delete_outline)),
                ),
            ],
          ]),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(PicPosSpacing.lg),
            child: FilledButton(
              key: const Key('receive.send'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kBigTarget)),
              onPressed: _drafts.isEmpty || _sent ? null : _send,
              child: Text(t('sendReceipt')),
            ),
          ),
        ),
      ]),
    );
  }
}

String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

class _LineDialog extends StatefulWidget {
  const _LineDialog({required this.item, required this.qty});
  final WhPoItem item;
  final String qty;
  @override
  State<_LineDialog> createState() => _LineDialogState();
}

class _LineDialogState extends State<_LineDialog> {
  String _cond = 'ok';
  final _batch = TextEditingController();
  final _expiry = TextEditingController();
  final _bin = TextEditingController();

  @override
  void dispose() {
    _batch.dispose();
    _expiry.dispose();
    _bin.dispose();
    super.dispose();
  }

  bool get _needsBatch => widget.item.trackExpiry && _cond == 'ok';
  bool get _valid => !_needsBatch || (_batch.text.trim().isNotEmpty && DateTime.tryParse(_expiry.text.trim()) != null);

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return AlertDialog(
      title: Text('${widget.item.name} × ${widget.qty}'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<String>(
            key: const Key('line.condition'),
            segments: [ButtonSegment(value: 'ok', label: Text(t('good'))), ButtonSegment(value: 'damaged', label: Text(t('damaged')))],
            selected: {_cond},
            onSelectionChanged: (s) => setState(() => _cond = s.first),
          ),
          if (_needsBatch) ...[
            const SizedBox(height: PicPosSpacing.sm),
            TextField(key: const Key('line.batch'), controller: _batch, textDirection: TextDirection.ltr, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: t('batchNo'))),
            TextField(key: const Key('line.expiry'), controller: _expiry, textDirection: TextDirection.ltr, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: t('expiryDate'), hintText: '2027-01-31')),
          ],
          const SizedBox(height: PicPosSpacing.sm),
          TextField(key: const Key('line.bin'), controller: _bin, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: t('binOptional'))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel'))),
        FilledButton(
          key: const Key('line.add'),
          onPressed: _valid
              ? () => Navigator.pop(
                    context,
                    _Draft(widget.item, widget.qty, _cond,
                        batch: _needsBatch ? _batch.text.trim() : null,
                        expiry: _needsBatch ? _expiry.text.trim() : null,
                        bin: _bin.text.trim().isEmpty ? null : _bin.text.trim()),
                  )
              : null,
          child: Text(t('add')),
        ),
      ],
    );
  }
}
