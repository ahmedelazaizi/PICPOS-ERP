import 'package:flutter/material.dart';
import 'package:picpos_ui/picpos_ui.dart';

import 'l10n/strings.dart';
import 'screens/login_page.dart';
import 'screens/onboarding_page.dart';
import 'session/app_lock.dart';
import 'session/wh_session.dart';
import 'shell/warehouse_shell.dart';
import 'store/wh_local_store.dart';

/// Version shown in Settings (keep in step with pubspec `version`).
const kAppVersion = '0.1.0+1';

class PicPosWarehouseApp extends StatelessWidget {
  const PicPosWarehouseApp({
    super.key,
    required this.settings,
    required this.session,
    required this.store,
    this.initialDestination = 0,
    this.lockEnabled = true,
  });
  final PicPosAppSettings settings;
  final WhSession session;
  final WhLocalStore store;
  final int initialDestination;

  /// The local PIN gate. Always on in the app; widget tests may bypass it.
  final bool lockEnabled;

  @override
  Widget build(BuildContext context) {
    return PicPosMaterialApp(
      settings: settings,
      title: (l) => S.table.lookup('appTitle', ar: l.languageCode != 'en'),
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          if (!session.restored) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          if (!session.paired) return OnboardingPage(session: session);
          if (!session.loggedIn) return LoginPage(session: session);
          final shell = WarehouseShell(session: session, store: store, initialIndex: initialDestination);
          return lockEnabled ? AppLockGate(session: session, child: shell) : shell;
        },
      ),
    );
  }
}
