import 'package:flutter/material.dart';

import '../data/local_store.dart';
import '../l10n/strings.dart';
import '../state/app_controller.dart';
import 'common.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  Future<void> _sync(BuildContext context, AppController controller) async {
    final pending = await controller.pendingDocs();
    final synced = await controller.syncNow();
    if (!context.mounted) return;
    final s = S.of(context);
    String message;
    if (!synced) {
      final error = controller.lastSyncError;
      final reason = error == 'sessionRequired'
          ? s.t('sessionRequired')
          : !controller.isPaired
              ? s.t('deviceRevoked')
              : error == 'rate_limited' || error == 'too_many_attempts'
                  ? s.t('syncRateLimited')
                  : error == null || error.contains('SocketException') || error.contains('TimeoutException')
                      ? s.t('error')
                      : '${s.t('syncFailed')} ($error)';
      message = reason;
    } else if (pending.isEmpty) {
      message = s.t('syncEmpty');
    } else {
      final statuses = {for (final entry in await controller.store.outbox()) entry.globalId: entry.status};
      if (!context.mounted) return;
      final accepted = pending.where((entry) => statuses[entry.globalId] == OutboxStatus.accepted).length;
      final rejected = pending.where((entry) => statuses[entry.globalId] == OutboxStatus.rejected).length;
      message = s.t('syncSent')
          .replaceAll('{count}', '${pending.length}')
          .replaceAll('{accepted}', '$accepted')
          .replaceAll('{rejected}', '$rejected');
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

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
                    InfoRow(s.t('connection'), s.t(c.online ? 'online' : 'offline'),
                        valueColor: c.online ? null : cs.error),
                    InfoRow(s.t('lastSync'), c.lastSync == null ? s.t('never') : _fmt(c.lastSync!)),
                    if (c.nextAutoSync != null) InfoRow(s.t('nextAutoSync'), _fmt(c.nextAutoSync!, seconds: true)),
                    InfoRow(s.t('pending'), '${count(OutboxStatus.pending)}'),
                    InfoRow(s.t('accepted'), '${count(OutboxStatus.accepted)}'),
                    InfoRow(s.t('rejected'), '${count(OutboxStatus.rejected)}',
                        valueColor: count(OutboxStatus.rejected) > 0 ? cs.error : null),
                    if (c.lastSyncError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(c.lastSyncError == 'sessionRequired' ? s.t('sessionRequired') : s.t('error'),
                            style: TextStyle(color: cs.error)),
                      ),
                    if (c.lastSyncError == 'sessionRequired')
                      TextButton(
                        key: const Key('signInAgain'),
                        onPressed: () async {
                          await c.signOut();
                        },
                        child: Text(s.t('login')),
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('syncNow'),
                      icon: c.syncing
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.sync),
                      label: Text(s.t('syncNow')),
                      onPressed: c.syncing ? null : () => _sync(context, c),
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
                title: Text('${s.t('kind_${e.kind}')} ${e.payload['number'] ?? e.payload['bookNumber'] ?? ''}'),
                subtitle: Text(e.status == OutboxStatus.rejected ? '${s.t('rejected')}: ${e.error}' : s.t('pending')),
              ),
          ],
        );
      },
    );
  }

  static String _fmt(DateTime d, {bool seconds = false}) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'
      '${seconds ? ':${d.second.toString().padLeft(2, '0')}' : ''}';
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