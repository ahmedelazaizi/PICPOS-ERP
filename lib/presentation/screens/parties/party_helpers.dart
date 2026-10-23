import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PARTY HELPERS — Labels, colors, icons, and type utilities
// ═══════════════════════════════════════════════════════════════════════════

/// Price levels for customers.
Map<String, String> get kPriceLevels => <String, String>{
  'default': tr('افتراضي (عام)'),
  'wholesale': tr('جملة'),
  'talabat': tr('طلبات'),
  'careem': tr('كريم'),
  'ashyae': tr('أشيائي'),
};

/// Get party type display text.
String getPartyTypeLabel(Party party) {
  if (party.isDeliveryCompany == true) return tr('شركة توصيل');
  final isCustomer = party.isCustomer;
  final isSupplier = party.isSupplier;
  if (isCustomer && isSupplier) return tr('عميل مورد');
  if (isCustomer) return tr('عميل');
  if (isSupplier) return tr('مورد');
  return tr('غير محدد');
}

/// Get party type color.
Color getPartyTypeColor(Party party) {
  if (party.isDeliveryCompany == true) return Colors.teal;
  final isCustomer = party.isCustomer;
  final isSupplier = party.isSupplier;
  if (isCustomer && isSupplier) return Colors.purple;
  if (isCustomer) return AppColors.primary;
  if (isSupplier) return AppColors.warning;
  return AppColors.textMuted;
}

/// Get party icon.
IconData getPartyIcon(Party party) {
  if (party.isDeliveryCompany == true) return PhosphorIconsBold.moped;
  final isCustomer = party.isCustomer;
  final isSupplier = party.isSupplier;
  if (isCustomer && isSupplier) return PhosphorIconsBold.usersThree;
  if (isCustomer) return PhosphorIconsBold.user;
  if (isSupplier) return PhosphorIconsBold.truck;
  return PhosphorIconsBold.question;
}

/// Get Arabic name for type key.
String getTypeArabicName(String type) {
  switch (type) {
    case 'customer':
      return tr('العميل');
    case 'supplier':
      return tr('المورد');
    case 'both':
      return tr('العميل المورد');
    default:
      return 'الطرف';
  }
}
