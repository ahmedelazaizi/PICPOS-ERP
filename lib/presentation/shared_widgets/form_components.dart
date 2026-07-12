import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';



/// Compact text field for forms
class CompactTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final bool isNumber;
  final bool enabled;
  final String? suffix;
  final int? maxLines;

  const CompactTextField({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.isNumber = false,
    this.enabled = true,
    this.suffix,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, size: 20) : null,
        suffixText: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }
}

/// Mini text field for compact forms
class MiniTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool isNumber;

  const MiniTextField({
    super.key,
    required this.controller,
    required this.label,
    this.isNumber = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        keyboardType: isNumber
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 10,
          ),
        ),
      ),
    );
  }
}

/// Toggle switch with label
class LabeledSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  const LabeledSwitch({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 20,
            color: value ? AppColors.primary : AppColors.textMuted,
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: value ? AppColors.primary : null),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.primary,
        ),
      ],
    );
  }
}
