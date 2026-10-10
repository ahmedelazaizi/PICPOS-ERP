// نماذج المعدِّلات المختارة (SelectedModifier + مستوى الكمية) — مستخرَجة من
// presentation/pos/widgets/modifier_selection_dialog.dart (م3-9) كي لا يسحب
// CartItemEntity (طبقة domain المشتركة مع الويب) حوارَ POS بالاستيراد.
// الحوار يعيد تصديرها فكلُّ من يستورده يبقى يرى نفس الأسماء.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/core/i18n/tr.dart';

import '../../core/theme/app_colors.dart';

/// Quantity level for options (قليل / وسط / كثير)
enum OptionQuantityLevel {
  none,   // No quantity level (used for additions)
  light,  // قليل
  medium, // وسط
  heavy,  // كثير
}

extension OptionQuantityLevelX on OptionQuantityLevel {
  String get label => switch (this) {
    OptionQuantityLevel.none   => '',
    OptionQuantityLevel.light  => tr('قليل'),
    OptionQuantityLevel.medium => tr('بدون'),
    OptionQuantityLevel.heavy  => tr('كثير'),
  };

  Color get color => switch (this) {
    OptionQuantityLevel.none   => AppColors.textMuted,
    OptionQuantityLevel.light  => const Color(0xFFF59E0B), // Amber
    OptionQuantityLevel.medium => const Color(0xFF3B82F6), // Blue
    OptionQuantityLevel.heavy  => const Color(0xFF10B981), // Emerald
  };

  IconData get icon => switch (this) {
    OptionQuantityLevel.none   => PhosphorIconsBold.circle,
    OptionQuantityLevel.light  => PhosphorIconsBold.drop,
    OptionQuantityLevel.medium => PhosphorIconsBold.dropHalf,
    OptionQuantityLevel.heavy  => PhosphorIconsBold.dropSimple,
  };

  /// Serialize to string for DB note storage
  String get code => switch (this) {
    OptionQuantityLevel.none   => '',
    OptionQuantityLevel.light  => 'L',
    OptionQuantityLevel.medium => 'M',
    OptionQuantityLevel.heavy  => 'H',
  };

  static OptionQuantityLevel fromCode(String code) => switch (code) {
    'L' => OptionQuantityLevel.light,
    'M' => OptionQuantityLevel.medium,
    'H' => OptionQuantityLevel.heavy,
    _   => OptionQuantityLevel.none,
  };
}

/// Selected modifier item in the cart
class SelectedModifier {
  final int itemId;
  final String itemName;
  final String groupName;
  final double extraPrice;
  final bool isOption; // true = option (no price), false = addition (with price)
  final OptionQuantityLevel quantityLevel; // quantity level for options

  SelectedModifier({
    required this.itemId,
    required this.itemName,
    required this.groupName,
    required this.extraPrice,
    this.isOption = false,
    this.quantityLevel = OptionQuantityLevel.none,
  });

  /// Display text combining quantity level + item name
  String get displayText {
    if (quantityLevel != OptionQuantityLevel.none) {
      return '${quantityLevel.label} $itemName';
    }
    return itemName;
  }
}
