import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/permissions/permission_codes.dart';
import 'permission_guard.dart';

/// أكواد رؤية أرقام المبيعات: العرض الأساسي أو كود المبالغ.
const List<String> kSalesFiguresCodes = [
  PermissionCodes.salesView,
  PermissionCodes.salesAmountsView,
];

/// مبلغ يظهر لمن يملك أيّ كود من [anyOf]، وللباقي [kMaskedValuePlaceholder]
/// بنفس شكل النص (تجاوز مدير النظام عبر [PermissionGuard.anyOf]).
class AnyPermissionMaskedText extends StatelessWidget {
  const AnyPermissionMaskedText({
    super.key,
    required this.anyOf,
    required this.text,
    this.style,
  });

  final List<String> anyOf;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return PermissionGuard.anyOf(
      anyOf: anyOf,
      fallback: Text(
        kMaskedValuePlaceholder,
        style: (style ?? const TextStyle()).copyWith(color: AppColors.textMuted),
      ),
      child: Text(text, style: style),
    );
  }
}
