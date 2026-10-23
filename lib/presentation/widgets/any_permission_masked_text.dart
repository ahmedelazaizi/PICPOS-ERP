import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/permissions/permission_codes.dart';
import 'permission_guard.dart';

/// أكواد رؤية أرقام فواتير المبيعات — **كلاهما معاً** (AUTHZ-004).
///
/// ‏`sales_view` شرطُ قرار المالك «لا أرقامَ بلا صلاحية عرض الشاشة»، و
/// `sales_amounts_view` بوّابةٌ أشدُّ مستقلّةٌ كانت وحدَها تحجب المبالغ قبل
/// `d2272da0` فلا تُسقطها `sales_view` وحدَها. تُستعمل مع `allOf`.
const List<String> kSalesFiguresCodes = [
  PermissionCodes.salesView,
  PermissionCodes.salesAmountsView,
];

/// مبلغٌ يظهر لمن يملك **كلَّ** أكواد [allOf] (وتجاوز مدير النظام عبر
/// [PermissionGuard.allOf])، وللباقي [kMaskedValuePlaceholder].
class AllPermissionsMaskedText extends StatelessWidget {
  const AllPermissionsMaskedText({
    super.key,
    required this.allOf,
    required this.text,
    this.style,
  });

  final List<String> allOf;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return PermissionGuard.allOf(
      allOf: allOf,
      fallback: Text(
        kMaskedValuePlaceholder,
        style: (style ?? const TextStyle()).copyWith(color: AppColors.textMuted),
      ),
      child: Text(text, style: style),
    );
  }
}

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
