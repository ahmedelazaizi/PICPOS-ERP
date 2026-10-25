// بوّابةُ الجلسة والدخول على أجهزة الفروع (عميل/مرآة) — خطة 2026-10-24،
// P2 (الرفض الحيّ + التحقّق عبر الرئيسي + تغيير الكلمة المتصل) وP3 (طوابع
// الاعتماد + shadow/enforce).
//
// القرار بعد نجاح التحقّق المحلّي (B.6.2):
//   ok                  ⇒ طابع session + إتمام الدخول
//   invalidCredential   ⇒ رفضٌ ملزِم (حتى لو طابقت البصمةُ المحلية) + رفضٌ يبقى بلا اتصال
//   passwordChangeRequired ⇒ PasswordChangeRequired (يفتح مسارَ التغيير المتصل)
//   branchDenied / mirrorDenied / lockedOut / deviceRevoked ⇒ رفض
//   deviceUnpaired / unreachable ⇒ سياسة الأوفلاين (طوابع + shadow/enforce)
// كلُّ شيءٍ هنا مشروطٌ بـ`SyncInterceptor.isClientMode` (عميل أو مرآة)؛
// المستقلّ والرئيسي لا يمرّان بهذا المسار أبدًا (B.8).
library;

import 'dart:async';

import '../../core/auth/password_policy.dart';
import '../../core/i18n/tr.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../services/auth/credential_stamp_store.dart';
import '../../services/auth/offline_login_policy.dart';
import '../../services/server_proxy.dart';
import '../../services/sync/strategies/user_branch_access_sync_strategy.dart';
import '../../services/sync/strategies/user_sync_strategy.dart';
import '../database/database.dart';
import '../database/daos/user_credential_dao.dart';
import '../database/sync_interceptor.dart';
import '../../domain/repositories/auth_repository.dart';

/// منفذُ الاتصال بالرئيسي — يُحقن في الاختبار بلا شبكة.
abstract interface class SessionAuthorityPort {
  Future<SessionMintResult> acquire(
      {required int userId, String? username, String? password, String? cardCode});
  Future<SessionMintResult> mintDirect(
      {String? username, String? password, String? cardCode});
  Future<PasswordChangeResult> changeOwnPassword({
    String? username,
    String? currentPassword,
    String? cardCode,
    required String newPassword,
  });

  /// يسحب `/api/users` و`/api/user-branch-access` برمزٍ صريح ويطبّقهما.
  Future<bool> pullCredentialFeeds(AppDatabase db, String token);
  bool hasSessionToken(int userId);
}

/// `/api/user-branch-access` is the whole table; this device only has the users
/// and branches its feed delivered, and a row for an unknown one would fail its
/// foreign key and discard the rest. Keep only the rows this device can hold.
Future<Map<String, dynamic>> _onlyKnownRows(
    AppDatabase db, Map<String, dynamic> feed) async {
  final users = {for (final u in await db.select(db.users).get()) u.id};
  final branches = await db.select(db.branches).get();
  final ids = {for (final b in branches) b.id};
  final gids = {for (final b in branches) if (b.globalId != null) b.globalId};
  bool known(Object? r) =>
      r is Map &&
      users.contains((r['userId'] as num?)?.toInt()) &&
      (gids.contains(r['branchGlobalId']) ||
          ids.contains((r['branchId'] as num?)?.toInt()));
  return {
    ...feed,
    'user_branch_access': (feed['user_branch_access'] as List).where(known).toList(),
  };
}

class ServerProxyAuthority implements SessionAuthorityPort {
  ServerProxyAuthority([ServerProxy? proxy]) : _p = proxy ?? ServerProxy.instance;
  final ServerProxy _p;

  @override
  Future<SessionMintResult> acquire(
          {required int userId, String? username, String? password, String? cardCode}) =>
      _p.acquireSession(
          userId: userId, username: username, password: password, cardCode: cardCode);

  @override
  Future<SessionMintResult> mintDirect(
          {String? username, String? password, String? cardCode}) =>
      _p.mintDirect(username: username, password: password, cardCode: cardCode);

  @override
  Future<PasswordChangeResult> changeOwnPassword({
    String? username,
    String? currentPassword,
    String? cardCode,
    required String newPassword,
  }) =>
      _p.changeOwnPassword(
          username: username,
          currentPassword: currentPassword,
          cardCode: cardCode,
          newPassword: newPassword);

  @override
  Future<bool> pullCredentialFeeds(AppDatabase db, String token) async {
    // A feed that cannot be applied (e.g. a role the device has not synced yet)
    // is "not delivered", never an exception out of the login.
    try {
      final users = await _p.fetchFeedWithToken('/api/users', token);
      if (users == null || users['users'] is! List) return false;
      await UserSyncStrategy(db).syncFromJson(users);
      final access = await _p.fetchFeedWithToken('/api/user-branch-access', token);
      if (access != null && access['user_branch_access'] is List) {
        await UserBranchAccessSyncStrategy(db)
            .syncFromJson(await _onlyKnownRows(db, access));
      }
      return true;
    } catch (e) {
      unawaited(DiagnosticLogger.log('AUTH', 'credential feed not applied: $e'));
      return false;
    }
  }

  @override
  bool hasSessionToken(int userId) => _p.hasSessionToken(userId);
}

class AuthSessionGate {
  AuthSessionGate({
    required this.db,
    required this.policy,
    required this.stamps,
    SessionAuthorityPort? authority,
    this.refreshUsers,
    this.onShadowWouldReject,
  }) : authority = authority ?? ServerProxyAuthority();

  final AppDatabase db;
  final OfflineLoginPolicy policy;
  final CredentialStampStore stamps;
  final SessionAuthorityPort authority;

  /// يُجدول سحبَ `users` بعد رفضٍ حيّ (غير حاجب).
  final Future<void> Function()? refreshUsers;

  /// ما كان سيُرفض في وضع enforce (تسجيلٌ فقط في shadow).
  final void Function(OfflineLoginVerdict verdict, int userId)? onShadowWouldReject;

  static const deviceRevokedKey = 'device_revoked_v1';

  /// THE switch: shadow (observe + log what would be rejected) -> enforce.
  /// Device-local (offline_login_mode ∈ kDeviceLocalSettingKeys): flipping it
  /// on one device never reaches another; flip back to shadow to roll back.
  static Future<void> setMode(AppDatabase db, OfflineLoginMode m) =>
      db.setSetting(OfflineLoginMode.settingKey, m.name);

  Future<OfflineLoginMode> mode() async {
    try {
      return OfflineLoginMode.parse(
          await db.getSettingValue(OfflineLoginMode.settingKey));
    } catch (_) {
      return OfflineLoginMode.shadow;
    }
  }

  Future<bool> _isDeviceRevoked() async {
    try {
      return (await db.getSettingValue(deviceRevokedKey)) == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> _setDeviceRevoked(bool v) async {
    try {
      await db.setSetting(deviceRevokedKey, v ? 'true' : '');
    } catch (_) {}
  }

  AuthRejectedException _revokedError() =>
      AuthRejectedException(tr('أُلغي اعتماد هذا الجهاز من النظام الرئيسي.'));

  /// بعد نجاح التحقّق المحلّي. يعيد المستخدمَ (محدَّثًا إن صُحِّح علمُ التغيير).
  Future<UserWithRole> afterLocalSuccess(
    UserWithRole result, {
    String? username,
    String? password,
    String? cardCode,
  }) async {
    if (!SyncInterceptor.isClientMode) return result;
    try {
      await stamps.bootstrapIfNeeded(db);
    } catch (e) {
      unawaited(DiagnosticLogger.log('AUTH', 'stamp bootstrap failed: $e'));
    }
    final user = result.user;
    final res = await authority.acquire(
        userId: user.id, username: username, password: password, cardCode: cardCode);

    switch (res.outcome) {
      case SessionMintOutcome.ok:
        await _onOk(user);
        return user.forcePasswordChange ? await _clearStaleForceFlag(result) : result;
      case SessionMintOutcome.invalidCredential:
        await _denied(user);
        throw AuthRejectedException(
            tr('كلمة المرور تغيّرت على النظام الرئيسي أو الحساب موقوف.'));
      case SessionMintOutcome.branchDenied:
        await _denied(user);
        throw AuthRejectedException('ليس لديك صلاحية الدخول لهذا الفرع');
      case SessionMintOutcome.mirrorDenied:
        await _denied(user);
        throw AuthRejectedException(tr('هذا الجهاز كونسول مدير الفروع؛ حسابك غير مخوَّل له.'));
      case SessionMintOutcome.passwordChangeRequired:
        throw PasswordChangeRequired(
            userId: user.id, username: user.username, viaCard: _isCard(cardCode));
      case SessionMintOutcome.lockedOut:
        throw AuthRejectedException(tr('تم قفل الحساب مؤقتاً على النظام الرئيسي.'));
      case SessionMintOutcome.deviceRevoked:
        await _setDeviceRevoked(true);
        throw _revokedError();
      case SessionMintOutcome.deviceUnpaired:
      case SessionMintOutcome.unreachable:
        await _offline(result);
        return result;
    }
  }

  bool _isCard(String? c) => c != null && c.isNotEmpty;

  Future<void> _onOk(User user) async {
    if (user.passwordHash.isNotEmpty) {
      try {
        await policy.recordVerified(user.id, passwordHash: user.passwordHash);
      } catch (e) {
        unawaited(DiagnosticLogger.log('AUTH', 'stamp write failed: $e'));
      }
    }
    if (await _isDeviceRevoked()) await _setDeviceRevoked(false); // الرئيسي يقبله
  }

  /// الرئيسي قبل الدخول (لا 403 password_change_required) ⇒ علمُ التغيير المحلي
  /// القديم لا معنى له: يُمسح.
  Future<UserWithRole> _clearStaleForceFlag(UserWithRole r) async {
    await db.clearForcePasswordChangeFlag(r.user.id);
    return (await db.getUserById(r.user.id)) ?? r;
  }

  Future<void> _denied(User user) async {
    try {
      await stamps.markRejected(user.id, user.passwordHash);
    } catch (_) {}
    final refresh = refreshUsers;
    if (refresh != null) unawaited(refresh().catchError((Object _) {}));
  }

  /// الرئيسي غير متاح (أو لا يعرف هذا الجهاز): السياسة المحلّية.
  Future<void> _offline(UserWithRole result) async {
    final user = result.user;
    if (await _isDeviceRevoked()) throw _revokedError();
    // كلمةٌ مؤقّتة لا تفتح العمل؛ تُغيَّر والجهاز متصل فقط.
    if (user.forcePasswordChange) {
      throw AuthRejectedException(tr('تغيير كلمة المرور يتطلب اتصالًا بالنظام الرئيسي.'));
    }
    OfflineLoginVerdict verdict;
    try {
      verdict = await policy.check(user.id, passwordHash: user.passwordHash);
    } catch (e) {
      // تعذّر التقييم نفسُه: لا سماحَ صامت (يُرفض في enforce، ويُسجَّل في shadow).
      unawaited(DiagnosticLogger.log('AUTH', 'offline policy unavailable: $e'));
      verdict = const OfflineLoginVerdict(OfflineLoginDecision.notProvisioned,
          graceDays: OfflineLoginPolicy.defaultGraceDays);
    }
    final m = await mode();
    if (verdict.rejectedIn(m)) {
      throw AuthRejectedException(_rejectionMessage(verdict));
    }
    if (!verdict.allowed) {
      unawaited(DiagnosticLogger.log('AUTH',
          'SHADOW: offline login would be rejected: ${verdict.decision.name} user=${user.id}'));
      onShadowWouldReject?.call(verdict, user.id);
    }
  }

  String _rejectionMessage(OfflineLoginVerdict v) {
    switch (v.decision) {
      case OfflineLoginDecision.expired:
        return tr(
          'انتهت مدة الدخول دون اتصال ({p0} يومًا). اتصل بالرئيسي لتجديد التحقق.',
          {'p0': v.graceDays},
        );
      case OfflineLoginDecision.clockRolledBack:
        return tr('تعذّر التحقق من وقت الجهاز. اتصل بالرئيسي لتجديد التحقق.');
      case OfflineLoginDecision.rejectedByMain:
        return tr('كلمة المرور تغيّرت على النظام الرئيسي أو الحساب موقوف.');
      case OfflineLoginDecision.notProvisioned:
        return tr(
            'هذا الحساب غير مُسلَّم لهذا الجهاز من النظام الرئيسي. اتصل بالرئيسي ثم أعد المحاولة.');
      case OfflineLoginDecision.credentialChanged:
        return tr(
            'بيانات دخول هذا الحساب لم تُؤكَّد من النظام الرئيسي على هذا الجهاز. اتصل بالرئيسي ثم أعد المحاولة.');
      case OfflineLoginDecision.allowed:
        return '';
    }
  }

  /// B.6.3: فشل التحقّق المحلّي ⇒ اسأل الرئيسي. عند النجاح تُسحب بياناتُ الدخول
  /// **برمز ذلك المستخدم** (فيُختم) ثم تُعاد المحاولة محليًا. لا سحبَ بلا هوية
  /// أبدًا. [passwordOnly]: المُدخَل كلمةٌ أو بطاقةٌ بلا اسم — كلمةٌ بلا اسمٍ لا
  /// تُعدّ دليلًا على الرئيسي، فإن لم يُقبل كبطاقةٍ وكان الجهازُ لم يستلم أيَّ
  /// اعتمادٍ بعد ⇒ رسالةٌ تطلب الاسم.
  Future<UserWithRole?> verifyViaMain({
    String? username,
    String? password,
    String? cardCode,
    bool passwordOnly = false,
    required Future<UserWithRole?> Function() retryLocal,
  }) async {
    if (!SyncInterceptor.isClientMode) return null;
    final byName = username != null && username.isNotEmpty;
    final byCard = _isCard(cardCode);
    if (!byName && !byCard) return null;
    final res = await authority.mintDirect(
        username: byName ? username : null,
        password: byName ? password : null,
        cardCode: byName ? null : cardCode);
    switch (res.outcome) {
      case SessionMintOutcome.ok:
        if (!await authority.pullCredentialFeeds(db, res.token!)) return null;
        return retryLocal();
      case SessionMintOutcome.passwordChangeRequired:
        throw PasswordChangeRequired(username: username ?? '', viaCard: !byName);
      case SessionMintOutcome.lockedOut:
        throw AuthRejectedException(tr('تم قفل الحساب مؤقتاً على النظام الرئيسي.'));
      case SessionMintOutcome.deviceRevoked:
        await _setDeviceRevoked(true);
        throw _revokedError();
      case SessionMintOutcome.branchDenied:
        throw AuthRejectedException('ليس لديك صلاحية الدخول لهذا الفرع');
      case SessionMintOutcome.mirrorDenied:
        throw AuthRejectedException(tr('هذا الجهاز كونسول مدير الفروع؛ حسابك غير مخوَّل له.'));
      case SessionMintOutcome.invalidCredential:
      case SessionMintOutcome.deviceUnpaired:
      case SessionMintOutcome.unreachable:
        if (passwordOnly && (await stamps.readAll()).isEmpty) {
          throw AuthRejectedException(tr('أدخل اسم المستخدم لأول دخول على هذا الجهاز.'));
        }
        return null;
    }
  }
  /// تغيير كلمة المرور من الجهاز — متصلٌ فقط (B.7.2). عند النجاح: البصمة التي
  /// أعادها الرئيسي تُكتب محليًّا (يُسحب الصفّ أولًا إن لم يكن موجودًا)، ويُختم
  /// الاعتماد، ويبقى رمزُ الجلسة الجديد في الذاكرة.
  Future<void> changeOwnPassword({
    required String username,
    String? currentPassword,
    String? cardCode,
    required String newPassword,
  }) async {
    if (!SyncInterceptor.isClientMode) {
      throw StateError('changeOwnPassword is for client/mirror devices only');
    }
    final r = await authority.changeOwnPassword(
        username: username,
        currentPassword: currentPassword,
        cardCode: cardCode,
        newPassword: newPassword);
    switch (r.outcome) {
      case PasswordChangeOutcome.ok:
        await _applyChange(r, username);
        return;
      case PasswordChangeOutcome.invalidCredential:
        throw AuthRejectedException(tr('اسم المستخدم أو كلمة المرور غير صحيحة'));
      case PasswordChangeOutcome.rejected:
        throw AuthRejectedException(_policyMessage(r.code));
      case PasswordChangeOutcome.branchDenied:
        throw AuthRejectedException('ليس لديك صلاحية الدخول لهذا الفرع');
      case PasswordChangeOutcome.mirrorDenied:
        throw AuthRejectedException(tr('هذا الجهاز كونسول مدير الفروع؛ حسابك غير مخوَّل له.'));
      case PasswordChangeOutcome.lockedOut:
        throw AuthRejectedException(tr('تم قفل الحساب مؤقتاً على النظام الرئيسي.'));
      case PasswordChangeOutcome.hostTooOld:
        throw AuthRejectedException(tr('حدِّث النظام الرئيسي أو غيّر كلمة المرور منه.'));
      case PasswordChangeOutcome.unreachable:
        throw AuthRejectedException(tr('تغيير كلمة المرور يتطلب اتصالًا بالنظام الرئيسي.'));
    }
  }

  String _policyMessage(String? code) {
    switch (code) {
      case 'password_too_short':
        return tr('يجب أن تكون كلمة المرور {p0} خانات على الأقل.', {'p0': kMinPasswordLength});
      case 'password_same_as_current':
        return tr('كلمة المرور الجديدة يجب أن تختلف عن الحالية.');
      case 'password_same_as_username':
        return tr('كلمة المرور الجديدة يجب ألا تطابق اسم المستخدم.');
    }
    // Unknown code: generic message (kept out of a `default:` arm, which the
    // i18n runtime-safety guard treats as a non-UI constant context).
    return tr('كلمة المرور الجديدة غير مقبولة، اختر كلمة أخرى.');
  }

  Future<void> _applyChange(PasswordChangeResult r, String username) async {
    final hash = r.passwordHash;
    if (hash == null || hash.isEmpty || r.userId == null) return;
    var user = await db.getUserByUsername(username);
    if (user == null) {
      // جهازٌ لم يرَ هذا المستخدم بعد: اسحب صفّه ببطاقته الجديدة.
      await authority.pullCredentialFeeds(db, r.token!);
      user = await db.getUserByUsername(username);
    }
    if (user == null) return;
    await db.applyServerCredential(user.user.id, hash);
    await stamps.stampSession(user.user.id, hash, serverTime: r.serverTime);
  }
}
