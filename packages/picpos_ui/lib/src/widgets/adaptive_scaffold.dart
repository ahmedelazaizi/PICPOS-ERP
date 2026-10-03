import 'package:flutter/material.dart';

import '../l10n.dart';
import '../tokens.dart';

class PicPosDestination {
  const PicPosDestination({required this.icon, required this.label, IconData? selectedIcon})
      : selectedIcon = selectedIcon ?? icon;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// App frame: bottom `NavigationBar` below 600 dp, `NavigationRail` at
/// 600 dp and wider (ARCHITECTURE-M §3.1). Direction follows the ambient
/// `Directionality`, so the rail sits on the start side (right in Arabic).
///
/// When there are more than [maxBarDestinations] destinations, the phone bar
/// shows the first `max - 1` plus «المزيد / More», which opens a sheet with
/// the rest; the rail always shows all of them.
class PicPosAdaptiveScaffold extends StatelessWidget {
  const PicPosAdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.body,
    this.railLeading,
    this.railTrailing,
    this.maxBarDestinations = 5,
  }) : assert(destinations.length >= 2);

  final List<PicPosDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget body;
  final Widget? railLeading;
  final Widget? railTrailing;
  final int maxBarDestinations;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      return c.maxWidth < PicPosBreakpoints.medium ? _phone(context) : _tablet(context);
    });
  }

  bool get _overflows => destinations.length > maxBarDestinations;
  int get _barDirect => _overflows ? maxBarDestinations - 1 : destinations.length;

  Widget _phone(BuildContext context) {
    final t = Tr.of(context, picposUiStrings);
    final direct = destinations.take(_barDirect).toList();
    final barIndex = selectedIndex < _barDirect ? selectedIndex : _barDirect;
    return Scaffold(
      body: SafeArea(bottom: false, child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: barIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) => i < _barDirect ? onSelected(i) : _openMore(context),
        destinations: [
          for (final d in direct)
            NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
          if (_overflows)
            NavigationDestination(icon: const Icon(Icons.more_horiz), label: t('more')),
        ],
      ),
    );
  }

  Future<void> _openMore(BuildContext context) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = _barDirect; i < destinations.length; i++)
            ListTile(
              leading: Icon(i == selectedIndex ? destinations[i].selectedIcon : destinations[i].icon),
              title: Text(destinations[i].label),
              selected: i == selectedIndex,
              onTap: () => Navigator.of(ctx).pop(i),
            ),
        ]),
      ),
    );
    if (picked != null) onSelected(picked);
  }

  Widget _tablet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Row(children: [
          LayoutBuilder(builder: (context, c) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: onSelected,
                    labelType: NavigationRailLabelType.all,
                    leading: railLeading,
                    trailing: railTrailing,
                    destinations: [
                      for (final d in destinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
          VerticalDivider(width: 1, thickness: 1, color: cs.outlineVariant),
          Expanded(child: body),
        ]),
      ),
    );
  }
}

/// List/detail: both panes side by side at 840 dp and wider, otherwise the
/// list only (the app pushes the detail as a page).
class PicPosTwoPane extends StatelessWidget {
  const PicPosTwoPane({super.key, required this.list, required this.detail, this.listWidth = 360});
  final Widget list;
  final Widget detail;
  final double listWidth;

  static bool isTwoPane(BuildContext context) => MediaQuery.sizeOf(context).width >= PicPosBreakpoints.expanded;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < PicPosBreakpoints.expanded) return list;
      return Row(children: [
        SizedBox(width: listWidth, child: list),
        VerticalDivider(width: 1, thickness: 1, color: Theme.of(context).colorScheme.outlineVariant),
        Expanded(child: detail),
      ]);
    });
  }
}
