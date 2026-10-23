import 'package:flutter/material.dart';

/// ألوانُ حالات الطاولات — **مصدرٌ واحد** للشبكة والخريطة وعمود الحالات.
///
/// كانت الألوانُ hex ثابتةً منثورةً في ثلاثة ملفات (وخريطةُ المصمّم تختلف عن
/// البطاقة: «مشغولة» فيروزيّةٌ هنا وزرقاءُ هناك). وهي الآن تتبع سطوعَ الثيم:
/// درجةٌ أغمقُ على الخلفية الفاتحة كي يبقى النصُّ الملوَّن مقروءاً، وأفتحُ على
/// الداكنة. واللونُ **لا يكفي وحدَه** للدلالة — لذلك تُرافقه أيقونةٌ ونصٌّ في
/// كلِّ موضع (راجع `TableStatusInfo`).
///
/// مبنيٌّ ليُعاد استعمالُه في إعادة تصميم اللوحة (P5) كما هو.
abstract final class TableStatusPalette {
  /// شفافيّةُ الطاولة المعتَّمة (لا تطابق الحالةَ المميَّزة).
  static const double dimmedOpacity = 0.35;

  static const _light = <String, Color>{
    'available': Color(0xFF059669),
    'reserved': Color(0xFFB45309),
    'occupied': Color(0xFF2563EB),
    'paid': Color(0xFFEA580C),
    'out_of_service': Color(0xFF64748B),
    'cleaning': Color(0xFF4F46E5),
  };

  static const _dark = <String, Color>{
    'available': Color(0xFF10B981),
    'reserved': Color(0xFFF59E0B),
    'occupied': Color(0xFF60A5FA),
    'paid': Color(0xFFFB923C),
    'out_of_service': Color(0xFFCBD5E1),
    'cleaning': Color(0xFF818CF8),
  };

  /// الحالاتُ القديمةُ التي لا يكتبها أحد تُرسَم كـ«مشغولة» (راجع
  /// `table_status_info.dart`).
  static const _aliases = <String, String>{
    'seated': 'occupied',
    'ordered': 'occupied',
    'eating': 'occupied',
    'billing': 'occupied',
  };

  /// لونُ [status] لسطوع [brightness]. حالةٌ مجهولةٌ ترجع إلى «متاحة» كما
  /// كانت البطاقةُ تفعل.
  static Color colorFor(Brightness brightness, String status) {
    final table = brightness == Brightness.dark ? _dark : _light;
    final key = _aliases[status] ?? status;
    return table[key] ?? table['available']!;
  }

  /// لونُ [status] للثيم الحاليّ.
  static Color of(BuildContext context, String status) =>
      colorFor(Theme.of(context).brightness, status);

  /// لونٌ محايدٌ لمدخل «عرض الكل» — لا يشبه لونَ أيّ حالة.
  static Color neutral(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;
}
