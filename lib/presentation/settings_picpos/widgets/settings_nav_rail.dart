import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/license_service.dart';
import '../../picpos_shell/picpos_surface.dart';

/// ترتيبُ مجموعات عمود الإعدادات كما في التصميم.
List<String> get kSettingsGroupOrder => <String>[
  tr('التشغيل'),
  tr('الأمان'),
  tr('الربط'),
  tr('المال والبيانات'),
  tr('الامتدادات'),
];

/// ما يحتاجه العمودُ من القسم — دون `children` ولا `keywords`.
///
/// مفصولٌ عن `_SettingsSection` عمداً: بناءُ أولاد القسم يستدعي عشراتِ
/// المزوِّدات وقاعدةَ البيانات، والعمودُ لا يحتاج منها شيئاً. فهذا ما يجعله
/// **قابلاً للقياس وحدَه** — نفسُ سببِ فصل `SettingsSectionPane`.
class SettingsNavRailItem {
  const SettingsNavRailItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.group,
    required this.desc,
    this.count,
  });

  final String id;
  final String title;
  final IconData icon;
  final String group;
  final String desc;

  /// عددُ الإعدادات الظاهرة في القسم — يُقاس بـ`countVisibleSettings` ولا
  /// يُكتَب بيد. `null` ⇒ لا شارة.
  final int? count;
}

/// عمودُ أقسام الإعدادات (RTL) — على تصميم `PicPos-Settings`.
///
/// ‏٣٢٦px كما في `grid-template-columns:326px 1fr`: بحثٌ أعلاه، ثمّ الأقسامُ
/// في مجموعاتها، ثمّ تذييلٌ بالنسخة وحالةِ الترخيص.
///
/// ═══ عدّادُ القسم ═══
///
/// التصميمُ يعرض رقماً لكلِّ قسمٍ (‏١٤ · ١٢ · ١١ …) ومجموعَه ٩٤. وقد قِيس
/// 2026-08-25 أنّ تلك أرقامُ **نموذجٍ** لا تقابل شيئاً: حوارُ «البيع السريع»
/// وحدَه فيه ٦٣ مفتاحاً والتصميمُ يكتب بجانبه «١١».
///
/// فالرقمُ هنا **مقيسٌ من الشجرة** عبر `countVisibleSettings` — عددُ ما
/// يُعرَض فعلاً في القسم (‏قرارُ المالك 2026-08-25). لا يمكنه أن يبطُل: يرتفع
/// بإضافة صفٍّ وينزل بحذفه بلا تدخّل.
///
/// و[count] `null` ⇒ لا شارة. يقيسه `settings_count_test`.
class SettingsNavRail extends StatelessWidget {
  const SettingsNavRail({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onSelect,
    required this.search,
  });

  final List<SettingsNavRailItem> items;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final Widget search;

  @override
  Widget build(BuildContext context) {
    // المجموعاتُ بترتيب التصميم، ثمّ أيُّ مجموعةٍ مستجدّةٍ خلفها — فلا يختفي
    // قسمٌ لأنّ مجموعتَه لم تُذكر في قائمة الترتيب.
    final groups = <String>{
      ...kSettingsGroupOrder.where((g) => items.any((s) => s.group == g)),
      ...items.map((s) => s.group).where((g) => !kSettingsGroupOrder.contains(g)),
    }.toList();

    return Container(
      width: 326,
      decoration: BoxDecoration(
        color: context.picposCard,
        border: BorderDirectional(start: BorderSide(color: context.picposHairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 12),
            child: search,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 16),
              children: [
                for (final group in groups) ...[
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(8, 12, 8, 6),
                    child: Text(
                      group,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                    ),
                  ),
                  for (final s in items.where((s) => s.group == group))
                    _NavItem(
                      item: s,
                      selected: s.id == selectedId,
                      onTap: () => onSelect(s.id),
                    ),
                ],
              ],
            ),
          ),
          const SettingsRailFooter(),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final SettingsNavRailItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.30)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : context.picposField,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  item.icon,
                  size: 18,
                  color: selected ? AppColors.primary : AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge?.copyWith(
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected ? AppColors.primary : null,
                      ),
                    ),
                    Text(
                      item.desc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall
                          ?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              // شارةُ العدد — على أوّل الصفّ (يسارُه في RTL) كما في التصميم.
              // مقيسةٌ لا مكتوبة؛ انظر توثيقَ `SettingsNavRailItem.count`.
              if (item.count != null) ...[
                const SizedBox(width: 8),
                Text(
                  '${item.count}',
                  style: text.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color:
                        selected ? AppColors.primary : AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// تذييلُ العمود: النسخةُ وحالةُ الترخيص.
///
/// ⚠️ النسخةُ من [AppConstants.appVersion] لا نصّاً ثابتاً — بلاغُ المالك
/// 2026-08-22 كان على رقمِ إصدارٍ مكتوبٍ بيدٍ لا يتحرّك مهما تغيّرت النسخة.
/// والترخيصُ من `activationStatusProvider` الحيّ، فلا يُعرض «مرخّصة» لجهازٍ
/// غيرِ مفعَّل.
class SettingsRailFooter extends ConsumerWidget {
  const SettingsRailFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final activated = ref.watch(activationStatusProvider);

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 14, 18, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        children: [
          Icon(
            activated.value == true
                ? PhosphorIconsBold.sealCheck
                : PhosphorIconsBold.seal,
            size: 18,
            color: activated.value == true
                ? AppColors.success
                : AppColors.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('النسخة {p0}', {'p0': AppConstants.appVersion}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  switch (activated.value) {
                    true => tr('مرخّصة'),
                    false => tr('غير مفعّلة'),
                    null => '…',
                  },
                  style: text.labelSmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
