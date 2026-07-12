// ═══════════════════════════════════════════════════════════════════════════
// TOUCH KEYBOARD CONTROLLER — Feature 031
// ═══════════════════════════════════════════════════════════════════════════
//
// Owns the runtime state of the on-screen keyboard:
//   - which layout is currently visible (Arabic / English / Numeric),
//   - whether shift is down (English only),
//   - the most-recently-used alphabetical layout (so a numeric→alpha
//     switch returns to whichever alphabet the operator last used),
//   - the focused TextField's controller + metadata (ActiveFieldContext)
//     so key presses route to the right input.
//
// All character keystrokes flow through `pressKey` / `pressBackspace` /
// `pressEnter` / `pressShift` / `pressCurrency`, which mutate the field's
// `TextEditingController.value` cursor-aware. They MUST NOT use
// `controller.text +=` — that bypasses inputFormatters / maxLength
// (spec FR-015, contract `keyboard-overlay.md` §Key-press → text).
//
// Lifetime: singleton-per-ProviderContainer. Created lazily on first
// `show`. Never disposed during the app's lifetime.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../touch_keyboard/providers/touch_mode_provider.dart';

enum TouchKeyboardLayout { arabicAlpha, englishAlpha, numeric }

/// Snapshot of the focused text-input field's properties — captured
/// when the FocusManager listener fires `onFocusChanged`. The controller
/// uses this to (a) decide initial layout, (b) route key presses back to
/// the right `TextEditingController`, and (c) explicitly unfocus the
/// SPECIFIC text field when the user dismisses the keyboard (so that
/// dismissal isn't undone by a focus event for the same field).
class ActiveFieldContext {
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextInputType keyboardType;
  final bool obscureText;
  final bool readOnly;
  final int? maxLines;

  const ActiveFieldContext({
    required this.controller,
    required this.focusNode,
    required this.keyboardType,
    required this.obscureText,
    required this.readOnly,
    required this.maxLines,
  });

  factory ActiveFieldContext.fromEditableText(EditableText et) {
    return ActiveFieldContext(
      controller: et.controller,
      focusNode: et.focusNode,
      keyboardType: et.keyboardType,
      obscureText: et.obscureText,
      readOnly: et.readOnly,
      maxLines: et.maxLines,
    );
  }
}

class TouchKeyboardState {
  final bool isVisible;
  final TouchKeyboardLayout layout;
  final bool isShiftDown;
  final ActiveFieldContext? field;
  final TouchKeyboardLayout mostRecentAlphaLayout;

  const TouchKeyboardState({
    this.isVisible = false,
    this.layout = TouchKeyboardLayout.arabicAlpha,
    this.isShiftDown = false,
    this.field,
    this.mostRecentAlphaLayout = TouchKeyboardLayout.arabicAlpha,
  });

  TouchKeyboardState copyWith({
    bool? isVisible,
    TouchKeyboardLayout? layout,
    bool? isShiftDown,
    ActiveFieldContext? field,
    bool clearField = false,
    TouchKeyboardLayout? mostRecentAlphaLayout,
  }) {
    return TouchKeyboardState(
      isVisible: isVisible ?? this.isVisible,
      layout: layout ?? this.layout,
      isShiftDown: isShiftDown ?? this.isShiftDown,
      field: clearField ? null : (field ?? this.field),
      mostRecentAlphaLayout:
          mostRecentAlphaLayout ?? this.mostRecentAlphaLayout,
    );
  }
}

class TouchKeyboardController extends Notifier<TouchKeyboardState> {
  @override
  TouchKeyboardState build() {
    // Feature 031 (US4 / FR-020) — when the operator flips Touch Mode off
    // from the Settings screen, immediately dismiss the overlay so it
    // doesn't linger above whatever's on screen. Flipping it ON has no
    // immediate side-effect; the next focus event mounts the overlay.
    ref.listen<bool>(touchModeProvider, (prev, next) {
      if (prev == true && next == false) hide();
    });
    return const TouchKeyboardState();
  }

  /// Called by the global FocusManager listener in `_TouchKeyboardWrapper`.
  /// `null` / read-only / non-EditableText focus → hide.
  void onFocusChanged(EditableText? focused) {
    if (focused == null || focused.readOnly) {
      hide();
      return;
    }
    show(focused);
  }

  /// Show the keyboard for [focused], picking the right layout per
  /// research D9 (numeric for number/phone fields, otherwise the
  /// most-recently-used alphabetical layout).
  void show(EditableText focused) {
    final field = ActiveFieldContext.fromEditableText(focused);
    final newLayout = _layoutForKeyboardType(field.keyboardType);
    state = state.copyWith(
      isVisible: true,
      field: field,
      layout: newLayout,
      // Reset shift on any focus change (data-model §2 sub-state rules).
      isShiftDown: false,
    );
  }

  void hide() {
    if (!state.isVisible) return;
    // Feature 031 bugfix v3 — capture the field's FocusNode BEFORE we
    // clear state.field, then unfocus it directly. The previous v2 fix
    // unfocused `FocusManager.instance.primaryFocus`, but at the moment
    // hide() runs (from the X-button's onTap), the primary focus may
    // already have bounced to the InkWell — so we'd unfocus the InkWell
    // instead of the TextField, and the TextField would still be
    // focused. The next listener fire would then call show() and
    // re-mount the keyboard. Unfocusing the SPECIFIC FocusNode we
    // captured at show() time avoids this race.
    final fieldFocusNode = state.field?.focusNode;
    state = state.copyWith(isVisible: false, clearField: true);
    fieldFocusNode?.unfocus();
  }

  /// Returns true iff the keyboard was visible AND was dismissed.
  /// Used by AppShortcuts' Esc handler (research D10).
  bool dismissIfVisible() {
    if (!state.isVisible) return false;
    hide();
    return true;
  }

  void cycleAlphaLayout() {
    final next = state.layout == TouchKeyboardLayout.arabicAlpha
        ? TouchKeyboardLayout.englishAlpha
        : TouchKeyboardLayout.arabicAlpha;
    state = state.copyWith(
      layout: next,
      mostRecentAlphaLayout: next,
      isShiftDown: false,
    );
  }

  void toggleNumeric() {
    final next = state.layout == TouchKeyboardLayout.numeric
        ? state.mostRecentAlphaLayout
        : TouchKeyboardLayout.numeric;
    state = state.copyWith(layout: next, isShiftDown: false);
  }

  void pressKey(String value) {
    final field = state.field;
    if (field == null) return;
    HapticFeedback.selectionClick(); // No-op on Web (T027 polish target).
    final ctrl = field.controller;
    final v = ctrl.value;
    final selStart = v.selection.isValid ? v.selection.start : v.text.length;
    final selEnd = v.selection.isValid ? v.selection.end : v.text.length;
    final text = v.text;
    final newText = text.replaceRange(selStart, selEnd, value);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selStart + value.length),
    );
    if (state.isShiftDown) {
      state = state.copyWith(isShiftDown: false);
    }
  }

  void pressBackspace() {
    final field = state.field;
    if (field == null) return;
    HapticFeedback.selectionClick();
    final ctrl = field.controller;
    final v = ctrl.value;
    if (!v.selection.isValid) {
      // Default: delete one code unit from the end.
      if (v.text.isEmpty) return;
      final newText = v.text.substring(0, v.text.length - 1);
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
      return;
    }
    if (v.selection.start != v.selection.end) {
      final newText =
          v.text.replaceRange(v.selection.start, v.selection.end, '');
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: v.selection.start),
      );
    } else if (v.selection.start > 0) {
      final cursor = v.selection.start;
      final newText = v.text.replaceRange(cursor - 1, cursor, '');
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: cursor - 1),
      );
    }
  }

  void pressEnter() {
    final field = state.field;
    if (field == null) return;
    HapticFeedback.selectionClick();
    final isMultiLine = (field.maxLines ?? 1) > 1 || field.maxLines == null;
    if (isMultiLine) {
      pressKey('\n');
    } else {
      // Best-effort submit: unfocus the field. The framework's onSubmitted
      // handler fires on focus loss for fields that wired onEditingComplete
      // / onSubmitted callbacks; for fields that didn't, the operator's
      // intent (advance to next control) is still honored.
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  void pressShift() {
    HapticFeedback.selectionClick();
    state = state.copyWith(isShiftDown: !state.isShiftDown);
  }

  /// Currency-symbol shortcut on the numeric layout (US2 / T016 wires
  /// this to the actual currency provider; for now insert a placeholder
  /// that the layout overrides at the call site).
  void pressCurrency(String symbol) {
    pressKey(symbol);
  }

  TouchKeyboardLayout _layoutForKeyboardType(TextInputType type) {
    // Both `TextInputType.number` and `TextInputType.numberWithOptions(...)`
    // share the same `index` (2). `TextInputType.phone` is index 3.
    if (type.index == TextInputType.number.index ||
        type.index == TextInputType.phone.index) {
      return TouchKeyboardLayout.numeric;
    }
    return state.mostRecentAlphaLayout;
  }
}

final touchKeyboardControllerProvider =
    NotifierProvider<TouchKeyboardController, TouchKeyboardState>(
  TouchKeyboardController.new,
);
