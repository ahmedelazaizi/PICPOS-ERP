import 'dart:async';

import 'package:flutter/material.dart';
import 'package:picpos_api_client/picpos_api_client.dart';

import '../l10n/strings.dart';
import 'wh_session.dart';

const kWhIdleLockDuration = Duration(minutes: 5);

/// Keeps the authenticated shell behind the local PIN without touching the
/// server session. The PIN verifier is stored by [WhSession] in [SecretStore].
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.session,
    required this.child,
    this.idleDuration = kWhIdleLockDuration,
    DateTime Function()? now,
  }) : _now = now;

  final WhSession session;
  final Widget child;
  final Duration idleDuration;
  final DateTime Function()? _now;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

enum _LockPhase { checking, setup, locked, unlocked }

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  late final DateTime Function() _now = widget._now ?? DateTime.now;
  _LockPhase _phase = _LockPhase.checking;
  Timer? _idleTimer;
  bool _backgrounded = false;
  String? _error;
  DateTime? _lastActivity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    final configured = await widget.session.hasLocalPin();
    if (!mounted) return;
    if (configured) {
      _lock();
    } else {
      setState(() => _phase = _LockPhase.setup);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _backgrounded = true;
    } else if (state == AppLifecycleState.resumed && _backgrounded) {
      _backgrounded = false;
      if (_phase == _LockPhase.unlocked) _lock();
    }
  }

  void _lock() {
    _idleTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _phase = _LockPhase.locked;
      _error = null;
    });
  }

  void _markActivity() {
    if (_phase != _LockPhase.unlocked) return;
    _lastActivity = _now();
    final activityAt = _lastActivity;
    _idleTimer?.cancel();
    _idleTimer = Timer(widget.idleDuration, () {
      if (mounted &&
          _phase == _LockPhase.unlocked &&
          _lastActivity == activityAt) {
        _lock();
      }
    });
  }

  void _unlock() {
    _idleTimer?.cancel();
    setState(() {
      _phase = _LockPhase.unlocked;
      _error = null;
    });
    _markActivity();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _LockPhase.checking => const Center(child: CircularProgressIndicator()),
      _LockPhase.setup => _PinSetup(
        onSave: (pin, confirmation) async {
          final first = normalizeCredential(pin);
          final second = normalizeCredential(confirmation);
          if (first != second) {
            setState(() => _error = 'app_pin_mismatch');
            return;
          }
          try {
            await widget.session.setLocalPin(first);
            if (mounted) _unlock();
          } on FormatException catch (error) {
            if (mounted) setState(() => _error = error.message);
          }
        },
        error: _error,
      ),
      _LockPhase.locked => _PinUnlock(
        onUnlock: (pin) async {
          final ok = await widget.session.verifyLocalPin(pin);
          if (!mounted) return;
          if (ok) {
            _unlock();
          } else {
            setState(() => _error = 'incorrect_app_pin');
          }
        },
        error: _error,
      ),
      _LockPhase.unlocked => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _markActivity(),
        child: widget.child,
      ),
    };
  }
}

class _PinSetup extends StatefulWidget {
  const _PinSetup({required this.onSave, this.error});
  final Future<void> Function(String pin, String confirmation) onSave;
  final String? error;

  @override
  State<_PinSetup> createState() => _PinSetupState();
}

class _PinSetupState extends State<_PinSetup> {
  final _pin = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    await widget.onSave(_pin.text, _confirmation.text);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return _PinSurface(
      title: t('appPinSetupTitle'),
      body: t('appPinSetupBody'),
      error: widget.error == null ? null : S.errorText(context, widget.error!),
      children: [
        TextField(
          key: const Key('wh.appPinSetup'),
          controller: _pin,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(labelText: t('appPin')),
        ),
        TextField(
          key: const Key('wh.appPinConfirm'),
          controller: _confirmation,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(labelText: t('confirmAppPin')),
        ),
        FilledButton(
          key: const Key('wh.appPinSave'),
          onPressed: _busy ? null : _save,
          child: Text(t('saveAppPin')),
        ),
      ],
    );
  }
}

class _PinUnlock extends StatefulWidget {
  const _PinUnlock({required this.onUnlock, this.error});
  final Future<void> Function(String pin) onUnlock;
  final String? error;

  @override
  State<_PinUnlock> createState() => _PinUnlockState();
}

class _PinUnlockState extends State<_PinUnlock> {
  final _pin = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() => _busy = true);
    await widget.onUnlock(_pin.text);
    if (mounted) {
      _pin.clear();
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return _PinSurface(
      title: t('appPinLockedTitle'),
      body: t('appPinLockedBody'),
      error: widget.error == null ? null : S.errorText(context, widget.error!),
      children: [
        TextField(
          key: const Key('wh.appPinUnlock'),
          controller: _pin,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(labelText: t('appPin')),
          onSubmitted: (_) => _busy ? null : _unlock(),
        ),
        FilledButton(
          key: const Key('wh.appPinUnlockSubmit'),
          onPressed: _busy ? null : _unlock,
          child: Text(t('unlockApp')),
        ),
      ],
    );
  }
}

class _PinSurface extends StatelessWidget {
  const _PinSurface({
    required this.title,
    required this.body,
    required this.children,
    this.error,
  });
  final String title;
  final String body;
  final List<Widget> children;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text(body),
                const SizedBox(height: 24),
                ...children.expand(
                  (child) => [child, const SizedBox(height: 12)],
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
