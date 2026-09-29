import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../domain/models/table_actions.dart';

/// نصوصُ الكبسات — نصُّ المواصفة حرفياً، بترتيب [TableAction].
Map<TableAction, String> get tableActionLabels => {
  TableAction.open: tr('فتح طاولة'),
  TableAction.addItems: tr('إضافة طلب'),
  TableAction.transfer: tr('نقل الطلب'),
  TableAction.merge: tr('دمج الطاولات'),
  TableAction.splitBill: tr('تقسيم الفاتورة'),
  TableAction.printBill: tr('طباعة الفاتورة'),
  TableAction.reserve: tr('حجز طاولة'),
  TableAction.pay: tr('الدفع'),
  TableAction.changeStatus: tr('تغيير الحالة'),
  TableAction.cancelOrder: tr('إلغاء الطلب'),
  TableAction.closeTable: tr('إغلاق الطاولة'),
  TableAction.log: tr('سجل الطاولة'),
};

IconData tableActionIcon(TableAction action) {
  switch (action) {
    case TableAction.open:
      return PhosphorIconsBold.doorOpen;
    case TableAction.addItems:
      return PhosphorIconsBold.plus;
    case TableAction.transfer:
      return PhosphorIconsBold.arrowsLeftRight;
    case TableAction.merge:
      return PhosphorIconsBold.intersect;
    case TableAction.splitBill:
      return PhosphorIconsBold.columns;
    case TableAction.printBill:
      return PhosphorIconsBold.printer;
    case TableAction.reserve:
      return PhosphorIconsBold.calendarPlus;
    case TableAction.pay:
      return PhosphorIconsBold.currencyCircleDollar;
    case TableAction.changeStatus:
      return PhosphorIconsBold.arrowsClockwise;
    case TableAction.cancelOrder:
      return PhosphorIconsBold.xCircle;
    case TableAction.closeTable:
      return PhosphorIconsBold.checkCircle;
    case TableAction.log:
      return PhosphorIconsBold.clockCounterClockwise;
  }
}

/// لونُ الكبسة. `cancelOrder` وحدَه بلون الخطر — يهدم طلباً حياً. أما
/// `closeTable` فروتينٌ: الحسابُ سُدِّد، والطاولةُ تحتاج تحريراً لا غير.
Color tableActionColor(TableAction action) {
  switch (action) {
    case TableAction.open:
      return AppColors.success;
    case TableAction.addItems:
      return AppColors.info;
    case TableAction.transfer:
      return AppColors.booking;
    case TableAction.merge:
      return AppColors.warning;
    case TableAction.splitBill:
      return const Color(0xFF06B6D4);
    case TableAction.printBill:
      return const Color(0xFF64748B);
    case TableAction.reserve:
      return Colors.orange;
    case TableAction.pay:
      return AppColors.success;
    case TableAction.changeStatus:
      return const Color(0xFF6366F1);
    case TableAction.cancelOrder:
      return AppColors.error;
    case TableAction.closeTable:
      return const Color(0xFF0EA5E9);
    case TableAction.log:
      return AppColors.textMuted;
  }
}

/// الهدمُ يُميَّز بالشكل لا باللون وحده: كبسةٌ ممتلئةٌ بين كبساتٍ محدَّدةٍ
/// بإطار. «إلغاء الطلب» يمحو طلباً حيّاً، و«إغلاق الطاولة» روتينٌ بعد
/// سدادٍ كامل — جمعُهما في شكلٍ واحدٍ يجعل النادلَ يمحو طلباً وهو يظنّ
/// أنه ينظّف طاولة.
bool isDestructiveTableAction(TableAction action) =>
    action == TableAction.cancelOrder;

/// قائمةُ كبسات الطاولة — مشتقّةٌ من [actionsForStatus] لا من شروطٍ
/// متناثرة.
///
/// ودجتٌ مستقلّةٌ بلا مستودعٍ ولا `ref`: شاشةُ الطاولات لا تُركَّب في
/// اختبارات الويدجت (تتعلّق على مؤقّت drift عند إغلاق القاعدة)، فلو بقيت
/// هذه القائمةُ داخل حالتها لبقيت بلا اختبارٍ إلى الأبد — وهي بالضبط ما
/// يقرّر أيَّ فعلٍ يُعرَض لأيّ حالة.
class TableActionsMenu extends StatelessWidget {
  const TableActionsMenu({
    super.key,
    required this.status,
    required this.onSelected,
  });

  /// حالةُ الطاولة كما هي مخزَّنةٌ (`available` / `occupied` / `paid` / …).
  final String status;

  final ValueChanged<TableAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in actionsForStatus(status)) ...[
          TableActionButton(
            action: action,
            onPressed: () => onSelected(action),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class TableActionButton extends StatelessWidget {
  const TableActionButton({
    super.key,
    required this.action,
    required this.onPressed,
  });

  final TableAction action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = tableActionLabels[action]!;
    final icon = tableActionIcon(action);
    final color = tableActionColor(action);

    return SizedBox(
      width: double.infinity,
      child: isDestructiveTableAction(action)
          ? ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(label),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18, color: color),
              label: Text(label, style: TextStyle(color: color)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: color),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
    );
  }
}
