import 'package:flutter/material.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_ui/picpos_ui.dart';
import 'package:picpos_device/picpos_device.dart';

import 'admin_session.dart';
import 'app_lock.dart';
import 'l10n/strings.dart';
import 'screens/onboarding_screen.dart';
import 'shell/admin_shell.dart';

/// Version shown in Settings (keep in step with pubspec `version`).
const kAppVersion = '0.1.0+1';

class PicPosAdminApp extends StatelessWidget {
  const PicPosAdminApp({
    super.key,
    required this.settings,
    this.startInShell = false,
    this.initialDestination = 0,
    this.session,
  });
  final PicPosAppSettings settings;

  /// Tests/previews: open the shell directly instead of the pairing screen.
  final bool startInShell;
  final int initialDestination;
  final AdminSession? session;

  @override
  Widget build(BuildContext context) {
    return PicPosMaterialApp(
      settings: settings,
      title: (l) => S.table.lookup('appTitle', ar: l.languageCode != 'en'),
      home: _Root(
        startInShell: startInShell,
        initialDestination: initialDestination,
        session: session,
      ),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root({
    required this.startInShell,
    required this.initialDestination,
    this.session,
  });
  final bool startInShell;
  final int initialDestination;
  final AdminSession? session;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  late final AdminSession _session =
      widget.session ?? AdminSession(KeystoreSecretStore());
  bool _preview = false;
  String? _restoreError;

  @override
  void initState() {
    super.initState();
    _session.addListener(_changed);
    if (!widget.startInShell) _restore();
  }

  Future<void> _restore() async {
    try {
      await _session.restore();
      if (_session.loggedIn) await _session.refresh();
    } on ApiError catch (error) {
      if (mounted) setState(() => _restoreError = error.code);
    } on Exception catch (error) {
      if (mounted) setState(() => _restoreError = '$error');
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session.removeListener(_changed);
    if (widget.session == null) _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = AdminShell(
      session: _session,
      initialIndex: widget.initialDestination,
      onOpenPairing: () => setState(() => _preview = false),
    );
    if (widget.startInShell || (_preview && !_session.paired)) {
      return shell;
    }
    if (_session.loggedIn) {
      return AppLockGate(session: _session, child: shell);
    }
    return OnboardingScreen(
      session: _session,
      initialError: _restoreError,
      onPreview: () => setState(() => _preview = true),
    );
  }
}
