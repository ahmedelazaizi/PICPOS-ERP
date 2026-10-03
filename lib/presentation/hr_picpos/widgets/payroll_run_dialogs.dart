// J4 (الجزء ٣) — حواراتُ المسيّر: تسويةٌ يدويّةٌ على قسيمة (بسببٍ إلزاميّ)،
// والصرفُ (خزنةٌ أو بنك، سندٌ لكلّ موظفٍ أو سندٌ جماعيّ، ودفترُ سنداتٍ
// اختياريّ)، وسببُ العكس، وطباعةُ القسائم وتصديرُ السجلّ.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../data/services/excel_service.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../../domain/models/hr_payroll.dart';
import '../../../services/printing/pdf_compute_helper.dart';
import '../../../services/printing/printing_models.dart' show DocumentCompanyHeader;
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_payroll_labels.dart';
import '../hr_payroll_providers.dart';
import '../payslip_pdf.dart';
import 'hr_form_kit.dart';

String _errorText(Object e) => e is HrException ? e.message : '$e';

/// هويّةُ المنشأة من إعدادات `company_*`.
Future<DocumentCompanyHeader> loadPayslipCompany(WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  Future<String?> s(String k) => db.getSettingValue(k);
  return DocumentCompanyHeader(
    name: await s('company_name') ?? '',
    phone: await s('company_phone'),
    phone2: await s('company_phone2'),
    address: await s('company_address'),
    taxId: await s('company_tax_id'),
    nameEn: await s('company_name_en'),
    crNumber: await s('company_cr_number'),
  );
}

/// يطبع قسائمَ [lines] (صفحةٌ لكلّ موظف) بلغة الواجهة.
Future<void> printPayslips(BuildContext context, WidgetRef ref, PayrollRun run,
    List<PayrollLine> lines) async {
  final english = Localizations.localeOf(context).languageCode == 'en';
  try {
    final doc = await buildPayslipDocument(
      run: run,
      lines: lines,
      company: await loadPayslipCompany(ref),
      english: english,
    );
    await PdfComputeHelper.layoutPdf(doc,
        documentLabel: 'payslip', name: 'payslip_${run.period}.pdf');
  } catch (e) {
    if (context.mounted) {
      AppToast.show(context, _errorText(e), type: ToastType.error);
    }
  }
}

/// يصدّر سجلَّ المسيّر إلى Excel.
Future<void> exportPayrollRegister(
    BuildContext context, WidgetRef ref, PayrollRun run) async {
  try {
    final (headers, rows) =
        await ref.read(databaseProvider).payrollRegister(run.id);
    final excel = ref.read(excelServiceProvider) as ExcelService;
    final path = await excel.exportReport(
          title: tr('سجل الرواتب {p0}', {'p0': run.period}),
          headers: [for (final h in headers) tr(h)],
          rows: [
            for (final r in rows)
              [for (final c in r) c is String && c.isNotEmpty ? trData(c) : c],
          ],
          periodFrom: run.from,
          periodTo: run.to,
        );
    if (path != null && context.mounted) {
      AppToast.show(context, tr('تم تصدير سجل الرواتب'));
    }
  } catch (e) {
    if (context.mounted) {
      AppToast.show(context, _errorText(e), type: ToastType.error);
    }
  }
}

/// تسويةٌ يدويّةٌ على قسيمة.
class PayrollAdjustmentDialog extends ConsumerStatefulWidget {
  const PayrollAdjustmentDialog(
      {super.key, required this.runId, required this.employeeId});
  final int runId;
  final int employeeId;

  @override
  ConsumerState<PayrollAdjustmentDialog> createState() =>
      _PayrollAdjustmentDialogState();
}

class _PayrollAdjustmentDialogState
    extends ConsumerState<PayrollAdjustmentDialog> {
  final _amount = TextEditingController();
  final _label = TextEditingController();
  final _reason = TextEditingController();
  String _kind = PayItemKind.earning;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _label.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(databaseProvider).addPayrollManualItem(
            runId: widget.runId,
            employeeId: widget.employeeId,
            kind: _kind,
            amount: double.tryParse(_amount.text.trim()) ?? 0,
            reason: _reason.text,
            label: _label.text,
            userId: ref.read(authProvider).user?.id,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PicPosDialog(
      icon: PhosphorIconsBold.pencilSimpleLine,
      title: tr('تسوية على القسيمة'),
      width: 560,
      onCancel: () => Navigator.of(context).pop(false),
      primaryAction: PicPosDialogAction(
        label: tr('حفظ'),
        icon: PhosphorIconsBold.floppyDisk,
        busy: _saving,
        onPressed: _saving ? null : _save,
      ),
      body: [
        if (_error != null)
          PicPosDialogBanner(
            icon: PhosphorIconsBold.warningCircle,
            text: _error!,
            color: AppColors.statusError(context),
          ),
        PicPosDialogRow(children: [
          HrDropdown<String>(
            fieldKey: const Key('payroll_adj_kind'),
            label: tr('النوع'),
            value: _kind,
            items: {
              PayItemKind.earning: payItemKindLabel(PayItemKind.earning),
              PayItemKind.deduction: payItemKindLabel(PayItemKind.deduction),
            },
            onChanged: (v) => setState(() => _kind = v ?? _kind),
          ),
          HrTextField(
            fieldKey: const Key('payroll_adj_amount'),
            label: tr('المبلغ'),
            controller: _amount,
            number: true,
            required: true,
          ),
        ]),
        HrTextField(
          fieldKey: const Key('payroll_adj_label'),
          label: tr('البيان'),
          controller: _label,
        ),
        HrTextField(
          fieldKey: const Key('payroll_adj_reason'),
          label: tr('السبب'),
          controller: _reason,
          required: true,
          maxLines: 2,
        ),
      ],
    );
  }
}

/// صرفُ المسيّر.
class PayrollPayDialog extends ConsumerStatefulWidget {
  const PayrollPayDialog({super.key, required this.run, this.lineIds});
  final PayrollRun run;
  final List<int>? lineIds;

  @override
  ConsumerState<PayrollPayDialog> createState() => _PayrollPayDialogState();
}

class _PayrollPayDialogState extends ConsumerState<PayrollPayDialog> {
  int? _safe;
  int? _book;
  bool _bulk = false;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final safe = _safe;
    if (safe == null) {
      setState(() => _error = tr('اختر الخزنة أو البنك.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(databaseProvider).payPayrollRun(
            widget.run.id,
            safeId: safe,
            bulk: _bulk,
            lineIds: widget.lineIds,
            bookId: _book,
            userId: ref.read(authProvider).user?.id,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final safes = ref.watch(payrollSafesProvider).value ?? const <PayrollSafe>[];
    final books = ref.watch(paymentBooksProvider).value ?? const [];
    return PicPosDialog(
      icon: PhosphorIconsBold.handCoins,
      title: tr('صرف الرواتب'),
      subtitle: widget.run.period,
      width: 620,
      onCancel: () => Navigator.of(context).pop(false),
      primaryAction: PicPosDialogAction(
        label: tr('صرف'),
        icon: PhosphorIconsBold.check,
        busy: _saving,
        onPressed: _saving ? null : _save,
      ),
      body: [
        if (_error != null)
          PicPosDialogBanner(
            icon: PhosphorIconsBold.warningCircle,
            text: _error!,
            color: AppColors.statusError(context),
          ),
        PicPosDialogRow(children: [
          HrDropdown<int>(
            fieldKey: const Key('payroll_pay_safe'),
            label: tr('الخزنة أو البنك'),
            value: _safe,
            required: true,
            items: {
              for (final s in safes)
                s.id: '${trData(s.name)} · ${s.type == 'bank' ? tr('بنك') : tr('خزنة')}',
            },
            onChanged: (v) => setState(() => _safe = v),
          ),
          HrDropdown<int>(
            fieldKey: const Key('payroll_pay_book'),
            label: tr('دفتر سندات الصرف'),
            value: _book,
            emptyLabel: tr('بلا دفتر'),
            items: {for (final b in books) b.id: b.displayName},
            onChanged: (v) => setState(() => _book = v),
          ),
        ]),
        Wrap(spacing: 10, children: [
          PicPosDialogChoice(
            icon: PhosphorIconsBold.users,
            label: tr('سند صرف لكل موظف'),
            selected: !_bulk,
            onTap: () => setState(() => _bulk = false),
          ),
          PicPosDialogChoice(
            icon: PhosphorIconsBold.bank,
            label: tr('تحويل بنكي جماعي بسند واحد'),
            selected: _bulk,
            onTap: () => setState(() => _bulk = true),
          ),
        ]),
        Text(
          tr('القيد: من حـ/ الرواتب المستحقة إلى حـ/ الخزنة أو البنك.'),
          style: TextStyle(fontSize: 12, color: context.picposMuted),
        ),
      ],
    );
  }
}

/// يطلب سبباً إلزاميّاً (للعكس) — يعيده أو `null`.
Future<String?> askPayrollReason(BuildContext context,
        {required String title, required String action}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(title: title, action: action),
    );

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.action});
  final String title;
  final String action;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PicPosDialog(
      icon: PhosphorIconsBold.arrowCounterClockwise,
      title: widget.title,
      width: 520,
      accent: AppColors.statusError(context),
      onCancel: () => Navigator.of(context).pop(),
      primaryAction: PicPosDialogAction(
        label: widget.action,
        icon: PhosphorIconsBold.check,
        color: AppColors.statusError(context),
        onPressed: () {
          if (_controller.text.trim().isEmpty) return;
          Navigator.of(context).pop(_controller.text.trim());
        },
      ),
      body: [
        HrTextField(
          fieldKey: const Key('payroll_reason'),
          label: tr('السبب'),
          controller: _controller,
          required: true,
          maxLines: 2,
        ),
      ],
    );
  }
}
