import 'package:flutter/material.dart';

/// Professional color palette for UralCash POS System
/// Brand Colors: #134657 (Dark), #2B737F (Primary), #469CA5 (Light)
class AppColors {
  AppColors._();

  // Primary Colors - UralCash Teal Palette
  static const Color primary = Color(0xFF2B737F);       // Teal
  static const Color primaryDark = Color(0xFF134657);   // Dark Teal
  static const Color primaryLight = Color(0xFF469CA5);  // Light Teal

  // Secondary Colors
  static const Color secondary = Color(0xFF1E293B);     // Slate
  static const Color secondaryDark = Color(0xFF0F172A);
  static const Color secondaryLight = Color(0xFF334155);

  // Semantic Colors
  static const Color success = Color(0xFF22C55E);       // Green
  static const Color successDark = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);       // Amber
  static const Color warningDark = Color(0xFFD97706);
  static const Color error = Color(0xFFEF4444);         // Red
  static const Color errorDark = Color(0xFFDC2626);
  static const Color info = Color(0xFF469CA5);          // Light Teal (matches brand)
  static const Color booking = Color(0xFF8B5CF6);       // Purple (Vibrant Purple for booking)
  static const Color bookingDark = Color(0xFF7C3AED);

  // Surface Colors
  static const Color surface = Color(0xFFF8FAFC);       // Slate 50
  static const Color surfaceDark = Color(0xFF134657);   // Dark Teal
  static const Color card = Colors.white;
  static const Color cardDark = Color(0xFF1E4A5A);      // Darker Teal

  // Text Colors
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textOnPrimary = Colors.white;

  // Border Colors
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderDark = Color(0xFF2B737F);    // Primary Teal

  // Gradients - UralCash Brand
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [success, successDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient errorGradient = LinearGradient(
    colors: [error, errorDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient brandGradient = LinearGradient(
    colors: [primaryDark, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // POS Specific Colors
  static const Color posBackground = Color(0xFFF1F5F9);
  static const Color posCard = Colors.white;
  static const Color posCategoryActive = primary;
  static const Color posCategoryInactive = Color(0xFFE2E8F0);
  static const Color posPrice = success;
  static const Color posDiscount = error;
}
