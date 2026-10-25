import 'package:flutter/material.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';
import '../printing/label_printer.dart';
import '../scan/camera_scan_view.dart';
import '../screens/documents_page.dart';
import '../screens/home_page.dart';
import '../screens/lookup_page.dart';
import '../screens/outbox_page.dart';
import '../screens/settings_page.dart';
import '../session/wh_session.dart';
import '../store/wh_local_store.dart';
import '../sync/wh_ops.dart';
import '../widgets/wh_widgets.dart';

/// Phone: bottom bar (Home, Lookup, Documents, Outbox, Settings); wider
/// screens get the rail from [PicPosAdaptiveScaffold]. An offline / queue
/// banner sits above every tab.
class WarehouseShell extends StatefulWidget {
  const WarehouseShell({
    super.key,
    required this.session,
    required this.store,
    this.initialIndex = 0,
    this.printer = const NoPrinter(),
    this.scanner = scanWithCamera,
  });
  final WhSession session;
  final WhLocalStore store;
  final int initialIndex;
  final LabelPrinter printer;
  final Scanner scanner;

  static const destinationCount = 5;

  @override
  State<WarehouseShell> createState() => _WarehouseShellState();
}

class _WarehouseShellState extends State<WarehouseShell> {
  late int _index = widget.initialIndex;
  late final WhOps _ops = WhOps(session: widget.session, store: widget.store, printer: widget.printer, scanner: widget.scanner);

  @override
  void initState() {
    super.initState();
    // Whatever was left from the last run goes out as soon as the app opens.
    _ops.outbox.drain();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final pages = <Widget>[
      HomePage(session: widget.session),
      LookupPage(session: widget.session, scanner: widget.scanner),
      DocumentsPage(ops: _ops),
      OutboxPage(ops: _ops),
      SettingsPage(session: widget.session, ops: _ops),
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
      body: Column(children: [
        OfflineBanner(sync: _ops.sync),
        Expanded(child: pages[_index]),
      ]),
    );
  }
}
