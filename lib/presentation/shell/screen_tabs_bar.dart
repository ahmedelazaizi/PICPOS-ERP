import 'package:ural_erp/core/i18n/tr.dart';
// lib/presentation/shell/screen_tabs_bar.dart
//
// شريطُ تابات الشاشات — بلاغُ المالك 2026-09-12: «لو خلينا الشاشات فعلا
// تفتح فى تابات ويتم التنقل من الاعلى حرفيا بينهم هيكون افضل بكتير».
//
// ⚠️ **ويحلُّ محلَّ `AppBreadcrumbs` الخاملِ تماماً.** ذاك كان يعرض مدخلاً
// أو مدخلَين — لأنّ `setBreadcrumbs` **يستبدل** القائمةَ في كلّ تنقّل، وهو
// نصُّ البلاغ «ولا يفتح اكثر من تابين» — وصفرَ مداخلَ قابلةٍ للنقر: رأسُ
// المجموعة يُبنى بلا `onTap`، والمدخلُ الثاني يُبنى بـ`onTap` ثمّ يُرسَم
// بـ`onTap: isLast ? null : item.onTap`. فالوحيدُ الذي يحمل ردَّ فعلٍ هو
// عينُ الوحيدِ الذي يُلغى ردُّ فعله.
//
// ⚠️ **وجرسُ التنبيهات كان ساكناً في `AppBreadcrumbs`.** فاستبدالُ الشريط
// بلا نقلِ الجرس كان يُسقط كلَّ تنبيهات النظام من الواجهة — ميزةٌ تموت
// صامتةً بلا أن يشتكيَ أحدٌ إلّا متأخّراً.

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../widgets/notifications/notification_bell.dart';

/// ما يحتاجه الشريطُ لرسم تابٍ واحد.
@immutable
class ScreenTabView {
  /// فهرسُ الشاشة — `AppScreen.value`.
  final int index;
  final String label;
  final IconData icon;

  /// هل يُسمَح بإغلاقه؟ التابُ الوحيدُ لا يُغلَق.
  final bool closable;

  const ScreenTabView({
    required this.index,
    required this.label,
    required this.icon,
    this.closable = true,
  });
}

class ScreenTabsBar extends StatelessWidget {
  final List<ScreenTabView> tabs;

  /// فهرسُ الشاشة المعروضة.
  final int active;

  final void Function(int screenIndex) onSelect;
  final void Function(int screenIndex) onClose;

  /// الانتقالُ إلى الشاشة الأولى — كان زرَّ «البيت» في فتات الخبز.
  final VoidCallback? onHome;

  const ScreenTabsBar({
    super.key,
    required this.tabs,
    required this.active,
    required this.onSelect,
    required this.onClose,
    this.onHome,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 6),
          if (onHome != null)
            IconButton(
              onPressed: onHome,
              icon: const Icon(PhosphorIconsBold.house, size: 15),
              color: AppColors.textMuted,
              splashRadius: 15,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: tr('الشاشة الأولى'),
            ),
          Expanded(
            // ⚠️ **والتمريرُ لازمٌ لا تحسين**: ثمانيةُ تابات بعناوينَ عربيّةٍ
            // تتجاوز عرضَ النافذة على شاشةٍ ١٣٦٦، و`Row` بلا تمريرٍ يرمي
            // بتراً في زمن التشغيل لا يراه أحدٌ إلّا في السجلّ.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final t in tabs)
                    _Tab(
                      tab: t,
                      isActive: t.index == active,
                      onSelect: () => onSelect(t.index),
                      onClose: () => onClose(t.index),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          const NotificationBell(),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  final ScreenTabView tab;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  const _Tab({
    required this.tab,
    required this.isActive,
    required this.onSelect,
    required this.onClose,
  });

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;
    final theme = Theme.of(context);
    // ⚠️ حبرُ التاب الخامل يُقرأ من الثيم لا من ثابتٍ فاتح: هذا الشريطُ في
    // منطقة المحتوى لا في الشريط الجانبيّ، فيتبع الوضعَ الغامق.
    final idleInk =
        theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.75) ??
            AppColors.textMuted;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onSelect,
        child: Container(
          height: 38,
          constraints: const BoxConstraints(maxWidth: 190),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary.withValues(alpha: 0.12)
                : _hovered
                    ? theme.dividerColor.withValues(alpha: 0.12)
                    : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: active ? AppColors.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.tab.icon,
                size: 14,
                color: active ? AppColors.primary : idleInk,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.tab.label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    color: active ? AppColors.primary : idleInk,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              // ⚠️ **وموضعُ الزرّ محفوظٌ دائماً.** إظهارُه بالتمرير وحدَه
              // كان يُزحزح العنوانَ فيقع النقرُ على تابٍ مجاور.
              SizedBox(
                width: 20,
                child: widget.tab.closable && (_hovered || active)
                    ? InkWell(
                        onTap: widget.onClose,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(
                            PhosphorIconsBold.x,
                            size: 11,
                            color: idleInk,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
