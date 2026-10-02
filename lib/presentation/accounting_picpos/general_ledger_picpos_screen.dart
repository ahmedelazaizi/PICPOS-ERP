import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/arabic_utils.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/providers/manufacturing_providers.dart';
import '../../data/providers/providers.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../../services/excel_export_helper.dart';
import '../../services/printing/report_pdf_generator.dart';
import '../picpos_shell/picpos_dialog.dart';
import '../picpos_shell/picpos_empty_state.dart';
import '../picpos_shell/picpos_screen_scaffold.dart';
import '../picpos_shell/picpos_toolbar.dart';
import '../widgets/report_components.dart' show DateRangeFilter;
import '../picpos_shell/picpos_surface.dart';

/// دفترُ الأستاذ بهويّة PicPos — تبويبُ `gl` في حاويةِ الحسابات.
///
/// التصميمُ: شريطُ مرشِّحاتٍ (60px) فيه منتقي الحساب بارزاً، ثمّ رأسُ أعمدةٍ
/// (34px)، ثمّ صفُّ الرصيد الافتتاحيّ، ثمّ الصفوف (44px)، ثمّ شريطُ
/// الإجماليات (56px بحدٍّ علويٍّ بلون العلامة).
///
/// ⚠️ **الـvirtualization مقصودٌ لا تفصيلَ شكل.** الأصلُ نُقل إلى
/// `DataTable2` بعد أن جمّد `DataTable` الشاشةَ على حساباتٍ بآلافِ السطور
/// (Cluster 024). فالفوركُ يبني الصفوفَ بـ`ListView.builder` — نفسُ الضمان
/// بتخطيطِ التصميم.
///
/// ⚠️ **ونطاقُ الفروع أمنيٌّ لا مرشِّحُ راحة.** `branchScopeProvider` يُمرَّر
/// إلى الاستعلام كـ`allowedBranchIds`، ومَن نطاقُه كاملٌ يمرّ بلا أثر.
/// إسقاطُه يفتح حركاتِ فروعٍ لا يملكها المستخدم.
class GeneralLedgerPicPosScreen extends ConsumerStatefulWidget {
  const GeneralLedgerPicPosScreen({
    super.key,
    this.initialAccountId,
    this.initialAccountLabel,
    this.initialFrom,
    this.initialTo,
  });

  /// يُفتَح الدفترُ مرشَّحاً على هذا الحساب ويُحمَّل فوراً — رابطُ «عرض في
  /// دفتر الأستاذ» من لوح دليل الحسابات. `null` ⇒ السلوكُ المعتاد (يختار
  /// المستخدمُ الحساب).
  final int? initialAccountId;

  /// «الرمز - الاسم» كما يُعرض على زرّ منتقي الحساب.
  final String? initialAccountLabel;

  /// مدى التاريخ الابتدائيّ — السنةُ الماليّةُ التي قرأ اللوحُ أرصدتَها، كي
  /// يطابق الدفترُ ما رآه المستخدمُ هناك.
  final DateTime? initialFrom;
  final DateTime? initialTo;

  @override
  ConsumerState<GeneralLedgerPicPosScreen> createState() =>
      _GeneralLedgerPicPosScreenState();
}

class _GeneralLedgerPicPosScreenState
    extends ConsumerState<GeneralLedgerPicPosScreen> {
  int? _accountId;
  String? _accountName;
  int? _costCenterId;
  int? _branchId;
  DateTime _fromDate = DateTime(DateTime.now().year, 1, 1);
  DateTime _toDate = DateTime.now();
  List<Map<String, dynamic>> _rows = const [];
  // ⚠️ منوَّعةٌ صراحةً لا `List<dynamic>`: الأصلُ كتم `avoid_dynamic_calls`
  //    بـ`ignore_for_file` على الملفّ كلِّه، وهو كتمٌ يمتدّ لما لم يُقصد.
  List<CostCenter> _costCenters = const [];
  bool _loading = false;

  final _fmt = NumberFormat('#,##0.00', 'ar_EG');
  final _dateFmt = DateFormat('yyyy/MM/dd');

  @override
  void initState() {
    super.initState();
    final id = widget.initialAccountId;
    if (id == null) return;
    _accountId = id;
    _accountName = widget.initialAccountLabel;
    _fromDate = widget.initialFrom ?? _fromDate;
    _toDate = widget.initialTo ?? _toDate;
    // بعد الإطار الأوّل: `_load` يقرأ `ref` ويستدعي `setState`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(ref.read(accountingRepositoryProvider));
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(accountingRepositoryProvider);

    final movements = _rows.where((r) => r['is_opening'] != true).toList();
    final opening = _rows.isNotEmpty && _rows.first['is_opening'] == true
        ? (_rows.first['balance'] as double? ?? 0)
        : 0.0;
    final closing =
        _rows.isNotEmpty ? (_rows.last['balance'] as double? ?? 0) : 0.0;
    final totalDebit = movements.fold<double>(
        0, (s, r) => s + (r['debit'] as double? ?? 0));
    final totalCredit = movements.fold<double>(
        0, (s, r) => s + (r['credit'] as double? ?? 0));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: PicPosScreenScaffold(
        title: tr('دفتر الأستاذ العام'),
        subtitle: tr('حركة الحساب والرصيد التراكمي'),
        icon: PhosphorIconsBold.book,
        headerActions: [
          if (_rows.isNotEmpty) ...[
            Text(tr('{p0} حركة', {'p0': movements.length}),
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: AppColors.textMuted)),
            const SizedBox(width: 10),
            IconButton(
              tooltip: tr('طباعة PDF'),
              icon: const Icon(PhosphorIconsBold.filePdf, size: 18),
              onPressed: () => ReportPdfGenerator.printGeneralLedger(
                accountName: _accountName ?? '',
                data: _rows,
                fromDate: _fromDate,
                toDate: _toDate,
              ),
            ),
            IconButton(
              tooltip: tr('تصدير Excel'),
              icon: const Icon(PhosphorIconsBold.fileXls, size: 18),
              onPressed: _exportExcel,
            ),
          ],
        ],
        toolbar: _buildToolbar(repo),
        body: _buildBody(opening, closing, totalDebit, totalCredit, movements),
      ),
    );
  }

  Widget _buildToolbar(IAccountingRepository repo) {
    return PicPosToolbar(
      children: [
        // منتقي الحساب — بارزٌ بحدٍّ بلون العلامة كما في التصميم.
        _AccountPickerButton(
          label: _accountName ?? tr('اختر الحساب'),
          selected: _accountId != null,
          onTap: () => _pickAccount(repo),
        ),
        _FilterChip(
          icon: PhosphorIconsBold.crosshair,
          label: _costCenterLabel(),
          active: _costCenterId != null,
          onTap: () => _pickCostCenter(repo),
        ),
        _FilterChip(
          icon: PhosphorIconsBold.calendarBlank,
          label: '${_dateFmt.format(_fromDate)} — ${_dateFmt.format(_toDate)}',
          active: true,
          onTap: _pickDateRange,
        ),
        Consumer(
          builder: (context, ref, _) {
            final branches = ref.watch(branchListProvider);
            return branches.maybeWhen(
              data: (list) {
                if (list.isEmpty) return const SizedBox.shrink();
                final name = _branchId != null
                    ? list
                            .where((b) => b.id == _branchId)
                            .map((b) => b.name)
                            .firstOrNull ??
                        tr('الفرع')
                    : tr('كل الفروع');
                return _FilterChip(
                  icon: PhosphorIconsBold.buildings,
                  label: name,
                  active: _branchId != null,
                  onTap: () => _pickBranch(list),
                );
              },
              orElse: () => const SizedBox.shrink(),
            );
          },
        ),
        FilledButton.icon(
          onPressed: _accountId != null ? () => _load(repo) : null,
          icon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
          label:  Text(tr('عرض')),
        ),
      ],
    );
  }

  Widget _buildBody(
    double opening,
    double closing,
    double totalDebit,
    double totalCredit,
    List<Map<String, dynamic>> movements,
  ) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rows.isEmpty) {
      return PicPosEmptyState(
        icon: PhosphorIconsBold.book,
        title: _accountId == null
            ? tr('اختر حساباً لعرض حركاته')
            : tr('لا توجد حركات للفترة المحددة'),
        hint: _accountId == null
            ? tr('الرصيدُ التراكميُّ يُحسب على طبيعة الحساب.')
            : tr('جرّب توسيعَ المدى الزمنيّ أو رفعَ مرشِّح مركز التكلفة.'),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const _LedgerHeaderRow(),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: _rows.length,
              itemBuilder: (context, i) => _LedgerRow(
                row: _rows[i],
                fmt: _fmt,
                dateFmt: _dateFmt,
                costCenterName: _costCenterNameFor(_rows[i]),
              ),
            ),
          ),
          _LedgerTotalsRow(
            count: movements.length,
            debit: _fmt.format(totalDebit),
            credit: _fmt.format(totalCredit),
            closing: _fmt.format(closing),
          ),
        ],
      ),
    );
  }

  String _costCenterLabel() {
    if (_costCenterId == null) return tr('كل مراكز التكلفة');
    return _costCenters
            .where((c) => c.id == _costCenterId)
            .map((c) => c.name)
            .firstOrNull ??
        tr('مركز التكلفة');
  }

  /// اسمُ المركز من رقمه — القاعدةُ تُرجع `cost_center_id` لا الاسم،
  /// فالوصلُ هنا لا اختراعَ فيه.
  String _costCenterNameFor(Map<String, dynamic> row) {
    final id = row['cost_center_id'];
    if (id == null) return '';
    return _costCenters
            .where((c) => c.id == id)
            .map((c) => c.name)
            .firstOrNull ??
        '';
  }

  Future<void> _load(IAccountingRepository repo) async {
    if (_accountId == null) return;
    setState(() => _loading = true);
    try {
      // ⚠️ نطاقُ الفروع الأمنيُّ — يُمرَّر للاستعلام، ومَن نطاقُه كاملٌ
      //    يمرّ بلا أثر. راجع تعليقَ الصنف.
      final scope = await ref.read(branchScopeProvider.future);
      final centers = await repo.getActiveCostCenters();
      final data = await repo.getAccountLedger(
        _accountId!,
        _fromDate,
        _toDate,
        costCenterId: _costCenterId,
        branchId: _branchId,
        allowedBranchIds: scope.hasFullAccess ? null : scope.allowedBranchIds,
      );
      if (!mounted) return;
      setState(() {
        _rows = data;
        _costCenters = centers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
    }
  }

  void _exportExcel() {
    ExcelExportHelper.export(
      context: context,
      title: tr('دفتر الأستاذ - {_accountName}', {'_accountName': _accountName}),
      headers:  [
        tr('التاريخ'),
        tr('رقم القيد'),
        tr('البيان'),
        tr('مدين'),
        tr('دائن'),
        tr('الرصيد'),
      ],
      rows: _rows
          .map((r) => [
                r['entry_date'],
                r['entry_number'],
                r['description'],
                r['debit'],
                r['credit'],
                r['balance'],
              ])
          .toList(),
      fromDate: _fromDate,
      toDate: _toDate,
    );
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
      initialEntryMode: DatePickerEntryMode.input,
      builder: (ctx, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 380),
            child: child!,
          ),
        ),
      ),
    );
    if (range == null) return;
    // ⚠️ التسويةُ إلى بداية/نهاية اليوم — بدونها تسقط حركاتُ آخرِ يومٍ
    //    لأنّ `entry_date` يحمل وقتاً فعليّاً (إصلاح FIL-1).
    setState(() {
      _fromDate = DateRangeFilter.normalizeStart(range.start);
      _toDate = DateRangeFilter.normalizeEnd(range.end);
    });
  }

  Future<void> _pickAccount(IAccountingRepository repo) async {
    final accounts = await repo.getAllAccounts();
    if (!mounted) return;

    final picked = await showDialog<Account>(
      context: context,
      builder: (ctx) {
        var filter = '';
        return StatefulBuilder(
          builder: (ctx, setInner) {
            final matches = accounts.where((a) {
              if (filter.isEmpty) return true;
              final q = ArabicUtils.normalize(filter.toLowerCase());
              return ArabicUtils.normalize(a.name.toLowerCase()).contains(q) ||
                  a.code.contains(q);
            }).toList();

            return PicPosDialog(
              icon: PhosphorIconsBold.listMagnifyingGlass,
              title: tr('اختر الحساب'),
              subtitle: tr('{p0} من {p1} حساباً', {'p0': matches.length, 'p1': accounts.length}),
              width: 560,
              onCancel: () => Navigator.pop(ctx),
              body: [
                TextField(
                  autofocus: true,
                  onChanged: (v) => setInner(() => filter = v),
                  decoration:  InputDecoration(
                    isDense: true,
                    hintText: tr('بحث بالاسم أو الرمز...'),
                    prefixIcon:
                        const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 380,
                  child: matches.isEmpty
                      ?  PicPosEmptyState(
                          icon: PhosphorIconsBold.magnifyingGlass,
                          title: tr('لا حسابَ يطابق البحث'),
                        )
                      : ListView.builder(
                          itemCount: matches.length,
                          itemBuilder: (ctx, i) {
                            final acc = matches[i];
                            // التدرّجُ من طول الرمز — نفسُ قاعدةِ الأصل.
                            final level = (acc.code.length / 2).floor();
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsetsDirectional.only(
                                start: 12.0 + (level * 12.0),
                                end: 12,
                              ),
                              leading: CircleAvatar(
                                radius: 13,
                                backgroundColor:
                                    AppColors.primary.withValues(alpha: 0.10),
                                child: Text(
                                  acc.code.isNotEmpty
                                      ? acc.code.substring(0, 1)
                                      : '?',
                                  style: const TextStyle(
                                      fontSize: 11, color: AppColors.primary),
                                ),
                              ),
                              title: Text(
                                '${acc.code} — ${trData(acc.name)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: level <= 2
                                      ? FontWeight.w800
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                _accountTypeLabel(acc.accountType),
                                style: const TextStyle(fontSize: 11),
                              ),
                              onTap: () => Navigator.pop(ctx, acc),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked == null || !mounted) return;
    setState(() {
      _accountId = picked.id;
      _accountName = '${picked.code} - ${trData(picked.name)}';
    });
  }

  Future<void> _pickCostCenter(IAccountingRepository repo) async {
    final centers = _costCenters.isNotEmpty
        ? _costCenters
        : await repo.getActiveCostCenters();
    if (!mounted) return;
    _costCenters = centers;

    final picked = await _pickFromList(
      icon: PhosphorIconsBold.crosshair,
      title: tr('مركز التكلفة'),
      allLabel: tr('كل مراكز التكلفة'),
      items: [
        for (final c in centers) (c.id, '${c.code} — ${trData(c.name)}'),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _costCenterId = picked.$1);
  }

  Future<void> _pickBranch(List<Branche> branches) async {
    final picked = await _pickFromList(
      icon: PhosphorIconsBold.buildings,
      title: tr('الفرع'),
      allLabel: tr('كل الفروع'),
      items: [for (final b in branches) (b.id, trData(b.name))],
    );
    if (picked == null || !mounted) return;
    setState(() => _branchId = picked.$1);
  }

  /// منتقٍ بسيطٌ يُرجع `(id?, )` — و`null` يعني أُغلق بلا اختيار،
  /// بينما `(null, )` يعني «الكل» صراحةً.
  Future<(int?,)?> _pickFromList({
    required IconData icon,
    required String title,
    required String allLabel,
    required List<(int, String)> items,
  }) {
    return showDialog<(int?,)>(
      context: context,
      builder: (ctx) => PicPosDialog(
        icon: icon,
        title: title,
        width: 460,
        onCancel: () => Navigator.pop(ctx),
        body: [
          ListTile(
            dense: true,
            leading: const Icon(PhosphorIconsBold.list, size: 16),
            title: Text(allLabel),
            onTap: () => Navigator.pop(ctx, (null,)),
          ),
          const Divider(height: 1),
          for (final (id, label) in items)
            ListTile(
              dense: true,
              title: Text(label, style: const TextStyle(fontSize: 13)),
              onTap: () => Navigator.pop(ctx, (id,)),
            ),
        ],
      ),
    );
  }

  String _accountTypeLabel(String type) => switch (type) {
        'asset' => tr('أصول'),
        'contra_asset' => tr('أصول مقابلة'),
        'liability' => tr('خصوم'),
        'equity' => tr('حقوق ملكية'),
        'revenue' => tr('إيرادات'),
        'contra_revenue' => tr('إيرادات مقابلة'),
        'expense' => tr('مصروفات'),
        _ => type,
      };
}

// ── قياساتُ الأعمدة من التصميم ────────────────────────────────────────────
const double _wDate = 110;
const double _wNo = 140;
const double _wCc = 170;
const double _wAmount = 150;
const double _wBalance = 170;

class _AccountPickerButton extends StatelessWidget {
  const _AccountPickerButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 40,
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 460),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: context.picposField,
          border: Border.all(
            color: selected ? AppColors.primary : context.picposHairline,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(PhosphorIconsBold.listMagnifyingGlass,
                size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('الحساب المعروض'),
                      style: text.labelSmall
                          ?.copyWith(color: AppColors.textMuted)),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const Icon(PhosphorIconsBold.caretDown,
                size: 14, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: 0.06)
              : Colors.transparent,
          border: Border.all(
              color: active ? AppColors.primary : context.picposHairline),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: active ? AppColors.primary : AppColors.textMuted),
            const SizedBox(width: 8),
            Text(label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: active
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    )),
            const SizedBox(width: 6),
            const Icon(PhosphorIconsBold.caretDown,
                size: 12, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _LedgerHeaderRow extends StatelessWidget {
  const _LedgerHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w800);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.picposField,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        children: [
          SizedBox(width: _wDate, child: Text(tr('التاريخ'), style: style)),
          SizedBox(width: _wNo, child: Text(tr('رقم القيد'), style: style)),
          Expanded(child: Text(tr('البيان'), style: style)),
          SizedBox(width: _wCc, child: Text(tr('مركز التكلفة'), style: style)),
          SizedBox(
              width: _wAmount,
              child: Text(tr('مدين'), style: style, textAlign: TextAlign.end)),
          SizedBox(
              width: _wAmount,
              child: Text(tr('دائن'), style: style, textAlign: TextAlign.end)),
          SizedBox(
              width: _wBalance,
              child: Text(tr('الرصيد'), style: style, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.row,
    required this.fmt,
    required this.dateFmt,
    required this.costCenterName,
  });

  final Map<String, dynamic> row;
  final NumberFormat fmt;
  final DateFormat dateFmt;
  final String costCenterName;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isOpening = row['is_opening'] == true;
    final debit = row['debit'] as double? ?? 0;
    final credit = row['credit'] as double? ?? 0;
    final balance = row['balance'] as double? ?? 0;
    final date = row['entry_date'];
    final dateStr = date is DateTime ? dateFmt.format(date) : '';
    final desc = row['description']?.toString() ?? '';

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isOpening
            ? AppColors.primary.withValues(alpha: 0.06)
            : Colors.transparent,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _wDate,
            child: Text(dateStr,
                style: text.labelMedium
                    ?.copyWith(color: AppColors.textSecondary)),
          ),
          SizedBox(
            width: _wNo,
            child: Text(
              row['entry_number']?.toString() ?? '',
              style: text.labelMedium?.copyWith(
                  color: AppColors.primary, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Tooltip(
              message: desc,
              child: Text(
                desc,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(
                  fontWeight: isOpening ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
            ),
          ),
          SizedBox(
            width: _wCc,
            child: Text(
              costCenterName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelSmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
          SizedBox(
            width: _wAmount,
            child: Text(
              debit > 0 ? fmt.format(debit) : '',
              textAlign: TextAlign.end,
              style: text.labelMedium?.copyWith(
                  color: AppColors.success, fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(
            width: _wAmount,
            child: Text(
              credit > 0 ? fmt.format(credit) : '',
              textAlign: TextAlign.end,
              style: text.labelMedium?.copyWith(
                  color: AppColors.error, fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(
            width: _wBalance,
            child: Text(
              fmt.format(balance),
              textAlign: TextAlign.end,
              style: text.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: balance >= 0 ? context.picposText : AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerTotalsRow extends StatelessWidget {
  const _LedgerTotalsRow({
    required this.count,
    required this.debit,
    required this.credit,
    required this.closing,
  });

  final int count;
  final String debit;
  final String credit;
  final String closing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.picposField,
        border: const Border(
            top: BorderSide(color: AppColors.primary, width: 2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(tr('إجمالي الحركة خلال الفترة · {count} حركة', {'count': count}),
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ),
          SizedBox(
            width: _wAmount,
            child: Text(debit,
                textAlign: TextAlign.end,
                style: text.titleSmall?.copyWith(
                    color: AppColors.success, fontWeight: FontWeight.w800)),
          ),
          SizedBox(
            width: _wAmount,
            child: Text(credit,
                textAlign: TextAlign.end,
                style: text.titleSmall?.copyWith(
                    color: AppColors.error, fontWeight: FontWeight.w800)),
          ),
          SizedBox(
            width: _wBalance,
            child: Text(closing,
                textAlign: TextAlign.end,
                style: text.titleMedium?.copyWith(
                    color: AppColors.primary, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
