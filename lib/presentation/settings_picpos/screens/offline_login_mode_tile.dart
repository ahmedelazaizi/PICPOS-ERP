// Leftover #1a: "Settings > Network > Offline login on this device" - the switch
// from `shadow` (observe + log) to `enforce` (refuse every account the main has
// not delivered), with what shadow WOULD have refused in the last N days.
//
// Shown on branch devices (client / mirror) only - the main never goes through
// this path. Permission-gated by `settings_edit` (decided by the caller and
// passed in, so the widget is testable without providers). The confirmation is a
// PicPosDialog. Switching back to `shadow` is the rollback and needs no dialog.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/offline_login_providers.dart';
import '../../../data/providers/providers.dart';
import '../../../services/auth/offline_login_policy.dart';
import '../../../services/auth/shadow_login_log.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../screens/first_run/widgets/first_run_callout.dart';

String offlineModeLabel(OfflineLoginMode m) => switch (m) {
      OfflineLoginMode.shadow => tr('مراقبة فقط (shadow)'),
      OfflineLoginMode.enforce => tr('إلزام (enforce)'),
    };

String _decisionLabel(OfflineLoginDecision d) => switch (d) {
      OfflineLoginDecision.notProvisioned =>
        tr('حساب لم يسلّمه الرئيسي لهذا الجهاز'),
      OfflineLoginDecision.credentialChanged =>
        tr('حساب تغيّرت بيانات دخوله دون تأكيد من الرئيسي'),
      _ => d.name,
    };

/// The sentence that sums up what shadow mode would have refused.
String shadowSummaryText(ShadowLoginSummary s) => s.isClean
    ? tr('خلال آخر {p0} يومًا لم يكن سيُرفض أي دخول دون اتصال لو كان الإلزام مفعّلًا.',
        {'p0': s.windowDays})
    : tr('خلال آخر {p0} يومًا كان سيُرفض {p1} دخولًا دون اتصال (من {p2} حساب) لو كان الإلزام مفعّلًا.',
        {'p0': s.windowDays, 'p1': s.total, 'p2': s.accounts});

/// Wired to the live providers.
class OfflineLoginModeSection extends ConsumerWidget {
  const OfflineLoginModeSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(offlineLoginModeActionsProvider);
    return OfflineLoginModeTile(
      mode: ref.watch(offlineLoginModeProvider).value ?? OfflineLoginMode.shadow,
      summary: ref.watch(offlineShadowSummaryProvider).value ??
          const ShadowLoginSummary.empty(kShadowSummaryDays),
      allowed:
          ref.watch(hasPermissionProvider(PermissionCodes.settingsEdit)).value ??
              false,
      onChange: actions.setMode,
    );
  }
}

class OfflineLoginModeTile extends StatelessWidget {
  const OfflineLoginModeTile({
    super.key,
    required this.mode,
    required this.summary,
    required this.allowed,
    required this.onChange,
  });

  final OfflineLoginMode mode;
  final ShadowLoginSummary summary;

  /// The signed-in user holds `settings_edit`.
  final bool allowed;
  final Future<void> Function(OfflineLoginMode mode) onChange;

  Future<void> _enable(BuildContext context) async {
    final ok = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.shieldCheck,
      title: tr('تفعيل إلزام الدخول دون اتصال'),
      message: tr(
          'بعد التفعيل لا يدخل دون اتصال إلا من سلّم الرئيسي بيانات دخوله لهذا الجهاز وما زال ضمن مدة السماح. يمكنك الرجوع إلى المراقبة في أي وقت.'),
      confirmLabel: tr('تفعيل الإلزام'),
      danger: !summary.isClean,
      details: [
        const SizedBox(height: 10),
        PicPosDialogBanner(
          icon: summary.isClean
              ? PhosphorIconsBold.checkCircle
              : PhosphorIconsBold.warning,
          text: shadowSummaryText(summary),
          color: summary.isClean ? AppColors.success : AppColors.warning,
        ),
      ],
    );
    if (ok) await onChange(OfflineLoginMode.enforce);
  }

  @override
  Widget build(BuildContext context) {
    final enforce = mode == OfflineLoginMode.enforce;
    return Container(
      key: const Key('offline_login_mode_tile'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.picposCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.picposHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('الدخول دون اتصال على هذا الجهاز'),
            style: TextStyle(
                fontWeight: FontWeight.w800, color: context.picposText),
          ),
          const SizedBox(height: 4),
          Text(
            tr('الوضع الحالي: {p0}', {'p0': offlineModeLabel(mode)}),
            key: const Key('offline_login_mode_current'),
            style: TextStyle(
                fontWeight: FontWeight.w700, color: context.picposText),
          ),
          const SizedBox(height: 6),
          Text(
            tr('في وضع المراقبة يدخل المستخدم دون اتصال ويُسجَّل ما كان سيُرفض. في وضع الإلزام لا يدخل دون اتصال إلا من سلّم الرئيسي بيانات دخوله لهذا الجهاز، خلال مدة السماح (الافتراضي 7 أيام).'),
            style: TextStyle(color: context.picposMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          FirstRunCallout(
            key: const Key('offline_login_shadow_summary'),
            title: shadowSummaryText(summary),
            body: summary.isClean
                ? null
                : summary.byDecision.entries
                    .map((e) => '${_decisionLabel(e.key)}: ${e.value}')
                    .join('\n'),
            tone: summary.isClean ? FirstRunTone.success : FirstRunTone.warning,
            icon: summary.isClean ? Icons.check_circle_outline : Icons.warning_amber,
          ),
          const SizedBox(height: 10),
          if (enforce)
            OutlinedButton.icon(
              key: const Key('offline_login_back_to_shadow'),
              onPressed: allowed ? () => onChange(OfflineLoginMode.shadow) : null,
              icon: const Icon(Icons.undo, size: 18),
              label: Text(tr('الرجوع إلى المراقبة')),
            )
          else
            FilledButton.icon(
              key: const Key('offline_login_enable_enforce'),
              onPressed: allowed ? () => _enable(context) : null,
              icon: const Icon(Icons.verified_user_outlined, size: 18),
              label: Text(tr('تفعيل الإلزام')),
            ),
          if (!allowed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr('تتطلب صلاحية تعديل الإعدادات.'),
                key: const Key('offline_login_denied'),
                style: TextStyle(color: context.picposMuted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
