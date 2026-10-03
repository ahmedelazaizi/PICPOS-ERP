import 'package:flutter/material.dart';
import 'package:picpos_ui/picpos_ui.dart';

import 'l10n/strings.dart';
import 'screens/onboarding_screen.dart';
import 'shell/admin_shell.dart';

/// Version shown in Settings (keep in step with pubspec `version`).
const kAppVersion = '0.1.0+1';

class PicPosAdminApp extends StatelessWidget {
  const PicPosAdminApp({super.key, required this.settings, this.startInShell = false, this.initialDestination = 0});
  final PicPosAppSettings settings;

  /// Tests/previews: open the shell directly instead of the pairing screen.
  final bool startInShell;
  final int initialDestination;

  @override
  Widget build(BuildContext context) {
    return PicPosMaterialApp(
      settings: settings,
      title: (l) => S.table.lookup('appTitle', ar: l.languageCode != 'en'),
      home: _Root(startInShell: startInShell, initialDestination: initialDestination),
    );
  }
}

/// M-0: pairing is UI-only, so "preview" moves from onboarding to the shell
/// and Settings can return to onboarding.
class _Root extends StatefulWidget {
  const _Root({required this.startInShell, required this.initialDestination});
  final bool startInShell;
  final int initialDestination;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  late bool _shell = widget.startInShell;

  @override
  Widget build(BuildContext context) {
    return _shell
        ? AdminShell(initialIndex: widget.initialDestination, onOpenPairing: () => setState(() => _shell = false))
        : OnboardingScreen(onPreview: () => setState(() => _shell = true));
  }
}
