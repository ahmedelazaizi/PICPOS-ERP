// TemplatedInvoiceService - library-level fonts and document decimals shared by the renderer parts.
part of '../templated_invoice_service.dart';

pw.Font? _arabicFont;

/// دقّةُ المستند الجاري طبعُه. تُحسم مرّةً في `printWithTemplate` **قبل**
/// بناء أيّ عنصر، لأن الإجمالياتِ قد تُبنى قبل الجدول أو بعده بحسب ترتيب
/// الأقسام — فحسمُها داخل باني الجدول كان سيترك أحدَ الطرفين على قيمةٍ
/// بائتة. والطباعةُ متسلسلةٌ فلا تتداخل مستندان.
int _docDecimals = TemplatedInvoiceService.kReceiptDecimalPlaces;

/// الخطُّ من المصنع وحدَه.
///
/// كان هنا سلَّمٌ خاصٌّ أوّلُه **Cairo** المحزوم. وCairo ينقصه الياءُ
/// المنفصلة U+FEF1، فكلُّ اسمٍ آخرُه ي بعد حرفٍ غيرِ موصول («صبري» ·
/// «بدري» · «المصري») يُطبع والياءُ راكبةٌ على ما قبلها. والمصنعُ عنده
/// نفسُ السلَّم بأساسٍ يحمل الأشكالَ كلَّها (Noto Naskh).
/// الوزنُ العريضُ **ملفٌّ لا خاصية**: الحزمة لا تصطنع العريض، فـ
/// `FontWeight.bold` بلا وجهٍ عريضٍ محمَّلٍ يسقط على العاديّ بلا أثر —
/// موثَّقٌ في `base_generator.dart:44`. ورسمُ الإيصال أرى ذلك بالعين: صفُّ
/// العناوين بعد رفع التعبئة عنه بقي بوزن البدن نفسِه.
pw.Font? _arabicBoldFont;

Future<void> _initFont() async {
  _arabicFont ??= await BaseGenerator.initFont();
  _arabicBoldFont ??= await BaseGenerator.initBoldFont();
}
