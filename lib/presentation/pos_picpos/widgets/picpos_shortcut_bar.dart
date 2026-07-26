import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// One entry in the bottom shortcut strip.
class PicPosShortcut {
  final String label;
  final String keyLabel;
  final VoidCallback onPressed;
  final Color? color;
  final bool enabled;

  const PicPosShortcut({
    required this.label,
    required this.keyLabel,
    required this.onPressed,
    this.color,
    this.enabled = true,
  });
}

/// Bottom keyboard-shortcut strip.
///
/// The strip is a LABEL for the physical keys, not a second source of truth:
/// every entry carries the same callback the key handler invokes, so a key
/// and its button can never drift apart. Mouse users get the same actions
/// without having to learn the keys.
class PicPosShortcutBar extends StatelessWidget {
  final List<PicPosShortcut> shortcuts;

  const PicPosShortcutBar({super.key, required this.shortcuts});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: AppColors.primaryDark,
        border: Border(top: BorderSide(color: AppColors.primary, width: 2)),
      ),
      child: Row(
        children: [
          for (final s in shortcuts)
            Expanded(child: _ShortcutButton(shortcut: s)),
        ],
      ),
    );
  }
}

class _ShortcutButton extends StatelessWidget {
  final PicPosShortcut shortcut;

  const _ShortcutButton({required this.shortcut});

  @override
  Widget build(BuildContext context) {
    final enabled = shortcut.enabled;
    final tint = shortcut.color ?? Colors.white;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: enabled ? shortcut.onPressed : null,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: Colors.white24),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: tint.withValues(alpha: 0.45)),
                ),
                child: Text(
                  shortcut.keyLabel,
                  style: TextStyle(
                    color: tint,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  shortcut.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tint,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
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
