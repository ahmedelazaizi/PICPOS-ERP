// الخطوة ٤ (مستقل) — المسؤول الأول: اسمُ الدخول `admin` **للقراءة فقط** (B20/E12،
// SEC-001) وكلمةُ مرورٍ لا تقلّ عن 8 أحرف (E11). كلمةُ مرور المطوّر إلزاميّةٌ
// لكن في قسمٍ قابلٍ للطيّ. كلُّ الكلمات في الذاكرة فقط ولا تُحفَظ في المسودّة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../domain/models/first_run/first_run_validation.dart';
import '../../../picpos_shell/picpos_surface.dart';
import '../first_run_controller.dart';
import '../widgets/first_run_callout.dart';
import '../widgets/first_run_field.dart';

class StepUsersLocal extends ConsumerStatefulWidget {
  const StepUsersLocal({super.key});

  @override
  ConsumerState<StepUsersLocal> createState() => _StepUsersLocalState();
}

class _StepUsersLocalState extends ConsumerState<StepUsersLocal> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(firstRunControllerProvider.select((x) => x.secrets));
    final ctl = ref.read(firstRunControllerProvider.notifier);
    final eye = IconButton(
      key: const Key('first_run_password_toggle'),
      tooltip: _visible ? tr('إخفاء') : tr('إظهار'),
      icon: Icon(_visible ? Icons.visibility_off : Icons.visibility, size: 18),
      onPressed: () => setState(() => _visible = !_visible),
    );
    final short = s.adminPassword.isNotEmpty &&
        s.adminPassword.length < kFirstRunPasswordMin;
    final mismatch = s.adminPasswordConfirm.isNotEmpty &&
        s.adminPassword != s.adminPasswordConfirm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FirstRunField(
          key: const Key('first_run_admin_username'),
          label: tr('اسم دخول المسؤول'),
          value: kFirstRunAdminUsername,
          readOnly: true,
          ltr: true,
        ),
        const SizedBox(height: 4),
        Text(
          tr('اسم الدخول ثابت: admin. يمكنك إضافة مستخدمين آخرين من الإعدادات بعد البدء.'),
          style: TextStyle(fontSize: 12, color: context.picposMuted),
        ),
        const SizedBox(height: 14),
        FirstRunField(
          key: const Key('first_run_admin_password'),
          label: tr('كلمة مرور المسؤول'),
          value: s.adminPassword,
          obscure: !_visible,
          ltr: true,
          suffix: eye,
          onChanged: (v) => ctl.updateSecrets((x) => x.copyWith(adminPassword: v)),
        ),
        const SizedBox(height: 12),
        FirstRunField(
          key: const Key('first_run_admin_password_confirm'),
          label: tr('تأكيد كلمة المرور'),
          value: s.adminPasswordConfirm,
          obscure: !_visible,
          ltr: true,
          onChanged: (v) =>
              ctl.updateSecrets((x) => x.copyWith(adminPasswordConfirm: v)),
        ),
        const SizedBox(height: 6),
        Text(
          short
              ? tr('كلمة مرور المسؤول يجب أن تكون 8 أحرف على الأقل.')
              : mismatch
                  ? tr('كلمتا المرور غير متطابقتين.')
                  : tr('8 أحرف على الأقل. لا تُحفظ في ملف المسودة.'),
          key: const Key('first_run_password_hint'),
          style: TextStyle(
            fontSize: 12,
            color: short || mismatch ? context.picposText : context.picposMuted,
            fontWeight: short || mismatch ? FontWeight.w800 : FontWeight.w400,
          ),
        ),
        const SizedBox(height: 14),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const Key('first_run_developer_section'),
            initiallyExpanded: true,
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text(tr('كلمة مرور المطوّر (إلزامية)')),
            subtitle: Text(tr('تحمي أدوات المطوّر وتغيير الباقة. احفظها في مكان آمن.')),
            children: [
              FirstRunField(
                key: const Key('first_run_dev_password'),
                label: tr('كلمة مرور المطوّر'),
                value: s.developerPassword,
                obscure: !_visible,
                ltr: true,
                onChanged: (v) =>
                    ctl.updateSecrets((x) => x.copyWith(developerPassword: v)),
              ),
              const SizedBox(height: 12),
              FirstRunField(
                key: const Key('first_run_dev_password_confirm'),
                label: tr('تأكيد كلمة مرور المطوّر'),
                value: s.developerPasswordConfirm,
                obscure: !_visible,
                ltr: true,
                onChanged: (v) => ctl.updateSecrets(
                    (x) => x.copyWith(developerPasswordConfirm: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        FirstRunCallout(
          title: tr('تُخزَّن كلمات المرور مُجزَّأة (hash) ولا تُحفظ نصًّا.'),
          body: tr('إن أُغلق التطبيق قبل الإنهاء ستُطلب منك مجدداً.'),
          icon: Icons.lock_outline,
        ),
      ],
    );
  }
}
