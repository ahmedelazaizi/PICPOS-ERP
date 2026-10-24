// الخطوة ٣ (مقرّ) — قاعدة بيانات PostgreSQL: المضيف/المنفذ/القاعدة/المستخدم/الكلمة،
// «اختبار الاتصال» و«تهيئة القاعدة» (‏مخطّط + زرع + تحقّق عبر
// `ServerProvisioningService`). لا يتقدّم «التالي» قبل نجاح التهيئة فعلاً، وتعديلُ
// أيّ حقلٍ يُبطل نتيجتَها.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../domain/models/first_run/first_run_draft.dart';
import '../../../../domain/models/first_run/first_run_invalidation.dart' as inv;
import '../../../../services/setup/server_provisioning_service.dart';
import '../../../picpos_shell/picpos_surface.dart';
import '../first_run_controller.dart';
import '../first_run_ops.dart';
import '../widgets/first_run_callout.dart';
import '../widgets/first_run_field.dart';

class StepStoragePg extends ConsumerStatefulWidget {
  const StepStoragePg({super.key});

  @override
  ConsumerState<StepStoragePg> createState() => _StepStoragePgState();
}

class _StepStoragePgState extends ConsumerState<StepStoragePg> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(firstRunControllerProvider.select((s) => s.draft));
    final secrets = ref.watch(firstRunControllerProvider.select((s) => s.secrets));
    final ops = ref.watch(firstRunOpsProvider);
    final ctl = ref.read(firstRunControllerProvider.notifier);
    final opsCtl = ref.read(firstRunOpsProvider.notifier);

    void edit(FirstRunDraft Function(FirstRunDraft x) change) =>
        ctl.update((x) => inv.invalidate(change(x), inv.FirstRunField.postgres));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: FirstRunField(
                key: const Key('first_run_pg_host'),
                label: tr('المضيف (Host)'),
                hint: tr('localhost أو 192.168.1.50'),
                value: d.pgHost,
                ltr: true,
                onChanged: (v) => edit((x) => x.copyWith(pgHost: v)),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: FirstRunField(
                key: const Key('first_run_pg_port'),
                label: tr('المنفذ'),
                value: d.pgPort,
                ltr: true,
                keyboardType: TextInputType.number,
                onChanged: (v) => edit((x) => x.copyWith(pgPort: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FirstRunField(
          key: const Key('first_run_pg_database'),
          label: tr('اسم القاعدة'),
          value: d.pgDatabase,
          ltr: true,
          onChanged: (v) => edit((x) => x.copyWith(pgDatabase: v)),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: FirstRunField(
                key: const Key('first_run_pg_user'),
                label: tr('اسم المستخدم'),
                value: d.pgUser,
                ltr: true,
                onChanged: (v) => edit((x) => x.copyWith(pgUser: v)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FirstRunField(
                key: const Key('first_run_pg_password'),
                label: tr('كلمة مرور PostgreSQL'),
                value: secrets.pgPassword,
                obscure: !_visible,
                ltr: true,
                suffix: IconButton(
                  tooltip: _visible ? tr('إخفاء') : tr('إظهار'),
                  icon: Icon(
                    _visible ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _visible = !_visible),
                ),
                onChanged: (v) {
                  ctl.updateSecrets((x) => x.copyWith(pgPassword: v));
                  ctl.update((x) => inv.invalidate(x, inv.FirstRunField.postgres));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const Key('first_run_pg_test'),
              onPressed: ops.anyBusy ? null : opsCtl.testPostgres,
              icon: const Icon(Icons.power_outlined, size: 18),
              label: Text(tr('اختبار الاتصال')),
            ),
            FilledButton.icon(
              key: const Key('first_run_pg_provision'),
              onPressed: ops.anyBusy ? null : opsCtl.provisionPostgres,
              icon: ops.pgBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.storage_outlined, size: 18),
              label: Text(tr('تهيئة قاعدة البيانات')),
            ),
            if (d.checks.provisioned)
              FirstRunStatusBadge(
                key: const Key('first_run_pg_ready'),
                label: tr('القاعدة جاهزة'),
                tone: FirstRunTone.success,
              ),
          ],
        ),
        if (ops.pgMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            ops.pgMessage!,
            key: const Key('first_run_pg_message'),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: ops.pgMessageOk ? context.picposText : context.picposMuted,
            ),
          ),
        ],
        if (ops.provisionRows.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final r in ops.provisionRows) _row(context, r),
        ],
        if (ops.provisionError != null) ...[
          const SizedBox(height: 10),
          FirstRunCallout(
            key: const Key('first_run_pg_error'),
            title: tr('فشلت تهيئة قاعدة البيانات.'),
            body: ops.provisionError,
            tone: FirstRunTone.danger,
            icon: Icons.error_outline,
          ),
        ],
        const SizedBox(height: 14),
        FirstRunCallout(
          title: tr('التهيئة آمنة للإعادة: لا تُحذف بيانات موجودة.'),
          body: tr('تُنشأ الجداول وتُزرع الأدوار والحسابات الأساسية، ولا تُغلق التطبيق أثناءها.'),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, ProvisionRow r) {
    final (icon, color) = switch (r.status) {
      ProvisionStatus.pending => (Icons.radio_button_unchecked, context.picposMuted),
      ProvisionStatus.running => (Icons.autorenew, context.picposBrandInk),
      ProvisionStatus.ok => (Icons.check_circle, firstRunToneColor(FirstRunTone.success)),
      ProvisionStatus.failed => (Icons.cancel, firstRunToneColor(FirstRunTone.danger)),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              r.detail == null ? r.label : '${r.label} — ${r.detail}',
              style: TextStyle(color: context.picposText, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
