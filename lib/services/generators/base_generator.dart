import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Base class for all generators with shared font initialization
abstract class BaseGenerator {
  static pw.Font? _arabicFont;
  static pw.Font? _fallbackFont;

  // ═══════════════════════════════════════════════════════════════════════
  // لماذا Noto Naskh أساسيٌّ وCairo احتياطيّ — وليس العكس
  // ═══════════════════════════════════════════════════════════════════════
  //
  // حزمةُ `pdf` لا تُشكّل بـOpenType: تحوّل النصَّ العربيَّ إلى **أشكال
  // العرض** (Presentation Forms-B، المدى U+FE70..FEFC) قبل الرسم.
  // مقيس: «صبري» ⇒ `U+FEF1 U+FEAE U+FE92 U+FEBB`.
  //
  // و`Cairo-Regular.ttf` ينقصه **١٧** من هذه الأشكال، منها الياءُ المنفصلة
  // `U+FEF1`. والأسوأُ من النقص شكلُه: عرضُ الرسم المفقود **صفرٌ مطابقٌ
  // لـ`.notdef`** ⇒ الحرفُ **يُحذف بالسكوت** ولا يظهر مربّعاً يلفت النظر.
  // يصيب كلَّ كلمةٍ آخرُها ي بعد حرفٍ غيرِ موصول (ر ز د ذ و ا): «صبري» ·
  // «بدري» · «خيري» · «المصري» — أسماءُ عملاءَ وأصنافٍ على كلّ مطبوع.
  //
  // ⚠️ **وإعادةُ تنزيل Cairo لا تُصلحه**: المرفوعُ مطابقٌ للرسميِّ من مستودع
  // google/fonts بايت ببايت (نفسُ SHA-256) — أي أن الخطَّ الرسميَّ نفسَه بلا
  // الرسم. الحلُّ خطٌّ آخر لا نسخةٌ أحدث.
  //
  // ⚠️⚠️ **و`fontFallback` وحدَه لا يُصلحه** — وهذا ما كان يبدو الحلَّ:
  // الحزمةُ تختار الخطَّ الاحتياطيَّ في `_preProcessSpans` على النصّ
  // **المنطقيّ** (‏`ص ب ر ي` = U+0635 U+0628 U+0631 U+064A) وCairo يحملها
  // كلَّها، فلا يُستدعى الاحتياطيُّ إطلاقاً. ثم يحوّل السطرُ 957 النصَّ إلى
  // أشكال العرض ويرسمها **بالخطّ المختار سلفاً**. مقيس: المستندُ يخرج بخطٍّ
  // واحدٍ حتى مع الثيم والاتجاه RTL.
  //
  // ⇒ الخطُّ الحاملُ لأشكال العرض لازم يكون **الأساسيّ**. قرارُ المالك
  // 2026-08-10: Noto Naskh أساسيّ (يغطّي ١٤٠/١٤١ — والناقصُ `U+FE75` نقطةٌ
  // **غيرُ مخصَّصةٍ** في يونيكود، فالتغطيةُ عملياً كاملة · ترخيصُ OFL).
  //
  // ولأن Noto ينقصه ٨٠ من ٩٥ محرفاً لاتينياً (مقيس)، يبقى Cairo احتياطياً —
  // والاحتياطيُّ **يعمل** للاتيني والأرقام لأنها غيرُ مُشكَّلةٍ أصلاً، فنقاطُها
  // المنطقيةُ هي نفسُها المرسومة. لا يختلط خطّان داخل الكلمة الواحدة.

  /// الخطُّ الاحتياطيّ — Cairo، للاتينيّ والأرقام وعلامات الترقيم التي لا
  /// يحملها الأساسيّ. اقرأ الشرحَ فوق ولا تعكس الدورَين.
  static Future<pw.Font?> initFallbackFont() async {
    if (_fallbackFont != null) return _fallbackFont;
    try {
      final data = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      _fallbackFont = pw.Font.ttf(data);
      debugPrint('[Font] Loaded Cairo fallback (latin/digits) ✓');
    } catch (e) {
      // لا نعطّل الطباعة: الغيابُ يترك اللاتينيَّ على الأساسيّ، وهو أهونُ من
      // فاتورةٍ لا تُطبع.
      debugPrint('[Font] Fallback font unavailable: $e');
    }
    return _fallbackFont;
  }

  /// الخطُّ الأساسيّ — Noto Naskh Arabic، وهو الذي يحمل أشكالَ العرض.
  ///
  /// IMPORTANT: Only cache successful Arabic loads — never cache Helvetica,
  /// so the next print retries instead of permanently using a non-Arabic font.
  static Future<pw.Font> initFont() async {
    if (_arabicFont != null) return _arabicFont!;

    // ① الأصلُ المحزوم (يعمل بلا إنترنت على أجهزة نقطة البيع)
    try {
      final fontData =
          await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
      _arabicFont = pw.Font.ttf(fontData);
      debugPrint('[Font] Loaded Noto Naskh from bundled asset ✓');
      return _arabicFont!;
    } catch (e) {
      debugPrint('[Font] Bundled Noto Naskh failed: $e');
    }

    // ② Cairo المحزوم — يطبع عربياً لكن بحرفٍ ناقصٍ في ١٧ شكلاً. أهونُ من
    //    مربّعاتٍ أو فشلِ طباعة، ويُسجَّل تحذيراً كي لا يمرّ صامتاً.
    try {
      final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      _arabicFont = pw.Font.ttf(fontData);
      debugPrint('[Font] WARNING: fell back to Cairo as BASE — 17 Arabic '
          'presentation forms (incl. U+FEF1 ي) will be silently dropped.');
      return _arabicFont!;
    } catch (e) {
      debugPrint('[Font] Bundled Cairo failed: $e');
    }

    // ③ الشبكة (تحتاج إنترنت)
    try {
      _arabicFont = await PdfGoogleFonts.notoNaskhArabicRegular();
      debugPrint('[Font] Loaded Noto Naskh from Google Fonts ✓');
      return _arabicFont!;
    } catch (e) {
      debugPrint('[Font] Google Fonts failed: $e');
    }

    // ④ Last resort: Helvetica — returned but NOT cached so next call retries
    debugPrint('[Font] WARNING: All Arabic font sources failed — Arabic text will show as boxes. '
        'Ensure assets/fonts/NotoNaskhArabic-Regular.ttf is bundled correctly.');
    return pw.Font.helvetica();
  }

  /// **المدخلُ الوحيد لإنشاء مستند PDF في المشروع.** لا تنادِ `pw.Document()`
  /// مباشرةً: المستندُ العاري بلا `theme` يعني أن كلَّ نصٍّ يقع على خطٍّ واحد،
  /// وأيُّ رسمٍ ينقصه ذلك الخطُّ **يُحذف بالسكوت**.
  ///
  /// ── لماذا `theme` لا `TextStyle` في كلّ موضع ───────────────────────────
  /// حزمةُ `pdf` تختار الخطَّ لكلّ نقطةٍ في `text.dart`:
  /// ```
  /// if (!font.isRuneSupported(rune)) { for (final fb in style.fontFallback) … }
  /// ```
  /// و`TextStyle.merge` يجمع القائمتَين:
  /// `fontFallback: [...other.fontFallback, ...fontFallback]`
  /// فالاحتياطيُّ الموضوعُ في `Theme.defaultTextStyle` **يبقى حتى مع `font:`
  /// صريحٍ** في النمط المحلّيّ — وهو ما يجعل الوصلَ مرّةً واحدةً لكلّ مستندٍ
  /// كافياً بدل ٣٧ موضعَ نمط. (‏مقروءٌ من مصدر الحزمة 3.12.0، لا مفترَض.)
  ///
  /// و`isRuneSupported` حرفياً `charToGlyphIndexMap.containsKey(charCode)` —
  /// وهي نفسُ الخريطة التي يقيسها
  /// `test/unit/pdf_arabic_glyph_coverage_test.dart`.
  ///
  /// غيابُ الاحتياطيّ لا يعطّل الطباعة: المستندُ يخرج بالخطّ الأساسيّ وحدَه،
  /// أي سلوكُ ما قبل الإصلاح.
  static Future<pw.Document> newDocument() async {
    final base = await initFont();
    final fb = await initFallbackFont();
    return pw.Document(
      theme: pw.ThemeData.withFont(
        base: base,
        fontFallback: fb == null ? const [] : [fb],
      ),
    );
  }
}

/// Invoice item model for generators
class InvoiceItem {
  final String name;
  final double quantity;
  final double price;
  final double total;
  final String? note;

  InvoiceItem({
    required this.name,
    required this.quantity,
    required this.price,
    required this.total,
    this.note,
  });
}

/// Statement item model for party statements
class StatementItem {
  final DateTime date;
  final String description;
  final double debit;
  final double credit;
  final double balance;

  StatementItem({
    required this.date,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
  });
}
