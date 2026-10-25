// ═══════════════════════════════════════════════════════════════════════════
// Four-eyes manager approval dialog (plan 2026-10-24, P5 / B.9).
//
// Shown where an operation needs a second user's authority. The REQUEST side
// (who asks, for what, how critical) and the APPROVE side (the second user types
// his credential on the same device) live in one PicPosDialog. The decision is
// made by [ManagerApprovalFlow]: on a branch device / console it is the MAIN that
// decides and signs a proof; offline a CRITICAL operation is refused outright.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/i18n/tr.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/auth_providers.dart';
import '../../data/providers/manager_approval_provider.dart';
import '../../services/approval/manager_approval_flow.dart';
import '../../services/login_rate_limiter.dart';
import '../../services/manager_approval_cache.dart';
import '../picpos_shell/picpos_dialog.dart';

/// The user-facing sentence for a refused [ManagerApprovalDecision].
String managerApprovalMessage(ManagerApprovalDecision d) {
  return switch (d.kind) {
    ManagerApprovalKind.approved => '',
    ManagerApprovalKind.selfApproval =>
      tr('لا يمكنك الموافقة على إجراءٍ طلبتَه بنفسك — يلزم مسؤولٌ آخر'),
    ManagerApprovalKind.notAuthorised => d.approverName == null
        ? tr('هذا المستخدم ليس لديه صلاحية لهذا الإجراء')
        : tr('المستخدم "{p0}" ليس لديه صلاحية لهذا الإجراء',
            {'p0': d.approverName}),
    ManagerApprovalKind.invalidCredentials => tr('كلمة المرور غير صحيحة'),
    ManagerApprovalKind.lockedOut =>
      tr('محاولات فاشلة كثيرة — أعد المحاولة لاحقاً'),
    ManagerApprovalKind.branchDenied =>
      tr('هذا المسؤول لا يملك صلاحية على هذا الفرع'),
    ManagerApprovalKind.passwordChangeRequired =>
      tr('على هذا المسؤول تغيير كلمة مروره المؤقتة أولاً'),
    ManagerApprovalKind.sessionRequired =>
      tr('انتهت جلسة الدخول — سجّل الدخول من جديد'),
    ManagerApprovalKind.offlineRefusedCritical => tr(
        'عملية مالية حرجة: تتطلب موافقة عبر النظام الرئيسي ولا تُقبل دون اتصال.'),
    ManagerApprovalKind.offlineRefusedMirror =>
      tr('المرآة للقراءة فقط دون اتصال — لا موافقة بلا النظام الرئيسي.'),
    ManagerApprovalKind.error => tr('تعذّر إتمام الموافقة — حاول مرة أخرى'),
  };
}

class ManagerApprovalDialog extends ConsumerStatefulWidget {
  const ManagerApprovalDialog({
    super.key,
    required this.permission,
    this.actionName,
    this.scope,
  });

  final String permission;
  final String? actionName;

  /// بابُ الطلب — يمنع صرفَ الإذن في بابٍ آخرَ يتقاسم نفسَ الكود.
  final String? scope;

  @override
  ConsumerState<ManagerApprovalDialog> createState() =>
      _ManagerApprovalDialogState();
}

class _ManagerApprovalDialogState extends ConsumerState<ManagerApprovalDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final input = _password.text.trim();
    if (input.isEmpty) {
      setState(() => _error = tr('الرجاء إدخال كلمة المرور'));
      return;
    }
    // SEC-009: bounded attempts per requesting user (the main also throttles).
    final limitKey = 'override:${ref.read(authProvider).user?.id}';
    final locked = LoginRateLimiter.getLockoutRemaining(limitKey);
    if (locked != null) {
      setState(() => _error = tr(
          'محاولات فاشلة كثيرة — أعد المحاولة بعد {p0} دقيقة',
          {'p0': locked.inMinutes + 1}));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await ref.read(managerApprovalFlowProvider).approve(
            input: input,
            permission: widget.permission,
            scope: widget.scope,
          );
      if (d.approved) {
        // Authorises this SINGLE action: the 60 s single-use cache spares a
        // second prompt for the same logical action (button → payment → save).
        ManagerApprovalCache.instance
            .grant(widget.permission, scope: widget.scope);
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      if (d.kind == ManagerApprovalKind.invalidCredentials) {
        LoginRateLimiter.recordFailure(limitKey);
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _error = managerApprovalMessage(d);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr('حدث خطأ: {e}', {'e': e});
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final requester = ref.watch(authProvider).user;
    final critical = ManagerApprovalFlow.isCritical(widget.permission);
    return PicPosDialog(
      icon: PhosphorIconsBold.shieldWarning,
      accent: AppColors.warning,
      width: 460,
      title: tr('تصريح المسؤول مطلوب'),
      subtitle: widget.actionName,
      headerChips: [
        if (critical)
          PicPosDialogChip(
            icon: PhosphorIconsBold.warning,
            label: tr('عملية حرجة'),
            tint: AppColors.error,
          ),
      ],
      body: [
        PicPosDialogBanner(
          icon: PhosphorIconsBold.usersThree,
          color: AppColors.warning,
          text: tr('هذا الإجراء يتطلب موافقة مسؤولٍ آخرَ غيرك — يُدخل المسؤول كلمة مروره هنا.'),
        ),
        const SizedBox(height: 12),
        PicPosDialogSummary(rows: [
          (
            label: tr('طالب الإجراء'),
            value: requester?.displayName ?? '-',
            color: null,
          ),
          (label: tr('الصلاحية'), value: widget.permission, color: null),
        ]),
        const SizedBox(height: 12),
        PicPosDialogField(
          label: tr('كلمة مرور المسؤول'),
          required: true,
          child: TextField(
            key: const ValueKey('managerApprovalPassword'),
            controller: _password,
            obscureText: _obscure,
            autofocus: true,
            enabled: !_busy,
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? PhosphorIconsBold.eye
                    : PhosphorIconsBold.eyeSlash),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          PicPosDialogBanner(
            icon: PhosphorIconsBold.warningCircle,
            color: AppColors.error,
            text: _error!,
          ),
        ],
      ],
      cancelLabel: tr('إلغاء'),
      onCancel: () {
        if (!_busy) Navigator.of(context).pop(false);
      },
      primaryAction: PicPosDialogAction(
        label: tr('تأكيد'),
        icon: PhosphorIconsBold.checkCircle,
        busy: _busy,
        onPressed: _busy ? null : _submit,
      ),
    );
  }
}
