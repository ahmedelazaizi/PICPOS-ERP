import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/strings.dart';
import 'screens/common.dart';
import 'printing/print_service.dart';
import 'screens/expense_screen.dart';
import 'screens/location_permission.dart';
import 'screens/pairing_screen.dart';
import 'screens/print_screen.dart';
import 'screens/route_screen.dart';
import 'screens/sync_screen.dart';
import 'state/app_controller.dart';
import 'theme/brand_theme.dart';

class PicposVanApp extends StatefulWidget {
  const PicposVanApp({super.key, required this.controller, this.printService, this.initialLocale = const Locale('ar')});
  final AppController controller;

  /// Receipt printing (I-4); null hides the printing entry (tests).
  final PrintService? printService;
  final Locale initialLocale;
  @override
  State<PicposVanApp> createState() => _PicposVanAppState();
}

class _PicposVanAppState extends State<PicposVanApp> {
  late Locale _locale = widget.initialLocale;
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    // Print results arrive after the sale screen has closed: show them on
    // the app-level messenger. A failed print never undoes the sale.
    widget.printService?.onOutcome = (o) {
      final ctx = _messenger.currentContext;
      if (ctx == null) return;
      _messenger.currentState?.showSnackBar(SnackBar(content: Text(printOutcomeText(S.of(ctx), o))));
    };
  }

  @override
  Widget build(BuildContext context) {
    final ps = widget.printService;
    ps?.locale = _locale.languageCode;
    final app = AppScope(
      controller: widget.controller,
      child: MaterialApp(
        scaffoldMessengerKey: _messenger,
        onGenerateTitle: (context) => S.of(context).t('appTitle'),
        debugShowCheckedModeBanner: false,
        locale: _locale,
        supportedLocales: S.supported,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final c = widget.controller;
            if (!c.isPaired) return const PairingScreen();
            if (!c.loggedIn) return const LoginScreen();
            return HomeShell(
              onToggleLocale: () => setState(
                  () => _locale = _locale.languageCode == 'ar' ? const Locale('en') : const Locale('ar')),
            );
          },
        ),
      ),
    );
    return ps == null ? app : PrintScope(service: ps, child: app);
  }
}

/// Phone layout: top app bar + Material navigation bar (3 destinations).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.onToggleLocale});
  final VoidCallback onToggleLocale;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // K-3: the route is open — the moment to ask for location (rationale first).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) askLocationIfNeeded(context, AppScope.of(context));
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = AppScope.of(context);
    final titles = [s.t('todayRoute'), s.t('vanStock'), s.t('sync')];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        actions: [
          TextButton(onPressed: widget.onToggleLocale, child: Text(s.t('language'))),
          IconButton(
            key: const Key('openExpense'),
            tooltip: s.t('expense'),
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExpenseScreen())),
          ),
          if (PrintScope.maybeOf(context) case final ps?)
            IconButton(
              key: const Key('openPrinting'),
              tooltip: s.t('printing'),
              icon: Badge(
                isLabelVisible: ps.queue.isNotEmpty,
                label: Text('${ps.queue.length}'),
                child: const Icon(Icons.print_outlined),
              ),
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrintCenterScreen())),
            ),
          IconButton(
            tooltip: s.t('syncNow'),
            onPressed: c.syncing ? null : c.syncNow,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: const [RouteScreen(), VanStockScreen(), SyncScreen()],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.route_outlined), selectedIcon: const Icon(Icons.route), label: titles[0]),
          NavigationDestination(icon: const Icon(Icons.inventory_2_outlined), selectedIcon: const Icon(Icons.inventory_2), label: titles[1]),
          NavigationDestination(icon: const Icon(Icons.sync_outlined), selectedIcon: const Icon(Icons.sync), label: titles[2]),
        ],
      ),
    );
  }
}
