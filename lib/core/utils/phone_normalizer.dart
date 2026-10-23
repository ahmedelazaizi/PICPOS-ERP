// تطبيعُ أرقام الهاتف — مصدرٌ واحدٌ للمطابقة (عملاءُ الحجوزات، منعُ التكرار).
//
// الهدف: رقمان يخصّان الجهازَ نفسَه يُنتجان المفتاحَ نفسَه مهما كُتبا
// (`+20 101 234 5678` · `00201012345678` · `01012345678` · `١٠١٢٣٤٥٦٧٨`).
// خالصٌ بلا اعتماديّات (يُستورَد من الـDAO ومن الواجهة).

/// مفاتيحُ الدول الأكثر استعمالاً (الأطول أوّلاً لتفادي التقاطِ بادئةٍ أقصر).
const List<String> kPhoneCountryCodes = <String>[
  '966', '971', '962', '964', '963', '961', '970', '965', '974', '968',
  '973', '218', '212', '213', '216', '249', '967', '20', //
];

/// أقلّ عددِ خاناتٍ لرقمٍ يُعدّ هاتفاً قابلاً للمطابقة.
const int kMinPhoneDigits = 6;

String _asciiDigits(String input) {
  final b = StringBuffer();
  for (final r in input.runes) {
    if (r >= 0x30 && r <= 0x39) {
      b.writeCharCode(r);
    } else if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660); // ٠-٩
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + r - 0x06F0); // ۰-۹
    }
  }
  return b.toString();
}

/// الرقمُ القياسيّ: أرقامٌ فقط، بلا `+`/`00`/مفتاح الدولة ولا أصفارِ البداية.
///
/// المفتاحُ يُنزَع إن سبقه `+`/`00` صراحةً، أو إن كان طولُ الرقم يدلّ على أنّه
/// دوليّ (مفتاح + 9 خاناتٍ على الأقل) — فلا يُقتطع `20` من رقمٍ محليٍّ قصير.
/// يعيد `''` إن قلّ الرقمُ عن [kMinPhoneDigits] (لا يُعدّ هاتفاً).
String normalizePhone(String? raw) {
  if (raw == null) return '';
  final text = raw.trim();
  if (text.isEmpty) return '';
  final explicitIntl = text.startsWith('+') ||
      text.startsWith('00') ||
      text.startsWith('٠٠') ||
      text.startsWith('۰۰');
  var d = _asciiDigits(text);
  if (d.startsWith('00')) d = d.substring(2);
  if (d.isEmpty) return '';
  for (final cc in kPhoneCountryCodes) {
    if (!d.startsWith(cc)) continue;
    if (explicitIntl || d.length >= cc.length + 9) {
      d = d.substring(cc.length);
    }
    break;
  }
  d = d.replaceFirst(RegExp(r'^0+'), '');
  return d.length < kMinPhoneDigits ? '' : d;
}

/// آخرُ 9 خاناتٍ من الرقم القياسيّ — مفتاحُ بحثٍ سريعٌ في SQL (`LIKE '%…'`).
String phoneTail9(String? raw) {
  final n = normalizePhone(raw);
  return n.length <= 9 ? n : n.substring(n.length - 9);
}

/// هل الرقمان لهاتفٍ واحد؟ (فارغٌ لا يطابق شيئاً.)
bool samePhone(String? a, String? b) {
  final na = normalizePhone(a);
  return na.isNotEmpty && na == normalizePhone(b);
}

/// تطبيعُ الاسم للمطابقة التامة: قصٌّ، طيُّ المسافات، أحرفٌ صغيرة، ونزعُ
/// التشكيل والتطويل. لا توحيدَ للألِف/الياء عمداً: المطابقةُ «تامةٌ» ولا
/// نريد دمجاً كاذباً.
String normalizePersonName(String? raw) {
  if (raw == null) return '';
  final noMarks = raw.replaceAll(RegExp('[\u064B-\u065F\u0670\u0640]'), '');
  return noMarks.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}
