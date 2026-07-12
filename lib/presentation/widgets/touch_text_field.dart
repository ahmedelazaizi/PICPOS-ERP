// Touch-optimized TextField for Windows Touch Devices
//
// This widget wraps TextField to ensure the system on-screen keyboard
// appears on Windows touch devices when the field is tapped.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform, Process;

/// A TextField wrapper that ensures the on-screen keyboard appears
/// on Windows touch devices when tapped.
///
/// On Windows, the system keyboard may not appear automatically
/// when a TextField is focused. This widget explicitly invokes
/// the keyboard using SystemChannels.textInput.
class TouchTextField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;
  final TextStyle? style;
  final TextAlign textAlign;
  final TextDirection? textDirection;

  const TouchTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.style,
    this.textAlign = TextAlign.start,
    this.textDirection,
  });

  @override
  State<TouchTextField> createState() => _TouchTextFieldState();
}

class _TouchTextFieldState extends State<TouchTextField> {
  late FocusNode _focusNode;
  bool _ownsNode = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsNode = true;
    }
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (_ownsNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _showKeyboard();
    }
  }

  /// Show the on-screen keyboard on Windows touch devices
  Future<void> _showKeyboard() async {
    // Only invoke on Windows desktop
    if (!Platform.isWindows) return;

    try {
      // Try TabTip first (better for touch screens)
      await Process.run('cmd', [
        '/c',
        'start',
        '',
        r'C:\Program Files\Common Files\microsoft shared\ink\TabTip.exe',
      ]);
    } catch (e) {
      // Fallback to SystemChannels
      try {
        await SystemChannels.textInput.invokeMethod('TextInput.show');
      } catch (_) {
        debugPrint('TouchTextField: Could not show keyboard: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _focusNode.requestFocus();
        _showKeyboard();
      },
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        decoration: widget.decoration,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        obscureText: widget.obscureText,
        autofocus: widget.autofocus,
        enabled: widget.enabled,
        readOnly: widget.readOnly,
        maxLines: widget.maxLines,
        minLines: widget.minLines,
        maxLength: widget.maxLength,
        onChanged: widget.onChanged,
        onEditingComplete: widget.onEditingComplete,
        onSubmitted: widget.onSubmitted,
        style: widget.style,
        textAlign: widget.textAlign,
        textDirection: widget.textDirection,
      ),
    );
  }
}

/// A TextFormField wrapper with touch keyboard support
class TouchTextFormField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onFieldSubmitted;
  final FormFieldSetter<String>? onSaved;
  final FormFieldValidator<String>? validator;
  final String? initialValue;
  final TextStyle? style;
  final TextAlign textAlign;
  final AutovalidateMode? autovalidateMode;

  const TouchTextFormField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.onChanged,
    this.onEditingComplete,
    this.onFieldSubmitted,
    this.onSaved,
    this.validator,
    this.initialValue,
    this.style,
    this.textAlign = TextAlign.start,
    this.autovalidateMode,
  });

  @override
  State<TouchTextFormField> createState() => _TouchTextFormFieldState();
}

class _TouchTextFormFieldState extends State<TouchTextFormField> {
  late FocusNode _focusNode;
  bool _ownsNode = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsNode = true;
    }
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (_ownsNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _showKeyboard();
    }
  }

  Future<void> _showKeyboard() async {
    if (!Platform.isWindows) return;

    try {
      await SystemChannels.textInput.invokeMethod('TextInput.show');
    } catch (e) {
      debugPrint('TouchTextFormField: Could not show keyboard: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _focusNode.requestFocus();
        _showKeyboard();
      },
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focusNode,
        decoration: widget.decoration,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        obscureText: widget.obscureText,
        autofocus: widget.autofocus,
        enabled: widget.enabled,
        readOnly: widget.readOnly,
        maxLines: widget.maxLines,
        minLines: widget.minLines,
        maxLength: widget.maxLength,
        onChanged: widget.onChanged,
        onEditingComplete: widget.onEditingComplete,
        onFieldSubmitted: widget.onFieldSubmitted,
        onSaved: widget.onSaved,
        validator: widget.validator,
        initialValue: widget.initialValue,
        style: widget.style,
        textAlign: widget.textAlign,
        autovalidateMode: widget.autovalidateMode,
      ),
    );
  }
}

/// Mixin that provides keyboard show functionality to any class
mixin TouchKeyboardMixin {
  /// Show the on-screen keyboard on Windows touch devices
  Future<void> showTouchKeyboard() async {
    if (!Platform.isWindows) return;

    try {
      await SystemChannels.textInput.invokeMethod('TextInput.show');
    } catch (e) {
      debugPrint('TouchKeyboardMixin: Could not show keyboard: $e');
    }
  }
}
