import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Base class for all generators with shared font initialization
abstract class BaseGenerator {
  static pw.Font? _arabicFont;
  static pw.Font? _fallbackFont;

  /// خطٌّ احتياطيٌّ يُمرَّر في `fontFallback` بجانب [initFont].
  ///
  /// ── لماذا يلزم ────────────────────────────────────────────────────────────
  /// حزمةُ `pdf` تحوّل النصَّ العربيَّ إلى **أشكال العرض** (Presentation
  /// Forms-B، المدى FE70–FEFF) قبل الرسم لأنها لا تُشكّل بـOpenType. و
  /// `Cairo-Regular.ttf` المرفوع ينقصه **الياءُ المنفصلة `U+FEF1`**.
  ///
  /// والأسوأُ من النقص شكلُه: عرضُ الرسم المفقود **صفر**، مطابقٌ تماماً لعرض
  /// `.notdef` (‏قِيس بنقطةِ استعمالٍ خاصٍّ `U+E000` = 0.0). فالحرفُ **يُحذف
  /// بالسكوت** ولا يظهر مربّعاً يلفت النظر — تُقرأ الكلمةُ ناقصةً وكأنها كلمةٌ
  /// أخرى. يصيب كلَّ كلمةٍ آخرُها ي بعد حرفٍ غيرِ موصول (ر ز د ذ و ا):
  /// «صبري» · «بدري» · «خيري» · «المصري» — أسماءُ عملاءَ وأصنافٍ تُطبَع على
  /// كلّ إيصالٍ وفاتورة.
  ///
  /// ⚠️ **وإعادةُ تنزيل Cairo لا تُصلحه**: الملفُّ المرفوع مطابقٌ للرسميِّ من
  /// مستودع google/fonts **بايت ببايت** (نفسُ SHA-256، مقيس 2026-08-10) — أي
  /// أنّ الخطَّ الرسميَّ نفسَه لا يحمل الرسم. الحلُّ خطٌّ آخر لا نسخةٌ أحدث.
  ///
  /// Noto Naskh Arabic يغطّي ١٤٠ من ١٤١ من المدى (‏والناقصُ `U+FE75` نقطةٌ
  /// **غيرُ مخصَّصةٍ** في يونيكود) فالتغطيةُ عملياً كاملة. ترخيصُ OFL.
  ///
  /// ⚠️ **غيرُ موصولٍ بعدُ بمواقع الرسم.** الأصلُ محزومٌ والمُحمِّلُ جاهز، لكنّ
  /// مواضعَ `pw.TextStyle` لا تمرّر `fontFallback` بعد، و٣٨ موضعَ
  /// `pw.Document(` لا يضع أيٌّ منها `theme:`. الوصلُ الأنظف مرّةً واحدةً لكلّ
  /// مستند:
  /// ```dart
  /// pw.Document(theme: pw.ThemeData.withFont(base: arabicFont, fontFallback: [fb]))
  /// ```
  /// لأنّ `Text` يدمج `Theme.defaultTextStyle` مع النمط المحلّيّ، فـ
  /// `fontFallback` يبقى حتى مع `font:` صريحٍ في النمط.
  static Future<pw.Font?> initFallbackFont() async {
    if (_fallbackFont != null) return _fallbackFont;
    try {
      final data =
          await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
      _fallbackFont = pw.Font.ttf(data);
      debugPrint('[Font] Loaded Noto Naskh fallback ✓');
    } catch (e) {
      // لا نعطّل الطباعة: الغيابُ يعيد سلوكَ ما قبل الإصلاح (حرفٌ ناقص) وهو
      // أهونُ من فاتورةٍ لا تُطبع.
      debugPrint('[Font] Fallback font unavailable: $e');
    }
    return _fallbackFont;
  }

  /// Initialize Arabic font — local bundled asset first, Google Fonts fallback.
  /// IMPORTANT: Only cache successful Cairo loads — never cache Helvetica fallback,
  /// so the next print retries instead of permanently using a non-Arabic font.
  static Future<pw.Font> initFont() async {
    if (_arabicFont != null) return _arabicFont!;

    // ① Load from bundled asset (works offline on POS machines)
    try {
      final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      _arabicFont = pw.Font.ttf(fontData);
      debugPrint('[Font] Loaded Cairo from bundled asset ✓');
      return _arabicFont!;
    } catch (e) {
      debugPrint('[Font] Bundled asset failed: $e');
    }

    // ② Fallback: download from Google Fonts (requires internet)
    try {
      _arabicFont = await PdfGoogleFonts.cairoRegular();
      debugPrint('[Font] Loaded Cairo from Google Fonts ✓');
      return _arabicFont!;
    } catch (e) {
      debugPrint('[Font] Google Fonts failed: $e');
    }

    // ③ Last resort: Helvetica — returned but NOT cached so next call retries
    debugPrint('[Font] WARNING: All Arabic font sources failed — Arabic text will show as boxes. '
        'Ensure assets/fonts/Cairo-Regular.ttf is bundled correctly.');
    return pw.Font.helvetica();
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
