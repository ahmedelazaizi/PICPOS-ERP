// J4 (الجزء ٣) — السلفُ والقروض: المبلغُ والأقساطُ والمسدَّدُ والرصيد وسندُ
// الصرف. سلفةٌ جديدةٌ تُصرف بسند صرفٍ (ورقةٌ من دفتر السندات اختياريّاً)،
// والتسديدُ المبكّرُ بسند قبض — لصاحب `hr_advances_manage`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../../domain/models/hr_payroll.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_labels.dart';
import '../hr_payroll_labels.dart';
import '../hr_payroll_providers.dart';
import '../hr_picpos_providers.dart';
import 'hr_form_kit.dart';
import 'hr_table.dart';

class AdvancesView extends ConsumerWidget {
  const AdvancesView({super.key, this.employeeId, this.compact = false});

  /// موظفٌ واحد (ملفّ الموظف) أو الكلّ.
  final int? employeeId;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(employeeAdvancesProvider(employeeId)).value ??
        const <EmployeeAdvance>[];
    final canManage = ref
            .watch(hasPermissionProvider(PermissionCodes.hrAdvancesManage))
            .value ??
        false;
    final open = rows.where((a) => a.status == AdvanceStatus.active);
    final balance = open.fold<double>(0, (s, a) => s + a.balance);

    Future<void> create() async {
      final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AdvanceDialog(employeeId: employeeId));
      if (ok == true) refreshPayroll(ref);
    }

    Future<void> settle(EmployeeAdvance a) async {
      final ok = await showDialog<bool>(
          context: context, builder: (_) => _SettleDialog(advance: a));
      if (ok == true) refreshPayroll(ref);
    }

    return Column(children: [
      HrToolbar(children: [
        FilledButton.icon(
          key: const Key('advance_new'),
          onPressed: canManage ? create : null,
          icon: const Icon(PhosphorIconsBold.plus, size: 16),
          label: Text(tr('سلفة جديدة')),
        ),
        HrPill(
          label: tr('الرصيد المفتوح: {p0}', {'p0': hrMoney(balance)}),
          color: balance > 0
              ? AppColors.statusWarning(context)
              : AppColors.statusSuccess(context),
          icon: PhosphorIconsBold.wallet,
        ),
      ]),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: HrTable(
            minWidth: compact ? 820 : 1060,
            emptyIcon: PhosphorIconsBold.handCoins,
            emptyTitle: tr('لا سلف بعد'),
            columns: [
              if (employeeId == null) HrTableColumn(tr('الموظف'), flex: 3),
              HrTableColumn(tr('النوع')),
              HrTableColumn(tr('التاريخ')),
              HrTableColumn(tr('المبلغ')),
              HrTableColumn(tr('الأقساط')),
              HrTableColumn(tr('المسدد')),
              HrTableColumn(tr('الرصيد')),
              HrTableColumn(tr('السند')),
              HrTableColumn(tr('الحالة')),
              const HrTableColumn('', flex: 1),
            ],
            rows: [
              for (final a in rows)
                HrTableRow(
                  key: Key('advance_row_${a.id}'),
                  cells: [
                    if (employeeId == null) HrCellText(a.employeeName ?? ''),
                    HrCellText(advanceKindLabel(a.kind),
                        sub: a.legacy ? tr('مرحَّل من النظام القديم') : null),
                    HrCellText(hrDate(a.issueDate), number: true),
                    HrCellText(hrMoney(a.amount), number: true),
                    HrCellText(
                        '${a.installments} × ${hrMoney(a.installmentAmount)}',
                        number: true,
                        sub: tr('من {p0}',
                            {'p0': hrPeriod(a.startYear, a.startMonth)})),
                    HrCellText(hrMoney(a.repaid), number: true),
                    HrCellText(hrMoney(a.balance),
                        number: true,
                        color: a.balance > 0
                            ? AppColors.statusWarning(context)
                            : null),
                    HrCellText(a.voucherNumber ?? '—',
                        number: true,
                        sub: a.bookNumber == null ? null : '#${a.bookNumber}'),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: HrPill(
                        label: advanceStatusLabel(a.status),
                        color: a.status == AdvanceStatus.active
                            ? AppColors.statusWarning(context)
                            : AppColors.statusSuccess(context),
                      ),
                    ),
                    if (canManage &&
                        a.status == AdvanceStatus.active &&
                        a.balance > 0)
                      IconButton(
                        key: Key('advance_settle_${a.id}'),
                        tooltip: tr('تسديد مبكر'),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        iconSize: 16,
                        onPressed: () => settle(a),
                        icon: const Icon(PhosphorIconsBold.checkCircle),
                      )
                    else
                      const SizedBox(),
                  ],
                ),
            ],
          ),
        ),
      ),
    ]);
  }
}

/// صرفُ سلفةٍ أو قرض.
class AdvanceDialog extends ConsumerStatefulWidget {
  const AdvanceDialog({super.key, this.employeeId});
  final int? employeeId;

  @override
  ConsumerState<AdvanceDialog> createState() => _AdvanceDialogState();
}

class _AdvanceDialogState extends ConsumerState<AdvanceDialog> {
  late int? _employee = widget.employeeId;
  String _kind = AdvanceKind.advance;
  final _amount = TextEditingController();
  final _installments = TextEditingController(text: '1');
  final _notes = TextEditingController();
  late DateTime _start = () {
    final n = DateTime.now();
    return DateTime(n.year, n.month + 1);
  }();
  int? _safe;
  int? _book;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _installments.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_employee == null || _safe == null) {
      setState(() => _error = tr('اختر الموظف والخزنة.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(databaseProvider).createEmployeeAdvance(
            employeeId: _employee!,
            kind: _kind,
            amount: double.tryParse(_amount.text.trim()) ?? 0,
            installments: int.tryParse(_installments.text.trim()) ?? 1,
            startYear: _start.year,
            startMonth: _start.month,
            safeId: _safe!,
            bookId: _book,
            notes: _notes.text,
            userId: ref.read(authProvider).user?.id,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is HrException ? e.message : '$e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(hrProfilesProvider).value ?? const <EmployeeProfile>[];
    final safes = ref.watch(payrollSafesProvider).value ?? const <PayrollSafe>[];
    final books = ref.watch(paymentBooksProvider).value ?? const [];
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    final count = int.tryParse(_installments.text.trim()) ?? 1;
    return PicPosDialog(
      icon: PhosphorIconsBold.handCoins,
      title: tr('صرف سلفة أو قرض'),
      width: 680,
      onCancel: () => Navigator.of(context).pop(false),
      primaryAction: PicPosDialogAction(
        label: tr('صرف بسند'),
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
            fieldKey: const Key('advance_employee'),
            label: tr('الموظف'),
            value: _employee,
            required: true,
            items: {
              for (final p in people)
                if (p.status != EmployeeStatus.terminated) p.id!: p.name,
            },
            onChanged: widget.employeeId != null
                ? null
                : (v) => setState(() => _employee = v),
          ),
          HrDropdown<String>(
            fieldKey: const Key('advance_kind'),
            label: tr('النوع'),
            value: _kind,
            items: {for (final k in AdvanceKind.values) k: advanceKindLabel(k)},
            onChanged: (v) => setState(() => _kind = v ?? _kind),
          ),
        ]),
        PicPosDialogRow(children: [
          HrTextField(
            fieldKey: const Key('advance_amount'),
            label: tr('المبلغ'),
            controller: _amount,
            number: true,
            required: true,
            onChanged: (_) => setState(() {}),
          ),
          HrTextField(
            fieldKey: const Key('advance_installments'),
            label: tr('عدد الأقساط'),
            controller: _installments,
            number: true,
            onChanged: (_) => setState(() {}),
          ),
          HrLabeled(
            label: tr('أول قسط'),
            child: HrStepper(
              keyPrefix: 'advance_start',
              label: hrPeriod(_start.year, _start.month),
              onPrev: () => setState(
                  () => _start = DateTime(_start.year, _start.month - 1)),
              onNext: () => setState(
                  () => _start = DateTime(_start.year, _start.month + 1)),
            ),
          ),
        ]),
        if (amount > 0 && count > 0)
          Text(
            tr('القسط الشهري: {p0}', {'p0': hrMoney(amount / count)}),
            style: TextStyle(fontSize: 12, color: context.picposMuted),
          ),
        PicPosDialogRow(children: [
          HrDropdown<int>(
            fieldKey: const Key('advance_safe'),
            label: tr('الخزنة أو البنك'),
            value: _safe,
            required: true,
            items: {for (final s in safes) s.id: trData(s.name)},
            onChanged: (v) => setState(() => _safe = v),
          ),
          HrDropdown<int>(
            fieldKey: const Key('advance_book'),
            label: tr('دفتر سندات الصرف'),
            value: _book,
            emptyLabel: tr('بلا دفتر'),
            items: {for (final b in books) b.id: b.displayName},
            onChanged: (v) => setState(() => _book = v),
          ),
        ]),
        HrTextField(
          fieldKey: const Key('advance_notes'),
          label: tr('ملاحظات'),
          controller: _notes,
        ),
        Text(
          tr('القيد: من حـ/ سلف الموظفين إلى حـ/ الخزنة أو البنك.'),
          style: TextStyle(fontSize: 12, color: context.picposMuted),
        ),
      ],
    );
  }
}

class _SettleDialog extends ConsumerStatefulWidget {
  const _SettleDialog({required this.advance});
  final EmployeeAdvance advance;

  @override
  ConsumerState<_SettleDialog> createState() => _SettleDialogState();
}

class _SettleDialogState extends ConsumerState<_SettleDialog> {
  late final _amount =
      TextEditingController(text: widget.advance.balance.toString());
  int? _safe;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_safe == null) {
      setState(() => _error = tr('اختر الخزنة أو البنك.'));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(databaseProvider).settleEmployeeAdvance(
            widget.advance.id!,
            safeId: _safe!,
            amount: double.tryParse(_amount.text.trim()),
            userId: ref.read(authProvider).user?.id,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is HrException ? e.message : '$e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final safes = ref.watch(payrollSafesProvider).value ?? const <PayrollSafe>[];
    return PicPosDialog(
      icon: PhosphorIconsBold.checkCircle,
      title: tr('تسديد مبكر'),
      subtitle: widget.advance.employeeName,
      width: 520,
      onCancel: () => Navigator.of(context).pop(false),
      primaryAction: PicPosDialogAction(
        label: tr('قبض بسند'),
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
        HrTextField(
          fieldKey: const Key('advance_settle_amount'),
          label: tr('المبلغ'),
          controller: _amount,
          number: true,
        ),
        HrDropdown<int>(
          fieldKey: const Key('advance_settle_safe'),
          label: tr('الخزنة أو البنك'),
          value: _safe,
          required: true,
          items: {for (final s in safes) s.id: trData(s.name)},
          onChanged: (v) => setState(() => _safe = v),
        ),
      ],
    );
  }
}
