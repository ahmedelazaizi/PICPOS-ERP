/// Industry Mode Strategy Pattern
///
/// Encapsulates mode-specific POS behavior for Supermarket, Restaurant, and Cafe modes.
/// This reduces conditional logic scattered across POS components.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../data/database/database.dart';

/// Abstract strategy defining mode-specific POS behavior
abstract class IndustryModeStrategy {
  /// The mode this strategy represents
  IndustryMode get mode;

  /// Display name for this mode (Arabic)
  String get displayName;

  /// Icon representing this mode
  IconData get icon;

  /// Whether barcode scanning is the primary input method
  bool get showBarcodeInput => true;

  /// Whether to show table selection (restaurant mode only)
  bool get showTableSelection => false;

  /// Whether to show kitchen print button
  bool get showKitchenPrint => false;

  /// Whether to show scale connection indicator
  bool get showScaleIndicator => false;

  /// Whether to show "Save & Print" quick action
  bool get showSaveAndPrint => false;

  /// Whether to show delivery options
  bool get showDeliveryOptions => false;

  /// Whether to show invoice lookup
  bool get showInvoiceLookup => true;

  /// Whether to show held orders functionality
  bool get showHeldOrders => true;

  /// Whether to require table selection before ordering
  bool get requireTableSelection => false;

  /// Primary action button label
  String get primaryActionLabel => 'إتمام البيع';

  /// Primary action button icon
  IconData get primaryActionIcon => PhosphorIconsBold.shoppingCartSimple;

  /// Whether product grid should use compact layout
  bool get useCompactGrid => false;

  /// Number of default grid columns
  int get defaultGridColumns => 4;

  /// Factory method to get strategy for a given mode
  static IndustryModeStrategy forMode(IndustryMode mode) {
    switch (mode) {
      case IndustryMode.supermarket:
        return SupermarketStrategy();
      case IndustryMode.restaurant:
        return RestaurantStrategy();
      case IndustryMode.cafe:
        return CafeStrategy();
      case IndustryMode.retail:
        return SupermarketStrategy();
    }
  }
}

/// Supermarket mode - optimized for fast retail sales
class SupermarketStrategy extends IndustryModeStrategy {
  @override
  IndustryMode get mode => IndustryMode.supermarket;

  @override
  String get displayName => 'سوبر ماركت / بيع بالتجزئة';

  @override
  IconData get icon => PhosphorIconsBold.barcode;

  @override
  bool get showBarcodeInput => true;

  @override
  bool get showScaleIndicator => true;

  @override
  bool get showSaveAndPrint => true;

  @override
  bool get showDeliveryOptions => true;

  @override
  bool get showInvoiceLookup => true;

  @override
  String get primaryActionLabel => 'إتمام البيع';

  @override
  IconData get primaryActionIcon => PhosphorIconsBold.shoppingCartSimple;

  @override
  int get defaultGridColumns => 4;
}

/// Restaurant mode - table-based ordering with kitchen integration
class RestaurantStrategy extends IndustryModeStrategy {
  @override
  IndustryMode get mode => IndustryMode.restaurant;

  @override
  String get displayName => 'مطعم / صالات طعام';

  @override
  IconData get icon => PhosphorIconsBold.cookingPot;

  @override
  bool get showBarcodeInput => false;

  @override
  bool get showTableSelection => true;

  @override
  bool get showKitchenPrint => true;

  @override
  bool get requireTableSelection => true;

  @override
  String get primaryActionLabel => 'إرسال للمطبخ';

  @override
  IconData get primaryActionIcon => PhosphorIconsBold.cookingPot;

  @override
  bool get useCompactGrid => true;

  @override
  int get defaultGridColumns => 3;
}

/// Cafe mode - quick orders without table management
class CafeStrategy extends IndustryModeStrategy {
  @override
  IndustryMode get mode => IndustryMode.cafe;

  @override
  String get displayName => 'كافيه / طلبات سريعة';

  @override
  IconData get icon => PhosphorIconsBold.coffee;

  @override
  bool get showBarcodeInput => false;

  @override
  bool get showKitchenPrint => true;

  @override
  bool get showHeldOrders => true;

  @override
  String get primaryActionLabel => 'إتمام الطلب';

  @override
  IconData get primaryActionIcon => PhosphorIconsBold.coffee;

  @override
  bool get useCompactGrid => true;

  @override
  int get defaultGridColumns => 3;
}

/// Extension to easily get strategy from IndustryMode
extension IndustryModeStrategyExtension on IndustryMode {
  IndustryModeStrategy get strategy => IndustryModeStrategy.forMode(this);
}
