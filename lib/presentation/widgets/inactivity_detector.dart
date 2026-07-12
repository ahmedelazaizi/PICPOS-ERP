import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/auth_providers.dart';
import '../../services/session_timeout_service.dart' show sessionTimeoutProvider;

/// Wraps the entire app to detect user inactivity.
///
/// Spec 119 (Bug L) — يقرأ المدة من sessionTimeoutProvider (إعداد
/// `session_timeout_minutes` من DB) بدل ثابت 15 دقيقة. لو الإعداد = 0،
/// timeout مُعطَّل (لا auto-logout). قبلاً كان hardcoded 15 يتجاهل
/// إعدادات النظام.
class InactivityDetector extends ConsumerStatefulWidget {
  final Widget child;

  const InactivityDetector({super.key, required this.child});

  @override
  ConsumerState<InactivityDetector> createState() => _InactivityDetectorState();
}

class _InactivityDetectorState extends ConsumerState<InactivityDetector> {
  Timer? _inactivityTimer;

  @override
  void initState() {
    super.initState();
    // Defer to avoid modifying provider during build phase
    Future.microtask(() => _resetTimer());
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    super.dispose();
  }

  void _resetTimer() {
    _inactivityTimer?.cancel();

    // Spec 119 (Bug L) — قراءة من sessionTimeoutProvider.
    // قبلاً hardcoded `AuthState.inactivityTimeout` = 15 minutes كان
    // يتجاهل إعدادات النظام. الآن نقرأ الإعداد من DB. لو الإعداد = 0
    // (معطَّل من admin)، نُلغي auto-logout.
    final timeoutMinutes = ref.read(sessionTimeoutProvider).value
        ?? AuthState.inactivityTimeout.inMinutes;
    if (timeoutMinutes > 0) {
      _inactivityTimer = Timer(
        Duration(minutes: timeoutMinutes),
        _onInactive,
      );
    }

    // Update last activity in auth state
    final auth = ref.read(authProvider);
    if (auth.isAuthenticated) {
      ref.read(authProvider.notifier).updateActivity();
    }
  }

  void _onInactive() {
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) return;

    ref.read(authProvider.notifier).logout();

    if (mounted) {
      // Navigate to login
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetTimer(),
      onPointerMove: (_) => _resetTimer(),
      child: widget.child,
    );
  }
}
