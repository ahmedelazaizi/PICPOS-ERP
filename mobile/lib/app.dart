import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/strings.dart';
import 'screens/common.dart';
import 'screens/pairing_screen.dart';
import 'screens/route_screen.dart';
import 'screens/sync_screen.dart';
import 'state/app_controller.dart';
import 'theme/brand_theme.dart';

class PicposVanApp extends StatefulWidget {
  const PicposVanApp({super.key, required this.controller, this.initialLocale = const Locale('ar')});
  final AppController controller;
  final Locale initialLocale;
  @override
  State<PicposVanApp> createState() => _PicposVanAppState();
}

class _PicposVanAppState extends State<PicposVanApp> {
  late Locale _locale = widget.initialLocale;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: widget.controller,
      child: MaterialApp(
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
