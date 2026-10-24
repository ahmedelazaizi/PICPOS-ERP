// الخطوة ٦ — المراجعة: قائمةُ عنوان/قيمة بروابط «تعديل»، وسطرُ تأكيد العملة،
// وتقدّمُ مراحل التشغيل، وفشلُ مرحلةٍ يبقى هنا بسببه مع إعادة المحاولة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart' show CurrencyInfo;
import '../../../../core/i18n/tr.dart';
import '../../../../domain/models/first_run/first_run_currency.dart';
import '../../../../domain/models/first_run/first_run_packs.dart';
import '../../../../domain/models/first_run/first_run_path.dart';
import '../../../../domain/models/first_run/first_run_steps.dart';
import '../../../../domain/models/first_run/first_run_validation.dart';
import '../../setup_wizard/setup_finish_runner.dart';
import '../first_run_controller.dart';
import '../first_run_texts.dart';
import '../widgets/first_run_callout.dart';
import '../widgets/first_run_summary.dart';
import 'step_review_server.dart';

String _packName(FirstRunPack p) => switch (p) {
      FirstRunPack.pos => tr('نقطة بيع فقط'),
      FirstRunPack.restaurant => tr('مطاعم فقط'),
      FirstRunPack.business => tr('نقطة بيع + محاسبة + مستودعات'),
      FirstRunPack.full => tr('النظام الكامل'),
    };

String _eInvoiceName(FirstRunEInvoice? e) => switch (e) {
      FirstRunEInvoice.jordan => tr('الأردن — JoFotara'),
      FirstRunEInvoice.egypt => tr('مصر — ETA'),
      _ => tr('بدون'),
    };

class StepReview extends ConsumerWidget {
  const StepReview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(firstRunControllerProvider);
    final d = s.draft;
    final ctl = ref.read(firstRunControllerProvider.notifier);
    final steps = stepsFor(d.path);
    void edit(FirstRunStep step) => ctl.jumpToStep(steps.indexOf(step));
    final currency = d.currency.isEmpty ? '—' : CurrencyInfo.fromCode(d.currency).nameAr;
    final company = reviewIsCompanyPath(d.path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (d.path == FirstRunPath.branch) ...reviewBranchSections(d, edit),
        if (d.path == FirstRunPath.mirror) ...reviewMirrorSections(d, edit),
        if (company) ...[
        FirstRunSummarySection(
          title: tr('الشركة والنشاط'),
          editKey: const Key('first_run_edit_company'),
          onEdit: () => edit(FirstRunStep.company),
          rows: [
            (tr('نوع النسخة'), firstRunPathTitle(d.path)),
            (tr('الشركة'), d.companyName.trim()),
            (tr('الباقة'), _packName(d.pack)),
            (tr('الفرع / المخزن'), '${d.branchName.trim()} / ${d.warehouseName.trim()}'),
          ],
        ),
        FirstRunSummarySection(
          title: tr('العملة والضريبة'),
          onEdit: () => edit(FirstRunStep.company),
          rows: [
            (tr('العملة'), '$currency (${d.currency})'),
            (
              tr('ضريبة القيمة المضافة'),
              d.vatEnabled ? '${d.vatRate.toInt()}%' : tr('معطّلة')
            ),
            (tr('الفوترة الإلكترونية'), _eInvoiceName(d.eInvoice)),
            (tr('السنة المالية'), '${d.fiscalYear}'),
          ],
        ),
        if (d.path == FirstRunPath.standalone)
          FirstRunSummarySection(
            title: tr('البيانات والمسؤول'),
            editKey: const Key('first_run_edit_users'),
            onEdit: () => edit(FirstRunStep.users),
            rows: [
              (tr('مكان البيانات'), s.storage?.path ?? '—'),
              (tr('المسؤول'), kFirstRunAdminUsername),
              (tr('كلمة المرور'), '••••••••'),
            ],
          ),
        if (d.path == FirstRunPath.hq) ...reviewHqSections(d, edit),
        ],
        if (company && d.currency.isNotEmpty)
          FirstRunCallout(
            key: const Key('first_run_currency_confirm'),
            title: tr('العملة: {p0} — لا يمكن تغييرها بعد أول فاتورة.',
                {'p0': d.currency}),
            tone: FirstRunTone.warning,
            icon: Icons.warning_amber_rounded,
          ),
        if (s.busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(
            key: const Key('first_run_run_stage'),
            s.runStage?.label ?? tr('جارٍ التشغيل…'),
          ),
        ],
        if (s.failedStage != null) ...[
          const SizedBox(height: 12),
          FirstRunCallout(
            key: const Key('first_run_failure'),
            title: tr('فشلت مرحلة: {p0}', {'p0': s.failedStage!.label}),
            body: s.failureMessage,
            tone: FirstRunTone.danger,
            icon: Icons.error_outline,
          ),
        ],
      ],
    );
  }
}
