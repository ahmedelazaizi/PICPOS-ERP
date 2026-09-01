/// تسويةُ نصٍّ رقميٍّ كتبه إنسان (أرقامٌ عربيّة · فواصلُ آلاف · نصُّ عملة ·
/// عشريّةٌ أوروبيّة) إلى عددٍ دارتيّ — أو `null` إن لم يكن رقماً.
///
/// ═══ لماذا في ملفٍّ مشترك ═══
///
/// كان هذا الجسمُ يعيش داخلَ `ExcelService.normalizeNumericString` وحدَه،
/// فاستوردَه محلِّلُ صفوفِ المنتجات ولم يستوردْه محلِّلُ صفوفِ كشفِ البنك —
/// وهذا الأخيرُ كان يجرّد الفاصلةَ بـ`replaceAll(',', '')` بلا فحصِ
/// موضعٍ، فـ`"1500,50"` تصير `150050`: **مئةَ ضعف**، في مبلغِ كلِّ سطرِ
/// كشف. والصفُّ يُقبَل ويُعَدُّ في «استُورد N سطراً» فلا خطأَ يظهر.
///
/// ⚠️ **ولا يُعاد اختراعُه في الطرفين**: نسختان من قواعد الفاصلة تنحرفان
/// بأوّل تعديل، فيقبل مستوردٌ ما يرفضه الآخرُ على نفس الخليّة. فالجسمُ هنا
/// واحد، و`ExcelService.normalizeNumericString` تُمرّر إليه (‏واجهتُها
/// العامّةُ باقيةٌ — لها اختبارُها `test/unit/excel_numeric_parse_test.dart`).
///
/// ⚠️ **نقيّةٌ بلا استيرادٍ إطلاقاً**: يستوردها `bank_statement_row.dart`
/// الموصوفُ بأنّه «يُقاس بلا قاعدةٍ ولا نظامِ ملفّات» — فاستيرادُ
/// `excel_service.dart` منه (وفيه `dart:io` ومنتقي الملفّات) كان سيكسر
/// ذلك العقدَ ويصنع دورةَ استيرادٍ في آنٍ واحد.
///
/// ⚠️ **و`NaN`/`Infinity` مرفوضان بحكم الخطوة ٣**: النمطُ
/// `^[+-]?[0-9.,]+…$` لا يقبل حروفاً، فـ`"NaN"` تُردُّ `null` بدل أن
/// تمرَّ عدداً غيرَ ماليٍّ يُعدي كلَّ جمعٍ بعده. أمّا `double.nan` **عدداً**
/// فلا تمرُّ بهنا أصلاً — على المنادي أن يفحص `isFinite`.
num? normalizeNumericCellText(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  // 1) Map Arabic-Indic + Extended Arabic-Indic digits and separators.
  final sb = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      sb.writeCharCode(0x30 + (r - 0x0660)); // ٠-٩ → 0-9
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      sb.writeCharCode(0x30 + (r - 0x06F0)); // ۰-۹ → 0-9
    } else if (r == 0x066B) {
      sb.write('.'); // Arabic decimal separator ٫
    } else if (r == 0x066C || r == 0x00A0 || r == 0x2009 || r == 0x202F) {
      // Arabic thousands ٬, NBSP, thin/narrow spaces → drop (grouping)
    } else {
      sb.writeCharCode(r);
    }
  }
  s = sb.toString();
  // 2) Strip known currency notations (symbols + common AR/EN abbreviations)
  //    and grouping whitespace — but NOT arbitrary letters/operators, so a
  //    formula or typo is rejected (step 3) instead of being mined for digits
  //    (e.g. "B2*1.1" must NOT become 21.1).
  const currencyTokens = [
    'ج.م.', 'ج.م', 'جنيه', 'ر.س', 'ريال', 'د.ك', 'دينار', 'درهم',
    'د.إ', 'د.ل', 'ل.س', 'ل.ل', 'egp', 'usd', 'sar', 'aed', 'kwd', 'le',
  ];
  var t = s.toLowerCase();
  for (final tok in currencyTokens) {
    t = t.replaceAll(tok, '');
  }
  t = t
      .replaceAll(RegExp(r'[\s   ]'), '') // any leftover spaces
      .replaceAll(RegExp(r'[$€£¥₺﷼%]'), ''); // currency symbols / percent
  if (t.isEmpty) return null;
  // 3) Reject anything that is not a bare (optionally grouped/signed) number —
  //    this is what keeps formulas ("=SUM(..)", "B2*1.1") and typos out.
  if (!RegExp(r'^[+-]?[0-9.,]+([eE][+-]?[0-9]+)?$').hasMatch(t)) return null;
  s = t;
  if (s == '-' || s == '+') return null;
  // 4) Resolve dot vs comma. When both appear, the LAST one is the decimal
  //    mark (covers both "1,234.56" and "1.234,56"); the other is grouping.
  final hasDot = s.contains('.');
  final hasComma = s.contains(',');
  if (hasDot && hasComma) {
    if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
      s = s.replaceAll('.', '').replaceAll(',', '.'); // European
    } else {
      s = s.replaceAll(',', ''); // English grouping
    }
  } else if (hasComma) {
    final parts = s.split(',');
    // single comma with non-3-digit tail = decimal comma (e.g. "12,5");
    // otherwise treat commas as thousands grouping.
    if (parts.length == 2 && parts[1].length != 3) {
      s = '${parts[0]}.${parts[1]}';
    } else {
      s = s.replaceAll(',', '');
    }
  }
  return double.tryParse(s);
}
