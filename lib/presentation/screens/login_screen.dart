import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:ural_erp/core/utils/friendly_error.dart';
import 'package:ural_erp/presentation/widgets/dialogs/app_confirm_dialog.dart';
import 'package:ural_erp/domain/models/app_close_cart_gate.dart';
import 'package:ural_erp/presentation/widgets/dialogs/cart_not_empty_close_dialog.dart';
import 'package:ural_erp/presentation/pos/providers/cart_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async' show unawaited;
import 'dart:io';
import '../../core/config/brand.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../core/networking/sync_failure_class.dart';
import '../../core/networking/sync_retry_policy.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../../services/login_rate_limiter.dart';
import '../../services/network_service.dart';
import '../../services/server_proxy.dart';
import '../widgets/dialogs/force_change_password_dialog.dart';
import '../widgets/user_language_selector.dart';
import '../../core/i18n/locale_provider.dart';

/// Login screen for user authentication.
///
/// Single-page brand-cohesive design — gradient background carries the Ural
/// teal identity throughout, one logo at the top, the form rendered as a
/// translucent glass card so the inputs stay legible without breaking the
/// gradient. Ural Technology contact info is pinned at the bottom (matching
/// the "About" dialog in Settings). All authentication logic is preserved
/// exactly (sensitive — do not refactor).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  // MSR Card swipe detection
  final _cardBuffer = StringBuffer();
  DateTime _lastKeyTime = DateTime.now();
  static const _msrMaxKeyInterval = Duration(milliseconds: 50);

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // BUG-U19: confirm before quitting from the login screen (the main app
  // already confirms on exit).
  Future<void> _confirmExitApp() async {
    // #B2: منعُ الخروجَ هنا أيضاً وسلّةُ البيع عامرة.
    //
    // مُثبَتٌ لا مفترَض: `cartControllerProvider` عامٌّ (`NotifierProvider`
    // بلا `autoDispose`) فحالتُه تبقى حيّةً عبر الشاشات كلِّها. الخروجُ
    // اليدويُّ من التطبيق (`app_shell.dart` زرّ «خروج») يمسح السلّةَ صراحةً
    // قبل تسجيل الخروج — لكن `InactivityDetector._onInactive` (تسجيلُ
    // خروجٍ تلقائيٌّ بسبب عدم النشاط) **لا يمسحها**؛ فلو تُرك كاشيرٌ سلّتَه
    // عامرةً حتى انتهت مهلةُ الجلسة، تظهر شاشةُ الدخول هذه والسلّةُ لا تزال
    // ممتلئةً. فهذا الزرُّ ينهي العمليةَ مباشرةً (`exit(0)`) بلا فحصٍ سابق.
    final cartItemCount = ref.read(cartControllerProvider).items.length;
    if (shouldBlockAppCloseForCart(cartItemCount)) {
      await showCartNotEmptyCloseBlockedDialog(context);
      return;
    }

    final ok = await AppConfirmDialog.show(
      context,
      title: tr('إغلاق البرنامج'),
      message: tr('هل تريد إغلاق البرنامج؟'),
      confirmLabel: tr('إغلاق'),
      isDangerous: true,
    );
    if (ok) exit(0);
  }

  Future<void> _login() async {
    // Password is required, username is optional
    if (_passwordController.text.isEmpty) {
      setState(() => _errorMessage = tr('يرجى إدخال كلمة المرور'));
      return;
    }

    // Rate limiting check
    final loginKey = _usernameController.text.isNotEmpty
        ? _usernameController.text
        : _passwordController.text;
    final lockoutRemaining = LoginRateLimiter.getLockoutRemaining(loginKey);
    if (lockoutRemaining != null) {
      final minutes = lockoutRemaining.inMinutes;
      final seconds = lockoutRemaining.inSeconds % 60;
      setState(() => _errorMessage =
          tr('محاولات كثيرة — انتظر {minutes}:{p0} دقيقة', {'minutes': minutes, 'p0': seconds.toString().padLeft(2, '0')}));
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authRepo = ref.read(authRepositoryProvider);
      UserWithRole? user;

      Future<UserWithRole?> tryAuth() async {
        if (_usernameController.text.isNotEmpty) {
          return authRepo.authenticateUser(
            _usernameController.text,
            _passwordController.text,
          );
        }
        return authRepo.authenticateByPasswordOrCard(_passwordController.text);
      }

      user = await tryAuth();

      // ── Client mode: if local auth fails, pull users from server then retry ──
      // This handles the "server-created user can't login on client" case:
      // the user exists on the server but hasn't been synced locally yet.
      //
      // We prefer a focused users-only sync over performFullSync — the latter
      // takes 10+ seconds on a real DB and the user is already waiting on the
      // login button. A targeted users sync via SyncService.syncTable('users')
      // uses the same _fetchJson helper that powers the post-login refresh
      // (15-second connection timeout, dart:io HttpClient with badCertificate
      // tolerance, ngrok-skip-browser-warning header) — i.e. the path that
      // we know works on this client even when the lighter ServerProxy
      // fetchUsers() fails ("token missing or server down").
      if (user == null && NetworkService.instance.isClient) {
        try {
          final serverUrl = NetworkService.instance.buildServerUrl();
          if (serverUrl.isNotEmpty) {
            debugPrint('[Login] Local auth failed in client mode — '
                'pulling users from server before giving up');
            final syncRepo = ref.read(syncRepositoryProvider);
            // Targeted users sync first (fast path).
            try {
              await syncRepo.performTableSync(serverUrl, 'users')
                  .timeout(const Duration(seconds: 6));
              user = await tryAuth();
              if (user != null) {
                debugPrint('[Login] Auth succeeded after users-only sync ✓');
              }
            } catch (e) {
              debugPrint('[Login] users-only sync failed: $e');
            }
            // Full sync as a last-resort if targeted sync didn't help.
            if (user == null) {
              await syncRepo.performFullSync(serverUrl).timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw 'sync timeout',
              );
              user = await tryAuth();
              if (user != null) {
                debugPrint('[Login] Auth succeeded after full sync ✓');
              }
            }
          }
        } catch (e) {
          debugPrint('[Login] Server user sync failed: $e — '
              'staying on local auth result');
        }
      }

      // ── Client mode: refresh user data from server after successful auth ──
      // A user who logged in before may have had server-side changes since
      // (e.g. admin updated defaultScreen, role, permissions). If we navigate
      // with stale local data, they'll land on the wrong screen or lack
      // permissions. A quick sync + re-fetch guarantees the freshest state.
      // Kept short (3 sec max) to avoid noticeable login delay if server is slow.
      if (user != null && NetworkService.instance.isClient) {
        await DiagnosticLogger.startSession(
            'CLIENT LOGIN user=${user.user.username} id=${user.user.id}');
        await DiagnosticLogger.log('LOGIN',
            'pre-refresh: defaultScreen=${user.user.defaultScreen} '
            'roleId=${user.user.roleId} isActive=${user.user.isActive} '
            'isLocked=${user.user.isLocked}');
        try {
          await DiagnosticLogger.log('LOGIN', 'fetching /api/users from server');
          final serverUsers = await ServerProxy.instance.fetchUsers()
              .timeout(const Duration(seconds: 4));
          if (serverUsers == null) {
            await DiagnosticLogger.log('LOGIN',
                '❌ fetchUsers returned null — token missing or server down');
          } else {
            await DiagnosticLogger.log('LOGIN',
                '✓ fetchUsers → ${serverUsers.length} users');
            Map<String, dynamic>? mine;
            for (final u in serverUsers) {
              if ((u['id'] as num?)?.toInt() == user.user.id) {
                mine = u;
                break;
              }
            }
            if (mine == null) {
              await DiagnosticLogger.log('LOGIN',
                  '⚠ user id=${user.user.id} not in server response');
            } else {
              final db = ref.read(databaseProvider);
              final newDefaultScreen = mine['defaultScreen'] as String?;
              final newRoleId = (mine['roleId'] as num?)?.toInt();
              // Day 6A: route through DAO method — no Drift types in presentation.
              await db.applyServerSync(
                userId: user.user.id,
                defaultScreen: newDefaultScreen ?? 'pos',
                roleId: newRoleId,
                displayName: mine['displayName'] as String? ?? user.user.displayName,
              );
              await DiagnosticLogger.log('LOGIN',
                  '✓ patched local row: defaultScreen=$newDefaultScreen '
                  'roleId=$newRoleId');
            }
          }

          // Refresh users + permissions + roles + role_permissions IN ORDER
          // so FK constraints don't reject role_permissions rows referencing
          // permission/role IDs that aren't synced yet.
          //
          // 'users' is included so that admin operators who have just created
          // a new cashier on the server can have that cashier appear on this
          // client without a manual sync — the previous list omitted users,
          // which is why the operator's report "مش راضى يدخل على المستخدمين
          // بعد اكتر من محاوله" surfaced: the cashier row was never pulled,
          // so authenticateUser() couldn't find them locally and the server
          // fallback (fetchUsers) was the only path — and that path was
          // failing with "token missing or server down".
          final serverUrl = NetworkService.instance.buildServerUrl();
          if (serverUrl.isNotEmpty) {
            final syncRepo = ref.read(syncRepositoryProvider);
            // Feature 051 (v132): user_branch_access and user_warehouse_access
            // are pulled here so route guards and screen-level branch scoping
            // see fresh data right after login. The first-login *gate* in
            // `_verifyBranchAccess` does its own lazy fetch when local is
            // empty (so that gate doesn't depend on this loop running first),
            // but adding the tables here keeps them current on every login.
            // ─── Spec 125 US3 — smart retry wrapper ────────────────────
            // Bounded exponential backoff (3 attempts, 0/250/500ms) ≤750ms
            // total per table before giving up. Aggregates persistent
            // failures into ONE toast at loop end (FR-017 / FR-018).
            // ⚠️ Real-time sync sacred (FR-015): no batching, no cooldown
            // BETWEEN tables — each call still fires immediately.
            SyncPersistentFailure? firstPersistentFailure;
            for (final t in [
              'users',
              'permissions',
              'roles',
              'role_permissions',
              'user_branch_access',
              'user_warehouse_access',
            ]) {
              try {
                await SyncRetryPolicy.withSyncRetry(
                  () async {
                    final result = await syncRepo
                        .performTableSync(serverUrl, t)
                        .timeout(const Duration(seconds: 5));
                    // performTableSync CATCHES the underlying error and reports
                    // it in `result.success` instead of throwing. withSyncRetry
                    // only classifies an outcome as a failure when the request
                    // throws, and nothing here read `success` — so a pull that
                    // never happened was retried zero times, raised no toast,
                    // and printed "✓ synced table: $t (immediate)" in the login
                    // log. A silently missed `user_branch_access` pull leaves
                    // the user with no branch rows at all, which BranchScope
                    // then fails CLOSED on: every branch-tagged invoice, report
                    // and party disappears from the UI with no error anywhere.
                    if (!result.success) {
                      throw StateError(result.message);
                    }
                    return result;
                  },
                  tag: '${t.toUpperCase()}-SYNC',
                  onClassification: (cls) {
                    // immediate/slow/transient → already logged by policy
                    // (SYNC-SLOW / SYNC-RETRY). persistent reported below.
                    if (cls == SyncFailureClass.immediate ||
                        cls == SyncFailureClass.transient) {
                      unawaited(DiagnosticLogger.log(
                        'LOGIN',
                        '✓ synced table: $t (${cls.name})',
                      ));
                    } else if (cls == SyncFailureClass.slow) {
                      unawaited(DiagnosticLogger.log(
                        'LOGIN',
                        '✓ synced table: $t (slow — see SYNC-SLOW)',
                      ));
                    }
                  },
                );
              } on SyncPersistentFailure catch (e) {
                firstPersistentFailure ??= e;
                await DiagnosticLogger.log(
                  'LOGIN',
                  '✗ $t persistent failure after '
                  '${SyncRetryPolicy.maxAttempts} attempts',
                );
              }
            }

            // Aggregate toast — show ONCE at the end if any persistent
            // failure happened, never per-table. (FR-018)
            if (firstPersistentFailure != null && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(firstPersistentFailure.toUserMessageAr()),
                  backgroundColor: AppColors.error,
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          }

          final refreshed = await authRepo.getUserById(user.user.id);
          if (refreshed != null) {
            user = refreshed;
            await DiagnosticLogger.log('LOGIN',
                'post-refresh from DB: defaultScreen='
                '${refreshed.user.defaultScreen} roleId=${refreshed.user.roleId}');
          } else {
            await DiagnosticLogger.log('LOGIN',
                '⚠ getUserById returned null after patch');
          }

          // Diagnostic: count how many permissions this role actually has locally
          try {
            final db = ref.read(databaseProvider);
            final rid = user.user.roleId ?? 0;
            if (rid > 0) {
              final perms = await db.getPermissionsForRole(rid);
              await DiagnosticLogger.log('LOGIN',
                  'LOCAL role_permissions count for roleId=$rid: '
                  '${perms.length} — codes=${perms.map((p) => p.code).join(",")}');
            }
          } catch (e) {
            await DiagnosticLogger.log('LOGIN',
                '⚠ role perm diagnostic failed: $e');
          }
        } catch (e) {
          await DiagnosticLogger.log('LOGIN', '❌ post-auth refresh error: $e');
        }
      }

      if (user != null) {
        LoginRateLimiter.recordSuccess(loginKey);

        // Check if password change is forced
        if (user.user.forcePasswordChange) {
          if (!mounted) return;
          final changed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => ForceChangePasswordDialog(
              userId: user!.user.id,
              username: user.user.username,
            ),
          );

          if (changed != true) {
            if (mounted) {
              setState(() => _errorMessage = tr('يجب تغيير كلمة المرور للمتابعة'));
            }
            return;
          }

          // Re-fetch user to get updated state
          user = await authRepo.getUserById(user.user.id);
          if (user == null) return;
        }

        ref.read(authProvider.notifier).login(user);

        // #Forensic Log: Login with device info
        try {
          final deviceInfo =
              '${Platform.operatingSystem} ${Platform.operatingSystemVersion} | ${Platform.localHostname}';
          final logger = ref.read(activityLoggerProvider);
          await logger.logLogin(
            user.user.id,
            user.user.displayName,
            deviceInfo: deviceInfo,
          );
        } catch (e) {
          debugPrint('[ActivityLog] Error: $e');
        } // Don't fail login if logging fails

        // Navigation will be handled by main.dart watching auth state
      } else {
        final remaining = LoginRateLimiter.recordFailure(loginKey);
        setState(() {
          if (remaining <= 0) {
            _errorMessage = tr('تم قفل الحساب لمدة 15 دقيقة بسبب محاولات كثيرة');
          } else {
            _errorMessage = _usernameController.text.isEmpty
                ? tr('كلمة المرور غير صحيحة ({remaining} محاولات متبقية)', {'remaining': remaining})
                : tr('اسم المستخدم أو كلمة المرور غير صحيحة ({remaining} محاولات متبقية)', {'remaining': remaining});
          }
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = friendlyError(e, context: 'LOGIN');
      });
    } finally {
      // On successful login, main.dart navigates away while this finally
      // block is still queued from the await above — the State is disposed
      // before the setState runs. Guard with `mounted` to avoid the
      // setState-after-dispose assertion (no functional impact: when we're
      // gone we don't need the loading flag anyway).
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Handle MSR card swipe — rapid keystrokes ending with Enter
  Future<void> _onCardSwipe(String cardCode) async {
    if (cardCode.isEmpty || _isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final authRepo = ref.read(authRepositoryProvider);
      var user = await authRepo.authenticateByCardCode(cardCode);
      if (user != null) {
        // Check if password change is forced
        if (user.user.forcePasswordChange) {
          if (!mounted) return;
          final changed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => ForceChangePasswordDialog(
              userId: user!.user.id,
              username: user.user.username,
            ),
          );

          if (changed != true) {
            if (mounted) {
              setState(() => _errorMessage = tr('يجب تغيير كلمة المرور للمتابعة'));
            }
            return;
          }

          // Re-fetch user
          user = await authRepo.getUserById(user.user.id);
          if (user == null) return;
        }

        ref.read(authProvider.notifier).login(user);
        try {
          final deviceInfo =
              '${Platform.operatingSystem} ${Platform.operatingSystemVersion} | ${Platform.localHostname}';
          final logger = ref.read(activityLoggerProvider);
          await logger.logLogin(
            user.user.id,
            user.user.displayName,
            deviceInfo: deviceInfo,
          );
        } catch (e) {
          debugPrint('[ActivityLog] Error: $e');
        }
      } else {
        setState(() => _errorMessage = tr('بطاقة غير معرّفة في النظام'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = friendlyError(e, context: 'LOGIN-CARD'));
      }
    } finally {
      // Same dispose-race as _login above — guard with mounted.
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Open on-screen keyboard for touch screens (#11)
  void _openOnScreenKeyboard() {
    if (Platform.isWindows) {
      try {
        Process.run('cmd', ['/c', 'start', 'osk.exe']);
      } catch (e) {
        try {
          Process.run('cmd', [
            '/c',
            'start',
            '',
            'C:\\Program Files\\Common Files\\microsoft shared\\ink\\TabTip.exe',
          ]);
        } catch (_) {}
      }
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(userLocaleProvider);
    final direction = locale.languageCode == 'en'
        ? TextDirection.ltr
        : TextDirection.rtl;
    return Directionality(
      textDirection: direction,
      child: KeyboardListener(
        focusNode: FocusNode(),
        autofocus: true,
        onKeyEvent: (event) {
          if (event is! KeyDownEvent) return;
          final now = DateTime.now();
          final char = event.character;
          if (event.logicalKey == LogicalKeyboardKey.enter) {
            final code = _cardBuffer.toString().trim();
            _cardBuffer.clear();
            if (code.length >= 4) {
              _onCardSwipe(code);
            }
            return;
          }
          if (char != null && char.isNotEmpty) {
            if (now.difference(_lastKeyTime) > _msrMaxKeyInterval) {
              _cardBuffer.clear();
            }
            _cardBuffer.write(char);
            _lastKeyTime = now;
          }
        },
        child: Scaffold(
          body: Container(
            // Single full-screen gradient — same teal palette as the rest
            // of the app, so the brand identity carries through and the
            // login screen no longer feels visually split from the main UI.
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryDark,
                  AppColors.primary,
                  AppColors.primaryLight,
                ],
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
              ),
            ),
            child: Stack(
              children: [
                // Subtle decorative shapes for depth — same low-opacity
                // treatment used by the marketing slides in the brand
                // book. Keeps the screen from looking like a flat rectangle.
                PositionedDirectional(top: -90, end: -80, child: _decorBlob(260, 0.08)),
                PositionedDirectional(bottom: -70, start: -60, child: _decorBlob(200, 0.06)),
                PositionedDirectional(
                  top: 80,
                  start: 60,
                  child: _decorBlob(36, 0.05, square: true),
                ),
                SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: constraints.maxHeight),
                          child: IntrinsicHeight(
                            child: Column(
                              children: [
                                Expanded(
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24, vertical: 24),
                                      child: _buildLoginCard(),
                                    ),
                                  ),
                                ),
                                _buildContactFooter(),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const PositionedDirectional(
                  top: 16,
                  end: 16,
                  child: SizedBox(
                    width: 150,
                    child: UserLanguageToggle(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _decorBlob(double size, double opacity, {bool square = false}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: square ? BorderRadius.circular(size * 0.22) : null,
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
  }

  /// Glass card holding the brand mark, title, and the login form. Sits
  /// directly on the gradient — no white split-panel — and uses a single
  /// logo so the screen reads as one composition instead of two.
  Widget _buildLoginCard() {
    return Container(
      width: 460,
      padding: const EdgeInsetsDirectional.fromSTEB(32, 28, 32, 28),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Single brand logo (the previous design duplicated this on both
          // panels — confusing on first read).
          Container(
            width: 96,
            height: 96,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(Brand.logoAsset, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            Brand.name,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr('نظام إدارة الموارد المتكامل'),
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.18),
          ),
          const SizedBox(height: 22),
           Text(
            tr('تسجيل الدخول'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr('أدخل كلمة المرور للمتابعة'),
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 22),

          if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 14),
              // BUG-U39: stronger contrast so login errors are not missed.
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.error,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    PhosphorIconsBold.warning,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Password field — controller and submit handler unchanged. Styled
          // to read on the gradient (light glass fill, white text/icons,
          // subtle border).
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            cursorColor: Colors.white,
            decoration: InputDecoration(
              labelText: tr('كلمة المرور'),
              labelStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
              ),
              floatingLabelStyle: const TextStyle(color: Colors.white),
              prefixIcon: Icon(
                PhosphorIconsBold.lock,
                color: Colors.white.withValues(alpha: 0.85),
                size: 18,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? PhosphorIconsBold.eye
                      : PhosphorIconsBold.eyeSlash,
                  color: Colors.white.withValues(alpha: 0.85),
                  size: 18,
                ),
                onPressed: () => setState(
                  () => _obscurePassword = !_obscurePassword,
                ),
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.30),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white, width: 1.5),
              ),
            ),
            onSubmitted: (_) => _login(),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primaryDark,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: AppColors.primaryDark,
                        strokeWidth: 2,
                      ),
                    )
                  :  Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(PhosphorIconsBold.signIn, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          tr('تسجيل الدخول'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: _openOnScreenKeyboard,
                    icon: const Icon(PhosphorIconsBold.keyboard, size: 16),
                    label:  Text(
                      tr('لوحة المفاتيح'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: _confirmExitApp,
                    icon: const Icon(PhosphorIconsBold.power,
                      size: 16,
                      color: AppColors.error,
                    ),
                    label:  Text(
                      tr('إغلاق البرنامج'),
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 12,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(
                        color: AppColors.error.withValues(alpha: 0.55),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Vendor contact strip pinned at the bottom — phone, website, email pills
  /// + social icons + © line. Mirrors the "About" panel in the Settings
  /// dialog so the dev contact info has a consistent home.
  ///
  /// Values come from [Brand]; a brand that declares none renders nothing at
  /// all. Printing another product's support number on this screen is worse
  /// than printing no number — see `Brand.vendorName`.
  Widget _buildContactFooter() {
    if (!Brand.hasVendorInfo) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 18),
      child: Column(
        children: [
          Container(
            height: 1,
            margin: const EdgeInsets.only(bottom: 14),
            color: Colors.white.withValues(alpha: 0.18),
          ),
          Text(
            tr('تطوير: Ural Technology'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _contactPill(
                icon: PhosphorIconsBold.phone,
                label: '+962797990989',
                onTap: () => _launch('tel:+962797990989'),
              ),
              _contactPill(
                icon: PhosphorIconsBold.globe,
                label: 'www.uraljo.com',
                onTap: () => _launch('https://www.uraljo.com'),
              ),
              _contactPill(
                icon: PhosphorIconsBold.envelope,
                label: 'info@uraljo.com',
                onTap: () => _launch('mailto:info@uraljo.com'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _socialDot(
                icon: PhosphorIconsBold.whatsappLogo,
                color: const Color(0xFF25D366),
                onTap: () => _launch('https://wa.me/962797990989'),
              ),
              const SizedBox(width: 10),
              _socialDot(
                icon: PhosphorIconsBold.instagramLogo,
                color: const Color(0xFFE4405F),
                onTap: () => _launch('https://instagram.com/uraltechnology'),
              ),
              const SizedBox(width: 10),
              _socialDot(
                icon: PhosphorIconsBold.facebookLogo,
                color: const Color(0xFF1877F2),
                onTap: () => _launch('https://facebook.com/uraltechnology'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '© Ural Technology ${DateTime.now().year}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 11,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _socialDot({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[Login] Could not launch $url: $e');
    }
  }
}
