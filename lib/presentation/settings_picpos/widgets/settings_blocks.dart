import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';

/// بلوكاتُ شاشة الإعدادات — على تصميم `PicPos-Settings`.
///
/// المحتوى في التصميم ليس قائمةَ صفوفٍ واحدة، بل **بطاقاتٌ مقسَّمةٌ** على
/// شبكةِ ١٢ عموداً، ولكلٍّ منها جسدٌ من خمسةِ أنواعٍ مقيسةٍ من الملفّ:
/// `choice` · `values` · `switches` · `tiles` · `danger`.
///
/// ⚠️ وهذا ما سقط في التنسيق الأوّل: بُني العمودُ والترويسةُ وشريطةُ البطاقة
/// وبقي الجسدُ صفوفَ `ListTile` قديمةً بأسهم — فبانت الشاشةُ نصفَ منقولة.

// ═══════════════════════════════════════════════════════════════════════════
// الشبكة
// ═══════════════════════════════════════════════════════════════════════════

/// عنصرٌ في شبكة البلوكات مع حصّته من الأعمدة الاثني عشر.
class SettingsBlockSpan {
  const SettingsBlockSpan({required this.span, required this.child});

  /// حصّةُ العرض من ١٢ — كما `grid-column: span N` في التصميم.
  final int span;
  final Widget child;
}

/// شبكةُ البلوكات: اثنا عشر عموداً بفجوةِ ١٦ كما في التصميم.
///
/// ⚠️ وتنهار إلى عمودٍ واحدٍ تحت [collapseBelow]: بلوكُ `span 5` على شاشةٍ
/// ضيّقةٍ يصير أضيقَ من محتواه فيفيض — وهو نفسُ العطب الذي أمسكه اختبارُ
/// العرضَين في تبويبات الحسابات مرّتين.
class SettingsBlockGrid extends StatelessWidget {
  const SettingsBlockGrid({
    super.key,
    required this.blocks,
    this.gap = 16,
    this.collapseBelow = 1000,
  });

  final List<SettingsBlockSpan> blocks;
  final double gap;
  final double collapseBelow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width < collapseBelow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final b in blocks) ...[
                b.child,
                SizedBox(height: gap),
              ],
            ],
          );
        }

        // عرضُ العمود الواحد بعد خصم الفجوات الإحدى عشرة.
        final unit = (width - gap * 11) / 12;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final b in blocks)
              SizedBox(
                width: (unit * b.span) + gap * (b.span - 1),
                child: b.child,
              ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// غلافُ البلوك
// ═══════════════════════════════════════════════════════════════════════════

/// بطاقةُ بلوك: شريطةٌ لونيّةٌ ثمّ العنوانُ وسطرٌ خافت، وشارةٌ اختياريّة.
class SettingsBlock extends StatelessWidget {
  const SettingsBlock({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.badge,
    this.tint = AppColors.primary,
  });

  final String title;
  final String? subtitle;
  final String? badge;
  final Color tint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 13),
            child: Row(
              children: [
                Container(
                  width: 3.5,
                  height: 17,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: text.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            subtitle!,
                            style: text.labelSmall
                                ?.copyWith(color: AppColors.textMuted),
                          ),
                        ),
                    ],
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 4),
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge!,
                      style: text.labelSmall?.copyWith(
                        color: tint,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// choice — بطاقاتُ اختيارٍ متعادلة
// ═══════════════════════════════════════════════════════════════════════════

class SettingsChoiceOption<T> {
  const SettingsChoiceOption({
    required this.value,
    required this.label,
    required this.sub,
  });

  final T value;
  final String label;
  final String sub;
}

class SettingsChoiceBlock<T> extends StatelessWidget {
  const SettingsChoiceBlock({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.columns = 3,
  });

  final List<SettingsChoiceOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelect;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 18),
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth < 520 ? 1 : columns;
          final unit = (c.maxWidth - 11 * (cols - 1)) / cols;
          return Wrap(
            spacing: 11,
            runSpacing: 11,
            children: [
              for (final o in options)
                SizedBox(
                  width: unit,
                  child: _ChoiceCard<T>(
                    option: o,
                    selected: o.value == selected,
                    onTap: () => onSelect(o.value),
                    text: text,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ChoiceCard<T> extends StatelessWidget {
  const _ChoiceCard({
    required this.option,
    required this.selected,
    required this.onTap,
    required this.text,
  });

  final SettingsChoiceOption<T> option;
  final bool selected;
  final VoidCallback onTap;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.surface,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          selected ? AppColors.primary : AppColors.textMuted,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? Center(
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: selected ? AppColors.primary : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              option.sub,
              style: text.labelSmall?.copyWith(
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// values — صفٌّ بقيمةٍ في شريحة
// ═══════════════════════════════════════════════════════════════════════════

class SettingsValueRow extends StatelessWidget {
  const SettingsValueRow({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    this.sub,
    this.onTap,
    this.tint = AppColors.primary,
    this.first = false,
  });

  final IconData icon;
  final String title;
  final String? sub;

  /// شريحةُ القيمة على يسار الصفّ.
  ///
  /// ⚠️ `null` حين لا قيمةَ **تُقاس**. التصميمُ يعرض شريحةً لكلّ صفّ، وبعضُ
  /// الصفوف لا يقابله في التطبيق قيمةٌ واحدةٌ قابلةٌ للعرض — وشريحةٌ تُملأ
  /// بتخمينٍ أسوأُ من صفٍّ بلا شريحة.
  final String? value;
  final VoidCallback? onTap;
  final Color tint;

  /// أوّلُ صفٍّ في البلوك لا يحمل خطّاً علويّاً — الترويسةُ فوقه.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: first
              ? null
              : const Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 17, color: tint),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: text.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  if (sub != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        sub!,
                        style: text.labelSmall
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            if (value != null)
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium
                        ?.copyWith(color: tint, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            if (onTap != null) ...[
              const SizedBox(width: 9),
              const Icon(PhosphorIconsBold.caretLeft,
                  size: 13, color: AppColors.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}

/// جسدُ بلوكٍ من نوع `values` أو `switches` — نفسُ الحشوة في التصميم.
class SettingsRowsBody extends StatelessWidget {
  const SettingsRowsBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// switches — صفٌّ بمفتاح
// ═══════════════════════════════════════════════════════════════════════════

class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.sub,
    this.trailing,
    this.first = false,
  });

  final IconData icon;
  final String title;
  final String? sub;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// إجراءٌ إضافيٌّ قبل المفتاح — «تعيين PIN» في التصميم.
  final Widget? trailing;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppColors.textMuted),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: text.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                if (sub != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      sub!,
                      style: text.labelSmall
                          ?.copyWith(color: AppColors.textMuted),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// tiles — مربّعاتٌ بحالةٍ ونقطة
// ═══════════════════════════════════════════════════════════════════════════

class SettingsTile {
  const SettingsTile({
    required this.icon,
    required this.title,
    required this.sub,
    required this.meta,
    required this.onTap,
    this.tint = AppColors.primary,
    this.dot,
  });

  final IconData icon;
  final String title;
  final String sub;

  /// سطرُ الحالة أسفلَ المربّع.
  final String meta;
  final VoidCallback onTap;
  final Color tint;

  /// لونُ نقطة الحالة — `null` يعني لا نقطة.
  final Color? dot;
}

class SettingsTilesBlock extends StatelessWidget {
  const SettingsTilesBlock({
    super.key,
    required this.tiles,
    this.columns = 3,
  });

  final List<SettingsTile> tiles;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 16),
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = switch (c.maxWidth) {
            < 420 => 1,
            < 700 => 2,
            _ => columns,
          };
          final unit = (c.maxWidth - 11 * (cols - 1)) / cols;
          return Wrap(
            spacing: 11,
            runSpacing: 11,
            children: [
              for (final t in tiles)
                SizedBox(
                  width: unit,
                  child: _Tile(tile: t, text: text),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.tile, required this.text});

  final SettingsTile tile;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: tile.onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tile.tint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(tile.icon, size: 19, color: tile.tint),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tile.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        tile.sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelSmall
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const Icon(PhosphorIconsBold.caretLeft,
                    size: 14, color: AppColors.textMuted),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (tile.dot != null) ...[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tile.dot,
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
                Expanded(
                  child: Text(
                    tile.meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(
                      color: tile.dot ?? AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// danger — إجراءٌ لا رجعةَ فيه
// ═══════════════════════════════════════════════════════════════════════════

class SettingsDangerRow extends StatelessWidget {
  const SettingsDangerRow({
    super.key,
    required this.icon,
    required this.title,
    required this.sub,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String sub;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 18),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.07),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: AppColors.error),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: text.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.error)),
                  Text(sub,
                      style: text.labelSmall
                          ?.copyWith(color: AppColors.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(
                    color: AppColors.error.withValues(alpha: 0.5)),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
