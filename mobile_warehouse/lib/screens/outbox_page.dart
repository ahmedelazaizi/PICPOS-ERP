import 'package:flutter/material.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';
import '../store/wh_local_store.dart';

/// Pending / accepted / rejected operations of this phone. Skeleton for W2+:
/// shows what is stored, and says that sending is not enabled yet.
class OutboxPage extends StatelessWidget {
  const OutboxPage({super.key, required this.store});
  final WhLocalStore store;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PicPosPageHeader(title: t('navOutbox'), subtitle: t('outboxSub'), icon: Icons.outbox_outlined),
      Expanded(
        child: FutureBuilder<List<OutboxEntry>>(
          future: store.store.outbox(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final entries = snap.data!;
            if (entries.isEmpty) {
              return EmptyState(icon: Icons.outbox_outlined, title: t('outboxEmpty'), message: t('outboxNote'));
            }
            return ListView(padding: const EdgeInsets.all(PicPosSpacing.lg), children: [
              Text(t('outboxNote')),
              for (final e in entries)
                ListTile(
                  title: Text(e.kind, textDirection: TextDirection.ltr),
                  subtitle: Text(e.error ?? e.globalId, textDirection: TextDirection.ltr),
                  trailing: StatusPill(
                    label: e.status.name,
                    tone: switch (e.status) {
                      OutboxStatus.pending => PicPosTone.warning,
                      OutboxStatus.accepted => PicPosTone.success,
                      OutboxStatus.rejected => PicPosTone.error,
                    },
                  ),
                ),
            ]);
          },
        ),
      ),
    ]);
  }
}
