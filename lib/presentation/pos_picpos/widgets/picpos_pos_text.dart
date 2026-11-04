import 'package:flutter/material.dart';

import '../../../core/theme/readable_colors.dart' as readable;
import '../../picpos_shell/picpos_surface.dart';

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
///
/// ── لماذا صارت الدوالُّ تأخذ `BuildContext` (2026-08-29) ──────────────────
///
/// كان اللونان ثابتَين: `#0A0A0A` للقيمة و`#334155` للتسمية. وكلاهما **حبرٌ
/// داكنٌ على أرضيّةٍ فاتحة**، فبقيا كما هما في الوضع الغامق — حبرٌ أسودُ على
/// كرتٍ داكن. وهو الشطرُ الثاني من بلاغ المالك 2026-08-29 («تضاربٌ في ألوان
/// النصوص»)، وأوسعُ أثراً من أيِّ أرضيّةٍ لأنّ الكلاسَ يغذّي **٥٤** موضعاً
/// في `pos_picpos/`.
///
/// ⚠️ **ولماذا `BuildContext` إلزاميٌّ لا اختياريّ.** الاختياريُّ كان يعني
/// أنّ موضعاً يَنسى تمريرَه يبقى فاتحاً **صامتاً** — لا خطأ ترجمةٍ ولا اختبارٌ
/// أحمر. والإلزامُ يجعل المحلّلَ يعدُّ المواضعَ نيابةً عنّا: ٥٤ موضعاً لا
/// يُترجَم أحدُها حتّى يُمرَّر السياق.
///
/// ⚠️ **و[_value] و[_label] خاصّتان عمداً.** كانتا عامّتَين ويُقرآن مباشرةً
/// في ثلاثةِ مواضع، وكلُّ قراءةٍ مباشرةٍ تتجاوز شرطَ الوضع. وخصخصتُهما تسدُّ
/// البابَ بالمحلّل لا بالمراجعة.
class PicPosText {
  const PicPosText._();

  /// لون القيم في **الوضع الفاتح**: الأرقام، أسماء الأصناف، الإجماليات.
  ///
  /// أسود شبه صافي مش `Colors.black` القاطع — شاشات التِل الرخيصة بتعمل
  /// halation حوالين الأسود المطلق على خلفية بيضاء فالنص يبان مهزوز.
  static const Color _value = Color(0xFF0A0A0A);

  /// لونُ القيمة تابعاً للوضع.
  ///
  /// الفاتحُ يبقى [_value] **بايتاً ببايت** — حجّةُ الـhalation أعلاه ما زالت
  /// قائمةً ولم يتغيّر شيءٌ لمستعملي الوضع الفاتح.
  ///
  /// والداكنُ يأخذ حبرَ الثيم نفسَه (`context.picposText`) لا رمزاً جديداً:
  /// شاشةٌ واحدةٌ بحبرَين هي عينُ العطبِ الموصوفِ في `AppColors.cardDark`.
  static Color valueOf(BuildContext context) =>
      context.picposIsDark ? context.picposText : _value;

  /// لونُ التسمية تابعاً للوضع — الفاتحُ `#334155` (رمادي غامق بدل
  /// `picposMuted` الباهت على شاشات التِل) والداكنُ `#CBD5E1` (تباينه ٦٫٤ على
  /// كرت الافتراضيّة و١١٫٥ على كرت PicPos). القيمتان في `readable_colors.dart`.
  static Color labelOf(BuildContext context) =>
      readable.readableLabel(context);

  /// حبرُ الهويّة (أزرق) تابعاً للوضع: الفاتحُ `primaryDark` كما كان،
  /// والداكنُ `picposBrandInk` — `primaryDark` على كرتٍ داكن غير مقروء.
  static Color brandOf(BuildContext context) => readable.readableBrand(context);

  /// لونٌ دلاليٌّ (أحمر/أخضر/كهرماني) **مقروءٌ** فوق كرتِ الوضع الحاليّ.
  ///
  /// ألوانُ `AppColors.error/success/warning` مضبوطةٌ للأرضيّة الفاتحة، فتهبط
  /// تحت ٤٫٥:١ على الكرت الداكن (أحمر ٢٫٥) — وأخضر `#22C55E` على الفاتح
  /// نفسِه ٢٫١. فإن كان [c] مقروءاً يُرجَع **كما هو** (الهويّةُ بايتاً ببايت)،
  /// وإلا تُزاح إضاءتُه (HSL) نحو الأفتح في الغامق والأغمق في الفاتح حتى
  /// يبلغ ٥:١ على [on] (الافتراضيّ: كرتُ الوضع).
  static Color readableOn(BuildContext context, Color c, {Color? on}) =>
      readable.readableOn(context, c, on: on);

  /// نمط قيمة: بولد وحبرُ القيمة. المقاس من المستدعي دايماً.
  ///
  /// [color] للألوان الدلالية (أخضر للربح، أحمر للمديونية) — بتغلب [valueOf]
  /// عشان الدلالة أهم من التوحيد.
  static TextStyle v(
    BuildContext context,
    double size, {
    FontWeight weight = FontWeight.bold,
    Color? color,
    FontStyle? fontStyle,
  }) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color ?? valueOf(context),
        fontStyle: fontStyle,
      );

  /// نمط تسمية: بولد وحبرُ التسمية. المقاس من المستدعي دايماً.
  static TextStyle l(
    BuildContext context,
    double size, {
    FontWeight weight = FontWeight.bold,
    Color? color,
    FontStyle? fontStyle,
  }) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color ?? labelOf(context),
        fontStyle: fontStyle,
      );
}
