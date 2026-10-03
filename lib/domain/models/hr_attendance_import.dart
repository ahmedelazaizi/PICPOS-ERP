// J4 (الجزء ٢) — استيرادُ بصماتِ جهاز الحضور من ملفّ CSV.
//
// الأجهزةُ تصدّر أعمدةً مختلفة، فالربطُ قابلٌ للضبط: عمودُ كود الموظف،
// وعمودُ التاريخ والوقت (أو عمودان منفصلان)، وعمودُ الاتجاه اختياريّاً.
// بلا عمود اتجاهٍ تكون أوّلُ بصمةٍ في اليوم حضوراً وآخرُها انصرافاً.
//
// هنا التحليلُ وحدَه (خالصٌ وقابلٌ للاختبار)؛ مطابقةُ الكود بالموظف وتوزيعُ
// البصمات على أيّام العمل في `HrAttendanceDao.previewAttendanceImport`.

/// ربطُ أعمدة الملفّ (فهارسُ تبدأ من صفر).
class AttendanceCsvMapping {
  const AttendanceCsvMapping({
    this.codeColumn = 0,
    this.dateTimeColumn = 1,
    this.timeColumn,
    this.directionColumn,
    this.hasHeader = true,
    this.delimiter,
  });
  final int codeColumn;

  /// التاريخُ والوقتُ معاً — أو التاريخُ وحدَه إن كان [timeColumn] محدَّداً.
  final int dateTimeColumn;
  final int? timeColumn;
  final int? directionColumn;
  final bool hasHeader;

  /// `null` ⇒ يُكتشَف من السطر الأوّل (‏Tab ثمّ `;` ثمّ `,`).
  final String? delimiter;

  AttendanceCsvMapping copyWith({
    int? codeColumn,
    int? dateTimeColumn,
    int? Function()? timeColumn,
    int? Function()? directionColumn,
    bool? hasHeader,
  }) =>
      AttendanceCsvMapping(
        codeColumn: codeColumn ?? this.codeColumn,
        dateTimeColumn: dateTimeColumn ?? this.dateTimeColumn,
        timeColumn: timeColumn == null ? this.timeColumn : timeColumn(),
        directionColumn:
            directionColumn == null ? this.directionColumn : directionColumn(),
        hasHeader: hasHeader ?? this.hasHeader,
        delimiter: delimiter,
      );
}

enum PunchDirection { checkIn, checkOut, unknown }

/// سطرٌ من الملفّ بعد التحليل: بصمةٌ صالحة أو [error] (مفتاحٌ عربيٌّ لـ`tr`).
class AttendancePunch {
  const AttendancePunch({
    required this.line,
    required this.code,
    this.at,
    this.direction = PunchDirection.unknown,
    this.error,
    this.employeeId,
    this.employeeName,
    this.workDate,
  });
  final int line;
  final String code;
  final DateTime? at;
  final PunchDirection direction;
  final String? error;

  // تُملأ عند المعاينة.
  final int? employeeId;
  final String? employeeName;
  final DateTime? workDate;

  bool get isValid => error == null && at != null;

  AttendancePunch resolved({
    int? employeeId,
    String? employeeName,
    DateTime? workDate,
    String? error,
  }) =>
      AttendancePunch(
        line: line,
        code: code,
        at: at,
        direction: direction,
        error: error ?? this.error,
        employeeId: employeeId ?? this.employeeId,
        employeeName: employeeName ?? this.employeeName,
        workDate: workDate ?? this.workDate,
      );
}

String detectCsvDelimiter(String text) {
  final first = text.split(RegExp(r'\r?\n')).firstWhere(
      (l) => l.trim().isNotEmpty,
      orElse: () => '');
  if (first.contains('\t')) return '\t';
  if (first.contains(';')) return ';';
  return ',';
}

/// يقسم سطراً بمحدِّدٍ مع احترام علامات الاقتباس.
List<String> splitCsvLine(String line, String delimiter) {
  final out = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (ch == delimiter && !quoted) {
      out.add(cell.toString().trim());
      cell.clear();
    } else {
      cell.write(ch);
    }
  }
  out.add(cell.toString().trim());
  return out;
}

/// صفوفُ الملفّ غيرُ الفارغة (بعد نزع علامة BOM).
List<List<String>> csvRows(String text, {String? delimiter}) {
  final clean = text.startsWith('\uFEFF') ? text.substring(1) : text;
  final d = delimiter ?? detectCsvDelimiter(clean);
  return [
    for (final line in clean.split(RegExp(r'\r?\n')))
      if (line.trim().isNotEmpty) splitCsvLine(line, d),
  ];
}

final _isoDate = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$');
final _dmyDate = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$');
final _time = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AaPp][Mm])?$');

/// يفهم `yyyy-MM-dd HH:mm[:ss]` و`dd/MM/yyyy HH:mm[:ss]` (و`T` فاصلاً،
/// وAM/PM اختياريّاً). [time] يُمرَّر حين يكون الوقتُ في عمودٍ مستقلّ.
DateTime? parsePunchDateTime(String text, {String? time}) {
  var s = text.trim().replaceFirst('T', ' ');
  if (time != null) s = '$s ${time.trim()}';
  final parts = s.split(RegExp(r'\s+'));
  if (parts.length < 2) return null;
  final datePart = parts.first;
  final timePart = parts.sublist(1).join(' ');
  int y, mo, d;
  if (_isoDate.firstMatch(datePart) case final m?) {
    y = int.parse(m.group(1)!);
    mo = int.parse(m.group(2)!);
    d = int.parse(m.group(3)!);
  } else if (_dmyDate.firstMatch(datePart) case final m?) {
    d = int.parse(m.group(1)!);
    mo = int.parse(m.group(2)!);
    y = int.parse(m.group(3)!);
  } else {
    return null;
  }
  final t = _time.firstMatch(timePart.replaceAll(RegExp(r'\s+'), ' '));
  if (t == null) return null;
  var h = int.parse(t.group(1)!);
  final min = int.parse(t.group(2)!);
  final sec = int.tryParse(t.group(3) ?? '') ?? 0;
  final ampm = t.group(4)?.toLowerCase();
  if (ampm != null) {
    if (h < 1 || h > 12) return null;
    if (ampm == 'pm' && h != 12) h += 12;
    if (ampm == 'am' && h == 12) h = 0;
  }
  if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || min > 59 || sec > 59) {
    return null;
  }
  final dt = DateTime(y, mo, d, h, min, sec);
  if (dt.month != mo || dt.day != d) return null; // 31/02 مثلاً
  return dt;
}

const _inWords = {
  'in', 'i', '0', 'checkin', 'check-in', 'check in', 'c/in', 'c-in', 'entry',
  'دخول', 'حضور',
};
const _outWords = {
  'out', 'o', '1', 'checkout', 'check-out', 'check out', 'c/out', 'c-out',
  'exit', 'خروج', 'انصراف',
};

PunchDirection? parsePunchDirection(String text) {
  final v = text.trim().toLowerCase();
  if (_inWords.contains(v)) return PunchDirection.checkIn;
  if (_outWords.contains(v)) return PunchDirection.checkOut;
  return null;
}

/// يحلّل الملفّ كلَّه بـ[mapping]. كلُّ سطرٍ يعود: بصمةٌ أو خطأٌ برقم سطره.
List<AttendancePunch> parseAttendanceCsv(
    String text, AttendanceCsvMapping mapping) {
  final rows = csvRows(text, delimiter: mapping.delimiter);
  final out = <AttendancePunch>[];
  for (var i = mapping.hasHeader ? 1 : 0; i < rows.length; i++) {
    final row = rows[i];
    final line = i + 1;
    String cell(int? c) => c != null && c < row.length ? row[c] : '';
    final code = cell(mapping.codeColumn);
    if (code.isEmpty) {
      out.add(AttendancePunch(line: line, code: '', error: 'كود الموظف فارغ'));
      continue;
    }
    final at = parsePunchDateTime(cell(mapping.dateTimeColumn),
        time: mapping.timeColumn == null ? null : cell(mapping.timeColumn));
    if (at == null) {
      out.add(AttendancePunch(
          line: line, code: code, error: 'تاريخ ووقت غير مفهوم'));
      continue;
    }
    var direction = PunchDirection.unknown;
    if (mapping.directionColumn != null) {
      final parsed = parsePunchDirection(cell(mapping.directionColumn));
      if (parsed == null) {
        out.add(AttendancePunch(
            line: line, code: code, at: at, error: 'اتجاه البصمة غير مفهوم'));
        continue;
      }
      direction = parsed;
    }
    out.add(AttendancePunch(
        line: line, code: code, at: at, direction: direction));
  }
  return out;
}
