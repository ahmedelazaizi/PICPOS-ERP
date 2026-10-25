// الخطوة ٢ (فرع) / ٢ (مرآة) — الربط بالسيرفر الرئيسي.
//
// الفرع: عنوان + منفذ + اسم الجهاز + **رمز الإقران** الذي يصدره الرئيسي (٨ أحرف،
// يُمسح من الذاكرة بعد نجاح الإقران). المرآة: عنوان + منفذ + مدير الرئيسي وكلمته.
// لا شارة «تم الربط» قبل ردّ حقيقيّ من الخادم؛ وتعديل أيّ مُدخَل يُبطل الربط
// وما بعده (المزامنة والحساب).
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../domain/models/first_run/first_run_draft.dart';
import '../../../../domain/models/first_run/first_run_invalidation.dart' as inv;
import '../../../../domain/models/first_run/first_run_path.dart';
import '../../../picpos_shell/picpos_surface.dart';
import '../first_run_controller.dart';
import '../first_run_ops.dart';
import '../widgets/first_run_callout.dart';
import '../widgets/first_run_field.dart';

String _hostName() {
  try {
    return Platform.localHostname;
  } catch (_) {
    return '';
  }
}

class StepLink extends ConsumerStatefulWidget {
  const StepLink({super.key});

  @override
  ConsumerState<StepLink> createState() => _StepLinkState();
}

class _StepLinkState extends ConsumerState<StepLink> {
  @override
  void initState() {
    super.initState();
    // اسمُ الجهاز الافتراضيّ: اسمُ الحاسوب (‏يُترك لما كتبه المستخدم إن وُجد).
    Future<void>(() {
      if (!mounted) return;
      final d = ref.read(firstRunControllerProvider).draft;
      if (d.path != FirstRunPath.standalone && d.deviceName.trim().isEmpty) {
        final host = _hostName();
        if (host.isNotEmpty) {
          ref.read(firstRunControllerProvider.notifier)
              .update((x) => x.copyWith(deviceName: host));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(firstRunControllerProvider.select((s) => s.draft));
    final secrets = ref.watch(firstRunControllerProvider.select((s) => s.secrets));
    final ops = ref.watch(firstRunOpsProvider);
    final ctl = ref.read(firstRunControllerProvider.notifier);
    final opsCtl = ref.read(firstRunOpsProvider.notifier);
    final mirror = d.path == FirstRunPath.mirror;

    void edit(FirstRunDraft Function(FirstRunDraft x) change, inv.FirstRunField f) =>
        ctl.update((x) => inv.invalidate(change(x), f));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: FirstRunField(
                key: const Key('first_run_link_endpoint'),
                label: tr('عنوان السيرفر الرئيسي'),
                hint: '192.168.1.100',
                value: d.endpoint,
                ltr: true,
                onChanged: (v) =>
                    edit((x) => x.copyWith(endpoint: v), inv.FirstRunField.endpoint),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: FirstRunField(
                key: const Key('first_run_link_port'),
                label: tr('المنفذ'),
                value: d.port,
                ltr: true,
                keyboardType: TextInputType.number,
                onChanged: (v) =>
                    edit((x) => x.copyWith(port: v), inv.FirstRunField.port),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // A1: branch AND mirror devices are paired by the one-time code the
        // main issued (it carries the device kind and, for a branch, the branch).
        FirstRunField(
          key: const Key('first_run_link_device'),
          label: tr('اسم هذا الجهاز'),
          value: d.deviceName,
          onChanged: (v) =>
              edit((x) => x.copyWith(deviceName: v), inv.FirstRunField.deviceName),
        ),
        const SizedBox(height: 12),
        FirstRunField(
          key: const Key('first_run_link_code'),
          label: tr('رمز الإقران (8 أحرف من السيرفر الرئيسي)'),
          hint: 'XXXXXXXX',
          value: secrets.pairingCode,
          ltr: true,
          maxLength: 8,
          onChanged: (v) {
            ctl.updateSecrets((s) => s.copyWith(pairingCode: v.toUpperCase()));
            ctl.update((x) => inv.invalidate(x, inv.FirstRunField.pairingCode));
          },
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            FilledButton.icon(
              key: const Key('first_run_link_connect'),
              onPressed: ops.anyBusy ? null : opsCtl.pairDevice,
              icon: ops.linkBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link, size: 18),
              label: Text(tr('إقران واعتماد الربط')),
            ),
            const SizedBox(width: 12),
            if (d.checks.linked)
              FirstRunStatusBadge(
                key: const Key('first_run_link_badge'),
                label: tr('تم الربط'),
                tone: FirstRunTone.success,
              ),
          ],
        ),
        if (ops.linkMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            ops.linkMessage!,
            key: const Key('first_run_link_message'),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: ops.linkMessageOk ? context.picposText : context.picposMuted,
            ),
          ),
        ],
        const SizedBox(height: 14),
        if (d.endpoint.trim().toLowerCase().startsWith('http://'))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FirstRunCallout(
              key: const Key('first_run_link_tls_warning'),
              title: tr('الاتصال غير مشفّر (HTTP).'),
              body: tr('استعمل شبكة موثوقة أو اتصالًا مشفّرًا (HTTPS) عند الإمكان.'),
              tone: FirstRunTone.warning,
              icon: Icons.warning_amber_rounded,
            ),
          ),
        FirstRunCallout(
          title: mirror
              ? tr('المرآة تعرض بيانات المقر وتعمل بحساب مدير.')
              : tr('التهيئة الأولى تحتاج اتصالًا بالسيرفر الرئيسي.'),
          body: mirror
              ? tr('يصدر رمز المرآة من الإعدادات › الشبكة على السيرفر الرئيسي، ويُفعَّل الوضع عند إنهاء الإعداد.')
              : tr('يصدر رمز الإقران من الإعدادات › الشبكة على السيرفر الرئيسي.'),
        ),
      ],
    );
  }
}
