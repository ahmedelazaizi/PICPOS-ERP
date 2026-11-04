import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers/theme_mode_provider.dart';
import '../picpos_shell/picpos_surface.dart';

/// زرُّ التبديل بين الفاتح والداكن في الشريط الجانبي.
///
/// الشريطُ داكنٌ دائماً (`AppColors.secondary` ثابت في الوضعين) فألوان
/// النص/الخلفية الثابتة هنا مقصودة. والضغطُ يعكس **الوضع الفعلي** لا القيمة
/// المخزَّنة: في `system` يتبع سطوع المنصّة.
class ThemeToggleTile extends ConsumerWidget {
  /// `false` = أيقونةٌ فقط (الشريطُ المطويّ).
  final bool expanded;
  const ThemeToggleTile({super.key, required this.expanded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = isEffectivelyDark(
      ref.watch(themeModeProvider),
      MediaQuery.platformBrightnessOf(context),
    );
    void toggle() => ref
        .read(themeModeProvider.notifier)
        .toggle(MediaQuery.platformBrightnessOf(context));
    final label = isDark ? tr('الوضع الفاتح') : tr('الوضع الداكن');
    final icon = Icon(
      isDark ? PhosphorIconsBold.sun : PhosphorIconsBold.moon,
      color: isDark ? AppColors.warning : context.picposMuted,
      size: 16,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Tooltip(
        message: label,
        child: InkWell(
          key: const ValueKey('themeToggleTile'),
          borderRadius: BorderRadius.circular(8),
          onTap: toggle,
          child: Container(
            height: 36,
            padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: expanded
                ? Row(
                    children: [
                      icon,
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 20,
                        width: 34,
                        child: Switch(
                          value: isDark,
                          onChanged: (_) => toggle(),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          activeThumbColor: AppColors.warning,
                          inactiveThumbColor: context.picposMuted,
                        ),
                      ),
                    ],
                  )
                : Center(child: icon),
          ),
        ),
      ),
    );
  }
}
