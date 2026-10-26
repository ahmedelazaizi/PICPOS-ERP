import 'package:flutter/material.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_ui/picpos_ui.dart';

import 'l10n/strings.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'session/pos_session.dart';
import 'shell/pos_shell.dart';

/// Version shown in Settings (keep in step with pubspec `version`).
const kAppVersion = '0.1.0+1';

class PicPosPosApp extends StatelessWidget {
  const PicPosPosApp({super.key, required this.settings, this.session, this.startInShell = false, this.initialDestination = 0});
  final PicPosAppSettings settings;

  /// The pairing/sign-in state. Null = no host connection (tests/previews of
  /// the shell only).
  final PosSession? session;

  /// Tests/previews: open the shell directly instead of the pairing screen.
  final bool startInShell;
  final int initialDestination;

  @override
  Widget build(BuildContext context) {
    return PicPosMaterialApp(
      settings: settings,
      title: (l) => S.table.lookup('appTitle', ar: l.languageCode != 'en'),
      home: _Root(session: session, startInShell: startInShell, initialDestination: initialDestination),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root({required this.session, required this.startInShell, required this.initialDestination});
  final PosSession? session;
  final bool startInShell;
  final int initialDestination;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  late bool _preview = widget.startInShell;

  /// Without an injected session (tests/previews) the tablet is simply
  /// unpaired: an in-memory session that was never restored.
  late final PosSession _session = widget.session ?? PosSession(MemorySecretStore());

  @override
  void initState() {
    super.initState();
    // A revoked tablet wipes itself as soon as the desktop is reachable.
    widget.session?.verifyStillPaired();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        if (_preview) return _shell();
        if (!_session.paired) {
          return OnboardingScreen(session: _session, onPreview: () => setState(() => _preview = true));
        }
        if (!_session.loggedIn) return LoginScreen(session: _session);
        return _shell();
      },
    );
  }

  /// The shell. "Pairing" in its settings leaves the preview, or signs the
  /// cashier out of a real session (the tablet stays paired).
  Widget _shell() => PosShell(
        initialIndex: widget.initialDestination,
        onOpenPairing: () {
          if (_preview) {
            setState(() => _preview = false);
          } else {
            _session.signOut();
          }
        },
      );
}