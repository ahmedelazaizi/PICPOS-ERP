// مسارُ التنقّل — **تحت شريط التابات**.
//
// القاعدةُ ح‑٢ في `PLAN-REDESIGN-SCREENS.md`، قرارُ المالك 2026-09-18:
// «والمسار يفضل تحت التابات».
//
// ═══ وليس هذا إحياءً لـ`AppBreadcrumbs` ═══
//
// ذاك حُذف في 3.1.4.255 وكان معطَّلاً بثلاثة عيوبٍ لا عيبٍ واحد. وكلُّها
// يُعالَج هنا **بالبنية لا بالضبط**:
//
//   ١ — **قائمةٌ تُدفَع لا تُشتقّ.** `setBreadcrumbs` كان **يستبدل** القائمةَ
//       في كلّ تنقّلٍ لا يُضيف إليها، فما تراكم مسارٌ قطّ — وهو نصُّ بلاغ
//       المالك: «ولا يفتح اكثر من تابين». وهنا المسارُ **دالّةٌ في فهرس
//       الشاشة**: لا مزوِّدَ يُكتَب فيه، فلا حالةَ تفترق عمّا يُعرَض، ولا
//       شاشةَ تنسى أن تدفع مسارَها.
//
//   ٢ — **الوحيدُ الذي يحمل `onTap` هو عينُ الوحيدِ الذي يُلغى.** كان
//       يُرسَم بـ`onTap: isLast ? null : item.onTap`، ورأسُ المجموعة يُبنى
//       بلا `onTap` أصلاً: صفرُ مداخلَ قابلةٍ للنقر تحت مظهرٍ يوحي بالنقر.
//       وهنا **لا يُرسَم أيُّ مظهرِ نقر**، لأنّه لا شيءَ يُنقَر: مجموعةُ
//       القائمة الجانبيّة ليست شاشةً يُنتقَل إليها، والشاشةُ الحاليّةُ أنت
//       فيها. والتنقّلُ فوقَه مباشرةً في `ScreenTabsBar`.
//
//   ٣ — **البيتُ والجرسُ كانا فيه.** انتقلا إلى شريط التابات، فلا يُكرَّران
//       هنا — ولهذا هذا الشريطُ نحيفٌ بسطرٍ واحد.

import 'package:flutter/material.dart';
import '../../core/i18n/tr.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers/auth_providers.dart';

/// مسارُ شاشةٍ كما يُعرَض: مجموعتُها ثمّ اسمُها.
@immutable
class ScreenPath {
  const ScreenPath({
    required this.label,
    this.groupLabel,
    this.groupIcon,
  });

  /// اسمُ الشاشة كما في القائمة الجانبيّة.
  final String label;

  /// اسمُ مجموعتها — `null` حين لا مجموعةَ لها أو حين تُطابق اسمَها.
  final String? groupLabel;

  final IconData? groupIcon;
}

/// يشتقُّ مسارَ [screenIndex] من [kAllNavItemDefs] و[kNavGroupDefs].
///
/// ⚠️ **و`null` حالةٌ حقيقيّةٌ لا احتياطٌ نظريّ.** شاشتان مشحونتان بلا مدخلٍ
/// جانبيٍّ أصلاً — `syncConflicts` و`auditDashboard` — تُبلَغان من حوار
/// المزامنة ومن لوحة التدقيق لا من القائمة. فـ`firstWhere` بلا `orElse`
/// ترمي `StateError` وتُسقط **القشرةَ كلَّها** عند فتح إحداهما، لا الشريطَ
/// وحدَه.
///
/// ⚠️ **ويُشتقُّ من القائمة الكاملة لا من المسموح به.** مداخلُ
/// [kPicPosFoldedIntoAccountingHub] الستّةُ مطويّةٌ عن الشريط الجانبيّ في
/// PicPos وشاشاتُها **ما زالت تُبلَغ** من تبويبات حاوية «الحسابات»؛ فاشتقاقُه
/// من المسموح يترك المسارَ فارغاً في عين الموضع الذي يحتاجه — داخلَ حاويةٍ
/// لا يدلُّ عنوانُها على موضعك. والمعروضُ هنا اسمُ شاشةٍ أنت فيها الآن،
/// فلا يكشف ما لا تراه.
ScreenPath? resolveScreenPath(int screenIndex) {
  NavItemDef? item;
  for (final i in kAllNavItemDefs) {
    if (i.index == screenIndex) {
      item = i;
      break;
    }
  }
  if (item == null) return null;

  NavGroupDef? group;
  for (final g in kNavGroupDefs) {
    if (g.key == item.group) {
      group = g;
      break;
    }
  }

  // ⚠️ مجموعةٌ باسم شاشتها لا تُعرَض مرّتَين: «العملاء والموردين ‹ العملاء
  // والموردين» و«Dashboard ‹ Dashboard» حالتان قائمتان في الجدول لا فرضٌ.
  final showGroup = group != null && group.label != item.label;

  return ScreenPath(
    label: item.label,
    groupLabel: showGroup ? group.label : null,
    groupIcon: showGroup ? group.icon : null,
  );
}

/// شريطُ المسار — سطرٌ نحيفٌ تحت التابات: «المجموعة ‹ الشاشة».
class ScreenBreadcrumbs extends StatelessWidget {
  const ScreenBreadcrumbs({super.key, required this.screenIndex});

  /// فهرسُ الشاشة المعروضة — `AppScreen.value`.
  final int screenIndex;

  @override
  Widget build(BuildContext context) {
    final path = resolveScreenPath(screenIndex);
    if (path == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.28),
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.08),
          ),
        ),
      ),
      // ⚠️ **`Wrap` لا `Row`** — والدرسُ مقيسٌ في هذه الجلسة: ترويسةُ المستند
      // فاضت عند ٤٢٠px وكانت خضراءَ تماماً عند ١٤٠٠. و«المصروفات التشغيلية»
      // تحت «المالية والمحاسبة» أطولُ من ذلك بكثير.
      //
      // وكلُّ فتاتةٍ **طفلٌ مستقلٌّ** في `Wrap` لا داخلَ `Row`: `Wrap` يمنح
      // طفلَه عرضَه الأقصى، فيبتر النصُّ الطويلُ بثلاث نقاطٍ بدل أن يفيض —
      // بينما `Row` يمنح أبناءَه غيرَ المرِنين عرضاً **غيرَ محدود**.
      child: Wrap(
        spacing: 5,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (path.groupLabel case final g?) ...[
            if (path.groupIcon != null)
              Icon(path.groupIcon, size: 12, color: AppColors.textMuted),
            _Crumb(text: g, isCurrent: false),
            const Icon(
              PhosphorIconsBold.caretLeft,
              size: 10,
              color: AppColors.textMuted,
            ),
          ],
          _Crumb(text: path.label, isCurrent: true),
        ],
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({required this.text, required this.isCurrent});

  final String text;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return Text(
      tr(text),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11.5,
        height: 1.2,
        color: isCurrent ? AppColors.primary : AppColors.textMuted,
        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }
}
