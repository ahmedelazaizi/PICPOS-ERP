import 'package:flutter/material.dart';

import '../data/local_store.dart';
import '../l10n/strings.dart';
import 'collection_screen.dart';
import 'common.dart';
import 'sale_screen.dart';

/// Customer card: balance (last synced + unsent docs), credit limit, actions.
class CustomerScreen extends StatelessWidget {
  const CustomerScreen({super.key, required this.customerGlobalId});
  final String customerGlobalId;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder(
      future: Future.wait([
        c.store.get(Kinds.customers, customerGlobalId),
        c.effectiveBalance(customerGlobalId),
      ]),
      builder: (context, snap) {
        final data = snap.data;
        final customer = data?[0] as Map<String, Object?>?;
        final balance = data?[1] as double?;
        return Scaffold(
          appBar: AppBar(title: Text('${customer?['name'] ?? ''}')),
          floatingActionButton: customer == null
              ? null
              : FloatingActionButton.extended(
                  icon: const Icon(Icons.receipt_long),
                  label: Text(s.t('newSale')),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => SaleScreen(customerGlobalId: customerGlobalId),
                  )),
                ),
          body: customer == null || balance == null
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Builder(builder: (context) {
                            final limit = (customer['creditLimit'] as num? ?? 0).toDouble();
                            final over = limit > 0 && balance > limit;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                InfoRow(s.t('balance'), money(balance), valueColor: over ? cs.error : null),
                                InfoRow(s.t('creditLimit'), limit > 0 ? money(limit) : s.t('noLimit')),
                                if (limit > 0) InfoRow(s.t('available'), money(limit - balance)),
                                const SizedBox(height: 4),
                                Text(s.t('pendingNote'), style: Theme.of(context).textTheme.bodySmall),
                              ],
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.payments_outlined),
                        label: Text(s.t('collect')),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => CollectionScreen(customerGlobalId: customerGlobalId),
                        )),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
