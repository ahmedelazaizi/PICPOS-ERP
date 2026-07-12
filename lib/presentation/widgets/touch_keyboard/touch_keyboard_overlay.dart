// ═══════════════════════════════════════════════════════════════════════════
// TOUCH KEYBOARD OVERLAY — Feature 031
// ═══════════════════════════════════════════════════════════════════════════
//
// Bottom-anchored, slides up with a 150ms animation, height 280 dp on
// screens >= 800 dp tall (scales down to 240 dp at 600 dp tall — spec
// FR-009 / contract `keyboard-overlay.md` §Position).
//
// Mounting strategy: this widget is placed at the root of
// `MaterialApp.builder` (above the Navigator output) inside a Stack, so
// it floats over every route, dialog, and modal. We do NOT use
// `OverlayEntry.insert` — staying in the widget tree means hot-reload
// behaves cleanly and there are no orphan-entry edge cases.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'layouts/arabic_layout.dart';
import 'layouts/english_layout.dart';
import 'layouts/numeric_layout.dart';
import 'touch_keyboard_controller.dart';

/// Computes a screen-aware keyboard height. 280dp is the design target
/// for desktop/POS screens (>=800dp tall); we scale down to a 240dp floor
/// for 600dp-tall POS displays so the focused field stays visible after
/// scroll-into-view.
double touchKeyboardHeightFor(double screenHeight) {
  if (screenHeight >= 800) return 280;
  if (screenHeight <= 600) return 240;
  // Linear interpolation between the two anchors.
  final t = (screenHeight - 600) / (800 - 600);
  return 240 + 40 * t;
}

class TouchKeyboardOverlay extends ConsumerWidget {
  const TouchKeyboardOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVisible =
        ref.watch(touchKeyboardControllerProvider.select((s) => s.isVisible));
    final layout =
        ref.watch(touchKeyboardControllerProvider.select((s) => s.layout));
    final screenHeight = MediaQuery.sizeOf(context).height;
    final height = touchKeyboardHeightFor(screenHeight);

    return IgnorePointer(
      ignoring: !isVisible,
      // Feature 031 bugfix — every key inside is a Material InkWell. On
      // desktop/POS, InkWell-on-tap can grant focus to itself, which
      // would steal focus from the operator's TextField and trigger
      // _TouchKeyboardWrapper._onFocusChange to call hide() (because
      // the new focus owner is not inside an EditableText). The race
      // between hide() and the InkWell's onTap (which performs the
      // requested action like cycleAlphaLayout) made layout-switcher
      // keys feel sticky and unresponsive — the user reported this on
      // a real POS device. ExcludeFocus blocks every descendant from
      // becoming the focus owner, so the TextField stays focused
      // throughout the keyboard interaction.
      child: ExcludeFocus(
        child: AnimatedSlide(
          offset: isVisible ? Offset.zero : const Offset(0, 1),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              elevation: 12,
              color: Theme.of(context).colorScheme.surface,
              child: SizedBox(
                height: height,
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: _layoutFor(layout),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _layoutFor(TouchKeyboardLayout layout) {
    switch (layout) {
      case TouchKeyboardLayout.arabicAlpha:
        return const ArabicLayout();
      case TouchKeyboardLayout.englishAlpha:
        return const EnglishLayout();
      case TouchKeyboardLayout.numeric:
        return const NumericLayout();
    }
  }
}
