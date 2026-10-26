import 'package:flutter/material.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';
import '../session/wh_session.dart' show errorCode;
import '../sync/wh_ops.dart';
import '../sync/wh_outbox.dart';
import '../widgets/wh_widgets.dart';
import 'line_picker.dart';
import 'supervisor_proof.dart';

/// W3: staged transfers (request -> approve -> dispatch -> receive).
/// Requests, dispatches and receipts go through the outbox (idempotent);
/// approvals and shortage decisions need the office and are sent at once.
/// The accountant keeps the whole feature OFF until the in-transit accounting
/// is signed off; while it is off the office says so and so do we.
class TransfersPage extends StatefulWidget {
  const TransfersPage({super.key, required this.ops});
  final WhOps ops;
  @override
  State<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends State<TransfersPage> {
  List<WhDoc>? _docs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await widget.ops.online((c) => c.transfers());
      if (mounted) setState(() => _docs = d);
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorCode(e));
    }
  }

  Future<void> _queue(WhDoc d, String action, [Map<String, Object?> body = const {}]) async {
    final t = S.of(context);
    final id = await widget.ops.outbox.enqueue('transfer_$action', '${WhDocPaths.transfers}/${d.globalId}/$action', {...body, 'expectedVersion': d.version});
    final r = await widget.ops.outbox.drainFor([id]);
    if (!mounted) return;
    showOutcome(context, r, sent: t('sentNow'), saved: t('savedForLater'));
    await _load();
  }

  Future<void> _direct(WhDoc d, String action, [Map<String, Object?> body = const {}, String? approvalProof]) async {
    try {
      await widget.ops.online((c) => c.transferAction(d.globalId, action, body: {...body, 'expectedVersion': d.version}, commandId: newId('cmd'), approvalProof: approvalProof));
      if (mounted) showDone(context, S.of(context)('sentNow'));
    } on Object catch (e) {
      if (mounted) showFailure(context, e);
    }
    await _load();
  }

  Future<void> _receive(WhDoc d) async {
    final t = S.of(context);
    final got = <String, (String, String)>{};
    for (final l in d.lines) {
      final q = await askQuantity(context, title: t('receivedOf', {'q': ltr(l.quantity)}), initial: l.quantity);
      if (q == null || !mounted) return;
      // WH-012: the damaged part is entered here, otherwise it is booked as a
      // shortage (or as good stock when the user folds it into the received).
      final dmg = await askQuantity(context, title: t('damagedOf', {'q': ltr(l.quantity)}), initial: '0');
      if (dmg == null || !mounted) return;
      final total = (double.tryParse(q) ?? 0) + (double.tryParse(dmg) ?? 0);
      if (total > (double.tryParse(l.quantity) ?? 0) + 1e-9) {
        showDone(context, t('qtyExceeds'));
        return;
      }
      got[l.lineGlobalId] = (q, dmg);
    }
    await _queue(d, 'receive', {
      'lines': [for (final e in got.entries) {'lineGlobalId': e.key, 'received': e.value.$1, 'damaged': e.value.$2}],
    });
  }

  List<Widget> _actions(WhDoc d) {
    final t = S.of(context);
    final canTransfer = widget.ops.can('inventory_transfer');
    final canApprove = widget.ops.can('stock_adjust_approve');
    Widget b(String key, String label, VoidCallback f) => FilledButton.tonal(
        key: Key('${d.globalId}.$key'), style: FilledButton.styleFrom(minimumSize: const Size(0, 48)), onPressed: f, child: Text(label));
    return [
      if (d.state == 'requested' && canApprove) ...[
        b('approve', t('approve'), () => _direct(d, 'approve')),
        b('reject', t('reject'), () => _direct(d, 'reject')),
      ],
      // WH-010: a keeper without the approval right asks a supervisor to approve HERE.
      if (d.state == 'requested' && !canApprove && canTransfer)
        b('askApproval', t('askApproval'), () async {
          final p = await askSupervisorProof(context, widget.ops, kind: 'transfer', ref: d.globalId, action: 'approve');
          if (p != null && mounted) await _direct(d, 'approve', const {}, p.proof);
        }),
      if (d.state == 'approved' && canTransfer) b('dispatch', t('dispatch'), () => _queue(d, 'dispatch')),
      if (d.state == 'in_transit' && canTransfer) b('receive', t('receive'), () => _receive(d)),
      if (d.state == 'received_short' && canApprove) ...[
        b('return', t('returnToSource'), () => _direct(d, 'resolve', {'resolution': 'return_to_source'})),
        b('writeoff', t('writeOff'), () => _direct(d, 'resolve', {'resolution': 'write_off_loss'})),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t('transfersTitle')), actions: [
        IconButton(tooltip: t('refresh'), onPressed: _load, icon: const Icon(Icons.refresh)),
      ]),
      floatingActionButton: widget.ops.can('inventory_transfer')
          ? FloatingActionButton.extended(
              key: const Key('transfer.new'),
              // The office switched staged transfers off: a request would only
              // be refused, so the button is disabled and the page says why.
              onPressed: _error == 'staged_transfers_disabled'
                  ? null
                  : () async {
                      await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => NewTransferPage(ops: widget.ops)));
                      await _load();
                    },
              icon: const Icon(Icons.add),
              label: Text(t('newTransfer')),
            )
          : null,
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(PicPosSpacing.lg), child: Text(S.errorText(context, _error!), key: const Key('transfers.error'))))
          : _docs == null
              ? const Center(child: CircularProgressIndicator())
              : _docs!.isEmpty
                  ? EmptyState(icon: Icons.swap_horiz, title: t('transfersTitle'), message: t('transfersNone'))
                  : ListView(padding: const EdgeInsets.all(PicPosSpacing.lg), children: [
                      for (final d in _docs!)
                        PicPosBlock(
                          title: '${d.globalId.length > 12 ? d.globalId.substring(0, 12) : d.globalId}…',
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            StatusPill(label: t('state_${d.state}'), tone: PicPosTone.brand),
                            const SizedBox(height: PicPosSpacing.sm),
                            Text(t('transferLines', {'n': ltr(d.lines.length)})),
                            const SizedBox(height: PicPosSpacing.sm),
                            Wrap(spacing: PicPosSpacing.sm, runSpacing: PicPosSpacing.sm, children: _actions(d)),
                          ]),
                        ),
                    ]),
    );
  }
}

class NewTransferPage extends StatefulWidget {
  const NewTransferPage({super.key, required this.ops});
  final WhOps ops;
  @override
  State<NewTransferPage> createState() => _NewTransferPageState();
}

class _NewTransferPageState extends State<NewTransferPage> {
  final _lines = <PickedLine>[];
  // One document id per page (WH-011): a double tap re-queues the SAME document
  // instead of minting a second one, and a busy flag blocks the second tap.
  final _docId = newId('transfer');
  bool _busy = false;
  int? _from;
  int? _to;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final whs = widget.ops.info?.warehouses ?? const <WhWarehouse>[];
    DropdownMenuItem<int> item(WhWarehouse w) => DropdownMenuItem(value: w.id, child: Text(w.name));
    return Scaffold(
      appBar: AppBar(title: Text(t('newTransfer'))),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(PicPosSpacing.lg), children: [
            DropdownButtonFormField<int>(
              key: const Key('transfer.from'), initialValue: _from, items: [for (final w in whs) item(w)],
              onChanged: (v) => setState(() => _from = v), decoration: InputDecoration(labelText: t('fromWarehouse')),
            ),
            const SizedBox(height: PicPosSpacing.sm),
            DropdownButtonFormField<int>(
              key: const Key('transfer.to'), initialValue: _to, items: [for (final w in whs) item(w)],
              onChanged: (v) => setState(() => _to = v), decoration: InputDecoration(labelText: t('toWarehouse')),
            ),
            const SizedBox(height: PicPosSpacing.md),
            LinePicker(ops: widget.ops, lines: _lines, onChanged: () => setState(() {})),
          ]),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(PicPosSpacing.lg),
            child: FilledButton(
              key: const Key('transfer.send'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kBigTarget)),
              onPressed: _busy || _from == null || _to == null || _from == _to || _lines.isEmpty
                  ? null
                  : () async {
                      if (_busy) return; // a second tap before the next frame
                      setState(() => _busy = true);
                      final id = await widget.ops.outbox.enqueue('transfer_request', WhDocPaths.transfers, {
                        'globalId': _docId,
                        'fromWarehouseId': _from,
                        'toWarehouseId': _to,
                        'lines': [for (final l in _lines) l.toJson()],
                      });
                      final r = await widget.ops.outbox.drainFor([id]);
                      if (!context.mounted) return;
                      showOutcome(context, r, sent: t('sentNow'), saved: t('savedForLater'));
                      if (r.rejectedCode != null) {
                        setState(() => _busy = false);
                        return;
                      }
                      Navigator.pop(context);
                    },
              child: Text(t('sendRequest')),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Stock vouchers (in / out / damage) with a mandatory reason. Posted only
/// after a different user approves them in the approvals inbox.
class VoucherPage extends StatefulWidget {
  const VoucherPage({super.key, required this.ops});
  final WhOps ops;
  @override
  State<VoucherPage> createState() => _VoucherPageState();
}

class _VoucherPageState extends State<VoucherPage> {
  final _lines = <PickedLine>[];
  final _reason = TextEditingController();
  final _docId = newId('voucher'); // one document id per page (WH-011)
  bool _busy = false;
  String _type = 'out';
  int? _wh;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final whs = widget.ops.info?.warehouses ?? const <WhWarehouse>[];
    final ready = _wh != null && _reason.text.trim().isNotEmpty && _lines.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(t('voucherTitle'))),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(PicPosSpacing.lg), children: [
            SegmentedButton<String>(
              key: const Key('voucher.type'),
              segments: [
                ButtonSegment(value: 'in', label: Text(t('voucherIn'))),
                ButtonSegment(value: 'out', label: Text(t('voucherOut'))),
                ButtonSegment(value: 'damage', label: Text(t('voucherDamage'))),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: PicPosSpacing.sm),
            DropdownButtonFormField<int>(
              key: const Key('voucher.wh'), initialValue: _wh,
              items: [for (final w in whs) DropdownMenuItem(value: w.id, child: Text(w.name))],
              onChanged: (v) => setState(() => _wh = v), decoration: InputDecoration(labelText: t('warehouse')),
            ),
            const SizedBox(height: PicPosSpacing.sm),
            TextField(key: const Key('voucher.reason'), controller: _reason, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: t('reasonRequired'))),
            const SizedBox(height: PicPosSpacing.md),
            LinePicker(ops: widget.ops, lines: _lines, askBatch: _type == 'in', onChanged: () => setState(() {})),
          ]),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(PicPosSpacing.lg),
            child: FilledButton(
              key: const Key('voucher.send'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kBigTarget)),
              onPressed: !ready || _busy
                  ? null
                  : () async {
                      if (_busy) return; // a second tap before the next frame
                      setState(() => _busy = true);
                      final id = await widget.ops.outbox.enqueue('voucher_create', WhDocPaths.vouchers, {
                        'globalId': _docId,
                        'type': _type,
                        'warehouseId': _wh,
                        'reason': _reason.text.trim(),
                        'lines': [for (final l in _lines) l.toJson()],
                      });
                      final r = await widget.ops.outbox.drainFor([id]);
                      if (!context.mounted) return;
                      showOutcome(context, r, sent: t('voucherSent'), saved: t('savedForLater'));
                      if (r.rejectedCode != null) {
                        setState(() => _busy = false);
                        return;
                      }
                      Navigator.pop(context);
                    },
              child: Text(t('sendForApproval')),
            ),
          ),
        ),
      ]),
    );
  }
}
