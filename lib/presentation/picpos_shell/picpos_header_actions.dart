// شريطُ إجراءات ترويسة PicPos بأولويّات — بلاغُ المالك: زرُّ «إضافة طاولة»
// مقصوصٌ تحت منطقة العنوان.
//
// ═══ السببُ الجذريّ (خطة الطاولات A.4) ═══
//
// `PicPosPageHeader` كان يضع الإجراءات في `SingleChildScrollView` أفقيٍّ
// مثبَّتٍ من آخره (`reverse: true`)، فإذا ضاق العرضُ انزلق **أوّلُ** إجراءٍ
// (في RTL هو الأهمّ) خارجَ النافذة **بصمتٍ**: لا فيضانَ ولا تحذير.
//
// ═══ العلاج ═══
//
// كلُّ إجراءٍ له أولويّة (1 = الأهمّ). نقيس العرضَ المتاحَ فعلاً ونُبقي ظاهراً
// ما يتّسع بترتيب الأولويّة، ويذهب الباقي إلى قائمة «⋯». **الإجراءُ الأعلى
// أولويّةً لا يختفي أبداً.** والترتيبُ المرئيُّ يبقى ترتيبَ التمرير الأصليّ.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import '../widgets/permission_guard.dart';

/// خيارٌ داخل إجراءٍ منسدل (مثل اختيار المنطقة).
class PicPosHeaderChoice {
  const PicPosHeaderChoice({
    required this.label,
    required this.onSelected,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onSelected;
  final bool enabled;
}

/// إجراءٌ في ترويسة الشاشة: زرٌّ بنصٍّ وأيقونة، أو قائمةٌ منسدلةٌ ([choices]).
class PicPosHeaderAction {
  const PicPosHeaderAction({
    required this.label,
    required this.icon,
    this.onPressed,
    this.choices,
    this.priority = 5,
    this.tooltip,
    this.color,
    this.permission,
    this.actionName,
    this.iconOnly = false,
    this.buttonKey,
  });

  final String label;
  final IconData icon;

  /// فعلُ الزرّ. `null` مع [choices] `null` = زرٌّ معطَّل.
  final VoidCallback? onPressed;

  /// إن وُجدت صار الإجراءُ قائمةً منسدلة (الزرُّ يفتحها).
  final List<PicPosHeaderChoice>? choices;

  /// 1 = الأهمّ. الأقلُّ أهمّيةً (رقمٌ أكبر) يُنقَل أوّلاً إلى «⋯».
  final int priority;

  final String? tooltip;

  /// لونُ النصّ والأيقونة. الافتراضيُّ لونُ الثيم.
  final Color? color;

  /// كودُ صلاحيةٍ يحرس الفعل (يطلب موافقةَ مسؤولٍ عند غيابها) — في الزرّ
  /// الظاهر وفي مدخل «⋯» معاً، فلا تُفلت الحراسةُ بنقل الزرّ إلى القائمة.
  final String? permission;
  final String? actionName;

  /// زرٌّ أيقونةٌ بلا نصّ (يبقى [label] تلميحاً).
  final bool iconOnly;

  final Key? buttonKey;
}

/// نتيجةُ توزيع الإجراءات: أيُّها يظهر وأيُّها يذهب إلى «⋯».
@visibleForTesting
List<bool> planVisibleHeaderActions({
  required List<double> widths,
  required List<int> priorities,
  required double available,
  required double overflowWidth,
  required double gap,
}) {
  final n = widths.length;
  if (n == 0) return const [];
  double sum(Iterable<int> idx) =>
      idx.fold<double>(0, (s, i) => s + widths[i]) +
      gap * math.max(0, idx.length - 1);

  if (sum(List.generate(n, (i) => i)) <= available) {
    return List<bool>.filled(n, true);
  }

  final order = List<int>.generate(n, (i) => i)
    ..sort((a, b) {
      final c = priorities[a].compareTo(priorities[b]);
      return c != 0 ? c : a.compareTo(b);
    });

  final visible = <int>[];
  for (final i in order) {
    if (visible.isEmpty) {
      // الأعلى أولويّةً يظهر دائماً ولو ضاق العرض.
      visible.add(i);
      continue;
    }
    final needOverflow = n - visible.length - 1 > 0;
    final total =
        sum([...visible, i]) + (needOverflow ? gap + overflowWidth : 0);
    if (total <= available) {
      visible.add(i);
    } else {
      break;
    }
  }
  return [for (var i = 0; i < n; i++) visible.contains(i)];
}

class PicPosHeaderActionsBar extends ConsumerWidget {
  const PicPosHeaderActionsBar({super.key, required this.actions});

  final List<PicPosHeaderAction> actions;

  static const double _gap = 8;
  static const double _overflowWidth = 48;

  /// مفتاحُ زرّ «⋯».
  static const Key overflowKey = Key('picpos_header_overflow');

  /// تقديرُ عرض الزرّ: نصٌّ مقيسٌ فعلاً + أيقونة + حشوٌ + هامشُ أمان.
  double _estimate(BuildContext context, PicPosHeaderAction a) {
    if (a.iconOnly) return _overflowWidth;
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge ??
        const TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
    final painter = TextPainter(
      text: TextSpan(text: a.label, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    // أيقونة 18 + فاصل 8 + حشو أفقيّ 2×16 + أمان 16.
    return painter.width + 18 + 8 + 32 + 16;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.maxWidth.isFinite;
        final widths = [for (final a in actions) _estimate(context, a)];
        final plan = bounded
            ? planVisibleHeaderActions(
                widths: widths,
                priorities: [for (final a in actions) a.priority],
                available: constraints.maxWidth,
                overflowWidth: _overflowWidth,
                gap: _gap,
              )
            : List<bool>.filled(actions.length, true);

        final overflow = <PicPosHeaderAction>[
          for (var i = 0; i < actions.length; i++)
            if (!plan[i]) actions[i],
        ];

        final row = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < actions.length; i++)
              if (plan[i]) ...[
                if (i != plan.indexOf(true)) const SizedBox(width: _gap),
                _inline(context, actions[i]),
              ],
            if (overflow.isNotEmpty) ...[
              const SizedBox(width: _gap),
              _overflowMenu(context, ref, overflow),
            ],
          ],
        );

        // شبكةُ أمانٍ أخيرة: لو أخطأ التقديرُ بضعَ بكسلات صغّرنا الصفَّ
        // قليلاً بدل أن نقصَّ زرّاً.
        return Align(
          alignment: AlignmentDirectional.centerEnd,
          child: bounded
              ? ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerEnd,
                    child: row,
                  ),
                )
              : row,
        );
      },
    );
  }

  Widget _inline(BuildContext context, PicPosHeaderAction a) {
    final foreground = a.color;
    final style = foreground == null
        ? null
        : OutlinedButton.styleFrom(foregroundColor: foreground);

    Widget child;
    final choices = a.choices;
    if (choices != null) {
      child = PopupMenuButton<int>(
        key: a.buttonKey,
        tooltip: a.tooltip ?? a.label,
        onSelected: (i) => choices[i].onSelected(),
        itemBuilder: (_) => [
          for (var i = 0; i < choices.length; i++)
            PopupMenuItem<int>(
              value: i,
              enabled: choices[i].enabled,
              child: Text(choices[i].label),
            ),
        ],
        // `IgnorePointer`: زرٌّ بلا فعلٍ يبتلع الضغطة فلا تصل القائمة.
        child: IgnorePointer(
          child: a.iconOnly
              ? SizedBox(
                  width: _overflowWidth,
                  height: 40,
                  child: Icon(a.icon, size: 20, color: foreground),
                )
              : OutlinedButton.icon(
                  onPressed: () {},
                  icon: Icon(a.icon, size: 18),
                  label: Text(a.label),
                  style: style,
                ),
        ),
      );
    } else if (a.iconOnly) {
      child = IconButton(
        key: a.buttonKey,
        onPressed: a.onPressed,
        tooltip: a.tooltip ?? a.label,
        icon: Icon(a.icon, size: 20, color: foreground),
      );
    } else {
      child = OutlinedButton.icon(
        key: a.buttonKey,
        onPressed: a.onPressed,
        icon: Icon(a.icon, size: 18),
        label: Text(a.label),
        style: style,
      );
      if (a.tooltip != null) child = Tooltip(message: a.tooltip!, child: child);
    }

    final permission = a.permission;
    if (permission == null) return child;
    return PermissionGuard(
      permission: permission,
      allowManagerOverride: true,
      actionName: a.actionName ?? a.label,
      onGranted: a.onPressed,
      child: child,
    );
  }

  Widget _overflowMenu(
    BuildContext context,
    WidgetRef ref,
    List<PicPosHeaderAction> overflow,
  ) {
    // كلُّ مدخلٍ يحمل فعلَه؛ والإجراءُ المنسدلُ يُسطَّح: عنوانٌ معطَّل ثم
    // خياراتُه.
    final entries = <_OverflowEntry>[];
    for (final a in overflow) {
      final choices = a.choices;
      if (choices == null) {
        entries.add(_OverflowEntry(
          label: a.label,
          icon: a.icon,
          enabled: a.onPressed != null,
          run: () async {
            final permission = a.permission;
            if (permission != null) {
              final ok = await ensurePermission(
                ref,
                context,
                permission,
                actionName: a.actionName ?? a.label,
              );
              if (!ok) return;
            }
            a.onPressed?.call();
          },
        ));
      } else {
        entries.add(_OverflowEntry(
          label: a.label,
          icon: a.icon,
          enabled: false,
          isHeader: true,
        ));
        for (final c in choices) {
          entries.add(_OverflowEntry(
            label: c.label,
            enabled: c.enabled,
            indent: true,
            run: () async => c.onSelected(),
          ));
        }
      }
    }

    return PopupMenuButton<int>(
      key: overflowKey,
      tooltip: tr('مزيد من الإجراءات'),
      icon: const Icon(PhosphorIconsBold.dotsThreeOutline, size: 20),
      onSelected: (i) => entries[i].run?.call(),
      itemBuilder: (_) => [
        for (var i = 0; i < entries.length; i++)
          PopupMenuItem<int>(
            value: i,
            enabled: entries[i].enabled,
            child: Row(
              children: [
                if (entries[i].indent) const SizedBox(width: 24),
                if (entries[i].icon != null) ...[
                  Icon(entries[i].icon, size: 18),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    entries[i].label,
                    style: entries[i].isHeader
                        ? const TextStyle(fontWeight: FontWeight.w700)
                        : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _OverflowEntry {
  _OverflowEntry({
    required this.label,
    this.icon,
    this.enabled = true,
    this.run,
    this.isHeader = false,
    this.indent = false,
  });

  final String label;
  final IconData? icon;
  final bool enabled;
  final Future<void> Function()? run;
  final bool isHeader;
  final bool indent;
}
