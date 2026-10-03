// J4 (الجزء ٣) — قواعدُ احتساب المسيّر: مقامُ الأجر اليوميّ، الغيابُ وإجازةُ
// بلا أجر، التأخيرُ (بالدقيقة أو بالشرائح وسماحٌ شهريّ)، الإضافيّ، التأمينات
// (حصّتان وسقفٌ وأساس) والضريبةُ بشرائحَ تصاعديّة — كلُّها قيمٌ يضبطها
// المستخدم، والتأميناتُ والضريبةُ معطّلتان افتراضيّاً. الحفظُ لـ
// `hr_payroll_edit`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../../domain/models/hr_payroll.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_payroll_labels.dart';
import '../hr_payroll_providers.dart';
import 'hr_form_kit.dart';

class PayrollRulesView extends ConsumerWidget {
  const PayrollRulesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(payrollRulesProvider).value;
    if (rules == null) return const Center(child: CircularProgressIndicator());
    return _RulesForm(key: ValueKey(rules.encode()), rules: rules);
  }
}

class _RulesForm extends ConsumerStatefulWidget {
  const _RulesForm({super.key, required this.rules});
  final PayrollRules rules;

  @override
  ConsumerState<_RulesForm> createState() => _RulesFormState();
}

class _RulesFormState extends ConsumerState<_RulesForm> {
  late final PayrollRules r = widget.rules;
  late String _dayBasis = r.dayBasis;
  late final _hours = _num(r.defaultHoursPerDay);
  late final _absenceFactor = _num(r.absenceDayFactor);
  late bool _unrecorded = r.deductUnrecordedAbsence;
  late bool _unpaid = r.deductUnpaidLeave;
  late String _lateMode = r.latenessMode;
  late final _grace = _num(r.latenessGraceMinutes);
  late final _lateFactor = _num(r.latenessFactor);
  late bool _early = r.includeEarlyLeave;
  late final List<(TextEditingController, TextEditingController)> _tiers = [
    for (final t in r.latenessTiers) (_num(t.fromMinutes), _num(t.dayFraction)),
  ];
  late bool _overtime = r.overtimeEnabled;
  late final _otRate = _num(r.overtimeRate);
  late bool _insurance = r.insuranceEnabled;
  late final _insEmp = _num(r.insuranceEmployeePct);
  late final _insEr = _num(r.insuranceEmployerPct);
  late String _insBase = r.insuranceBase;
  late final _insCeiling = _num(r.insuranceCeiling);
  late bool _tax = r.taxEnabled;
  late final _taxExempt = _num(r.taxExemptionMonthly);
  late final List<(TextEditingController, TextEditingController)> _brackets = [
    for (final b in r.taxBrackets)
      (TextEditingController(text: b.upTo == null ? '' : _fmt(b.upTo!)),
          _num(b.ratePct)),
  ];
  bool _saving = false;

  static String _fmt(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  static TextEditingController _num(num v) =>
      TextEditingController(text: _fmt(v));

  @override
  void dispose() {
    for (final c in [
      _hours, _absenceFactor, _grace, _lateFactor, _otRate, _insEmp, _insEr,
      _insCeiling, _taxExempt,
      for (final t in _tiers) ...[t.$1, t.$2],
      for (final b in _brackets) ...[b.$1, b.$2],
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _d(TextEditingController c, [double f = 0]) =>
      double.tryParse(c.text.trim()) ?? f;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(databaseProvider).savePayrollRules(
            PayrollRules(
              dayBasis: _dayBasis,
              defaultHoursPerDay: _d(_hours, 8),
              absenceDayFactor: _d(_absenceFactor, 1),
              deductUnrecordedAbsence: _unrecorded,
              deductUnpaidLeave: _unpaid,
              latenessMode: _lateMode,
              latenessGraceMinutes: _d(_grace).round(),
              latenessFactor: _d(_lateFactor, 1),
              includeEarlyLeave: _early,
              latenessTiers: [
                for (final t in _tiers)
                  LatenessTier(
                      fromMinutes: _d(t.$1).round(), dayFraction: _d(t.$2)),
              ],
              overtimeEnabled: _overtime,
              overtimeRate: _d(_otRate, 1.25),
              insuranceEnabled: _insurance,
              insuranceEmployeePct: _d(_insEmp),
              insuranceEmployerPct: _d(_insEr),
              insuranceBase: _insBase,
              insuranceCeiling: _d(_insCeiling),
              taxEnabled: _tax,
              taxExemptionMonthly: _d(_taxExempt),
              taxBrackets: [
                for (final b in _brackets)
                  TaxBracket(
                      upTo: b.$1.text.trim().isEmpty ? null : _d(b.$1),
                      ratePct: _d(b.$2)),
              ],
            ),
            userId: ref.read(authProvider).user?.id,
          );
      refreshPayroll(ref);
      if (mounted) AppToast.show(context, tr('تم حفظ قواعد الرواتب'));
    } on HrException catch (e) {
      if (mounted) AppToast.show(context, e.message, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _check(String key, String label, bool value, ValueChanged<bool> set) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Checkbox(
          key: Key('payroll_rule_$key'),
          value: value,
          onChanged: (v) => setState(() => set(v ?? false)),
        ),
        Flexible(child: Text(label)),
      ]);

  Widget _pairs(
    String keyPrefix,
    List<(TextEditingController, TextEditingController)> rows,
    String first,
    String second,
    String addLabel,
  ) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(
                child: HrTextField(
                    fieldKey: Key('${keyPrefix}_${i}_a'),
                    label: first,
                    controller: rows[i].$1,
                    number: true),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: HrTextField(
                    fieldKey: Key('${keyPrefix}_${i}_b'),
                    label: second,
                    controller: rows[i].$2,
                    number: true),
              ),
              IconButton(
                tooltip: tr('حذف'),
                onPressed: () => setState(() => rows.removeAt(i)),
                icon: Icon(PhosphorIconsBold.trash,
                    size: 16, color: AppColors.statusError(context)),
              ),
            ]),
          ),
        TextButton.icon(
          key: Key('${keyPrefix}_add'),
          onPressed: () => setState(() =>
              rows.add((TextEditingController(), TextEditingController()))),
          icon: const Icon(PhosphorIconsBold.plus, size: 15),
          label: Text(addLabel),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final canEdit =
        ref.watch(hasPermissionProvider(PermissionCodes.hrPayrollEdit)).value ??
            false;
    void preset(double emp, double er) => setState(() {
          _insurance = true;
          _insEmp.text = _fmt(emp);
          _insEr.text = _fmt(er);
        });
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        HrSection(
          title: tr('الأجر اليومي والغياب'),
          icon: PhosphorIconsBold.calendarX,
          actions: [
            FilledButton.icon(
              key: const Key('payroll_rules_save'),
              onPressed: canEdit && !_saving ? _save : null,
              icon: const Icon(PhosphorIconsBold.floppyDisk, size: 16),
              label: Text(tr('حفظ القواعد')),
            ),
          ],
          child: HrFieldGrid(children: [
            HrDropdown<String>(
              fieldKey: const Key('payroll_rule_day_basis'),
              label: tr('مقام الأجر اليومي'),
              value: _dayBasis,
              items: {for (final b in DayBasis.values) b: dayBasisLabel(b)},
              onChanged: (v) => setState(() => _dayBasis = v ?? _dayBasis),
            ),
            HrTextField(
                fieldKey: const Key('payroll_rule_hours'),
                label: tr('ساعات اليوم الافتراضية'),
                controller: _hours,
                number: true),
            HrTextField(
                fieldKey: const Key('payroll_rule_absence_factor'),
                label: tr('معامل خصم يوم الغياب'),
                controller: _absenceFactor,
                number: true),
            _check('unrecorded', tr('خصم الأيام بلا بصمة ولا علامة'),
                _unrecorded, (v) => _unrecorded = v),
            _check('unpaid', tr('خصم الإجازة بدون أجر'), _unpaid,
                (v) => _unpaid = v),
          ]),
        ),
        const SizedBox(height: 12),
        HrSection(
          title: tr('التأخير والانصراف المبكر'),
          icon: PhosphorIconsBold.clockCountdown,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            HrFieldGrid(children: [
              HrDropdown<String>(
                fieldKey: const Key('payroll_rule_late_mode'),
                label: tr('طريقة الخصم'),
                value: _lateMode,
                items: {
                  for (final m in LatenessMode.values) m: latenessModeLabel(m),
                },
                onChanged: (v) => setState(() => _lateMode = v ?? _lateMode),
              ),
              HrTextField(
                  fieldKey: const Key('payroll_rule_grace'),
                  label: tr('دقائق سماح شهرية'),
                  controller: _grace,
                  number: true),
              HrTextField(
                  fieldKey: const Key('payroll_rule_late_factor'),
                  label: tr('معامل خصم الدقيقة'),
                  controller: _lateFactor,
                  number: true),
              _check('early', tr('احتساب الانصراف المبكر'), _early,
                  (v) => _early = v),
            ]),
            if (_lateMode == LatenessMode.tiers) ...[
              const SizedBox(height: 8),
              _pairs('payroll_tier', _tiers, tr('من دقيقة'),
                  tr('كسر اليوم المخصوم'), tr('إضافة شريحة')),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        HrSection(
          title: tr('العمل الإضافي'),
          icon: PhosphorIconsBold.timer,
          child: HrFieldGrid(children: [
            _check('overtime', tr('احتساب العمل الإضافي'), _overtime,
                (v) => _overtime = v),
            HrTextField(
                fieldKey: const Key('payroll_rule_ot_rate'),
                label: tr('معامل ساعة الإضافي (من أجر الساعة)'),
                controller: _otRate,
                number: true),
          ]),
        ),
        const SizedBox(height: 12),
        HrSection(
          title: tr('التأمينات الاجتماعية'),
          icon: PhosphorIconsBold.shieldCheck,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            HrFieldGrid(children: [
              _check('insurance', tr('تفعيل التأمينات'), _insurance,
                  (v) => _insurance = v),
              HrTextField(
                  fieldKey: const Key('payroll_rule_ins_emp'),
                  label: tr('حصة الموظف %'),
                  controller: _insEmp,
                  number: true),
              HrTextField(
                  fieldKey: const Key('payroll_rule_ins_er'),
                  label: tr('حصة المنشأة %'),
                  controller: _insEr,
                  number: true),
              HrDropdown<String>(
                fieldKey: const Key('payroll_rule_ins_base'),
                label: tr('أساس الاقتطاع'),
                value: _insBase,
                items: {
                  for (final b in InsuranceBase.values) b: insuranceBaseLabel(b),
                },
                onChanged: (v) => setState(() => _insBase = v ?? _insBase),
              ),
              HrTextField(
                  fieldKey: const Key('payroll_rule_ins_ceiling'),
                  label: tr('سقف الأجر الخاضع (0 بلا سقف)'),
                  controller: _insCeiling,
                  number: true),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ActionChip(
                key: const Key('payroll_preset_jo'),
                label: Text(tr('الضمان الاجتماعي الأردني 7.5% / 14.25%')),
                onPressed: () => preset(7.5, 14.25),
              ),
              ActionChip(
                key: const Key('payroll_preset_eg'),
                label: Text(tr('التأمينات المصرية 11% / 18.75%')),
                onPressed: () => preset(11, 18.75),
              ),
              Text(tr('قيم مرجعية للبدء — راجع النسب السارية قبل الاعتماد'),
                  style: TextStyle(fontSize: 11.5, color: context.picposMuted)),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        HrSection(
          title: tr('ضريبة الدخل'),
          icon: PhosphorIconsBold.receipt,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            HrFieldGrid(children: [
              _check('tax', tr('تفعيل ضريبة الرواتب'), _tax, (v) => _tax = v),
              HrTextField(
                  fieldKey: const Key('payroll_rule_tax_exempt'),
                  label: tr('إعفاء شهري'),
                  controller: _taxExempt,
                  number: true),
            ]),
            const SizedBox(height: 8),
            Text(tr('شرائح شهرية تصاعدية — اترك «حتى» فارغاً للشريحة الأخيرة'),
                style: TextStyle(fontSize: 11.5, color: context.picposMuted)),
            const SizedBox(height: 6),
            _pairs('payroll_bracket', _brackets, tr('حتى مبلغ'),
                tr('النسبة %'), tr('إضافة شريحة')),
          ]),
        ),
      ],
    );
  }
}
