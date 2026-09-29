import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';

/// Touch-friendly on-screen keyboard widget
/// Supports both full keyboard and numeric-only modes
class TouchKeyboard extends StatefulWidget {
  final TextEditingController controller;
  final bool numericOnly;
  final VoidCallback? onDone;
  final VoidCallback? onCancel;
  final String? label;

  const TouchKeyboard({
    super.key,
    required this.controller,
    this.numericOnly = false,
    this.onDone,
    this.onCancel,
    this.label,
  });

  @override
  State<TouchKeyboard> createState() => _TouchKeyboardState();

  /// Show touch keyboard as a bottom sheet
  static Future<String?> show(
    BuildContext context, {
    required TextEditingController controller,
    bool numericOnly = false,
    String? label,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TouchKeyboardSheet(
        controller: controller,
        numericOnly: numericOnly,
        label: label,
      ),
    );
  }
}

class _TouchKeyboardState extends State<TouchKeyboard> {
  bool _isShift = false;
  bool _isArabic = true;

  // Arabic keyboard layout
  static List<List<String>> get _arabicKeys => [
    [tr('١'), tr('٢'), tr('٣'), tr('٤'), tr('٥'), tr('٦'), tr('٧'), tr('٨'), tr('٩'), tr('٠')],
    [tr('ض'), tr('ص'), tr('ث'), tr('ق'), tr('ف'), tr('غ'), tr('ع'), tr('ه'), tr('خ'), tr('ح'), tr('ج')],
    [tr('ش'), tr('س'), tr('ي'), tr('ب'), tr('ل'), tr('ا'), tr('ت'), tr('ن'), tr('م'), tr('ك')],
    [tr('ء'), tr('ظ'), tr('ط'), tr('ذ'), tr('د'), tr('ز'), tr('ر'), tr('و'), tr('ة'), tr('ى')],
  ];

  // English keyboard layout
  static const List<List<String>> _englishKeys = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
  ];

  // Numeric keyboard layout
  static const List<List<String>> _numericKeys = [
    ['7', '8', '9'],
    ['4', '5', '6'],
    ['1', '2', '3'],
    ['.', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    if (widget.numericOnly) {
      return _buildNumericKeyboard();
    }
    return _buildFullKeyboard();
  }

  Widget _buildNumericKeyboard() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Display
          _buildDisplay(context),
          const SizedBox(height: 8),
          // Numeric keys
          ..._numericKeys.map((row) => _buildKeyRow(row, isNumeric: true)),
          const SizedBox(height: 8),
          // Action buttons
          _buildActionRow(),
        ],
      ),
    );
  }

  Widget _buildFullKeyboard() {
    final keys = _isArabic ? _arabicKeys : _englishKeys;
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Display
          _buildDisplay(context),
          const SizedBox(height: 8),
          // Keyboard rows
          ...keys.map((row) => _buildKeyRow(row)),
          // Special keys row
          _buildSpecialRow(),
          const SizedBox(height: 8),
          // Action buttons
          _buildActionRow(),
        ],
      ),
    );
  }

  Widget _buildDisplay(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary),
      ),
      child: Row(
        children: [
          if (widget.label != null) ...[
            Text(
              widget.label!,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              widget.controller.text.isEmpty
                  ? tr('أدخل القيمة...')
                  : widget.controller.text,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: widget.controller.text.isEmpty
                    ? Colors.grey
                    : Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            icon: const Icon(PhosphorIconsBold.x, size: 18),
            onPressed: () {
              widget.controller.clear();
              setState(() {});
            },
            tooltip: tr('مسح الكل'),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyRow(List<String> keys, {bool isNumeric = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: keys.map((key) {
          if (key == '⌫') {
            return _buildBackspaceKey();
          }
          return _buildKey(key, isNumeric: isNumeric);
        }).toList(),
      ),
    );
  }

  Widget _buildKey(String key, {bool isNumeric = false}) {
    String displayKey = key;
    if (!widget.numericOnly && !_isArabic && _isShift) {
      displayKey = key.toUpperCase();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => _onKeyTap(displayKey),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: isNumeric ? 70 : 36,
            height: isNumeric ? 60 : 48,
            alignment: Alignment.center,
            child: Text(
              displayKey,
              style: TextStyle(
                fontSize: isNumeric ? 24 : 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceKey() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: _onBackspace,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 70,
            height: 60,
            alignment: Alignment.center,
            child: const Icon(
              PhosphorIconsBold.backspace,
              color: Colors.orange,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpecialRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Shift key
          _buildSpecialKey(
            icon: PhosphorIconsBold.arrowUp,
            label: 'Shift',
            isActive: _isShift,
            onTap: () => setState(() => _isShift = !_isShift),
            width: 60,
          ),
          const SizedBox(width: 8),
          // Space bar
          Expanded(
            child: Material(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => _onKeyTap(' '),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  child:  Text(tr('مسافة')),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Language toggle
          _buildSpecialKey(
            icon: PhosphorIconsBold.globe,
            label: _isArabic ? 'EN' : tr('ع'),
            onTap: () => setState(() => _isArabic = !_isArabic),
            width: 50,
          ),
          const SizedBox(width: 8),
          // Backspace
          _buildSpecialKey(
            icon: PhosphorIconsBold.backspace,
            onTap: _onBackspace,
            color: Colors.orange.shade100,
            width: 60,
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialKey({
    IconData? icon,
    String? label,
    required VoidCallback onTap,
    Color? color,
    double width = 50,
    bool isActive = false,
  }) {
    return Material(
      color: isActive
          ? AppColors.primary.withValues(alpha: 0.2)
          : (color ?? Colors.grey.shade200),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: width,
          height: 48,
          alignment: Alignment.center,
          child: icon != null
              ? Icon(icon, size: 20, color: isActive ? AppColors.primary : null)
              : Text(
                  label ?? '',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isActive ? AppColors.primary : null,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        if (widget.onCancel != null)
          Expanded(
            child: ElevatedButton.icon(
              onPressed: widget.onCancel,
              icon: const Icon(PhosphorIconsBold.x),
              label:  Text(tr('إلغاء')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade300,
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        if (widget.onCancel != null) const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: widget.onDone,
            icon: const Icon(PhosphorIconsBold.check),
            label:  Text(tr('تم')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  void _onKeyTap(String key) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;

    final newText =
        text.substring(0, selection.start) +
        key +
        text.substring(selection.end);

    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + key.length),
    );

    if (_isShift && !_isArabic) {
      setState(() => _isShift = false);
    }
    setState(() {});
  }

  void _onBackspace() {
    final text = widget.controller.text;
    if (text.isEmpty) return;

    final selection = widget.controller.selection;
    if (selection.start == 0) return;

    final newText =
        text.substring(0, selection.start - 1) + text.substring(selection.end);

    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start - 1),
    );
    setState(() {});
  }
}

/// Bottom sheet wrapper for TouchKeyboard
class _TouchKeyboardSheet extends StatefulWidget {
  final TextEditingController controller;
  final bool numericOnly;
  final String? label;

  const _TouchKeyboardSheet({
    required this.controller,
    this.numericOnly = false,
    this.label,
  });

  @override
  State<_TouchKeyboardSheet> createState() => _TouchKeyboardSheetState();
}

class _TouchKeyboardSheetState extends State<_TouchKeyboardSheet> {
  late TextEditingController _localController;

  @override
  void initState() {
    super.initState();
    _localController = TextEditingController(text: widget.controller.text);
  }

  @override
  void dispose() {
    _localController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: TouchKeyboard(
            controller: _localController,
            numericOnly: widget.numericOnly,
            label: widget.label,
            onDone: () {
              widget.controller.text = _localController.text;
              Navigator.pop(context, _localController.text);
            },
            onCancel: () => Navigator.pop(context),
          ),
        ),
      ),
    );
  }
}

/// Helper extension to add touch keyboard support to TextFields
extension TouchKeyboardTextField on TextField {
  /// Wrap TextField with touch keyboard support
  static Widget withTouchKeyboard({
    required BuildContext context,
    required TextEditingController controller,
    bool numericOnly = false,
    String? label,
    InputDecoration? decoration,
    TextStyle? style,
    bool readOnly = true,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      decoration: decoration,
      style: style,
      onTap: () async {
        await TouchKeyboard.show(
          context,
          controller: controller,
          numericOnly: numericOnly,
          label: label,
        );
      },
    );
  }
}
