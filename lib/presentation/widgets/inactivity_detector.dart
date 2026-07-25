import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/auth_providers.dart';
import '../../services/session_timeout_service.dart'
    show sessionTimeoutProvider, kWarningSeconds;

/// Wraps the app shell and signs the user out after a period of real
/// inactivity. Reads its duration from the `session_timeout_minutes` setting
/// (`0` = disabled) — the single canonical key both the POS settings screen
/// and the general settings screen write.
///
/// Four defects this replaces (all reported from the field as "النظام بيخرج
/// فجأة لشاشة الدخول"):
///
///  1. **Mouse-only activity.** The old detector listened to `onPointerDown` /
///     `onPointerMove` on its own subtree. A cashier driving the app with a
///     keyboard-wedge barcode scanner, or typing an invoice without touching
///     the mouse, registered as idle and got signed out mid-transaction. It
///     also sat inside the shell's content area, so activity on the sidebar
///     never counted. Both are fixed by observing input GLOBALLY —
///     `HardwareKeyboard` for keys and the gesture binding's global pointer
///     route — so the detector is immune to where it is mounted.
///
///  2. **Hardcoded 15-minute fallback.** It read the duration with
///     `ref.read(sessionTimeoutProvider).value ?? 15`. `initState` ran that
///     read while the provider was still `AsyncLoading`, so `.value` was null
///     and a 15-minute timer was armed **even when the admin had set the
///     timeout to "معطل"**. The timer is now armed only once a real value has
///     resolved; there is no numeric fallback.
///
///  3. **No reaction to setting changes.** Nothing re-armed when the admin
///     changed the setting, so disabling it left the running timer alive. A
///     `ref.listen` now re-arms (or cancels) immediately.
///
///  4. **No warning, and a broken navigation call.** Sign-out was instant and
///     silent, and it called `Navigator.pushNamedAndRemoveUntil('/')` — a
///     route that is not registered on `MaterialApp`, resolved against the
///     shell's *nested* navigator. A 60-second countdown banner with a "إبقاء
///     الجلسة" button now precedes sign-out, and navigation is left to
///     `MaterialApp.home`, which already switches on `isAuthenticated`.
class InactivityDetector extends ConsumerStatefulWidget {
  final Widget child;

  const InactivityDetector({super.key, required this.child});

  @override
  ConsumerState<InactivityDetector> createState() => _InactivityDetectorState();
}

class _InactivityDetectorState extends ConsumerState<InactivityDetector> {
  Timer? _inactivityTimer;
  Timer? _warningTimer;
  Timer? _countdownTimer;

  /// Seconds left before sign-out, or null when no warning is showing.
  final ValueNotifier<int?> _countdown = ValueNotifier<int?>(null);

  /// Resolved timeout in minutes. `null` = the setting has not loaded yet, so
  /// nothing is armed (deliberately — see defect 2 above). `0` = disabled.
  int? _timeoutMinutes;

  /// Re-arming on every raw pointer move would rebuild two timers per mouse
  /// sample, and a barcode scanner fires a burst of key events per scan.
  /// Coalesce activity into at most one re-arm per second.
  DateTime _lastRearm = DateTime.fromMillisecondsSinceEpoch(0);
  static const _rearmThrottle = Duration(seconds: 1);

  bool _armScheduled = false;

  @override
  void initState() {
    super.initState();
    // Global input observers — independent of this widget's position in the
    // tree, so the sidebar, dialogs, overlays and the on-screen keyboard all
    // count as activity.
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointerEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointerEvent);
    _cancelTimers();
    _countdown.dispose();
    super.dispose();
  }

  // ── Activity sources ──────────────────────────────────────────────────────

  /// Passive keyboard observer. Returns `false` so the event keeps
  /// propagating to whatever widget actually has focus.
  bool _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) _onActivity();
    return false;
  }

  void _onPointerEvent(PointerEvent event) {
    if (event is PointerDownEvent ||
        event is PointerMoveEvent ||
        event is PointerUpEvent ||
        event is PointerSignalEvent ||
        event is PointerHoverEvent) {
      _onActivity();
    }
  }

  void _onActivity() {
    final minutes = _timeoutMinutes;
    if (minutes == null || minutes <= 0) return;

    // While the warning banner is up, ANY activity dismisses it and restarts
    // the full window — the operator is demonstrably present.
    if (_countdown.value != null) {
      _armTimers();
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastRearm) < _rearmThrottle) return;
    _armTimers();
  }

  // ── Timer lifecycle ───────────────────────────────────────────────────────

  void _cancelTimers() {
    _inactivityTimer?.cancel();
    _warningTimer?.cancel();
    _countdownTimer?.cancel();
    _inactivityTimer = null;
    _warningTimer = null;
    _countdownTimer = null;
  }

  /// (Re)arm from the current `_timeoutMinutes`. Cancels everything and shows
  /// nothing when the setting is `0` (disabled) or still unknown (`null`).
  void _armTimers() {
    _cancelTimers();
    _countdown.value = null;
    _lastRearm = DateTime.now();

    final minutes = _timeoutMinutes;
    if (minutes == null || minutes <= 0) return;

    final totalSeconds = minutes * 60;
    final warnAt = totalSeconds - kWarningSeconds;
    if (warnAt > 0) {
      _warningTimer = Timer(Duration(seconds: warnAt), _startCountdown);
    }
    _inactivityTimer = Timer(Duration(seconds: totalSeconds), _onInactive);
  }

  /// Defer arming out of the build phase — `ref.listen(fireImmediately: true)`
  /// fires synchronously during build, and `_armTimers` writes `_countdown`,
  /// which would rebuild the banner mid-build.
  void _scheduleArm() {
    if (_armScheduled) return;
    _armScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _armScheduled = false;
      if (mounted) _armTimers();
    });
  }

  void _startCountdown() {
    if (!mounted) return;
    var remaining = kWarningSeconds;
    _countdown.value = remaining;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      remaining--;
      if (remaining <= 0) {
        timer.cancel();
      } else {
        _countdown.value = remaining;
      }
    });
  }

  void _onInactive() {
    _cancelTimers();
    _countdown.value = null;

    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) return;

    // Mirror the manual-logout cleanup in AppShell so the next user does not
    // inherit the previous one's nav items / permissions / branch scope.
    ref.invalidate(userNavItemsProvider);
    ref.invalidate(userAllowedScreensProvider);
    ref.invalidate(currentUserPermissionsProvider);
    ref.invalidate(userRoleProvider);
    ref.invalidate(activeBranchIdProvider);
    ref.read(authProvider.notifier).logout();
    // No Navigator call: `MaterialApp.home` switches to LoginScreen the moment
    // `isAuthenticated` flips. The old pushNamedAndRemoveUntil('/') targeted an
    // unregistered route on the shell's nested navigator.
  }

  @override
  Widget build(BuildContext context) {
    // Watch (not read) the setting so this rebuilds both on first resolution
    // — `initState` is too early, the provider is still AsyncLoading there —
    // and on every later invalidation, including the admin switching it to
    // "معطل" (0), which must cancel a countdown that is already running.
    // `.value` stays null while loading or on error; in that case nothing is
    // armed, rather than falling back to a hardcoded duration.
    final minutes = ref.watch(sessionTimeoutProvider).value;
    if (minutes != null && minutes != _timeoutMinutes) {
      _timeoutMinutes = minutes;
      _scheduleArm();
    }

    return Stack(
      // The previous implementation returned a `Listener` wrapping the child,
      // which passed the parent's TIGHT constraints straight through. A Stack
      // defaults to StackFit.loose, which would hand the child loose
      // constraints instead and change the shell's layout. `expand` preserves
      // the original tight-constraint contract exactly.
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<int?>(
            valueListenable: _countdown,
            builder: (context, remaining, _) {
              if (remaining == null) return const SizedBox.shrink();
              return _InactivityWarningBanner(
                secondsRemaining: remaining,
                onKeepAlive: _armTimers,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Countdown strip shown for the last [kWarningSeconds] before auto sign-out.
class _InactivityWarningBanner extends StatelessWidget {
  final int secondsRemaining;
  final VoidCallback onKeepAlive;

  const _InactivityWarningBanner({
    required this.secondsRemaining,
    required this.onKeepAlive,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orange.shade700, Colors.red.shade600],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer_outlined, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'سيتم تسجيل الخروج تلقائياً خلال $secondsRemaining ثانية بسبب عدم النشاط',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed: onKeepAlive,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                ),
                child: const Text(
                  'إبقاء الجلسة',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
