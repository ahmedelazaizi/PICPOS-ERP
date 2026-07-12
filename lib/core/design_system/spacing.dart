/// Spacing constants for consistent layout
///
/// Usage:
/// ```dart
/// Padding(padding: EdgeInsets.all(Spacing.md))
/// SizedBox(height: Spacing.lg)
/// ```
library;

/// Spacing scale following 4px base
abstract final class Spacing {
  Spacing._();

  /// 4px - Micro spacing
  static const double xs = 4;

  /// 8px - Small spacing
  static const double sm = 8;

  /// 12px - Medium-small spacing
  static const double md = 12;

  /// 16px - Medium spacing
  static const double lg = 16;

  /// 24px - Large spacing
  static const double xl = 24;

  /// 32px - Extra large spacing
  static const double xxl = 32;

  /// 48px - Section spacing
  static const double section = 48;

  /// 64px - Page spacing
  static const double page = 64;
}

/// Border radius constants
abstract final class Radii {
  Radii._();

  /// 4px - Small radius
  static const double sm = 4;

  /// 8px - Medium radius
  static const double md = 8;

  /// 12px - Large radius
  static const double lg = 12;

  /// 16px - Extra large radius
  static const double xl = 16;

  /// Full circle
  static const double full = 999;
}

/// Icon sizes
abstract final class IconSizes {
  IconSizes._();

  /// 12px - Micro
  static const double xs = 12;

  /// 16px - Small
  static const double sm = 16;

  /// 20px - Medium
  static const double md = 20;

  /// 24px - Large
  static const double lg = 24;

  /// 32px - Extra large
  static const double xl = 32;

  /// 48px - Jumbo
  static const double xxl = 48;
}

/// Touch target sizes
abstract final class TouchTargets {
  TouchTargets._();

  /// 36px - Minimum touch target
  static const double min = 36;

  /// 44px - Standard touch target (recommended)
  static const double standard = 44;

  /// 56px - Large touch target
  static const double large = 56;
}
