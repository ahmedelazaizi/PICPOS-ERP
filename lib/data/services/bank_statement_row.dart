import 'numeric_cell_text.dart';

/// نتيجةُ تحليلِ صفٍّ من قالب كشف البنك.
///
/// إمّا [line] خريطةً جاهزةً لـ`importBankStatementLines`، وإمّا [error]
/// سبباً نصّيّاً يُعرَض للمحاسب. لا ثالثَ لهما، ولا يُطرَح صفٌّ بصمت.
class BankStatementRowResult {
  const BankStatementRowResult.ok(this.line) : error = null;
  const BankStatementRowResult.bad(this.error) : line = null;

  final Map<String, dynamic>? line;
  final String? error;
}

/// يحلّل صفَّ خلايا من قالب الكشف: التاريخ · المرجع · البيان · مدين · دائن.
///
/// ⚠️ **«مدين/دائن» من منظور البنك** — يُنقَلان كما هما، والمحرّكُ يقلبهما
/// عند المطابقة.
///
/// نقيّةٌ عن قصد: تُقاس بلا قاعدةٍ ولا نظامِ ملفّات، كـ`reportCellValue`.
BankStatementRowResult parseBankStatementRow(List<dynamic> cells) {
  if (cells.length < 5) {
    return const BankStatementRowResult.bad('الصفُّ ناقصٌ — يلزم خمسةُ أعمدة');
  }

  final date = _asDate(cells[0]);
  if (date == null) {
    return const BankStatementRowResult.bad('التاريخُ غيرُ مقروء');
  }

  final debit = _asAmount(cells[3]);
  final credit = _asAmount(cells[4]);
  if (debit == null || credit == null) {
    return const BankStatementRowResult.bad('المبلغُ غيرُ مقروءٍ أو سالب');
  }
  if (debit > 0 && credit > 0) {
    return const BankStatementRowResult.bad(
        'مدينٌ ودائنٌ في صفٍّ واحد — الحركةُ في عمودٍ واحدٍ لا اثنين');
  }
  if (debit == 0 && credit == 0) {
    return const BankStatementRowResult.bad('صفٌّ بلا حركة');
  }

  return BankStatementRowResult.ok({
    'date': date,
    'reference': cells[1]?.toString().trim(),
    'description': cells[2]?.toString().trim(),
    'debit': debit,
    'credit': credit,
    'balance': 0.0,
  });
}

DateTime? _asDate(dynamic v) {
  if (v is DateTime) return DateTime(v.year, v.month, v.day);
  final s = v?.toString().trim() ?? '';
  if (s.isEmpty) return null;
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// `null` = غيرُ مقروءٍ أو سالبٌ أو غيرُ منتهٍ. والإشارةُ يحملها **العمود**
/// لا الرقم.
///
/// ⚠️ **الفاصلةُ تُحلَّل بموضعها لا تُجرَّد** (مراجعةٌ 2026-09-01، مأخذ ١):
/// كانت `double.tryParse(s.replaceAll(',', ''))`، فـ`"1500,50"` (عشريّةٌ
/// أوروبيّة) تصير `150050` — **مئةَ ضعف** — و`"1.500,00"` تصير `1.5` لأنّ
/// `"1.50000"` يُحلَّل بنجاح. والصفُّ يُقبَل ويُعَدُّ في «استُورد N سطراً»
/// فلا خطأَ يظهر. وهذا عينُ العطب الذي أُصلح طبقةً أعلى في
/// `parseStatementBalance` (الكوميت c1851304): حُرس رقمُ رصيدِ الكشف الواحد،
/// وتُرك مبلغُ **كلِّ سطرٍ** في الملفّ.
///
/// والعلاجُ **نسخٌ لا اختراع**: [normalizeNumericCellText] هي عينُ الجسم
/// الذي يستعمله `ExcelService._cellToNum` منذ بلاغٍ ميدانيّ — أرقامٌ عربيّةٌ
/// وفواصلُ آلافٍ وعشريّةٌ أوروبيّةٌ ونصُّ عملة.
///
/// ⚠️ **وقرارٌ موثَّق — `"1500,50"` تُقبَل بـ`1500.5` لا تُرفَض**: القاعدةُ
/// المنسوخةُ تقرأ فاصلةً واحدةً بذيلٍ غيرِ ثلاثيٍّ فاصلةً عشريّةً أوروبيّة،
/// وهي القراءةُ الوحيدةُ الممكنةُ للنصّ (‏`1,500` بذيلٍ ثلاثيٍّ تبقى ألفاً
/// وخمسمئة). والمقصودُ من الإصلاح إعدامُ الـ«مئةِ ضعف» لا إعدامُ الصفّ:
/// رفضُ السطرِ يفقد حركةً بنكيّةً حقيقيّةً بلا داعٍ. وهذا **يفترق عمداً** عن
/// `parseStatementBalance` في الشاشة: ذاك رقمٌ **واحدٌ** يكتبه المستخدمُ الآن
/// ويستطيع إعادةَ كتابته، وهذا صفٌّ في ملفٍّ من البنك لا يُعاد.
///
/// ⚠️ **و`NaN`/`Infinity` مرفوضان على المسارَين**: `double.tryParse("NaN")`
/// يُرجع `NaN`، و`NaN < 0` و`NaN > 0` و`NaN == 0` كلُّها `false` — فكان
/// الصفُّ يمرّ بقيمةٍ غيرِ ماليّة، وعلى PostgreSQL تُخزَّن فتُعدي كلَّ جمعٍ
/// بعدها. و`isFinite` يُفحَص على فرع `v is num` أيضاً لا على النصّ وحدَه:
/// خليّةٌ رقميّةٌ تصل `double.nan` لا تمرّ بالتحليل النصّيّ أصلاً.
double? _asAmount(dynamic v) {
  if (v == null) return 0;
  if (v is num) return _finiteNonNegative(v.toDouble());
  final s = v.toString().trim();
  if (s.isEmpty) return 0;
  final n = normalizeNumericCellText(s);
  if (n == null) return null;
  return _finiteNonNegative(n.toDouble());
}

double? _finiteNonNegative(double d) {
  if (!d.isFinite || d < 0) return null;
  return d;
}
