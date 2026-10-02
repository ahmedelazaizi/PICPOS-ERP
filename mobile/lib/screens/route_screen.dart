import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'common.dart';
import 'customer_screen.dart';

class _RouteRow {
  _RouteRow(this.customer, this.balance, this.visited);
  final Map<String, Object?> customer;
  final double balance;
  final bool visited;
}

/// Today's route: customers in route sequence with visit status.
class RouteScreen extends StatelessWidget {
  const RouteScreen({super.key});

  Future<List<_RouteRow>> _load(BuildContext context) async {
    final c = AppScope.of(context);
    return [
      for (final cu in await c.routeCustomers())
        _RouteRow(cu, await c.effectiveBalance(cu['globalId'] as String), await c.visitedToday(cu['globalId'] as String)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    AppScope.of(context); // rebuild on controller changes
    return FutureBuilder<List<_RouteRow>>(
      future: _load(context),
      builder: (context, snap) {
        final rows = snap.data;
        if (rows == null) return const Center(child: CircularProgressIndicator());
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = rows[i];
            return Card(
              child: ListTile(
                minTileHeight: 64,
                leading: CircleAvatar(
                  backgroundColor: r.visited ? cs.primaryContainer : cs.surfaceContainerHighest,
                  child: Text('${r.customer['sequence'] ?? i + 1}'),
                ),
                title: Text('${r.customer['name']}'),
                subtitle: Text('${s.t('balance')}: ${money(r.balance)}'),
                trailing: Chip(
                  avatar: Icon(r.visited ? Icons.check_circle : Icons.schedule, size: 18),
                  label: Text(s.t(r.visited ? 'visited' : 'notVisited')),
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => CustomerScreen(customerGlobalId: r.customer['globalId'] as String),
                )),
              ),
            );
          },
        );
      },
    );
  }
}
