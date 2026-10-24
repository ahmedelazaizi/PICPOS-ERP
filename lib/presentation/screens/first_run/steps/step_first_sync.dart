// الخطوة ٤ (فرع) — المزامنة الأولى: إلزاميّة. لا يُكمل الإعدادُ ما لم تنجح فعلاً؛
// وعند انعدام الاتصال تُشرح الحالةُ بعبارةٍ واضحةٍ ولا يتقدّم شيء.
//
// قائمةُ الجاهزية أربعةُ بنودٍ تُرفع كلُّها بنجاح المزامنة الفعليّة (لا بنود
// «تجريبيّة»)، وشارةُ الاتصال من نتيجة آخر محاولة. بعد النجاح يُختار فرعُ الجهاز من
// الفروع المزامَنة (‏تلقائيّاً إن كان فرعاً وحيداً).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/tr.dart';
import '../../../picpos_shell/picpos_surface.dart';
import '../first_run_controller.dart';
import '../first_run_ops.dart';
import '../widgets/first_run_callout.dart';
import '../widgets/first_run_choice_card.dart';

class StepFirstSync extends ConsumerStatefulWidget {
  const StepFirstSync({super.key});

  @override
  ConsumerState<StepFirstSync> createState() => _StepFirstSyncState();
}

class _StepFirstSyncState extends ConsumerState<StepFirstSync> {
  @override
  void initState() {
    super.initState();
    // استئنافٌ بعد إعادة التشغيل: المزامنة تمّت سابقاً، والفروعُ في القاعدة المحلية.
    Future<void>(() {
      if (!mounted) return;
      if (ref.read(firstRunControllerProvider).draft.checks.firstSyncDone) {
        ref.read(firstRunOpsProvider.notifier).loadSyncedBranches();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(firstRunControllerProvider.select((s) => s.draft));
    final ops = ref.watch(firstRunOpsProvider);
    final opsCtl = ref.read(firstRunOpsProvider.notifier);
    final done = d.checks.firstSyncDone;
    final items = [
      tr('الاتصال بالسيرفر الرئيسي'),
      tr('المستخدمون والصلاحيات'),
      tr('الأصناف والأسعار والعملاء'),
      tr('إعدادات الفرع والمستودعات والصناديق'),
    ];
    final connection = ops.syncOffline
        ? (tr('غير متصل'), FirstRunTone.danger)
        : done
            ? (tr('متصل'), FirstRunTone.success)
            : ops.syncBusy
                ? (tr('جارٍ المزامنة…'), FirstRunTone.info)
                : (tr('بانتظار المزامنة'), FirstRunTone.warning);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FirstRunStatusBadge(
          key: const Key('first_run_sync_badge'),
          label: connection.$1,
          tone: connection.$2,
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.picposCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.picposHairline),
          ),
          child: Column(
            children: [
              for (final label in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        done
                            ? Icons.check_circle
                            : ops.syncBusy
                                ? Icons.autorenew
                                : Icons.radio_button_unchecked,
                        size: 18,
                        color: done
                            ? firstRunToneColor(FirstRunTone.success)
                            : context.picposMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(label, style: TextStyle(color: context.picposText)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const Key('first_run_sync_start'),
          onPressed: ops.anyBusy || !d.checks.linked ? null : opsCtl.startFirstSync,
          icon: ops.syncBusy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync, size: 18),
          label: Text(done ? tr('إعادة المزامنة') : tr('بدء المزامنة الأولى')),
        ),
        if (ops.syncMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            ops.syncMessage!,
            key: const Key('first_run_sync_message'),
            style: TextStyle(color: context.picposText, fontWeight: FontWeight.w700),
          ),
        ],
        if (ops.syncOffline) ...[
          const SizedBox(height: 10),
          FirstRunCallout(
            key: const Key('first_run_sync_offline'),
            title: tr('لا يمكن إجراء المزامنة الأولى دون اتصال بالسيرفر الرئيسي.'),
            body: tr('لا يكتمل الإعداد قبل نجاحها. تحقق من الشبكة وعنوان السيرفر ثم أعد المحاولة.'),
            tone: FirstRunTone.danger,
            icon: Icons.wifi_off_outlined,
          ),
        ] else if (!done && !ops.syncBusy) ...[
          const SizedBox(height: 10),
          FirstRunCallout(
            key: const Key('first_run_sync_required'),
            title: tr('المزامنة الأولى إلزامية قبل بدء التشغيل.'),
            body: tr('لا تُعاد المعاملات نفسها مرتين: لكل حركة معرّف فريد.'),
          ),
        ],
        if (done) ...[
          const SizedBox(height: 16),
          Text(
            tr('اختر فرع هذا الجهاز'),
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: context.picposText,
            ),
          ),
          const SizedBox(height: 8),
          if (ops.branches.isEmpty)
            Text(tr('لا توجد فروع مزامنة بعد.'),
                style: TextStyle(color: context.picposMuted)),
          for (final b in ops.branches) ...[
            FirstRunChoiceCard(
              key: Key('first_run_sync_branch_${b.id}'),
              icon: Icons.store_outlined,
              title: b.name,
              subtitle: b.code ?? '',
              selected: d.selectedBranchId == b.id,
              onTap: () => opsCtl.selectBranch(b),
            ),
            const SizedBox(height: 8),
          ],
        ],
        const SizedBox(height: 10),
        FirstRunCallout(
          title: tr('إلغاء مستخدم في الرئيسي لا يصل فورًا إلى فرع منقطع.'),
          body: tr('يصل التعطيل بالمزامنة التالية عند عودة الاتصال.'),
          tone: FirstRunTone.warning,
          icon: Icons.info_outline,
        ),
      ],
    );
  }
}
