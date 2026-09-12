// lib/domain/models/whatsapp_message.dart
//
// إرسالُ الفاتورة وكشفِ الحساب والمطالبة على واتساب — منفَذُ `wa.me` بقرار
// المالك 2026-09-12.
//
// ═══ ما يترتّب على اختيار `wa.me` — بنيويٌّ لا تفصيليّ ═══
//
// • **لا إرسالَ آليّ**: الرابطُ يفتح واتساب على جهاز المستخدم مملوءاً،
//   والمستخدمُ يضغط «إرسال» بنفسه. فلا طابورَ على الخادم ولا إعادةَ محاولة.
// • **ولا مرفقَ PDF**: الرابطُ يحمل نصّاً فقط.
// • **ولا إيصالَ تسليم**: لا شيءَ يعود، فحالةٌ تقول «أُرسِل» تكذب. المسجَّلُ
//   «فُتح واتساب» لا «وصلت الرسالة».
// • والإنسانُ في الحلقة بالبناء: لا تُرسَل رسالةٌ بلا ضغطةٍ منه — وهي
//   نقطةُ ضبطِ «موافقة التواصل» ما دام المنفَذُ هذا.

import '../../core/constants/app_constants.dart';
import '../../core/utils/number_utils.dart';

/// أوّلُ محرفٍ في كلّ نطاقِ أرقامٍ غيرِ لاتينيّ، بترتيب ٠..٩.
const _digitBases = <int>[
  0x0660, // ٠ — عربيّة هنديّة
  0x06F0, // ۰ — فارسيّة/أورديّة
];

/// مبلغٌ منسَّقٌ بعملة النظام وخانات كسره.
String _money(double v) =>
    '${NumberUtils.roundCurrency(v).toStringAsFixed(AppConstants.decimalPlaces)}'
    ' ${AppConstants.currencySymbol}';

String _date(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/'
    '${d.day.toString().padLeft(2, '0')}';

/// يحوّل الأرقامَ غيرَ اللاتينيّة إلى لاتينيّة ويُسقط ما عداها.
String _digitsOnly(String input) {
  final out = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0x30 && rune <= 0x39) {
      out.writeCharCode(rune);
      continue;
    }
    for (final base in _digitBases) {
      if (rune >= base && rune <= base + 9) {
        out.writeCharCode(0x30 + (rune - base));
        break;
      }
    }
  }
  return out.toString();
}

/// رقمٌ صالحٌ لـ`wa.me`: أرقامٌ فقط بصيغةٍ دوليّةٍ بلا `+`.
///
/// ⚠️ **ورقمٌ لم يُسوَّ لا يُنتج خطأً**: `wa.me` يفتح صفحةً تقول «الرقمُ غيرُ
/// صالح»، فيظنّ الموظّفُ أنّ العميلَ ليس على واتساب. فالإخفاقُ صامتٌ من
/// جهتنا — ولذلك يُرَدُّ `null` هنا ويُعرَض سببٌ مفهوم بدل فتح رابطٍ ميّت.
///
/// والقواعدُ صريحةٌ بترتيبها:
///   ١. `+` أو `00` في أوّله ⇒ دوليٌّ صريح، يُؤخَذ كما هو.
///   ٢. صفرٌ بادئٌ ⇒ محلّيّ، تُقَصّ الأصفارُ ويُسبَق برمز الدولة.
///   ٣. بدأ برمز الدولة أصلاً ⇒ دوليّ، ولا يُضاعَف الرمز.
///   ٤. ما عدا ذلك ⇒ محلّيٌّ بلا صفر، يُسبَق بالرمز.
String? normalizeWhatsAppPhone(
  String? raw, {
  required String defaultCountryCode,
}) {
  final cc = _digitsOnly(defaultCountryCode.trim());
  // رمزُ دولةٍ فارغٌ أو غيرُ رقميٍّ في الإعداد يُنتج رقماً مشوَّهاً لكلّ عميل.
  if (cc.isEmpty || cc.length > 4) return null;

  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;

  var digits = _digitsOnly(value);
  if (digits.isEmpty) return null;

  // بادئةُ الاتّصال الدوليّ `00` تُقَصّ أوّلاً — و`+` لا أثرَ لها بعد
  // `_digitsOnly`، فحضورُها يُعرَف من النصّ الأصليّ وحدَه.
  if (value.startsWith('00')) digits = digits.substring(2);

  // ⚠️ **وما بقي بعد قصِّ `00` قد يظلّ محلّيّاً.** `000101…` ليست بادئةً
  // دوليّةً لرقمٍ يبدأ بصفر — لا رقمَ دوليٌّ يبدأ بصفر أصلاً. فالسقوطُ إلى
  // فرع المحلّيّ هو ما يجعل القاعدتين تتّفقان بدل أن تتعارضا.
  final explicitInternational =
      value.startsWith('+') || (value.startsWith('00') && !digits.startsWith('0'));

  if (!explicitInternational) {
    if (digits.startsWith('0')) {
      digits = '$cc${digits.replaceFirst(RegExp(r'^0+'), '')}';
    } else if (!digits.startsWith(cc)) {
      digits = '$cc$digits';
    }
  }

  // ⚠️ الحدُّ الأدنى يمنع الامتداداتِ الداخليّةَ والأرقامَ الناقصة، والأعلى
  // حدُّ E.164. وفتحُ واتساب برقمٍ من ثلاث خاناتٍ يُربك الموظّفَ ولا يُفيده.
  if (digits.length < 10 || digits.length > 15) return null;
  return digits;
}

/// رابطُ `wa.me` بنصٍّ مملوء.
///
/// ⚠️ **والنصُّ يُرمَّز كاملاً.** `#` تقطعه عند المرساة و`&` تُقرأ فاصلَ
/// معاملاتٍ فيُبتَر ما بعدها — وكلاهما يقع في نصوصنا: «فاتورة #1024» و
/// «خصم 10% & شكراً». والمبتورُ يصل الزبونَ ناقصاً بلا أن يعلم أحد.
String buildWhatsAppUrl({required String phone, required String message}) =>
    'https://wa.me/$phone?text=${Uri.encodeComponent(message)}';

/// اسمُ المحلّ بعد التسوية — فارغُه لا يترك فجوةً في النصّ.
String _shop(String shopName) {
  final s = shopName.trim();
  return s.isEmpty ? AppConstants.appName : s;
}

/// نصُّ إرسال فاتورةٍ للعميل.
String composeInvoiceMessage({
  required String shopName,
  required String customerName,
  required String invoiceNumber,
  required double total,
  required DateTime issuedAt,
}) {
  final name = customerName.trim();
  return [
    'مرحباً${name.isEmpty ? '' : ' $name'} 👋',
    '',
    'فاتورتك من ${_shop(shopName)}:',
    'رقم الفاتورة: $invoiceNumber',
    'التاريخ: ${_date(issuedAt)}',
    'الإجمالي: ${_money(total)}',
    '',
    'شكراً لتعاملك معنا.',
  ].join('\n');
}

/// نصُّ كشف الحساب.
///
/// ⚠️ **الرصيدُ يُقال بمعناه لا برقمه عارياً.** الإشارةُ في هذا المستودع
/// `+debit / -credit`: الموجبُ **مستحقٌّ على العميل**، والسالبُ **لصالحه**.
/// ورسالةٌ تقول «رصيدك ‎-٥٠٠» يقرؤها الزبونُ مديونيّةً فيتّصل غاضباً.
String composeStatementMessage({
  required String shopName,
  required String customerName,
  required double balance,
  required DateTime asOf,
}) {
  final name = customerName.trim();
  final rounded = NumberUtils.roundCurrency(balance);
  final line = rounded > 0
      ? 'المستحقّ عليك: ${_money(rounded)}'
      : rounded < 0
          ? 'الرصيد لك: ${_money(-rounded)}'
          : 'لا مستحقّات — الحساب مسدَّد بالكامل.';

  return [
    'مرحباً${name.isEmpty ? '' : ' $name'} 👋',
    '',
    'كشف حسابك لدى ${_shop(shopName)}',
    'حتى تاريخ: ${_date(asOf)}',
    line,
    '',
    'لأي استفسار تواصل معنا.',
  ].join('\n');
}

/// نصُّ المطالبة — أو `null` إن لم يكن هناك ما يُطالَب به.
///
/// ⚠️ **ولا تُكتَب مطالبةٌ بصفرٍ ولا بسالب.** مطالبةُ عميلٍ منتظمٍ بمبلغٍ لا
/// يستحقّ إساءةٌ إليه، والرفضُ هنا أصحُّ من نصٍّ يقول «برجاء سداد ٠٫٠٠».
String? composeDueReminderMessage({
  required String shopName,
  required String customerName,
  required double dueAmount,
  DateTime? dueDate,
}) {
  final rounded = NumberUtils.roundCurrency(dueAmount);
  if (rounded <= 0) return null;

  final name = customerName.trim();
  return [
    'مرحباً${name.isEmpty ? '' : ' $name'} 👋',
    '',
    'تذكير من ${_shop(shopName)}:',
    'المبلغ المستحقّ: ${_money(rounded)}',
    if (dueDate != null) 'تاريخ الاستحقاق: ${_date(dueDate)}',
    '',
    'برجاء التكرّم بالسداد، ولك الشكر.',
  ].join('\n');
}
