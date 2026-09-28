// لوحُ المرتجعات المشترك — عدّاداتٌ فوق، وقائمةُ فواتيرَ في بطاقةٍ واحدةٍ
// تحمل رأسَها وترشيحَها، على تصميم `isReturns`.
//
// مكانُه `picpos_shell` لأن **توأمَين** يستعملانه: `sales_returns_picpos`
// و`purchase_returns_picpos`. وهما اليوم يرسمان نفسَ القائمة بنسختَين
// متطابقتَين تقريباً (‏`Card` + `ListTile` + `CircleAvatar`) — وهذا بالضبط
// نوعُ الازدواجِ الذي ينحرف بأوّل تعديل.
//
// ولا يعرف هذا الملفُّ القاعدةَ ولا Riverpod: يستقبل
// [PicPosReturnInvoiceRow] الخالص وردودَ نداء. فيُختبَر بلا مزوِّدٍ ولا قاعدة.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/models/picpos_return_view.dart';
import 'picpos_kpi_row.dart';

/// لونُ النصِّ الخافت — يُعاد تصديرُه باسمٍ محلّيٍّ كي لا تتغيّر مواضعُ
/// الاستعمال في شاشتَي المرتجعات.
Color picposReturnsMuted(BuildContext context) => picposMuted(context);

/// لونُ شارةِ الحالة — منقولٌ حرفيّاً عن `_getStatusColor` في شاشة مرتجع
/// المبيعات، فلا تختلف دلالةُ اللون بين الشاشتين.
Color picposReturnStatusColor(PicPosReturnStatus s) {
  switch (s) {
    case PicPosReturnStatus.completed:
      return AppColors.success;
    case PicPosReturnStatus.returned:
      return AppColors.error;
    case PicPosReturnStatus.partialReturn:
      return Colors.orange;
    case PicPosReturnStatus.voided:
      return Colors.grey;
    case PicPosReturnStatus.pending:
      return AppColors.warning;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// العدّادات
// ═══════════════════════════════════════════════════════════════════════════

/// صفُّ العدّاداتِ الأربعة.
///
/// البطاقةُ نفسُها مشتركةٌ في [PicPosKpiRow]؛ هذا الصنفُ يختار **ما يُعدّ**.
///
/// [isSales] محفوظٌ في العقد ولا يقلب اليومَ تسميةً: العدّاداتُ الأربعةُ تصف
/// **الفواتيرَ في المدى** لا المرتجعاتِ نفسَها، ووصفُها واحدٌ في الشاشتين.
/// ويبقى الوسيطُ لأن الشاشتين تمرّرانه أصلاً، ولأنّ أوّلَ عدّادٍ يختلف بينهما
/// (‏قيمةُ المرتجعات حين تحملها الحالة) سيحتاجه.
class PicPosReturnsSummaryCards extends StatelessWidget {
  const PicPosReturnsSummaryCards({
    super.key,
    required this.kpis,
    required this.isSales,
  });

  final PicPosReturnKpis kpis;
  final bool isSales;

  @override
  Widget build(BuildContext context) {
    return PicPosKpiRow(
      kpis: [
        PicPosKpi(
          label: 'فواتير الفترة',
          value: '${kpis.invoiceCount}',
          icon: PhosphorIconsBold.receipt,
          tint: AppColors.primary,
        ),
        PicPosKpi(
          label: 'إجمالي فواتير الفترة',
          value: kpis.invoicesTotalLabel,
          icon: PhosphorIconsBold.coins,
          tint: AppColors.info,
        ),
        PicPosKpi(
          label: 'مرتجعة كليّاً',
          value: '${kpis.fullyReturned}',
          icon: PhosphorIconsBold.arrowUUpLeft,
          tint: AppColors.error,
        ),
        PicPosKpi(
          label: 'مرتجعة جزئيّاً',
          value: '${kpis.partiallyReturned}',
          icon: PhosphorIconsBold.arrowsClockwise,
          tint: Colors.orange,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// قائمةُ الفواتير
// ═══════════════════════════════════════════════════════════════════════════

/// صفُّ فاتورةٍ مضغوطٌ — بدل `Card` + `ListTile` + `CircleAvatar`.
class PicPosReturnInvoiceTile extends StatelessWidget {
  const PicPosReturnInvoiceTile({
    super.key,
    required this.row,
    required this.selected,
    required this.onTap,
  });

  final PicPosReturnInvoiceRow row;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = picposReturnsMuted(context);
    final statusColor = picposReturnStatusColor(row.status);

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: .10)
                  : Colors.transparent,
              border: Border.all(
                color: selected ? AppColors.primary : theme.dividerColor,
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary
                        : theme.scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    PhosphorIconsBold.receipt,
                    size: 15,
                    color: selected ? Colors.white : AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        row.number,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: selected
                              ? AppColors.primary
                              : theme.textTheme.bodyLarge?.color,
                          fontFeatures: const [
                            ui.FontFeature.tabularFigures()
                          ],
                        ),
                      ),
                      Text(
                        row.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      row.totalLabel,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: theme.textTheme.bodyMedium?.color,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        row.status.label,
                        style: TextStyle(fontSize: 9.5, color: statusColor),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// بطاقةُ القائمة كاملةً: رأسٌ بعدّاد، ثمّ شريطُ ترشيحٍ يُمرَّر من الشاشة،
/// ثمّ الصفوف.
///
/// [filters] يُمرَّر لا يُبنى هنا: شاشةُ المبيعات ترشّح في الذاكرة وشاشةُ
/// المشتريات في SQL ولها منتقي مورّدٍ إضافيّ — فبناءُ الشريط هنا كان سيجبر
/// إحداهما على سلوكِ الأخرى.
class PicPosReturnsInvoicePanel extends StatelessWidget {
  const PicPosReturnsInvoicePanel({
    super.key,
    required this.rows,
    required this.selectedId,
    required this.onSelect,
    required this.filters,
    this.isLoading = false,
    this.emptyMessage = 'لا توجد فواتير في هذه الفترة',
  });

  final List<PicPosReturnInvoiceRow> rows;
  final int? selectedId;
  final ValueChanged<PicPosReturnInvoiceRow> onSelect;
  final Widget filters;
  final bool isLoading;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = picposReturnsMuted(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              border: Border(
                bottom: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Row(
              children: [
                const Icon(PhosphorIconsBold.listDashes,
                    size: 14, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'الفواتير',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
                const Spacer(),
                Text(
                  '${rows.length}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: muted,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: filters,
          ),
          Expanded(
            child: isLoading && rows.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? _empty(context, muted)
                    : ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, i) => PicPosReturnInvoiceTile(
                          key: ValueKey(rows[i].id),
                          row: rows[i],
                          selected: rows[i].id == selectedId,
                          onTap: () => onSelect(rows[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, Color muted) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIconsBold.receipt,
                  size: 48, color: muted.withValues(alpha: .4)),
              const SizedBox(height: 12),
              Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
      );
}
