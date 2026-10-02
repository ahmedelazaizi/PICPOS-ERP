import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../state/app_controller.dart';
import 'common.dart';

/// Visit state chip shared by the route list and the customer card.
class VisitChip extends StatelessWidget {
  const VisitChip(this.state, this.reason, {super.key});
  final VisitState state;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (state) {
      VisitState.planned => (Icons.schedule, s.t('planned'), null),
      VisitState.visited => (Icons.check_circle, s.t('visited'), cs.primary),
      VisitState.noSale => (Icons.do_not_disturb_on_outlined, s.t('noSale'), cs.error),
    };
    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(state == VisitState.noSale && reason != null ? '$label · ${s.t('nsr_$reason')}' : label),
    );
  }
}

/// "Visited" / "No sale (reason)" buttons on the customer card.
class VisitActions extends StatefulWidget {
  const VisitActions({super.key, required this.customerGlobalId});
  final String customerGlobalId;
  @override
  State<VisitActions> createState() => _VisitActionsState();
}

class _VisitActionsState extends State<VisitActions> {
  Future<void> _record(String outcome, [String? reason]) async {
    final s = S.of(context);
    try {
      await AppScope.of(context)
          .createVisit(customerGlobalId: widget.customerGlobalId, outcome: outcome, noSaleReason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('saved'))));
      }
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  Future<void> _noSale() async {
    final c = AppScope.of(context);
    final s = S.of(context);
    final reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(s.t('noSaleReason'), style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final r in c.noSaleReasons)
              ListTile(
                key: Key('nsr-$r'),
                title: Text(s.t('nsr_$r')),
                onTap: () => Navigator.pop(context, r),
              ),
          ],
        ),
      ),
    );
    if (reason != null) await _record('no_sale', reason);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = AppScope.of(context);
    return FutureBuilder<(VisitState, String?)>(
      future: c.visitState(widget.customerGlobalId),
      builder: (context, snap) {
        final st = snap.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (st != null) Align(alignment: AlignmentDirectional.centerStart, child: VisitChip(st.$1, st.$2)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  key: const Key('markVisited'),
                  icon: const Icon(Icons.check),
                  label: Text(s.t('markVisited')),
                  onPressed: st?.$1 == VisitState.visited ? null : () => _record('visited'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('noSale'),
                  icon: const Icon(Icons.do_not_disturb_on_outlined),
                  label: Text(s.t('noSale')),
                  onPressed: st?.$1 == VisitState.visited ? null : _noSale,
                ),
              ),
            ]),
          ],
        );
      },
    );
  }
}
