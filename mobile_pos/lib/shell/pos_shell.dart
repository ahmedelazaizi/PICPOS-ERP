import 'package:flutter/material.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';
import '../screens/placeholder_page.dart';
import '../screens/sale_page.dart';
import '../screens/settings_page.dart';

/// M-B screen map (ARCHITECTURE-M §3.2): tablet landscape first (rail),
/// phone allowed (bottom bar).
class PosShell extends StatefulWidget {
  const PosShell({super.key, this.initialIndex = 0, required this.onOpenPairing});
  final int initialIndex;
  final VoidCallback onOpenPairing;

  static const destinationCount = 5;

  @override
  State<PosShell> createState() => _PosShellState();
}

class _PosShellState extends State<PosShell> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final pages = <Widget>[
      const SalePage(),
      PlaceholderPage(title: t('navHeld'), subtitle: t('heldSub'), icon: Icons.pause_circle_outline, message: t('heldComing')),
      PlaceholderPage(title: t('navShift'), subtitle: t('shiftSub'), icon: Icons.point_of_sale, message: t('shiftComing')),
      PlaceholderPage(
          title: t('navReturns'), subtitle: t('returnsSub'), icon: Icons.assignment_return_outlined, message: t('returnsComing')),
      SettingsPage(onOpenPairing: widget.onOpenPairing),
    ];
    return PicPosAdaptiveScaffold(
      selectedIndex: _index,
      onSelected: (i) => setState(() => _index = i),
      railLeading: Padding(
        padding: const EdgeInsets.symmetric(vertical: PicPosSpacing.md),
        child: Text('PicPos',
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: context.picposBrandInk, fontWeight: FontWeight.w800)),
      ),
      destinations: [
        PicPosDestination(icon: Icons.shopping_cart_outlined, selectedIcon: Icons.shopping_cart, label: t('navSale')),
        PicPosDestination(icon: Icons.pause_circle_outline, selectedIcon: Icons.pause_circle, label: t('navHeld')),
        PicPosDestination(icon: Icons.point_of_sale_outlined, selectedIcon: Icons.point_of_sale, label: t('navShift')),
        PicPosDestination(
            icon: Icons.assignment_return_outlined, selectedIcon: Icons.assignment_return, label: t('navReturns')),
        PicPosDestination(icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: t('navSettings')),
      ],
      body: pages[_index],
    );
  }
}
