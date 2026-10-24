// شريطُ الخطوات: عمودٌ جانبيّ بأرقامٍ/علامات ✓ — الخطواتُ بعد `maxStep` معطّلة
// والضغطُ يرجع إلى أيّ خطوةٍ منجزة. تحت 640px يتحوّل إلى سطرٍ مضغوطٍ يعرض
// الخطوةَ النشطةَ فقط.
import 'package:flutter/material.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../picpos_shell/picpos_surface.dart';

class FirstRunStepper extends StatelessWidget {
  const FirstRunStepper({
    super.key,
    required this.titles,
    required this.current,
    required this.maxStep,
    required this.onSelect,
    this.compact = false,
  });

  final List<String> titles;
  final int current;
  final int maxStep;
  final ValueChanged<int> onSelect;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          tr('الخطوة {p0} من {p1} — {p2}', {
            'p0': current + 1,
            'p1': titles.length,
            'p2': titles[current],
          }),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: context.picposText,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < titles.length; i++)
          _Item(
            index: i,
            title: titles[i],
            active: i == current,
            done: i < maxStep,
            enabled: i <= maxStep,
            onTap: () => onSelect(i),
          ),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.index,
    required this.title,
    required this.active,
    required this.done,
    required this.enabled,
    required this.onTap,
  });

  final int index;
  final String title;
  final bool active;
  final bool done;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.picposBrandInk;
    final badgeColor = active
        ? AppColors.primary
        : done
            ? AppColors.success
            : context.picposHairline;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: active,
      label: title,
      child: InkWell(
        key: Key('first_run_step_$index'),
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onTap : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: active ? AppColors.primary.withValues(alpha: 0.09) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: badgeColor.withValues(alpha: active || done ? 1 : 0.5),
                ),
                child: done && !active
                    ? Icon(Icons.check, size: 15, color: Theme.of(context).colorScheme.onPrimary)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: active
                              ? Theme.of(context).colorScheme.onPrimary
                              : context.picposMuted,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: !enabled
                        ? context.picposMuted
                        : active
                            ? ink
                            : context.picposText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
