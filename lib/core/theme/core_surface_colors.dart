import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'readable_colors.dart';

/// أدوارُ ألوانٍ تتبع الثيم لودجتات `lib/core/widgets` (لا يجوز لها استيرادُ
/// `lib/presentation`). في الفاتح تعيد **عينَ** الثوابت التي كانت مكتوبةً.
extension CoreSurfaceColors on BuildContext {
  bool get _coreDark => Theme.of(this).brightness == Brightness.dark;

  /// نصٌّ رئيسيّ.
  Color get coreTextPrimary =>
      _coreDark ? AppColors.textPrimaryDark : AppColors.textPrimary;

  /// نصٌّ خافت.
  Color get coreTextMuted =>
      _coreDark ? AppColors.textMutedDark : AppColors.textMuted;

  /// سطحُ كرتٍ.
  Color get coreCard => _coreDark ? AppColors.cardDark : AppColors.card;

  /// لونُ هيكل التحميل (shimmer) فوق [coreCard].
  Color get coreSkeleton =>
      _coreDark ? AppColors.borderDark : AppColors.surface;

  /// لونُ حالةٍ مقصودٍ (خطأ…) يُترك كما هو في الفاتح، ويُصلَح للمقروئيّة في الداكن.
  Color coreStatusText(Color c, {Color? on}) =>
      _coreDark ? readableOn(this, c, on: on) : c;

  /// أيقونةٌ زخرفيّةٌ بشفافيّة [lightAlpha] في الفاتح (كما كانت)؛ وفي الداكن
  /// لونٌ مقروءٌ شبهُ كامل حتى لا تضيع فوق الخلفيّة الداكنة.
  Color coreSoftIcon(Color c, double lightAlpha) => _coreDark
      ? readableOn(this, c).withValues(alpha: 0.9)
      : c.withValues(alpha: lightAlpha);
}
