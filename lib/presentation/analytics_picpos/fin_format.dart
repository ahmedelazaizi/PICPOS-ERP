// تنسيقُ وألوانُ شاشة «المؤشرات والنسب المالية» — دوالُّ عرضٍ خالصةٌ بلا
// حالةٍ ولا مزوّدات، فتُختبر بقيمٍ مبنيّةٍ يدويّاً.
//
// ⚠️ المجهولُ يُعرَض «—» أو «غير متاح» **أبداً صفراً**: صفرٌ كاذبٌ يُقرأ
//    «لا فرق» بينما المعنى «لا أعرف».
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/i18n/tr.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/analytics/kpi_comparison.dart';
import '../../domain/analytics/ratio_engine.dart';
import '../picpos_shell/picpos_surface.dart';

/// علامةُ القيمة المجهولة.
const String kFinUnknown = '—';

/// يثبّت اتجاهَ الأرقام يساراً داخل نصٍّ عربيّ (لكيلا ينقلب «-5%»).
String _ltr(String s) => '\u200E$s\u200E';

/// مبلغٌ بخانات العملة الحاليّة وفواصل الآلاف. `null` ⇒ «—».
String finMoney(double? v, {bool withSymbol = true}) {
  if (v == null || !v.isFinite) return kFinUnknown;
  final body = _grouped(v);
  return _ltr(withSymbol ? '$body ${AppConstants.currencySymbolEn}' : body);
}

String _grouped(double v) {
  final dp = AppConstants.decimalPlaces;
  return NumberFormat('#,##0${dp > 0 ? '.${'0' * dp}' : ''}', 'en').format(v);
}

/// نسبةٌ مئويّةٌ بخانةٍ عشريّةٍ واحدة، بإشارةٍ صريحة. `null` ⇒ «—».
String finPercent(double? v, {bool signed = false}) {
  if (v == null || !v.isFinite) return kFinUnknown;
  final sign = signed && v > 0 ? '+' : '';
  return _ltr('$sign${v.toStringAsFixed(1)}%');
}

/// فرقٌ بمبلغ بإشارةٍ صريحة (للتغيّر حين يتعذّر حسابُ النسبة).
String finSignedMoney(double? v) {
  if (v == null || !v.isFinite) return kFinUnknown;
  final sign = v > 0 ? '+' : '';
  return _ltr('$sign${_grouped(v)}');
}

/// قيمةُ نسبةٍ بوحدتها. `null` ⇒ «—».
String finRatioValue(double? v, RatioUnit unit) {
  if (v == null || !v.isFinite) return kFinUnknown;
  switch (unit) {
    case RatioUnit.percent:
      return _ltr('${v.toStringAsFixed(1)}%');
    case RatioUnit.times:
      return _ltr('${v.toStringAsFixed(2)}×');
    case RatioUnit.days:
      return '${_ltr(v.toStringAsFixed(1))} ${tr('يوم')}';
  }
}

/// اسمُ المجموعة بلغة الواجهة.
String finGroupLabel(RatioGroup g) => switch (g) {
      RatioGroup.liquidity => tr('السيولة'),
      RatioGroup.profitability => tr('الربحية'),
      RatioGroup.efficiency => tr('الكفاءة'),
      RatioGroup.leverage => tr('الرافعة المالية'),
      RatioGroup.cashFlow => tr('التدفقات النقدية'),
      RatioGroup.growth => tr('النمو'),
    };

IconData finGroupIcon(RatioGroup g) => switch (g) {
      RatioGroup.liquidity => Icons.water_drop_outlined,
      RatioGroup.profitability => Icons.trending_up,
      RatioGroup.efficiency => Icons.speed,
      RatioGroup.leverage => Icons.balance,
      RatioGroup.cashFlow => Icons.payments_outlined,
      RatioGroup.growth => Icons.show_chart,
    };

/// نصُّ الحالة (يُعرَض مع اللون دائماً — اللونُ وحدَه لا يكفي).
String finStatusLabel(RatioStatus s) => switch (s) {
      RatioStatus.good => tr('جيد'),
      RatioStatus.warning => tr('تحذير'),
      RatioStatus.bad => tr('خطر'),
      RatioStatus.unknown => tr('غير محدد'),
    };

IconData finStatusIcon(RatioStatus s) => switch (s) {
      RatioStatus.good => Icons.check_circle_outline,
      RatioStatus.warning => Icons.warning_amber_rounded,
      RatioStatus.bad => Icons.error_outline,
      RatioStatus.unknown => Icons.help_outline,
    };

/// لونُ الحالة من رموز الثيم الدلاليّة.
Color finStatusColor(BuildContext context, RatioStatus s) => switch (s) {
      RatioStatus.good => AppColors.success,
      RatioStatus.warning => AppColors.warning,
      RatioStatus.bad => AppColors.error,
      RatioStatus.unknown => context.picposMuted,
    };

/// لونُ المواءمة: مؤاتٍ أخضر، غيرُ مؤاتٍ أحمر، وغيرُ ذلك خافت.
Color finFavourColor(BuildContext context, Favourability f) => switch (f) {
      Favourability.favourable => AppColors.success,
      Favourability.unfavourable => AppColors.error,
      Favourability.neutral || Favourability.unknown => context.picposMuted,
    };

/// أيقونةُ اتجاه التغيّر (لا سهمَ حين لا فرقَ أو لا معلوم).
IconData? finFavourIcon(Variance v) {
  final a = v.amount;
  if (a == null || a == 0) return null;
  return a > 0 ? Icons.arrow_upward : Icons.arrow_downward;
}
