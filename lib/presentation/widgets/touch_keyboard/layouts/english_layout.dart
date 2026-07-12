// ═══════════════════════════════════════════════════════════════════════════
// ENGLISH LAYOUT — Feature 031
// ═══════════════════════════════════════════════════════════════════════════
//
// QWERTY rows with sticky-shift (resets on any character key per
// data-model §2). Layout-switcher key returns to Arabic; "123" jumps
// to numeric. Same special keys as ArabicLayout for consistency.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../touch_keyboard_controller.dart';
import '../touch_keyboard_key.dart';

class EnglishLayout extends ConsumerWidget {
  const EnglishLayout({super.key});

  static const _row1 = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
  static const _row2 = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
  static const _row3 = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(touchKeyboardControllerProvider.notifier);
    final isShift = ref
        .watch(touchKeyboardControllerProvider.select((s) => s.isShiftDown));

    String cased(String c) => isShift ? c.toUpperCase() : c;

    Widget letter(String c) => TouchKeyboardKey(
          label: cased(c),
          onTap: () => controller.pressKey(cased(c)),
        );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Row(children: _row1.map(letter).toList()),
          ),
          Expanded(
            child: Row(
              children: [
                const Spacer(),
                ..._row2.map(letter),
                const Spacer(),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                TouchKeyboardKey(
                  icon: isShift ? Icons.arrow_upward : Icons.arrow_upward_outlined,
                  onTap: controller.pressShift,
                  flex: 2,
                  backgroundColor: isShift
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                ),
                ..._row3.map(letter),
                TouchKeyboardKey(
                  icon: Icons.backspace_outlined,
                  onTap: controller.pressBackspace,
                  flex: 2,
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
                  label: 'أ ب ج',
                  onTap: controller.cycleAlphaLayout,
                  flex: 2,
                  fontSize: 14,
                ),
                TouchKeyboardKey(
                  label: 'space',
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
      ),
    );
  }
}
