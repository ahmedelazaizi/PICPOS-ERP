import 'package:flutter/material.dart';

import '../../../core/design_system/spacing.dart';
import '../../../domain/models/table_actions.dart';
import '../../screens/tables/widgets/table_actions_menu.dart';
import '../../widgets/permission_guard.dart';

/// أفعالُ الشريط بترتيب صورة المالك — ثمانيةٌ من اثنتي عشرة.
///
/// الأربعُ الباقيةُ لا تُحذَف: «إضافة طلب» و«الدفع» فعلُهما الطبيعيُّ داخل
/// نافذة الطلب، و«إلغاء الطلب» و«سجل الطاولة» تبقيان في القائمة المنبثقة.
/// وشريطٌ من اثني عشر زرّاً يطول أطولَ من الخريطة.
const List<TableAction> railActions = [
  TableAction.open,
  TableAction.transfer,
  TableAction.merge,
  TableAction.splitBill,
  TableAction.printBill,
  TableAction.changeStatus,
  TableAction.reserve,
  TableAction.closeTable,
];

/// شريطُ الأفعال — يظهر كاملاً دائماً، ويُعطَّل ما لا يصلح.
///
/// **الأزرارُ تُعطَّل ولا تختفي**: شريطٌ يتغيّر طولُه مع كلِّ اختيارٍ يُربك،
/// والاختفاءُ يخفي عن المستخدم أن الفعلَ موجودٌ أصلاً — نفسُ قرار
/// `settings_permission_tiles.dart:187`.
///
/// ومصدرُ «أيُّ فعلٍ يصلح لأيّ حالة» هو [actionsForStatus] نفسُها التي تقودُ
/// القائمةَ المنبثقة، لا نسخةٌ منها: محرّكا صلاحيّةٍ يتباعدان هما علّةُ هذا
/// المستودع المعروفة.
///
/// كلُّ زرٍّ مغلَّفٌ بـ[PermissionGuard]`(showDisabled: true)` — التعطيلُ
/// هنا ثنائيُّ المصدر: صلاحيّةٌ غائبةٌ **أو** فعلٌ لا يصلح لحالة الطاولة
/// الحاليّة (أو لا طاولةَ مختارة أصلاً). `showDisabled: true` معناه أن
/// الحارس يُعطِّل الابنَ بدل أن يُخفيه — تحقّقتُ من ذلك بقراءة
/// `permission_guard.dart` (`_buildDisabledChild`، الأسطر ٢٦٧-٣٠٤): لكلّ
/// نوع زرٍّ معروفٍ (ومنها `OutlinedButton` المستعمَل هنا) يُعاد بناؤه بنفس
/// الشكل والنصّ و`onPressed: null` — لا `SizedBox.shrink()`.
class TablesActionRail extends StatelessWidget {
  const TablesActionRail({
    super.key,
    required this.tableStatus,
    required this.onAction,
  });

  /// حالةُ الطاولة المختارة — `null` يعني لا طاولةَ مختارة.
  final String? tableStatus;
  final ValueChanged<TableAction> onAction;

  @override
  Widget build(BuildContext context) {
    final allowed = tableStatus == null
        ? const <TableAction>[]
        : actionsForStatus(tableStatus!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `railActions` لا يحوي `log` — الفعلَ الوحيدَ بلا صلاحيّة — لكنّ
        // `!` تجعل ذلك عقداً ضمنيّاً ينكسر صامتاً لو أُضيف فعلٌ بلا كود.
        // فالقراءةُ صريحةٌ والتخطّي مكتوب.
        for (final action in railActions)
          if (permissionForAction(action) case final code?)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: PermissionGuard(
                permission: code,
                showDisabled: true,
                actionName: tableActionLabels[action],
                child: _RailButton(
                  action: action,
                  enabled: allowed.contains(action),
                  onTap: () => onAction(action),
                ),
              ),
            ),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.action,
    required this.enabled,
    required this.onTap,
  });

  final TableAction action;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(tableActionIcon(action), size: 18),
      label: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(tableActionLabels[action]!),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: tableActionColor(action),
        alignment: AlignmentDirectional.centerStart,
      ),
    );
  }
}
