// موصّلات Riverpod لمسار الويب (م3-6).
//
// ⚠️ الـoverrides توضع في **الـProviderScope الجذر** (`webProviderOverrides`):
// المزوّدات غير المُتجاوَزة تُحلّ دائماً من الجذر، فـ`ProviderScope` متداخل لن
// يصل إليه مزوّدٌ يقرأ `databaseProvider`.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/sync_interceptor.dart';
import '../data/providers/providers.dart';
import '../services/client_write_interceptor.dart';
import '../services/server_proxy.dart';
import 'web_remote_connection.dart';
import 'web_session.dart';

/// الجلسة الحالية؛ null = غير مسجَّل.
class WebSessionNotifier extends Notifier<WebSession?> {
  @override
  WebSession? build() => null;

  void signIn(WebSession s) {
    // م3-7: عنوان الأساس ورمز الجلسة لطبقة الكتابة عبر HTTP (ServerProxy).
    WebSession.active = s;
    SyncInterceptor.currentUserId = s.userId;
    SyncInterceptor.currentUserRole = s.roleName;
    SyncInterceptor.currentUserIsSystemAdmin =
        s.roleIsSystem && s.roleName == 'مدير النظام';
    ServerProxy.instance.setSessionToken(s.userId, s.token);
    state = s;
  }

  void signOut() {
    final s = state;
    WebSession.active = null;
    if (s != null) ServerProxy.instance.invalidateSessionToken(s.userId);
    SyncInterceptor.currentUserId = null;
    SyncInterceptor.currentUserRole = null;
    SyncInterceptor.currentUserIsSystemAdmin = null;
    state = null;
  }
}

final webSessionProvider =
    NotifierProvider<WebSessionNotifier, WebSession?>(WebSessionNotifier.new);

/// حالة القناة: null = متصلة، وإلا رسالةُ سبب الانقطاع.
class WebConnectionNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void closed(int? code, String? reason) {
    state = code == 4401
        ? 'انتهت الجلسة أو تغيّرت صلاحياتك. سجّل الدخول من جديد.'
        : 'انقطع الاتصال بالسيرفر.';
  }
}

final webConnectionProvider =
    NotifierProvider<WebConnectionNotifier, String?>(WebConnectionNotifier.new);

/// قاعدة الويب للجلسة الحالية (تُغلق عند الخروج).
final webDatabaseProvider = Provider<AppDatabase>((ref) {
  final session = ref.watch(webSessionProvider);
  if (session == null) {
    throw StateError('لا توجد جلسة ويب');
  }
  final notifier = ref.read(webConnectionProvider.notifier);
  var disposed = false; // إغلاقُ القناة بسبب الخروج نفسه ليس «انقطاعاً».
  final db = createWebDatabase(
    session,
    // خارج دورة البناء: نؤجّل التعديل كي لا يُكتب أثناء بناء مزوّد.
    onClosed: (code, reason) => Future.microtask(() {
      if (!disposed) notifier.closed(code, reason);
    }),
  );
  // م3-7: الكتابة عبر HTTP — المعترِض في «وضع العميل» (WriteRouter.isMirrorActive
  // صحيحة على الويب) وقاعدة القراءة البعيدة لاستعلامات البحث عن globalId.
  ClientWriteInterceptor.setup();
  ClientWriteInterceptor.initialize(db);
  ref.onDispose(() {
    disposed = true;
    SyncInterceptor.instance = null;
    unawaited(db.close());
  });
  return db;
});

/// مصادقة الويب: المستخدم من استجابة الدخول (لا قراءة من جدول `users` المحجوب).
class WebAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    final s = ref.watch(webSessionProvider);
    if (s == null) return const AuthState();
    final now = DateTime.now();
    // ⚠️ حقول User/Role هنا يجب أن تطابق أعمدة الجدولين؛ عمودٌ جديد
    // غير قابل للـnull يكسر التحليل فيُنبَّه المطوّر.
    final user = User(
      id: s.userId,
      username: s.username,
      passwordHash: '',
      passwordSalt: '',
      displayName: s.displayName,
      roleId: s.roleId,
      defaultScreen: '',
      isLocked: false,
      isActive: true,
      discountLimitIsPercent: true,
      forcePasswordChange: false,
      createdAt: now,
      rowVersion: 0,
    );
    final role = s.roleId == null
        ? null
        : Role(
            id: s.roleId!,
            name: s.roleName ?? '',
            isSystemRole: s.roleIsSystem,
            createdAt: now,
            rowVersion: 0,
          );
    return AuthState(
      userWithRole: UserWithRole(user: user, role: role),
      isAuthenticated: true,
      loginTime: now,
      lastActivity: now,
    );
  }
}

/// تُمرَّر إلى `ProviderScope(overrides:)` في `main_web_entry`.
final webProviderOverrides = [
  databaseProvider.overrideWith((ref) => ref.watch(webDatabaseProvider)),
  authProvider.overrideWith(WebAuthNotifier.new),
  // أكواد الصلاحيات من الدخول: جداول الصلاحيات نفسها محجوبة عن الويب.
  currentUserPermissionsProvider.overrideWith(
    (ref) async => ref.watch(webSessionProvider)?.permissionCodes ?? const [],
  ),
];
