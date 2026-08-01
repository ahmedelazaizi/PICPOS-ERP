import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app_main_screen.dart' show enforceShiftForUser;
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/entities/user_entity.dart';
import '../../pos/logic/open_shift_gate.dart';
import '../../pos/providers/cart_controller.dart';
import '../../shift_close_picpos/widgets/picpos_cashier_closing_dialog.dart';

/// Hand the till to another cashier without leaving the application.
///
/// Before this, the only way to change who was operating the till was a full
/// logout back to the login screen. On a busy counter that is slow enough
/// that cashiers simply don't do it — they keep ringing sales under whoever
/// happened to log in that morning, which makes the shift report, the
/// activity log and the variance JE attribute everything to the wrong person.
///
/// وردية الكاشير الخارج **بتفضل مفتوحة** — النسبة مضمونة بـ`shifts.userId`
/// و`getCurrentOpenShift(userId)`، فمبيعات الكاشير الجاي بتروح لورديته هو.
class PicposSwitchUserDialog extends ConsumerStatefulWidget {
  const PicposSwitchUserDialog._();

  /// Runs the whole flow: shift notice → credentials → session swap.
  ///
  /// Returns true only when the user was actually switched.
  static Future<bool> show(BuildContext context, WidgetRef ref) async {
    // إشعار مش بوابة: التحويل بيكمّل مهما كانت وردية الخارج مفتوحة.
    await notifyOpenShift(
      context: context,
      ref: ref,
      reason: 'قبل تحويل المستخدم',
    );
    if (!context.mounted) return false;

    final switched = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PicposSwitchUserDialog._(),
    );
    return switched ?? false;
  }

  @override
  ConsumerState<PicposSwitchUserDialog> createState() =>
      _PicposSwitchUserDialogState();
}

class _PicposSwitchUserDialogState
    extends ConsumerState<PicposSwitchUserDialog> {
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  UserWithRole? _selected;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final target = _selected;
    if (target == null) {
      setState(() => _error = 'اختر المستخدم أولاً');
      return;
    }
    if (_passwordController.text.isEmpty) {
      setState(() => _error = 'أدخل كلمة المرور');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final authRepo = ref.read(authRepositoryProvider);
      final authenticated = await authRepo.authenticateUser(
        target.user.username,
        _passwordController.text,
      );
      if (!mounted) return;

      if (authenticated == null) {
        setState(() {
          _busy = false;
          _error = 'كلمة المرور غير صحيحة';
          _passwordController.clear();
        });
        _passwordFocus.requestFocus();
        return;
      }

      final outgoing = ref.read(authProvider).user;
      final logger = ref.read(activityLoggerProvider);

      // Logged as a logout + a login rather than a bespoke "switch" event so
      // the activity log stays readable by the existing reports, which only
      // know those two.
      try {
        await logger.logLogout(
          outgoing?.id ?? 0,
          outgoing?.displayName ?? 'Unknown',
        );
      } catch (_) {
        // Never block a till handover on the audit log being unavailable.
      }

      // The cart belongs to the outgoing cashier's session. Carrying it over
      // would ring their half-built sale up under the new cashier's name.
      ref.read(cartControllerProvider.notifier).clearCart();

      // Every user-scoped provider must be dropped, not just the obvious
      // ones — leaving any of these cached hands the incoming cashier the
      // previous user's navigation, permissions or branch scope.
      ref.invalidate(userNavItemsProvider);
      ref.invalidate(userAllowedScreensProvider);
      ref.invalidate(currentUserPermissionsProvider);
      ref.invalidate(userRoleProvider);
      ref.invalidate(activeBranchIdProvider);

      // `switchUser` مش `login`: بتعمل تنظيف جلسة الخارج (توكنات السيرفر، حدّ
      // محاولات الدخول، علامات «اتسأل يفتح وردية») ثم تدخّل الجاي في خطوة
      // واحدة — بلا لحظة «مفيش مستخدم» اللي كانت هتقذف الكاشير لشاشة الدخول.
      ref.read(authProvider.notifier).switchUser(authenticated);

      try {
        await logger.logLogin(
          authenticated.user.id,
          authenticated.user.displayName,
        );
      } catch (_) {}

      if (mounted) Navigator.of(context).pop(true);

      // الكاشير الجاي لازم يتسأل يفتح ورديته. `switchUser` ما بتهدّش الشجرة
      // عن قصد (عشان الديالوج ده ما يموتش مع مفتاح `MaterialApp`)، فـ
      // `initState` — المكان الوحيد اللي كان بينادي الفحص ده — ما بتشتغلش.
      // من غير النداء ده هيبيع بلا وردية مفتوحة وفواتيره ما تتنسبش لأي
      // وردية. قبل إلغاء الإغلاق الإجباري كان ده متغطّى بالصدفة: ديالوج
      // الإغلاق كان بيسجّل الخروج فالشجرة تتهد.
      //
      // بعد الـ`pop` عشان ديالوج التبديل ما يكونش لسه فوق ديالوج فتح
      // الوردية.
      if (context.mounted) {
        await enforceShiftForUser(context, ref, callSite: 'switchUser');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'تعذّر تحويل المستخدم: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentId = ref.watch(authProvider).user?.id;
    final usersAsync = ref.watch(allUsersProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.usersThree, color: AppColors.primary),
            SizedBox(width: 8),
            Text('تحويل المستخدم'),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: usersAsync.when(
            loading: () => const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SizedBox(
              height: 120,
              child: Center(child: Text('تعذّر تحميل المستخدمين: $e')),
            ),
            data: (users) {
              // The current user is excluded — "switching" to yourself is a
              // no-op that would still clear the cart.
              final candidates = users
                  .where((u) => u.user.id != currentId && u.user.isActive)
                  .toList();

              if (candidates.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'لا يوجد مستخدم آخر نشط للتحويل إليه.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<UserWithRole>(
                    initialValue: _selected,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'المستخدم الجديد',
                      prefixIcon: Icon(PhosphorIconsBold.user, size: 18),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: candidates
                        .map(
                          (u) => DropdownMenuItem(
                            value: u,
                            child: Text(
                              '${u.user.displayName}'
                              '${u.role != null ? ' — ${u.role!.name}' : ''}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                              _selected = v;
                              _error = null;
                            }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    obscureText: _obscure,
                    enabled: !_busy,
                    autofocus: true,
                    onSubmitted: (_) => _busy ? null : _submit(),
                    inputFormatters: [
                      // A barcode scanner left focused on this field would
                      // otherwise inject a newline and submit a half-typed
                      // password.
                      FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      prefixIcon: const Icon(PhosphorIconsBold.lock, size: 18),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? PhosphorIconsBold.eye
                              : PhosphorIconsBold.eyeSlash,
                          size: 16,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(PhosphorIconsBold.warningCircle,
                            size: 14, color: AppColors.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                                color: AppColors.error, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(PhosphorIconsBold.signIn, size: 16),
            label: const Text('تحويل'),
          ),
        ],
      ),
    );
  }
}
