import 'package:flutter/material.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';
import '../screens/documents_page.dart';
import '../screens/home_page.dart';
import '../screens/lookup_page.dart';
import '../screens/outbox_page.dart';
import '../screens/settings_page.dart';
import '../session/wh_session.dart';
import '../store/wh_local_store.dart';

/// Phone: bottom bar (Home, Lookup, Documents, Outbox, Settings); wider
/// screens get the rail from [PicPosAdaptiveScaffold].
class WarehouseShell extends StatefulWidget {
  const WarehouseShell({super.key, required this.session, required this.store, this.initialIndex = 0});
  final WhSession session;
  final WhLocalStore store;
  final int initialIndex;

  static const destinationCount = 5;

  @override
  State<WarehouseShell> createState() => _WarehouseShellState();
}

class _WarehouseShellState extends State<WarehouseShell> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final pages = <Widget>[
      HomePage(session: widget.session),
      LookupPage(session: widget.session),
      const DocumentsPage(),
      OutboxPage(store: widget.store),
      SettingsPage(session: widget.session),
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
        PicPosDestination(icon: Icons.home_outlined, selectedIcon: Icons.home, label: t('navHome')),
        PicPosDestination(icon: Icons.qr_code_scanner, selectedIcon: Icons.qr_code_scanner, label: t('navLookup')),
        PicPosDestination(icon: Icons.description_outlined, selectedIcon: Icons.description, label: t('navDocuments')),
        PicPosDestination(icon: Icons.outbox_outlined, selectedIcon: Icons.outbox, label: t('navOutbox')),
        PicPosDestination(icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: t('navSettings')),
      ],
      body: pages[_index],
    );
  }
}
