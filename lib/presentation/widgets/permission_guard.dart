import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/permissions/permission_codes.dart';
import '../../data/providers/providers.dart';
import '../../services/manager_approval_cache.dart';

/// A widget that conditionally shows/hides or enables/disables its child
/// based on user permissions.
///
/// When [allowManagerOverride] is true, the widget is always shown but
/// actions require manager password verification if the user lacks permission.
///
/// Usage:
/// ```dart
/// PermissionGuard(
///   permission: PermissionCodes.posExpense,
///   allowManagerOverride: true, // Show button, ask for manager password
///   actionName: 'إضافة مصروف',
///   child: ElevatedButton(
///     onPressed: () => _showExpenseDialog(),
///     child: Text('مصروف'),
///   ),
/// )
/// ```
class PermissionGuard extends ConsumerWidget {
  /// The permission code required to show this widget
  final String permission;

  /// The child widget to show if permission is granted
  final Widget child;

  /// Widget to show when permission is denied (defaults to empty)
  final Widget? fallback;

  /// If true, shows the child but disabled instead of hiding it
  final bool showDisabled;

  /// Multiple permissions - user must have ALL of them
  final List<String>? allOf;

  /// Multiple permissions - user must have ANY of them
  final List<String>? anyOf;

  /// If true, allows manager override - shows the button but requires
  /// manager password when clicked if user doesn't have permission
  final bool allowManagerOverride;

  /// Human-readable name of the action (shown in override dialog)
  final String? actionName;

  const PermissionGuard({
    super.key,
    required this.permission,
    required this.child,
    this.fallback,
    this.showDisabled = false,
    this.allOf,
    this.anyOf,
    this.allowManagerOverride = false,
    this.actionName,
  });

  /// Constructor for requiring ALL of multiple permissions
  const PermissionGuard.allOf({
    super.key,
    required this.allOf,
    required this.child,
    this.fallback,
    this.showDisabled = false,
    this.allowManagerOverride = false,
    this.actionName,
  }) : permission = '',
       anyOf = null;

  /// Constructor for requiring ANY of multiple permissions
  const PermissionGuard.anyOf({
    super.key,
    required this.anyOf,
    required this.child,
    this.fallback,
    this.showDisabled = false,
    this.allowManagerOverride = false,
    this.actionName,
  }) : permission = '',
       allOf = null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissionsAsync = ref.watch(currentUserPermissionsProvider);

    // Always prefer cached data to prevent child unmount/remount flicker.
    // This is critical for POS where PermissionGuard wraps ProductGrid —
    // returning SizedBox.shrink during loading destroys the entire grid tree.
    final userPermissions = permissionsAsync.asData?.value;
    if (userPermissions == null) {
      // Only on very first load (no cached data yet)
      return permissionsAsync.isLoading
          ? child // Show child optimistically during initial load
          : (fallback ?? const SizedBox.shrink());
    }

    final hasPermission = _checkPermission(userPermissions);

    if (hasPermission) {
      return child;
    }

    // If manager override is allowed, show the widget with override wrapper
    if (allowManagerOverride) {
      return _ManagerOverrideWrapper(
        permission: permission.isNotEmpty
            ? permission
            : (allOf?.first ?? anyOf?.first ?? ''),
        actionName: actionName,
        child: child,
      );
    }

    if (showDisabled) {
      return _buildDisabledChild();
    }

    return fallback ?? const SizedBox.shrink();
  }

  bool _checkPermission(List<String> userPermissions) {
    // SYSTEM ADMIN BYPASS: مدير النظام لديه صلاحية كاملة
    // EXCEPT for critical financial operations — segregation of duties
    final isSystemAdmin = userPermissions.contains('system_admin') ||
        userPermissions.contains('*');
    if (isSystemAdmin && !_hasCriticalFinancialOp()) {
      return true;
    }

    // Check single permission
    if (permission.isNotEmpty) {
      return userPermissions.contains(permission);
    }

    // Check ALL of multiple permissions
    if (allOf != null && allOf!.isNotEmpty) {
      return allOf!.every((p) => userPermissions.contains(p));
    }

    // Check ANY of multiple permissions
    if (anyOf != null && anyOf!.isNotEmpty) {
      return anyOf!.any((p) => userPermissions.contains(p));
    }

    return false;
  }

  /// Returns true if any of the permissions being checked are critical financial ops.
  bool _hasCriticalFinancialOp() {
    if (permission.isNotEmpty &&
        PermissionCodes.criticalFinancialOps.contains(permission)) {
      return true;
    }
    if (allOf != null &&
        allOf!.any((p) => PermissionCodes.criticalFinancialOps.contains(p))) {
      return true;
    }
    if (anyOf != null &&
        anyOf!.any((p) => PermissionCodes.criticalFinancialOps.contains(p))) {
      return true;
    }
    return false;
  }

  Widget _buildDisabledChild() {
    // Try to disable the child if it's a button
    if (child is ElevatedButton) {
      final button = child as ElevatedButton;
      return ElevatedButton(
        onPressed: null,
        style: button.style,
        child: button.child,
      );
    }
    if (child is TextButton) {
      final button = child as TextButton;
      return TextButton(
        onPressed: null,
        style: button.style,
        child: button.child!,
      );
    }
    if (child is OutlinedButton) {
      final button = child as OutlinedButton;
      return OutlinedButton(
        onPressed: null,
        style: button.style,
        child: button.child!,
      );
    }
    if (child is IconButton) {
      final button = child as IconButton;
      return IconButton(
        onPressed: null,
        icon: button.icon,
        tooltip: button.tooltip,
      );
    }

    // For other widgets, wrap in IgnorePointer with reduced opacity
    return IgnorePointer(child: Opacity(opacity: 0.5, child: child));
  }
}

/// Wrapper that intercepts button presses and asks for manager override
class _ManagerOverrideWrapper extends ConsumerStatefulWidget {
  final String permission;
  final String? actionName;
  final Widget child;

  const _ManagerOverrideWrapper({
    required this.permission,
    this.actionName,
    required this.child,
  });

  @override
  ConsumerState<_ManagerOverrideWrapper> createState() =>
      _ManagerOverrideWrapperState();
}

class _ManagerOverrideWrapperState
    extends ConsumerState<_ManagerOverrideWrapper> {
  VoidCallback? _originalOnPressed;

  @override
  Widget build(BuildContext context) {
    // First, find the button and extract onPressed
    _extractOnPressed(widget.child);

    // Then wrap with GestureDetector to intercept taps
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _originalOnPressed != null
          ? () => _requestOverride(context)
          : null,
      child: AbsorbPointer(child: widget.child),
    );
  }

  /// Recursively find and extract onPressed from buttons
  void _extractOnPressed(Widget child) {
    if (child is ElevatedButton) {
      _originalOnPressed = child.onPressed;
      return;
    }
    if (child is OutlinedButton) {
      _originalOnPressed = child.onPressed;
      return;
    }
    if (child is TextButton) {
      _originalOnPressed = child.onPressed;
      return;
    }
    if (child is IconButton) {
      _originalOnPressed = child.onPressed;
      return;
    }
    if (child is InkWell) {
      _originalOnPressed = child.onTap;
      return;
    }
    if (child is GestureDetector) {
      _originalOnPressed = child.onTap;
      return;
    }

    // For wrapper widgets, recursively search
    if (child is Expanded) {
      _extractOnPressed(child.child);
      return;
    }
    if (child is SizedBox && child.child != null) {
      _extractOnPressed(child.child!);
      return;
    }
    if (child is Padding && child.child != null) {
      _extractOnPressed(child.child!);
      return;
    }
    if (child is Container && child.child != null) {
      _extractOnPressed(child.child!);
      return;
    }
    if (child is Center) {
      _extractOnPressed(child.child!);
      return;
    }
    if (child is Align) {
      _extractOnPressed(child.child!);
      return;
    }
    if (child is Material && child.child != null) {
      _extractOnPressed(child.child!);
      return;
    }
    if (child is AnimatedOpacity && child.child != null) {
      _extractOnPressed(child.child!);
      return;
    }
    if (child is Opacity && child.child != null) {
      _extractOnPressed(child.child!);
      return;
    }
    if (child is Flexible) {
      _extractOnPressed(child.child);
      return;
    }
    if (child is DecoratedBox && child.child != null) {
      _extractOnPressed(child.child!);
      return;
    }
    if (child is ColoredBox && child.child != null) {
      _extractOnPressed(child.child!);
      return;
    }
    if (child is ConstrainedBox && child.child != null) {
      _extractOnPressed(child.child!);
      return;
    }
    if (child is UnconstrainedBox && child.child != null) {
      _extractOnPressed(child.child!);
      return;
    }

    // If we can't find a button, set a default callback that does nothing
    // This allows the override dialog to show, but shows an error after
    _originalOnPressed = () {};
  }

  Future<void> _requestOverride(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ManagerOverrideDialog(
        permission: widget.permission,
        actionName: widget.actionName,
      ),
    );

    if (result == true && _originalOnPressed != null) {
      _originalOnPressed!();
    }
  }
}

/// Dialog for manager password entry
class _ManagerOverrideDialog extends ConsumerStatefulWidget {
  final String permission;
  final String? actionName;

  const _ManagerOverrideDialog({required this.permission, this.actionName});

  @override
  ConsumerState<_ManagerOverrideDialog> createState() =>
      _ManagerOverrideDialogState();
}

class _ManagerOverrideDialogState
    extends ConsumerState<_ManagerOverrideDialog> {
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _verifyPassword() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      setState(() => _errorMessage = 'الرجاء إدخال كلمة المرور');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authRepo = ref.read(authRepositoryProvider);

      // Authenticate by password or MSR card code
      final userWithRole = await authRepo.authenticateByPasswordOrCard(password);

      if (userWithRole == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'كلمة المرور غير صحيحة';
        });
        return;
      }

      // Check if authenticated user has the required permission or is system admin
      final userPermissions = await authRepo.getUserPermissionCodes(
        userWithRole.user.id,
      );

      // SYSTEM ADMIN BYPASS: مدير النظام لديه صلاحية كاملة
      // EXCEPT for critical financial operations — segregation of duties
      final isSystemAdmin =
          userPermissions.contains('system_admin') ||
          userPermissions.contains('*');
      final isCriticalOp =
          PermissionCodes.criticalFinancialOps.contains(widget.permission);

      if ((isSystemAdmin && !isCriticalOp) || userPermissions.contains(widget.permission)) {
        // Success! An admin has authorized this SINGLE action.
        //
        // Do NOT call `authProvider.notifier.elevate(...)` here — that used
        // to leak the authorization into session-wide state, so every
        // subsequent `PermissionGuard` in the tree started passing silently
        // until the user logged out. The contract of this dialog is pure:
        // validate the password, return `true`, and let the caller run
        // exactly one action. Next gated tap triggers a fresh prompt.
        //
        // ManagerApprovalCache: stamp this permission with a 60-second,
        // single-use approval token. The downstream defence-in-depth
        // checks (e.g. `_userHasPermissionFresh` inside
        // `_processPaymentAndSave`) consume the token so the cashier
        // doesn't get prompted a SECOND time for the same logical action
        // (button → payment → save). The token is consumed on first
        // read, so it can't authorise any later, distinct action.
        ManagerApprovalCache.instance.grant(widget.permission);
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'المستخدم "${userWithRole.user.displayName}" ليس لديه صلاحية لهذا الإجراء';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'حدث خطأ: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                PhosphorIconsBold.shieldWarning,
                color: AppColors.warning,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'تصريح المسؤول مطلوب',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.actionName != null) ...[
                Text(
                  'الإجراء: ${widget.actionName}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text(
                'هذا الإجراء يتطلب صلاحية خاصة.\nالرجاء إدخال كلمة مرور المسؤول للمتابعة.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'كلمة مرور المسؤول',
                  prefixIcon: const Icon(PhosphorIconsBold.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? PhosphorIconsBold.eye
                          : PhosphorIconsBold.eyeSlash,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  errorText: _errorMessage,
                ),
                onSubmitted: (_) => _verifyPassword(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading
                ? null
                : () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _verifyPassword,
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(PhosphorIconsBold.checkCircle, size: 18),
            label: const Text('تأكيد'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// A helper widget that checks permission and provides a boolean to builder
class PermissionBuilder extends ConsumerWidget {
  final String permission;
  final Widget Function(BuildContext context, bool hasPermission) builder;

  const PermissionBuilder({
    super.key,
    required this.permission,
    required this.builder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissionsAsync = ref.watch(currentUserPermissionsProvider);

    return permissionsAsync.when(
      data: (userPermissions) {
        final hasPermission = userPermissions.contains(permission);
        return builder(context, hasPermission);
      },
      loading: () => builder(context, false),
      error: (_, _) => builder(context, false),
    );
  }
}

/// B5: Public function to request manager approval for high-value operations
/// Returns true if approved, false if cancelled or denied.
Future<bool> requestManagerApproval(
  BuildContext context, {
  required String actionName,
  String permission = 'approve_high_value_return',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ManagerOverrideDialog(
      permission: permission,
      actionName: actionName,
    ),
  );
  return result == true;
}

/// Extension to check permission synchronously when you already have permissions
extension PermissionListExtension on List<String> {
  bool hasPermission(String code) => contains(code);
  bool hasAnyPermission(List<String> codes) => codes.any((c) => contains(c));
  bool hasAllPermissions(List<String> codes) => codes.every((c) => contains(c));
}
