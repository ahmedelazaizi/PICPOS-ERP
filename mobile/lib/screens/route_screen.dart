import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../state/app_controller.dart';
import 'common.dart';
import 'customer_screen.dart';
import 'visit_actions.dart';

class _RouteRow {
  _RouteRow(this.customer, this.balance, this.visit);
  final Map<String, Object?> customer;
  final double balance;
  final (VisitState, String?) visit;
  bool get visited => visit.$1 != VisitState.planned;
}

/// Today's route: customers in route sequence with visit status
/// (planned / visited / no sale + reason).
class RouteScreen extends StatelessWidget {
  const RouteScreen({super.key});

  Future<List<_RouteRow>> _load(BuildContext context) async {
    final c = AppScope.of(context);
    return [
      for (final cu in await c.routeCustomers())
        _RouteRow(cu, await c.effectiveBalance(cu['globalId'] as String), await c.visitState(cu['globalId'] as String)),
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
                trailing: VisitChip(r.visit.$1, r.visit.$2),
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
