// ═══════════════════════════════════════════════════════════════════════════
// Session Timeout Service (C-03)
// Auto-logout after configurable period of inactivity
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers/providers.dart' show settingsRepositoryProvider;

/// Settings key for session timeout in minutes.
/// Stored in the Settings table via SettingsDao.
/// Value: '5', '10', '15', '30', '60', or '0' (disabled)
const kSessionTimeoutKey = 'session_timeout_minutes';

/// Default timeout in minutes when no setting is configured.
const kDefaultTimeoutMinutes = 30;

/// Seconds before timeout to show warning countdown.
const kWarningSeconds = 60;

/// Manages inactivity-based session timeout.
///
/// Usage:
/// 1. Initialize after login: `SessionTimeoutService.instance.start(timeoutMinutes, onTimeout)`
/// 2. Wrap main scaffold with [SessionTimeoutListener] to capture user activity
/// 3. Call `stop()` on logout
class SessionTimeoutService {
  SessionTimeoutService._();
  static final instance = SessionTimeoutService._();

  Timer? _inactivityTimer;
  Timer? _warningTimer;
  Timer? _countdownTimer;
  VoidCallback? _onTimeout;
  int _timeoutMinutes = kDefaultTimeoutMinutes;
  bool _isActive = false;

  /// Countdown value visible to UI (seconds remaining before logout)
  final ValueNotifier<int?> countdownNotifier = ValueNotifier<int?>(null);

  /// Whether the warning countdown is currently showing
  bool get isWarningVisible => countdownNotifier.value != null;

  /// Start the timeout service after user login.
  void start({
    required int timeoutMinutes,
    required VoidCallback onTimeout,
  }) {
    _timeoutMinutes = timeoutMinutes;
    _onTimeout = onTimeout;
    _isActive = true;
    resetTimer();
  }

  /// Stop the timeout service (call on logout).
  void stop() {
    _isActive = false;
    _inactivityTimer?.cancel();
    _warningTimer?.cancel();
    _countdownTimer?.cancel();
    _inactivityTimer = null;
    _warningTimer = null;
    _countdownTimer = null;
    countdownNotifier.value = null;
    _onTimeout = null;
  }

  /// Reset the inactivity timer (called on every user interaction).
  void resetTimer() {
    if (!_isActive || _timeoutMinutes <= 0) return;

    // Cancel any existing timers
    _inactivityTimer?.cancel();
    _warningTimer?.cancel();
    _countdownTimer?.cancel();
    countdownNotifier.value = null;

    final totalSeconds = _timeoutMinutes * 60;
    final warningAt = totalSeconds - kWarningSeconds;

    if (warningAt > 0) {
      // Start warning timer
      _warningTimer = Timer(Duration(seconds: warningAt), _startCountdown);
    }

    // Start inactivity timer (full timeout)
    _inactivityTimer = Timer(Duration(seconds: totalSeconds), _handleTimeout);
  }

  /// Update timeout duration (e.g., when user changes setting).
  void updateTimeout(int newMinutes) {
    _timeoutMinutes = newMinutes;
    if (_isActive) resetTimer();
  }

  void _startCountdown() {
    int remaining = kWarningSeconds;
    countdownNotifier.value = remaining;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      remaining--;
      if (remaining <= 0) {
        timer.cancel();
        countdownNotifier.value = null;
      } else {
        countdownNotifier.value = remaining;
      }
    });
  }

  void _handleTimeout() {
    _countdownTimer?.cancel();
    countdownNotifier.value = null;
    _isActive = false;
    _onTimeout?.call();
  }

  /// Dispose all resources. Call when app is terminating.
  void dispose() {
    stop();
    countdownNotifier.dispose();
  }
}

/// Wrap your main scaffold with this widget to auto-reset the inactivity timer
/// on any mouse, keyboard, or touch interaction.
///
/// Example:
/// ```dart
/// SessionTimeoutListener(
///   child: Scaffold(body: ...),
/// )
/// ```
class SessionTimeoutListener extends StatelessWidget {
  final Widget child;

  const SessionTimeoutListener({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => SessionTimeoutService.instance.resetTimer(),
      onPointerMove: (_) => SessionTimeoutService.instance.resetTimer(),
      onPointerSignal: (_) => SessionTimeoutService.instance.resetTimer(),
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (_) => SessionTimeoutService.instance.resetTimer(),
        child: child,
      ),
    );
  }
}

/// A small warning banner that shows when the session is about to expire.
/// Place this in a Stack or at the top of your main scaffold.
class SessionTimeoutWarningBanner extends StatelessWidget {
  const SessionTimeoutWarningBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: SessionTimeoutService.instance.countdownNotifier,
      builder: (context, countdown, _) {
        if (countdown == null) return const SizedBox.shrink();

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.orange.shade700,
                Colors.red.shade600,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  'سيتم تسجيل الخروج تلقائياً خلال $countdown ثانية بسبب عدم النشاط',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 16),
                TextButton(
                  onPressed: () => SessionTimeoutService.instance.resetTimer(),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  ),
                  child: const Text('إبقاء الجلسة', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Riverpod provider for session timeout minutes from settings.
///
/// Spec 119 (Bug L) — قراءة فعلية من settings table بدلاً من ثابت
/// `kDefaultTimeoutMinutes`. قبلاً، الإعداد العام كان يُحفَظ في DB لكن
/// هذا الـ provider يُرجع 30 دائماً، فالـ InactivityDetector لا يرى
/// تغييرات الـ admin.
final sessionTimeoutProvider = FutureProvider<int>((ref) async {
  final settingsRepo = ref.watch(settingsRepositoryProvider);
  final raw = await settingsRepo.getSetting(kSessionTimeoutKey);
  return int.tryParse(raw ?? '') ?? kDefaultTimeoutMinutes;
});
