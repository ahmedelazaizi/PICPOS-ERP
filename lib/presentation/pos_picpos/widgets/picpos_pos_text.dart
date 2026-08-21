import 'package:flutter/material.dart';

/// أنماط نص نقطة بيع PicPos — **الوزن واللون فقط**.
///
/// ── ليه كلاس منفصل ومش تعديل في `PicPosTheme`؟ ────────────────────────────
/// `PicPosTheme` بيغذّي ~٣٠ شاشة PicPos تانية (الأصناف، الأطراف، التقارير،
/// الإعدادات...). تعديل `textTheme` هناك كان معناه إن قرار خاص بشاشة الكاشير
/// يتسرّب لكل حاجة في المنتج. فالتثبيت بيحصل هنا، ويُستدعى من ودجات
/// `pos_picpos/` بس.
///
/// ── ليه مفيش مقاسات جوه الكلاس ────────────────────────────────────────────
/// المقاسات في البيع السريع **بيانات** مش ثوابت: `posCartItemScaleProvider` و
/// `posButtonFontSizeProvider` و `posBottomPanelScaleProvider` وغيرهم
/// (`settings_providers.dart`) بيضبطهم المدير من ديالوج إعدادات العرض وهو شايف
/// النتيجة على شاشة التِل. فالمستدعي هو اللي بيحدّد المقاس دايماً، والكلاس ده
/// بيثبّت الوزن (bold) واللون. لو حطّينا مقاسات هنا كنا هنكسر السلايدرز.
///
/// ── التسميات بولد كمان ────────────────────────────────────────────────────
/// القرار كان «القيم بولد أسود، التسميات بولد رمادي غامق». فـ [l] بولد برضه —
/// التفرقة بقت في اللون لوحده، مش في الوزن.
class PicPosText {
  const PicPosText._();

  /// لون القيم: الأرقام، أسماء الأصناف، الإجماليات.
  ///
  /// أسود شبه صافي مش `Colors.black` القاطع — شاشات التِل الرخيصة بتعمل
  /// halation حوالين الأسود المطلق على خلفية بيضاء فالنص يبان مهزوز.
  static const Color value = Color(0xFF0A0A0A);

  /// لون التسميات الصغيرة: «التاريخ»، «رقم الفاتورة»، رؤوس الأعمدة.
  ///
  /// رمادي غامق مقروء بدل `AppColors.textMuted` (`#6B7280`) اللي كان باهت على
  /// شاشات التِل تحت إضاءة المحل.
  static const Color label = Color(0xFF334155);

  /// نمط قيمة: بولد وأسود غامق. المقاس من المستدعي دايماً.
  ///
  /// [color] للألوان الدلالية (أخضر للربح، أحمر للمديونية) — بتغلب [value]
  /// عشان الدلالة أهم من التوحيد.
  static TextStyle v(
    double size, {
    FontWeight weight = FontWeight.bold,
    Color? color,
    FontStyle? fontStyle,
  }) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color ?? value,
        fontStyle: fontStyle,
      );

  /// نمط تسمية: بولد ورمادي غامق. المقاس من المستدعي دايماً.
  static TextStyle l(
    double size, {
    FontWeight weight = FontWeight.bold,
    Color? color,
    FontStyle? fontStyle,
  }) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color ?? label,
        fontStyle: fontStyle,
      );
}
