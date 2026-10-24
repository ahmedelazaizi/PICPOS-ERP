// الخطوة ٥ (فرع) — حسابُ الفرع المعتمد: تحقّقٌ حقيقيّ من حسابٍ أنشأه المسؤولُ في
// الرئيسي (‏هاش مزامَن + حارسُ وصول الفرع + **جلسةُ خادم**، SEC-004). لا يُنشأ
// مستخدمٌ محلّيّ ولا مديرٌ في الفرع (E8). كلمةُ المرور لا تبقى بعد المحاولة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../domain/models/first_run/first_run_invalidation.dart' as inv;
import '../../../picpos_shell/picpos_surface.dart';
import '../first_run_controller.dart';
import '../first_run_ops.dart';
import '../widgets/first_run_callout.dart';
import '../widgets/first_run_field.dart';

class StepAccount extends ConsumerStatefulWidget {
  const StepAccount({super.key});

  @override
  ConsumerState<StepAccount> createState() => _StepAccountState();
}

class _StepAccountState extends ConsumerState<StepAccount> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(firstRunControllerProvider.select((s) => s.draft));
    final secrets = ref.watch(firstRunControllerProvider.select((s) => s.secrets));
    final ops = ref.watch(firstRunOpsProvider);
    final ctl = ref.read(firstRunControllerProvider.notifier);
    final opsCtl = ref.read(firstRunOpsProvider.notifier);
    final acc = ops.account;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FirstRunCallout(
          title: tr('مستخدمو الفرع من الإدارة الرئيسية.'),
          body: tr('أدخل حسابًا أنشأه المسؤول لهذا الفرع. لا يُنشأ مستخدم محلي هنا.'),
          icon: Icons.admin_panel_settings_outlined,
        ),
        const SizedBox(height: 14),
        FirstRunField(
          key: const Key('first_run_account_username'),
          label: tr('اسم المستخدم المعتمد'),
          value: d.accountUsername,
          ltr: true,
          onChanged: (v) => ctl.update((x) =>
              inv.invalidate(x.copyWith(accountUsername: v), inv.FirstRunField.branchUser)),
        ),
        const SizedBox(height: 12),
        FirstRunField(
          key: const Key('first_run_account_password'),
          label: tr('كلمة المرور'),
          value: secrets.accountPassword,
          obscure: !_visible,
          ltr: true,
          suffix: IconButton(
            tooltip: _visible ? tr('إخفاء') : tr('إظهار'),
            icon: Icon(_visible ? Icons.visibility_off : Icons.visibility, size: 18),
            onPressed: () => setState(() => _visible = !_visible),
          ),
          onChanged: (v) {
            ctl.updateSecrets((s) => s.copyWith(accountPassword: v));
            ctl.update((x) => inv.invalidate(x, inv.FirstRunField.branchUser));
          },
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            FilledButton.icon(
              key: const Key('first_run_account_verify'),
              onPressed: ops.anyBusy ? null : opsCtl.verifyAccount,
              icon: ops.accountBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_user_outlined, size: 18),
              label: Text(tr('التحقق من الحساب')),
            ),
            const SizedBox(width: 12),
            if (d.checks.accountVerified)
              FirstRunStatusBadge(
                key: const Key('first_run_account_badge'),
                label: tr('تم التحقق'),
                tone: FirstRunTone.success,
              ),
          ],
        ),
        if (acc != null && !acc.ok) ...[
          const SizedBox(height: 10),
          FirstRunCallout(
            key: const Key('first_run_account_error'),
            title: acc.error ?? '',
            tone: FirstRunTone.danger,
            icon: Icons.error_outline,
          ),
        ],
        if (acc != null && acc.ok && d.checks.accountVerified) ...[
          const SizedBox(height: 10),
          Container(
            key: const Key('first_run_account_result'),
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
                  '${acc.roleName} / ${d.selectedBranchName}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: context.picposText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr('عدد الصلاحيات: {p0}', {'p0': acc.permissionCount}),
                  style: TextStyle(color: context.picposMuted),
                ),
                if (acc.topPermissions.isNotEmpty)
                  Text(
                    acc.topPermissions.join('  ·  '),
                    textDirection: TextDirection.ltr,
                    style: TextStyle(color: context.picposMuted, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        FirstRunCallout(
          title: tr('دون اتصال تُستخدم آخر صلاحيات متزامنة ضمن المدة المعتمدة.'),
          body: tr('تحدد الإدارة الرئيسية مدة السماح، وبعدها يلزم الاتصال لتجديد التحقق.'),
          icon: Icons.schedule_outlined,
        ),
      ],
    );
  }
}
