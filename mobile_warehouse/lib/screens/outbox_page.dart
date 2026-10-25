import 'package:flutter/material.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';
import '../sync/wh_ops.dart';

/// Pending / accepted / rejected operations of this phone (W5 offline queue).
/// Pending ones are re-sent in order with the same ids; a rejected one is final
/// - the reason is shown and the user decides (it is never silently re-sent).
class OutboxPage extends StatefulWidget {
  const OutboxPage({super.key, required this.ops});
  final WhOps ops;

  @override
  State<OutboxPage> createState() => _OutboxPageState();
}

class _OutboxPageState extends State<OutboxPage> {
  late Future<List<OutboxEntry>> _entries = _load();

  Future<List<OutboxEntry>> _load() async {
    final all = await widget.ops.store.store.outbox();
    return [for (final e in all.reversed) if (e.error != 'dismissed') e];
  }

  bool _mine(OutboxEntry e) =>
      widget.ops.info == null || e.payload['userId'] == widget.ops.info!.userId;

  Future<void> _sendNow() async {
    await widget.ops.outbox.drain();
    if (mounted) {
      setState(() {
        _entries = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return ListenableBuilder(
      listenable: widget.ops.sync,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PicPosPageHeader(
          title: t('navOutbox'),
          subtitle: t('outboxSub'),
          icon: Icons.outbox_outlined,
          actions: [IconButton(key: const Key('outbox.send'), tooltip: t('sendNow'), onPressed: _sendNow, icon: const Icon(Icons.sync))],
        ),
        Expanded(
          child: FutureBuilder<List<OutboxEntry>>(
            future: _entries,
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final entries = snap.data!;
              if (entries.isEmpty) return EmptyState(icon: Icons.outbox_outlined, title: t('outboxEmpty'), message: t('outboxNote'));
              return ListView(padding: const EdgeInsets.all(PicPosSpacing.lg), children: [
                Text(t('outboxNote')),
                Text(t('queueCounts', {'p': '${widget.ops.sync.pending}', 'r': '${widget.ops.sync.rejected}'}), key: const Key('outbox.counts')),
                for (final e in entries)
                  ListTile(
                    key: Key('outbox.${e.globalId}'),
                    title: Text(S.table.entries.containsKey('kind_${e.kind}') ? t('kind_${e.kind}') : e.kind),
                    subtitle: Text(
                      e.status == OutboxStatus.rejected
                          ? S.errorText(context, e.error ?? 'rejected')
                          : !_mine(e)
                              ? t('forUser', {'u': '${e.payload['userName'] ?? ''}'})
                          : e.error == 'transport'
                              ? t('waitingNetwork')
                              : t('attempts', {'n': '${e.attempts}'}),
                    ),
                    trailing: e.status == OutboxStatus.rejected
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            StatusPill(label: t('status_rejected'), tone: PicPosTone.error),
                            IconButton(
                              key: Key('outbox.dismiss.${e.globalId}'),
                              tooltip: t('dismiss'),
                              onPressed: () async {
                                await widget.ops.outbox.dismiss(e);
                                if (mounted) {
      setState(() {
        _entries = _load();
      });
    }
                              },
                              icon: const Icon(Icons.close),
                            ),
                          ])
                        : StatusPill(
                            label: e.status == OutboxStatus.pending && !_mine(e) ? t('status_locked') : t('status_${e.status.name}'),
                            tone: e.status == OutboxStatus.pending ? PicPosTone.warning : PicPosTone.success,
                          ),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
