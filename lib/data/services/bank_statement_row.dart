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

/// `null` = غيرُ مقروءٍ أو سالب. والإشارةُ يحملها **العمود** لا الرقم.
double? _asAmount(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v < 0 ? null : v.toDouble();
  final s = v.toString().trim();
  if (s.isEmpty) return 0;
  final n = double.tryParse(s.replaceAll(',', ''));
  if (n == null || n < 0) return null;
  return n;
}
