import 'package:flutter/material.dart';

import '../data/local_store.dart';
import '../l10n/strings.dart';
import '../state/app_controller.dart';
import 'common.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<OutboxEntry>>(
      future: c.store.outbox(),
      builder: (context, snap) {
        final all = snap.data ?? const <OutboxEntry>[];
        int count(OutboxStatus st) => all.where((e) => e.status == st).length;
        final attention = all.where((e) => e.status != OutboxStatus.accepted).toList().reversed;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InfoRow(s.t('lastSync'), c.lastSync == null ? s.t('never') : _fmt(c.lastSync!)),
                    InfoRow(s.t('pending'), '${count(OutboxStatus.pending)}'),
                    InfoRow(s.t('accepted'), '${count(OutboxStatus.accepted)}'),
                    InfoRow(s.t('rejected'), '${count(OutboxStatus.rejected)}',
                        valueColor: count(OutboxStatus.rejected) > 0 ? cs.error : null),
                    if (c.lastSyncError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(s.t('error'), style: TextStyle(color: cs.error)),
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('syncNow'),
                      icon: c.syncing
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.sync),
                      label: Text(s.t('syncNow')),
                      onPressed: c.syncing ? null : c.syncNow,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(s.t('outbox'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (attention.isEmpty) Text(s.t('nothingPending')),
            for (final e in attention)
              ListTile(
                leading: Icon(e.status == OutboxStatus.rejected ? Icons.error_outline : Icons.schedule,
                    color: e.status == OutboxStatus.rejected ? cs.error : null),
                title: Text('${e.payload['number'] ?? e.payload['bookNumber'] ?? ''}'),
                subtitle: Text(e.status == OutboxStatus.rejected ? '${s.t('rejected')}: ${e.error}' : s.t('pending')),
              ),
          ],
        );
      },
    );
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class VanStockScreen extends StatelessWidget {
  const VanStockScreen({super.key});

  static Future<List<(Map<String, Object?>, double)>> _load(AppController c) async => [
        for (final p in await c.products()) (p, await c.availableStock(p['globalId'] as String)),
      ];

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    return FutureBuilder<List<(Map<String, Object?>, double)>>(
      future: _load(c),
      builder: (context, snap) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (p, q) in snap.data ?? const <(Map<String, Object?>, double)>[])
            ListTile(
              title: Text('${p['name']}'),
              subtitle: Text('${p['barcode'] ?? ''}'),
              trailing: Text(q.toStringAsFixed(q % 1 == 0 ? 0 : 2), style: Theme.of(context).textTheme.titleMedium),
            ),
        ],
      ),
    );
  }
}
