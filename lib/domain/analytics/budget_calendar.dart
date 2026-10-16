// Financial Intelligence — budget month → calendar dates.
//
// Pure Dart. `BudgetLines.month` is the 1-based INDEX of the month inside the
// fiscal year ("شهر N" in the budget dialog), not a calendar month number:
// month 1 starts on the fiscal year's actual start date. For a January fiscal
// year both readings coincide; for a year starting 1 July, month 1 = July and
// month 12 = June of the following calendar year.
//
// Month N covers [start + (N-1) months, start + N months), where "+ k months"
// keeps the start day-of-month (clamped to the target month's length), and the
// last period is capped at the fiscal year's end date so a short or irregular
// year never reaches past its own end.
//
// NOTE: `BudgetingDao.updateBudgetActuals` still maps month m to calendar month
// m of the start year (it is outside this module). For non-January fiscal years
// its stored `actualAmount` therefore describes different months than this
// mapping; the analytics engine never reads `actualAmount`.

/// A half-open date range: [start, endExclusive).
class BudgetPeriod {
  const BudgetPeriod(this.start, this.endExclusive);
  final DateTime start;
  final DateTime endExclusive;

  bool get isEmpty => !endExclusive.isAfter(start);
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// [d] shifted by [months], keeping its day-of-month (clamped).
DateTime addMonthsClamped(DateTime d, int months) {
  final total = d.year * 12 + (d.month - 1) + months;
  final y = total ~/ 12;
  final m = total % 12 + 1;
  final last = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, d.day > last ? last : d.day);
}

/// The dates of budget [month] (1..12) for a fiscal year [fyStart]..[fyEnd]
/// (both inclusive). Months outside 1..12 yield an empty period.
BudgetPeriod budgetPeriod(DateTime fyStart, DateTime fyEnd, int month) {
  final start0 = _day(fyStart);
  final hardEnd = _day(fyEnd).add(const Duration(days: 1));
  final empty = BudgetPeriod(start0, start0);
  if (month < 1 || month > 12) return empty;
  final start = addMonthsClamped(start0, month - 1);
  var end = addMonthsClamped(start0, month);
  if (end.isAfter(hardEnd)) end = hardEnd;
  if (!end.isAfter(start)) return empty;
  return BudgetPeriod(start, end);
}

int _dayNumber(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;

/// Fraction (0..1) of [period] covered by the inclusive day range
/// [from]..[to]. Counted in whole calendar days (DST-safe).
double periodFraction(BudgetPeriod period, DateTime from, DateTime to) {
  if (period.isEmpty) return 0.0;
  final pStart = _dayNumber(period.start);
  final pEnd = _dayNumber(period.endExclusive);
  final lo = _dayNumber(from) > pStart ? _dayNumber(from) : pStart;
  final hi = _dayNumber(to) + 1 < pEnd ? _dayNumber(to) + 1 : pEnd;
  if (hi <= lo) return 0.0;
  return ((hi - lo) / (pEnd - pStart)).clamp(0.0, 1.0);
}
