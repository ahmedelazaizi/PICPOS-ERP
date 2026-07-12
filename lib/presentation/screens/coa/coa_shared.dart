import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Shared type config for Chart of Accounts groups.
class AccountTypeInfo {
  final String label;
  final String range;
  final Color color;
  final IconData icon;

  const AccountTypeInfo(this.label, this.range, this.color, this.icon);
}

/// Standard type → visual config mapping for COA.
const kAccountTypeConfig = <String, AccountTypeInfo>{
  'asset': AccountTypeInfo('الأصول', '1xxx', Color(0xFF2563EB), PhosphorIconsBold.bank),
  'liability': AccountTypeInfo('الخصوم', '2xxx', Color(0xFFDC2626), PhosphorIconsBold.handCoins),
  'equity': AccountTypeInfo('حقوق الملكية', '3xxx', Color(0xFF7C3AED), PhosphorIconsBold.crown),
  'revenue': AccountTypeInfo('الإيرادات', '4xxx', Color(0xFF059669), PhosphorIconsBold.trendUp),
  'expense': AccountTypeInfo('المصروفات', '5xxx', Color(0xFFEA580C), PhosphorIconsBold.trendDown),
};

/// Format a double as an amount string.
String formatAccountAmount(double amount) {
  if (amount.abs() < 0.01) return '0.00';
  return amount.toStringAsFixed(AppConstants.decimalPlaces);
}
