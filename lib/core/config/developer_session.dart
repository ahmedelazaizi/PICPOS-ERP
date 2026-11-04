// ═══════════════════════════════════════════════════════════════════════════
// DEVELOPER SESSION — فتحُ أدوات المطوّر: ذاكرةٌ فقط، مرتبطٌ بمستخدمٍ وبمهلة
// ═══════════════════════════════════════════════════════════════════════════
//
// القاعدة: كلمةُ مرور المطوّر تُطلب في **كلّ جلسةٍ جديدة**. لذلك:
//   * الحالةُ تعيش في هذا الـNotifier وحده — لا SharedPreferences ولا settings
//     ولا secure storage ولا static. إعادةُ تشغيل التطبيق = `ProviderContainer`
//     جديد = مقفل.
//   * تُمسح عند تسجيل الخروج وعند تغيّر هوية المستخدم المصادَق بالاستماع إلى
//     [authProvider] (لا يصحّ أن يقرأ `AuthNotifier` هذا الـprovider: دورةُ
//     اعتماد). هذا يغطّي قفلَ الخمول لأنّ `InactivityDetector` ينتهي بـ`logout()`.
//   * المهلةُ منزلقة (10 دقائق) وتُمسح الحالةُ فعلياً عند انتهائها (مؤقّت)
//     فتعود البوّابةُ إلى طلب الكلمة دون انتظار إعادة بناءٍ من خارجها.
//   * المقارنةُ بمعرّف المستخدم لا بحالة المصادقة، فتجديدُ الجلسة لا يقفل.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/auth_providers.dart';

class DeveloperSession {
  final bool unlocked;
  final DateTime? expiresAt;

  /// معرّف المستخدم الذي فتح الجلسة (`null` إن لم يكن أحدٌ مصادَقاً).
  final int? userId;

  const DeveloperSession({
    this.unlocked = false,
    this.expiresAt,
    this.userId,
  });

  bool get isActive {
    if (!unlocked || expiresAt == null) return false;
    return DateTime.now().isBefore(expiresAt!);
  }
}

class DeveloperSessionNotifier extends Notifier<DeveloperSession> {
  /// Sliding window length — every successful auth or developer-tools
  /// mutation extends the session to `now + window`.
  static const Duration window = Duration(minutes: 10);

  Timer? _expiryTimer;

  @override
  DeveloperSession build() {
    ref.onDispose(() => _expiryTimer?.cancel());
    // مسحٌ عند الخروج أو تغيّر المستخدم. المقارنة بالمعرّف لا بالحالة كلّها.
    ref.listen<AuthState>(authProvider, (prev, next) {
      final s = state;
      if (!s.unlocked) return;
      final nextId = next.isAuthenticated ? next.user?.id : null;
      if (nextId == null || nextId != s.userId) clear();
    });
    return const DeveloperSession();
  }

  int? _currentUserId() {
    final a = ref.read(authProvider);
    return a.isAuthenticated ? a.user?.id : null;
  }

  void _arm(DateTime expiresAt) {
    _expiryTimer?.cancel();
    _expiryTimer = Timer(expiresAt.difference(DateTime.now()), () {
      if (!state.isActive) clear();
    });
  }

  void unlock() {
    final exp = DateTime.now().add(window);
    state = DeveloperSession(
      unlocked: true,
      expiresAt: exp,
      userId: _currentUserId(),
    );
    _arm(exp);
  }

  void extend() {
    if (!state.isActive) return;
    final exp = DateTime.now().add(window);
    state = DeveloperSession(
      unlocked: true,
      expiresAt: exp,
      userId: state.userId,
    );
    _arm(exp);
  }

  void clear() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    state = const DeveloperSession();
  }
}

final developerSessionProvider =
    NotifierProvider<DeveloperSessionNotifier, DeveloperSession>(
  DeveloperSessionNotifier.new,
);
