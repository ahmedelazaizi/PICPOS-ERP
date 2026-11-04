import 'package:flutter/material.dart';

import 'app_colors.dart';

/// حسابُ ألوانٍ **مقروءةٍ** بحسب الوضع والتباين — ملفٌّ محايدٌ لا يعتمد على
/// شاشات POS، فتستورده الودجتات العامّةُ دون أن يصل مسارُ الويب إلى `pos_*`.
/// (كان المنطقُ في `PicPosText`، ويفوّض إليه الآن.)

/// حبرُ العلامة في الوضع الغامق (`--brand-ink`)؛ الفاتحُ `AppColors.primary`.
const Color kBrandInkDark = Color(0xFF7DA6F5);

/// لونُ التسمية الصغيرة: الفاتحُ رماديٌّ غامق، والغامقُ رماديٌّ فاتح.
const Color _labelLight = Color(0xFF334155);
const Color _labelDark = Color(0xFFCBD5E1);

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// لونُ التسمية تابعاً للوضع.
Color readableLabel(BuildContext context) =>
    _isDark(context) ? _labelDark : _labelLight;

/// حبرُ الهويّة (أزرق) تابعاً للوضع: الفاتحُ `primaryDark` كما كان،
/// والغامقُ حبرُ العلامة مُصلَحاً للمقروئيّة على كرتِ الغامق.
Color readableBrand(BuildContext context) => _isDark(context)
    ? readableOn(context, kBrandInkDark)
    : AppColors.primaryDark;

/// لونٌ **مقروءٌ** فوق [on] (الافتراضيّ: كرتُ الوضع الحاليّ).
///
/// إن كان [c] يبلغ ٥:١ يُرجَع **كما هو**، وإلا تُزاح إضاءتُه (HSL) نحو الأفتح
/// في الغامق والأغمق في الفاتح حتى يبلغ ٥:١.
Color readableOn(BuildContext context, Color c, {Color? on}) {
  final dark = _isDark(context);
  final bg = on ?? (dark ? AppColors.cardDark : AppColors.card);
  if (_ratio(c, bg) >= 5.0) return c;
  final hsl = HSLColor.fromColor(c);
  final dir = dark ? 1.0 : -1.0;
  var l = hsl.lightness;
  var out = c;
  for (var i = 0; i < 40 && _ratio(out, bg) < 5.0; i++) {
    l = (l + dir * 0.025).clamp(0.0, 1.0);
    out = hsl.withLightness(l).toColor();
  }
  return out;
}

double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}
