// ═══════════════════════════════════════════════════════════════════════════
// TOUCH KEYBOARD KEY — Feature 031
// ═══════════════════════════════════════════════════════════════════════════
//
// Shared visual key widget used by every layout. A single, consistent
// look keeps the keyboard feeling cohesive when the operator switches
// between layouts. Min touch target 48×48 dp (spec FR-013).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class TouchKeyboardKey extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final int flex;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double fontSize;

  const TouchKeyboardKey({
    super.key,
    this.label = '',
    this.onTap,
    this.icon,
    this.flex = 1,
    this.backgroundColor,
    this.foregroundColor,
    this.fontSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final fg = foregroundColor ?? AppColors.textPrimary;
    final bg = backgroundColor ?? Theme.of(context).cardColor;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: icon != null
                    ? Icon(icon, color: fg, size: 20)
                    : Text(
                        label,
                        style: TextStyle(
                          color: fg,
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
