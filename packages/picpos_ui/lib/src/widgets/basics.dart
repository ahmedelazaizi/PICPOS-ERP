import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';
import '../tokens.dart';

/// Semantic tone of a pill/stripe.
enum PicPosTone { neutral, brand, success, warning, error }

extension PicPosToneColor on PicPosTone {
  Color color(BuildContext context) => switch (this) {
        PicPosTone.neutral => context.picposMuted,
        PicPosTone.brand => context.picposBrandInk,
        PicPosTone.success => PicPosTokens.successDeep,
        PicPosTone.warning => PicPosTokens.warningDeep,
        PicPosTone.error => PicPosTokens.errorDeep,
      };
}

/// Page header: optional icon badge (blue α 0.10, radius 12), title, one-line
/// subtitle, end-aligned actions in a `Wrap`, and a 2.5 px brand stripe.
class PicPosPageHeader extends StatelessWidget {
  const PicPosPageHeader({super.key, required this.title, this.subtitle, this.icon, this.actions = const []});
  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final ink = context.picposBrandInk;
    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        border: const Border(bottom: BorderSide(color: PicPosTokens.brandBlue, width: 2.5)),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(PicPosSpacing.gutter, 12, PicPosSpacing.gutter, 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: ink.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(PicPosRadii.badge),
              ),
              child: Icon(icon, size: 22, color: ink),
            ),
            const SizedBox(width: PicPosSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: tt.headlineSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle != null)
                  Text(subtitle!,
                      style: tt.bodySmall?.copyWith(color: context.picposMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }
}

/// Status chip: α 0.10 tone fill, tone text, radius 9.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.tone = PicPosTone.neutral, this.icon});
  final String label;
  final PicPosTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = tone.color(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(PicPosRadii.chip),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: c), const SizedBox(width: 4)],
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c)),
      ]),
    );
  }
}

/// Amounts and figures: tabular digits, always laid out LTR (so "-1,250.500"
/// keeps its sign and grouping inside Arabic text), weight 800.
class AmountText extends StatelessWidget {
  const AmountText(this.value, {super.key, this.style, this.color, this.textAlign});
  final String value;
  final TextStyle? style;
  final Color? color;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.titleMedium!;
    return Text(
      value,
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base.copyWith(
        fontWeight: FontWeight.w800,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Data freshness: neutral when fresh, amber after [warnAfter], red after
/// [staleAfter] (ARCHITECTURE-M ADR-M2 freshness table).
class AsOfBadge extends StatelessWidget {
  const AsOfBadge({
    super.key,
    required this.asOf,
    required this.now,
    this.warnAfter = const Duration(minutes: 15),
    this.staleAfter = const Duration(minutes: 60),
  });
  final DateTime asOf;
  final DateTime now;
  final Duration warnAfter;
  final Duration staleAfter;

  static PicPosTone toneFor(Duration age, Duration warnAfter, Duration staleAfter) =>
      age >= staleAfter ? PicPosTone.error : (age >= warnAfter ? PicPosTone.warning : PicPosTone.neutral);

  @override
  Widget build(BuildContext context) {
    final t = Tr.of(context, picposUiStrings);
    final local = asOf.toLocal();
    final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    final tone = toneFor(now.difference(asOf), warnAfter, staleAfter);
    return StatusPill(
      label: t(tone == PicPosTone.neutral ? 'asOf' : 'asOfStale', {'time': time}),
      tone: tone,
      icon: Icons.schedule,
    );
  }
}

/// The only circle in the system: icon disc, title, message, optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final ink = context.picposBrandInk;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(PicPosSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(shape: BoxShape.circle, color: ink.withValues(alpha: 0.10)),
              child: Icon(icon, size: 34, color: ink),
            ),
            const SizedBox(height: PicPosSpacing.lg),
            Text(title, style: tt.titleLarge, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: PicPosSpacing.sm),
              Text(message!, style: tt.bodyMedium?.copyWith(color: context.picposMuted), textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: PicPosSpacing.lg), action!],
          ]),
        ),
      ),
    );
  }
}
