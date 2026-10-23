import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

class ShortcutHintDef {
  final String keyLabel;
  final String label;
  final bool isHot;
  final bool isReturn;

  ShortcutHintDef({
    required this.keyLabel,
    required this.label,
    this.isHot = false,
    this.isReturn = false,
  });
}

class PosShortcutBar extends StatelessWidget {
  final List<ShortcutHintDef> shortcuts;

  const PosShortcutBar({super.key, required this.shortcuts});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: shortcuts
                    .map((s) => _buildShortcutHint(context, s))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutHint(BuildContext context, ShortcutHintDef hint) {
    final color = hint.isHot
        ? Colors.orange
        : hint.isReturn
        ? AppColors.error
        : Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsetsDirectional.only(end: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(
              hint.keyLabel,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            hint.label,
            style: TextStyle(
              color: Theme.of(
                context,
              ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
