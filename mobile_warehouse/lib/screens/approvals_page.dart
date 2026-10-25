import 'package:flutter/material.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';
import '../session/wh_session.dart' show errorCode;
import '../sync/wh_ops.dart';
import '../sync/wh_outbox.dart';
import '../widgets/wh_widgets.dart';

/// W5: what waits for MY approval (supervisor / manager). The server leaves
/// out what I wrote, dispatched, received or counted (four-eyes); decisions
/// are sent at once because they need the office's answer.
class ApprovalsPage extends StatefulWidget {
  const ApprovalsPage({super.key, required this.ops});
  final WhOps ops;
  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage> {
  List<WhApprovalItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final i = await widget.ops.online((c) => c.approvals());
      if (mounted) setState(() => _items = i);
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorCode(e));
    }
  }

  Future<void> _run(Future<Object?> Function(WarehouseLanClient c) f) async {
    try {
      await widget.ops.online(f);
      if (mounted) showDone(context, S.of(context)('decisionSent'));
    } on Object catch (e) {
      if (mounted) showFailure(context, e);
    }
    await _load();
  }

  Future<void> _open(WhApprovalItem a) async {
    final t = S.of(context);
    final key = newId('cmd');
    switch (a.type) {
      case 'transfer_request':
        return _choice(a, [
          (t('approve'), () => _run((c) => c.transferAction(a.ref, 'approve', commandId: key))),
          (t('reject'), () => _run((c) => c.transferAction(a.ref, 'reject', commandId: key))),
        ]);
      case 'voucher':
        return _choice(a, [
          (t('approve'), () => _run((c) => c.voucherAction(a.ref, 'approve', commandId: key))),
          (t('reject'), () => _run((c) => c.voucherAction(a.ref, 'reject', commandId: key))),
        ]);
      case 'transfer_shortage':
        return _choice(a, [
          (t('returnToSource'), () => _run((c) => c.transferAction(a.ref, 'resolve', body: {'resolution': 'return_to_source'}, commandId: key))),
          (t('writeOff'), () => _run((c) => c.transferAction(a.ref, 'resolve', body: {'resolution': 'write_off_loss'}, commandId: key))),
        ]);
      case 'count':
        try {
          final r = await widget.ops.online((c) => c.countReview(a.ref));
          if (!mounted) return;
          await showDialog<void>(context: context, builder: (_) => _ReviewDialog(review: r, onApprove: () => _run((c) => c.countApprove(a.ref, commandId: key))));
        } on Object catch (e) {
          if (mounted) showFailure(context, e);
        }
    }
  }

  Future<void> _choice(WhApprovalItem a, List<(String, VoidCallback)> actions) => showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(PicPosSpacing.lg),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(a.reason ?? S.of(context)('type_${a.type}'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: PicPosSpacing.md),
              for (final (label, f) in actions)
                Padding(
                  padding: const EdgeInsets.only(bottom: PicPosSpacing.sm),
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kBigTarget)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      f();
                    },
                    child: Text(label),
                  ),
                ),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t('approvalsTitle')), actions: [IconButton(tooltip: t('refresh'), onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(PicPosSpacing.lg), child: Text('${t('needsOffice')}\n${S.errorText(context, _error!)}', key: const Key('approvals.error'))))
          : _items == null
              ? const Center(child: CircularProgressIndicator())
              : _items!.isEmpty
                  ? EmptyState(icon: Icons.verified_outlined, title: t('approvalsTitle'), message: t('approvalsNone'))
                  : ListView(padding: const EdgeInsets.all(PicPosSpacing.lg), children: [
                      for (final a in _items!)
                        Card(
                          child: ListTile(
                            key: Key('approval.${a.ref}'),
                            minVerticalPadding: PicPosSpacing.md,
                            title: Text(t('type_${a.type}')),
                            subtitle: Text(a.reason ?? ''),
                            trailing: Text(t('ageMinutes', {'n': '${a.ageMinutes}'})),
                            onTap: () => _open(a),
                          ),
                        ),
                    ]),
    );
  }
}

class _ReviewDialog extends StatelessWidget {
  const _ReviewDialog({required this.review, required this.onApprove});
  final WhCountReview review;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return AlertDialog(
      title: Text(t('countReview')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (review.recountNeeded) Text(t('recountNeeded'), key: const Key('review.recount')),
          for (final r in review.rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${r.name ?? r.productId}: ${t('expectedShort')} ${ltr(r.expected)} · ${t('countedShort')} ${ltr(r.counted ?? '—')} · Δ ${ltr(r.variance ?? '—')}'
                '${r.movementsSinceCount > 0 ? ' · ⚠ ${t('movedSince')}' : ''}',
              ),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel'))),
        FilledButton(
          key: const Key('review.approve'),
          onPressed: review.readyForApproval
              ? () {
                  Navigator.pop(context);
                  onApprove();
                }
              : null,
          child: Text(t('approveCount')),
        ),
      ],
    );
  }
}
