import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/number_utils.dart';
import '../../../core/widgets/app_toast.dart';
// `ShiftReportDto` يوصل من providers.dart — ملف الـ DAO نفسه `part of` فمينفعش
// يتعمله import مباشر.
import '../../../data/providers/providers.dart';
import '../../../domain/entities/shift_closing_snapshot.dart';
import '../../../services/printing/shift_closing_print.dart';
import '../../picpos_shell/picpos_content_card.dart';
import 'picpos_cashier_closing_dialog.dart';

/// Past shifts, with the same balances report the cashier saw at close time
/// and a button to print it again.
///
/// Before this the closing report existed exactly once — on the paper that
/// came out of the printer. `ShiftsReportScreen` could show a shift's raw
/// row (expected / actual / variance) but had no reprint at all; its print
/// button was a stub that exported the whole list to Excel.
///
/// Two sources feed the report, and the difference is shown to the user
/// rather than hidden:
///  * **snapshot** — the exact figures printed at close, stored since v151.
///  * **recomputed** — for shifts closed before v151, re-aggregated over the
///    shift's own `[startTime, endTime]` window. The system columns come back
///    faithfully; the *actual* bank/click counts cannot, because they were
///    never stored. Labelled so nobody mistakes it for the original.
class PicposPastShiftsPanel extends ConsumerStatefulWidget {
  const PicposPastShiftsPanel({super.key});

  @override
  ConsumerState<PicposPastShiftsPanel> createState() =>
      _PicposPastShiftsPanelState();
}

class _PicposPastShiftsPanelState
    extends ConsumerState<PicposPastShiftsPanel> {
  static final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );

  bool _loading = true;
  String? _error;
  List<ShiftReportDto> _shifts = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Branch scope is applied in SQL by the repo — a restricted user must
      // not see another branch's shifts even on the first page.
      final scope = await ref.read(branchScopeProvider.future);
      final shifts =
          await ref.read(reportingRepositoryProvider).getShiftsReportPaginated(
                limit: 100,
                startDate: DateTime(
                    _range.start.year, _range.start.month, _range.start.day),
                endDate: DateTime(_range.end.year, _range.end.month,
                    _range.end.day, 23, 59, 59, 999),
                allowedBranchIds:
                    scope.hasFullAccess ? null : scope.allowedBranchIds,
              );
      if (!mounted) return;
      setState(() {
        _shifts = shifts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
      // Locale inherited from the app rather than forced to 'ar' — pinning it
      // here throws if the material localisation delegate for that locale
      // isn't registered, and the app already sets its own.
    );
    if (picked == null) return;
    setState(() => _range = picked);
    await _load();
  }

  /// Resolves the report for [shift], preferring the stored snapshot.
  ///
  /// Returns null when the shift is still open (nothing was closed, so there
  /// is nothing to reproduce).
  Future<({ShiftClosingSnapshot snapshot, bool recomputed})?> _resolveReport(
    ShiftReportDto shift,
  ) async {
    final stored = ShiftClosingSnapshot.tryDecode(shift.closingSnapshot);
    if (stored != null) return (snapshot: stored, recomputed: false);

    final endTime = shift.endTime;
    if (endTime == null) return null;

    // `shiftEnd` is what makes this correct: without it the aggregation runs
    // to the present moment and a shift closed last week would absorb every
    // sale made since.
    final aggregates =
        await ref.read(databaseProvider).getShiftClosingAggregates(
              userId: shift.userId,
              includeAllUsers: false,
              shiftStart: shift.startTime,
              shiftEnd: endTime,
              openingBalance: shift.openingBalance,
              branchId: shift.branchId,
            );

    final actualCash = shift.actualCash ?? 0;
    return (
      // كل سطر تحت مطابق حرفياً للـ getter المقابل في `PosClosingState`،
      // عشان الوردية المعاد احتسابها تتقرا بنفس تعريف الوردية الحيّة. أي
      // اختلاف هنا معناه ورقتين بنفس العنوان وأرقام مختلفة.
      snapshot: ShiftClosingSnapshot(
        invoiceCount: aggregates.salesCount + aggregates.returnsCount,
        totalSales: aggregates.salesCash +
            aggregates.salesBank +
            aggregates.salesClick +
            aggregates.salesCredit,
        systemCash: aggregates.systemCash,
        systemCard: aggregates.systemBank,
        systemClick: aggregates.systemClick,
        actualCash: actualCash,
        // Never stored before v151 — reported as 0 rather than invented.
        actualCard: 0,
        actualClick: 0,
        cashVariance: actualCash - aggregates.systemCash,
        cardVariance: 0,
        clickVariance: 0,
        totalVariance: shift.variance ?? (actualCash - aggregates.systemCash),
        totalExpenses: aggregates.expensesCash +
            aggregates.expensesBank +
            aggregates.expensesClick,
        cashRefunds: aggregates.returnsCash,
        // `cashIncome` في تقرير الإغلاق معناه مبيعات النقد، مش سندات القبض.
        cashIncome: aggregates.salesCash,
        creditSales: aggregates.salesCredit,
        creditSalesCount: aggregates.salesCreditCount,
        openingBalance: aggregates.openingBalance,
        employeeName: shift.userName,
        closedAt: endTime,
      ),
      recomputed: true,
    );
  }

  Future<void> _openShiftReport(ShiftReportDto shift) async {
    final resolved = await _resolveReport(shift);
    if (!mounted) return;

    if (resolved == null) {
      // Open shift — offer to close it instead of showing an empty report.
      await showDialog<void>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(tr('وردية #{p0} لسه مفتوحة', {'p0': shift.id})),
            content:  Text(
              tr('الوردية دي لسه ما اتقفلتش، فمفيش تقرير أرصدة ليها. تحب تقفلها دلوقتي؟'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:  Text(tr('إغلاق')),
              ),
              ElevatedButton.icon(
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () {
                  Navigator.pop(ctx);
                  PicposCashierClosingDialog.show(context);
                },
                icon: const Icon(PhosphorIconsBold.lockKey, size: 16),
                label:  Text(tr('إغلاق الوردية')),
              ),
            ],
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _ShiftReportDialog(
        shift: shift,
        snapshot: resolved.snapshot,
        recomputed: resolved.recomputed,
        onReprint: () => _reprint(resolved.snapshot),
      ),
    );
  }

  Future<void> _reprint(ShiftClosingSnapshot snapshot) async {
    try {
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final fontScale = double.tryParse(
              await settingsRepo.getSetting('closing_report_font_scale') ??
                  '') ??
          1.0;
      await printShiftClosingSnapshot(
        snapshot: snapshot,
        fontScale: fontScale,
        printersRepo: ref.read(printersRepositoryProvider),
        // إعادةُ الطباعة تمرّ بنفس المسار فتحترم القالبَ كذلك — وإلا
        // اختلفت النسخةُ المعادة عن الأصلية.
        db: ref.read(databaseProvider),
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, tr('تعذّرت الطباعة: {e}', {'e': e}), type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(PhosphorIconsBold.calendarBlank, size: 16),
                label: Text(
                  '${_dateFormat.format(_range.start).split(' ').first}'
                  '  ←  '
                  '${_dateFormat.format(_range.end).split(' ').first}',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 18),
              tooltip: tr('تحديث'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          _Notice(
            icon: PhosphorIconsBold.warningCircle,
            color: AppColors.error,
            text: tr('تعذّر تحميل الورديات: {_error}', {'_error': _error}),
          )
        else if (_shifts.isEmpty)
           _Notice(
            icon: PhosphorIconsBold.calendarX,
            color: AppColors.textMuted,
            text: tr('لا توجد ورديات في الفترة المحددة'),
          )
        else
          PicPosContentCard(
            child: Column(
              children: [
                for (var i = 0; i < _shifts.length; i++)
                  _ShiftTile(
                    shift: _shifts[i],
                    isEven: i.isEven,
                    onTap: () => _openShiftReport(_shifts[i]),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _Notice({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(icon, size: 34, color: color),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ShiftTile extends StatelessWidget {
  final ShiftReportDto shift;
  final bool isEven;
  final VoidCallback onTap;

  const _ShiftTile({
    required this.shift,
    required this.isEven,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOpen = shift.status != 'closed';
    final variance = shift.variance ?? 0;
    final fmt = DateFormat('yyyy-MM-dd HH:mm');

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        color: isEven ? AppColors.card : AppColors.surface,
        child: Row(
          children: [
            Container(
              width: 40,
              alignment: Alignment.center,
              child: Text(
                '#${shift.id}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shift.userName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${fmt.format(shift.startTime)}'
                    '${shift.endTime != null ? '  ←  ${fmt.format(shift.endTime!)}' : ''}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            if (isOpen)
               _Pill(text: tr('مفتوحة'), color: AppColors.warning)
            else if (variance.abs() > 0.01)
              _Pill(
                text: tr('فرق {p0}', {'p0': NumberUtils.formatCurrency(variance)}),
                color: variance < 0 ? AppColors.error : AppColors.info,
              )
            else
               _Pill(text: tr('مطابقة'), color: AppColors.success),
            const SizedBox(width: 8),
            // Signals up front whether opening this row yields the original
            // paper or a reconstruction, before the user commits to a tap.
            if (!isOpen && shift.closingSnapshot == null)
               Tooltip(
                message: tr('بدون لقطة أصلية — التقرير هيتعاد احتسابه'),
                child: const Icon(PhosphorIconsBold.arrowsClockwise,
                    size: 13, color: AppColors.textMuted),
              ),
            const SizedBox(width: 6),
            const Icon(PhosphorIconsBold.caretLeft,
                size: 14, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;

  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

/// The balances report itself — the same three-channel reconciliation the
/// cashier reviewed at close time, plus a reprint button.
class _ShiftReportDialog extends StatelessWidget {
  final ShiftReportDto shift;
  final ShiftClosingSnapshot snapshot;
  final bool recomputed;
  final Future<void> Function() onReprint;

  const _ShiftReportDialog({
    required this.shift,
    required this.snapshot,
    required this.recomputed,
    required this.onReprint,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.receipt,
                size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('تقرير وردية #{p0}', {'p0': shift.id}))),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (recomputed)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.4)),
                    ),
                    child:  Row(
                      children: [
                        const Icon(PhosphorIconsBold.warningCircle,
                            size: 16, color: AppColors.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr('معاد احتسابه — بدون لقطة أصلية. الوردية دي اتقفلت قبل حفظ لقطة الإغلاق، فالمبالغ الفعلية للبطاقة وكليك غير متاحة.'),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: context.picposField,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 8,
                    children: [
                      _Meta(label: tr('الكاشير'), value: shift.userName),
                      _Meta(
                          label: tr('البداية'),
                          value: fmt.format(shift.startTime)),
                      _Meta(
                        label: tr('النهاية'),
                        value: shift.endTime != null
                            ? fmt.format(shift.endTime!)
                            : '—',
                      ),
                      _Meta(
                        label: tr('عدد الفواتير'),
                        value: '${snapshot.invoiceCount}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                 _SectionLabel(tr('الحركة')),
                _Row(tr('الرصيد الافتتاحي'), snapshot.openingBalance),
                // الآجلُ تحت الإجمالي مباشرةً و«منها» تربطه به — بعيداً عنه
                // كان يُقرأ بنداً مستقلاً فيُجمع مرّتين. ونفسُ الترتيب على
                // الورقة كي لا تفترق الشاشةُ عن المطبوع.
                _Row(tr('إجمالي المبيعات (شامل الآجل)'), snapshot.totalSales),
                _Row(
                  tr('منها آجل — خارج التسوية ({p0})', {'p0': snapshot.creditSalesCount}),
                  snapshot.creditSales,
                ),
                _Row(tr('دخل النقد'), snapshot.cashIncome),
                _Row(tr('المصروفات'), snapshot.totalExpenses),
                _Row(tr('المرتجعات'), snapshot.cashRefunds),
                const SizedBox(height: 16),
                 _SectionLabel(tr('تفاصيل التسوية')),
                const _ReconHeader(),
                _ReconRow(
                  label: tr('النقد'),
                  system: snapshot.systemCash,
                  actual: snapshot.actualCash,
                  variance: snapshot.cashVariance,
                ),
                _ReconRow(
                  label: tr('البطاقة'),
                  system: snapshot.systemCard,
                  actual: snapshot.actualCard,
                  variance: snapshot.cardVariance,
                  unavailable: recomputed,
                ),
                _ReconRow(
                  label: tr('كليك'),
                  system: snapshot.systemClick,
                  actual: snapshot.actualClick,
                  variance: snapshot.clickVariance,
                  unavailable: recomputed,
                ),
                const Divider(height: 22),
                _Row(
                  tr('إجمالي الفارق'),
                  snapshot.totalVariance,
                  emphasize: true,
                  color: snapshot.totalVariance.abs() < 0.01
                      ? AppColors.success
                      : (snapshot.totalVariance < 0
                          ? AppColors.error
                          : AppColors.info),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: onReprint,
            icon: const Icon(PhosphorIconsBold.printer, size: 16),
            label:  Text(tr('إعادة الطباعة')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text(tr('إغلاق')),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final String label;
  final String value;

  const _Meta({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(value,
            style:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final double value;
  final bool emphasize;
  final Color? color;

  const _Row(this.label, this.value, {this.emphasize = false, this.color});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: emphasize ? 14 : 12.5,
      fontWeight: emphasize ? FontWeight.bold : FontWeight.w500,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(NumberUtils.formatCurrency(value), style: style),
        ],
      ),
    );
  }
}

class _ReconHeader extends StatelessWidget {
  const _ReconHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
        fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted);
    return  Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(tr('القناة'), style: style)),
          Expanded(
              flex: 3,
              child: Text(tr('النظام'), style: style, textAlign: TextAlign.end)),
          Expanded(
              flex: 3,
              child: Text(tr('الفعلي'), style: style, textAlign: TextAlign.end)),
          Expanded(
              flex: 3,
              child: Text(tr('الفارق'), style: style, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

class _ReconRow extends StatelessWidget {
  final String label;
  final double system;
  final double actual;
  final double variance;

  /// True when the actual count for this channel was never persisted (a
  /// pre-v151 shift). Shows «—» instead of a misleading 0.00.
  final bool unavailable;

  const _ReconRow({
    required this.label,
    required this.system,
    required this.actual,
    required this.variance,
    this.unavailable = false,
  });

  @override
  Widget build(BuildContext context) {
    const cell = TextStyle(fontSize: 12);
    final varianceColor = unavailable
        ? AppColors.textMuted
        : (variance.abs() < 0.01
            ? AppColors.success
            : (variance < 0 ? AppColors.error : AppColors.info));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            flex: 3,
            child: Text(NumberUtils.formatCurrency(system),
                style: cell, textAlign: TextAlign.end),
          ),
          Expanded(
            flex: 3,
            child: Text(
              unavailable ? '—' : NumberUtils.formatCurrency(actual),
              style: cell,
              textAlign: TextAlign.end,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              unavailable ? '—' : NumberUtils.formatCurrency(variance),
              style: cell.copyWith(
                  color: varianceColor, fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
