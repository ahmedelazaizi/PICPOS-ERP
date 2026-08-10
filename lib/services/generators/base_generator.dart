import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Base class for all generators with shared font initialization
abstract class BaseGenerator {
  static pw.Font? _arabicFont;
  static pw.Font? _boldFont;
  static pw.Font? _fallbackFont;

  // ═══════════════════════════════════════════════════════════════════════
  // خطٌّ واحدٌ كامل — ولا احتياطيَّ بعد اليوم
  // ═══════════════════════════════════════════════════════════════════════
  //
  // حزمةُ `pdf` لا تُشكّل بـOpenType: تحوّل النصَّ العربيَّ إلى **أشكال
  // العرض** (Presentation Forms-B، المدى U+FE70..FEFC) قبل الرسم.
  // مقيس: «صبري» ⇒ `U+FEF1 U+FEAE U+FE92 U+FEBB`.
  //
  // ── ما كان يحدث حتى 2026-08-10 ──────────────────────────────────────────
  // كان في المشروع خطّان **كلاهما ناقص**، فأيُّ تجهيزةٍ تكسر ناحية (مقيسٌ
  // بالرسم لا بالقراءة):
  //
  //   الخطّ                     أشكالُ العرض   العربيةُ الأساسية   اللاتينيّ
  //   Noto المقصوص (١٤٦ ك.ب)    كاملة          كاملة              **ناقص ٥٢**
  //   Cairo (٥٩٩ ك.ب)           **ناقص ١٦**    **ناقص ٥**         كامل
  //
  // فبـCairo أساساً تسقط الياءُ المنفصلة `U+FEF1` — وعرضُ الرسم المفقود
  // **صفرٌ مطابقٌ لـ`.notdef`** فيُحذف الحرفُ بالسكوت ولا يظهر مربّعاً. يصيب
  // كلَّ كلمةٍ آخرُها ي بعد حرفٍ غيرِ موصول (ر ز د ذ و ا): «صبري» · «بدري» ·
  // «المصري». وبالمقصوص أساساً بلا احتياطيٍّ يخرج **رقمُ الفاتورة نفسُه**
  // مربّعات: `SINV-24` ⇒ `⊠⊠⊠⊠-24`. وبخلطهما تُمسخ الكلمات.
  //
  // ── الحلّ ───────────────────────────────────────────────────────────────
  // أصلٌ **كامل**: Noto Naskh Arabic الرسميّ (static، ١٩٩ ك.ب) — مقيسٌ صفرَ
  // نقصٍ في الأربعة: أشكالُ العرض · العربيةُ الأساسية · `A-Z a-z` · الأرقامُ
  // والعلامات. فلا يُستدعى احتياطيٌّ أبداً، ولا يختلط خطّان في سطرٍ واحد —
  // وهو ما كان يعكس اللاتينيَّ حين ينقسم السطرُ بين خطَّين.
  //
  // ومعه وزنٌ عريضٌ حقيقيّ: الحزمةُ **لا تصطنع** العريض، فبلا ملفِّ Bold كان
  // `FontWeight.bold` يسقط على العاديّ بلا أثر.
  //
  // ⚠️ لا تُعِد Cairo أساساً ولا احتياطياً. القياسُ في
  // `test/unit/pdf_arabic_glyph_coverage_test.dart` و
  // `test/structural/single_pdf_font_source_test.dart`.

  /// مُبقًى للتوافق ولحالةِ عطبٍ في الأصل الكامل — **لا يُستعمل في المسار
  /// الطبيعيّ**. Cairo ينقصه ١٦ من أشكال العرض، فاستعمالُه احتياطياً يمسخ
  /// العربية. اقرأ الشرحَ فوق.
  @Deprecated('الأصلُ الكاملُ يُغني عنه — لا تُوصّله في مستندٍ جديد')
  static Future<pw.Font?> initFallbackFont() async {
    if (_fallbackFont != null) return _fallbackFont;
    try {
      final data = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      _fallbackFont = pw.Font.ttf(data);
    } catch (e) {
      debugPrint('[Font] Fallback font unavailable: $e');
    }
    return _fallbackFont;
  }

  /// الوزنُ العريض — نفسُ العائلة، مقيسٌ كاملاً كالعاديّ.
  ///
  /// يرجع `null` لو تعذّر: الحزمةُ ساعتها تستعمل الأساسَ، وهو سلوكُ ما قبل
  /// إضافته — نصٌّ صحيحٌ بوزنٍ واحد، لا فاتورةٌ لا تُطبع.
  static Future<pw.Font?> initBoldFont() async {
    if (_boldFont != null) return _boldFont;
    try {
      final data = await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf');
      _boldFont = pw.Font.ttf(data);
      debugPrint('[Font] Loaded Noto Naskh Bold ✓');
    } catch (e) {
      debugPrint('[Font] Bold font unavailable: $e');
    }
    return _boldFont;
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
  /// ⚠️ **بلا `fontFallback`.** الأصلُ كاملٌ فلا حاجةَ له — وإضافتُه ضارّة:
  /// أيُّ رمزٍ يسقط على Cairo يُرسم بخطٍّ آخرَ داخل السطر، فينقسم السطرُ بين
  /// خطَّين ويُعكس اللاتينيُّ داخله. مقيسٌ بالرسم 2026-08-10.
  static Future<pw.Document> newDocument() async {
    final base = await initFont();
    final bold = await initBoldFont();
    return pw.Document(
      theme: pw.ThemeData.withFont(
        base: base,
        bold: bold ?? base,
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
