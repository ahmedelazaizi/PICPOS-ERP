// ═══════════════════════════════════════════════════════════════════════════
// ARABIC LAYOUT — Feature 031
// ═══════════════════════════════════════════════════════════════════════════
//
// Three letter rows + one special-keys row. RTL by default; the parent
// MaterialApp's locale is `ar_EG` so the Row widgets read right-to-left
// without us imposing a Directionality. Numeric / hide / space / enter
// / backspace special keys sit in the bottom row.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../touch_keyboard_controller.dart';
import '../touch_keyboard_key.dart';

class ArabicLayout extends ConsumerWidget {
  const ArabicLayout({super.key});

  // Standard Arabic keyboard letter rows, trimmed to fit POS touch sizing.
  static const _row1 = ['ض', 'ص', 'ث', 'ق', 'ف', 'غ', 'ع', 'ه', 'خ', 'ح', 'ج'];
  static const _row2 = ['ش', 'س', 'ي', 'ب', 'ل', 'ا', 'ت', 'ن', 'م', 'ك', 'ط'];
  static const _row3 = ['ذ', 'ئ', 'ء', 'ؤ', 'ر', 'ى', 'ة', 'و', 'ز', 'ظ', 'د'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(touchKeyboardControllerProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(child: Row(children: _row1.map((c) => TouchKeyboardKey(label: c, onTap: () => controller.pressKey(c))).toList())),
        Expanded(child: Row(children: _row2.map((c) => TouchKeyboardKey(label: c, onTap: () => controller.pressKey(c))).toList())),
        Expanded(
          child: Row(
            children: [
              ..._row3.map((c) =>
                  TouchKeyboardKey(label: c, onTap: () => controller.pressKey(c))),
              TouchKeyboardKey(
                icon: Icons.backspace_outlined,
                onTap: controller.pressBackspace,
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              TouchKeyboardKey(
                label: '123',
                onTap: controller.toggleNumeric,
                flex: 2,
                fontSize: 16,
              ),
              TouchKeyboardKey(
                label: 'EN',
                onTap: controller.cycleAlphaLayout,
                flex: 2,
                fontSize: 16,
              ),
              TouchKeyboardKey(
                label: 'مسافة',
                onTap: () => controller.pressKey(' '),
                flex: 6,
                fontSize: 14,
              ),
              TouchKeyboardKey(
                icon: Icons.keyboard_return,
                onTap: controller.pressEnter,
                flex: 2,
              ),
              TouchKeyboardKey(
                icon: Icons.keyboard_hide_outlined,
                onTap: controller.hide,
                flex: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
