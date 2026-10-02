// هويّةُ الشركة على المطبوع — الاسمُ الإنجليزيُّ والسجلُّ التجاريّ.
//
// الخطوةُ الثانيةُ في معالج الإعداد تحفظ `company_name_en` و`company_cr_number`،
// ولم يكن أيُّ مطبوعٍ يقرؤهما. فهذا الملفُّ **مصدرٌ واحدٌ** لقواعد ظهورهما، كي
// لا يكتب كلُّ مولّدٍ (قوالبُ v1 وv2 والمولّداتُ الاحتياطيّة) قاعدتَه فتفترق:
//
//   • مستندٌ إنجليزيّ: الاسمُ الإنجليزيُّ هو الاسمُ الرئيسيُّ إن وُجد.
//   • مستندٌ عربيّ: الاسمُ العربيُّ رئيسيٌّ، والإنجليزيُّ سطرٌ ثانويٌّ تحته.
//   • السجلُّ التجاريُّ بجوار الرقم الضريبيّ: «س.ت: …» / "CR: …".
//   • فارغٌ ⇒ لا شيء — لا تسميةَ معلَّقةً بلا قيمة.
//
// حسابٌ خالصٌ: لا `package:pdf` ولا `package:flutter` (يحرسه اختبارٌ بنيويّ).
library;

import 'print_values.dart' show ltrIsolate;

/// مفتاحا الإعداد اللذان يكتبهما المعالجُ وشاشةُ «معلومات الشركة».
const String kCompanyNameEnSetting = 'company_name_en';
const String kCompanyCrNumberSetting = 'company_cr_number';

bool _isEnglish(String locale) => locale == 'en';

String _clean(String? v) => (v ?? '').trim();


/// الاسمُ الرئيسيُّ للشركة بلغة المستند.
String companyMainName({
  required String nameAr,
  String? nameEn,
  String locale = 'ar',
}) {
  final en = _clean(nameEn);
  if (_isEnglish(locale) && en.isNotEmpty) return en;
  return nameAr;
}

/// السطرُ الثانويّ — الاسمُ الإنجليزيُّ تحت العربيّ. `''` إن لم يلزم.
String companySecondaryName({
  required String nameAr,
  String? nameEn,
  String locale = 'ar',
}) {
  final en = _clean(nameEn);
  if (_isEnglish(locale) || en.isEmpty) return '';
  // لا يُكرَّر الاسمُ نفسُه إن كُتب العربيُّ والإنجليزيُّ بالحروف ذاتها.
  if (en == nameAr.trim()) return '';
  return en;
}

/// الاسمُ كما يُطبع في مكان «اسم الشركة»: رئيسيٌّ، وتحته الثانويُّ إن وُجد.
///
/// [separator] `\n` افتراضاً (سطرٌ ثانٍ). ⚠️ ومحرّكُ النطاقات (‏v2) يُمرِّر
/// `  ·  ` لأنّ عنصرَ `company_name` فيه صندوقٌ بارتفاعٍ ثابتٍ بالمليمتر ويليه
/// عنصرٌ بإحداثيٍّ ثابت — سطرٌ ثانٍ كان يفيض فوق العنوان.
String companyDisplayName({
  required String nameAr,
  String? nameEn,
  String locale = 'ar',
  String separator = '\n',
}) {
  final main = companyMainName(nameAr: nameAr, nameEn: nameEn, locale: locale);
  final second =
      companySecondaryName(nameAr: nameAr, nameEn: nameEn, locale: locale);
  return second.isEmpty ? main : '$main$separator$second';
}

/// «س.ت: 123» / "CR: 123" — `''` حين لا رقمَ.
String companyCrLine(String? crNumber, {String locale = 'ar'}) {
  final cr = _clean(crNumber);
  if (cr.isEmpty) return '';
  return '${_isEnglish(locale) ? 'CR' : 'س.ت'}: ${ltrIsolate(cr)}';
}

/// الرقمُ الضريبيُّ وبجواره السجلُّ التجاريُّ، سطراً واحداً.
///
/// ⚠️ بلا رقمٍ ضريبيٍّ يرجع `''` ولو وُجد السجلُّ: القيمةُ تُطبع خلف تسميةِ
/// «الرقم الضريبي»، فسجلٌّ وحدَه تحتها يُقرأ رقماً ضريبيّاً. ولمن يريده
/// منفرداً مفتاحُ `company_cr_number`.
String companyTaxWithCr({
  required String? taxId,
  String? crNumber,
  String locale = 'ar',
}) {
  final tax = _clean(taxId);
  if (tax.isEmpty) return '';
  final cr = companyCrLine(crNumber, locale: locale);
  final base = ltrIsolate(tax);
  return cr.isEmpty ? base : '$base  ·  $cr';
}
