// ═══════════════════════════════════════════════════════════════════════════
// NUMERIC LAYOUT — Feature 031
// ═══════════════════════════════════════════════════════════════════════════
//
// POS-style numpad. Auto-selected when the focused field declares
// `keyboardType: TextInputType.number / numberWithOptions / phone`
// (research D9). Always rendered LTR even under Arabic locale — POS
// numpads conventionally read 0-9 left-to-right (contract
// `keyboard-overlay.md` §RTL).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../touch_keyboard_controller.dart';
import '../touch_keyboard_key.dart';

class NumericLayout extends ConsumerWidget {
  const NumericLayout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(touchKeyboardControllerProvider.notifier);

    Widget digit(String d) =>
        TouchKeyboardKey(label: d, onTap: () => controller.pressKey(d));

    // Force LTR so digits read 0-9 left to right regardless of app locale.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Row(
              children: [
                digit('1'),
                digit('2'),
                digit('3'),
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
                digit('4'),
                digit('5'),
                digit('6'),
                TouchKeyboardKey(
                  label: AppConstants.currencySymbolAr,
                  onTap: () =>
                      controller.pressCurrency(AppConstants.currencySymbolAr),
                  fontSize: 16,
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                digit('7'),
                digit('8'),
                digit('9'),
                TouchKeyboardKey(
                  icon: Icons.keyboard_return,
                  onTap: controller.pressEnter,
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                TouchKeyboardKey(
                  label: 'أ ب ج',
                  onTap: controller.toggleNumeric,
                  fontSize: 14,
                ),
                digit('0'),
                TouchKeyboardKey(
                    label: '.', onTap: () => controller.pressKey('.')),
                TouchKeyboardKey(
                  icon: Icons.keyboard_hide_outlined,
                  onTap: controller.hide,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
