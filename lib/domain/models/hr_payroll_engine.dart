// J4 (الجزء ٣) — محرّكُ القسيمة: دالّةٌ خالصةٌ من (الموظف، الفترة، ملخّص
// الحضور، البنود، القواعد) إلى بنود الاستحقاق والاستقطاع. لا قاعدةَ هنا،
// فيُختبر وحدَه ويقرؤه الـDAO.
//
// قراراتٌ مفترَضة (قابلةٌ للضبط حيث يذكر):
//  • النسبيّةُ (تعيينٌ أو إنهاءٌ في منتصف الشهر) بأيّام التقويم:
//    الأساسيُّ × أيّامِ الخدمة في الشهر ÷ أيّامِ الشهر — ومثلُه البدلاتُ والبنودُ
//    الثابتة.
//  • الأجرُ اليوميُّ بحسب [PayrollRules.dayBasis] (‏÷٣٠ افتراضيّاً)، وأجرُ
//    الساعة = اليوميّ ÷ ساعات يوم الموظف (أو الافتراضيّة ٨).
//  • كلُّ بندٍ يُقرَّب بمنازل العملة، والصافي مجموعُ المقرَّب.
//  • أقساطُ السلف تُقصَّر حتى لا يصير الصافي سالباً؛ الباقي يبقى رصيداً.
import 'dart:math' as math;

import '../../core/utils/financial_utils.dart';
import 'hr_attendance.dart';
import 'hr_payroll.dart';

/// مدخلاتُ قسيمة موظفٍ واحد.
class PayInput {
  const PayInput({
    required this.basicSalary,
    required this.from,
    required this.to,
    required this.rules,
    this.salaryType = 'monthly',
    this.hoursPerDay,
    this.hireDate,
    this.terminationDate,
    this.summary,
    this.allowances = const [],
    this.components = const [],
    this.commission = 0,
    this.bonuses = const [],
    this.penalties = const [],
    this.advances = const [],
    this.manual = const [],
  });
  final double basicSalary;
  final DateTime from;
  final DateTime to;
  final PayrollRules rules;
  final String salaryType;
  final double? hoursPerDay;
  final DateTime? hireDate;
  final DateTime? terminationDate;
  final AttendanceSummary? summary;

  /// بدلاتُ ملف الموظف (الاسم، القيمةُ الشهريّةُ الكاملة).
  final List<(String, double)> allowances;
  final List<SalaryComponent> components;
  final double commission;
  final List<PayrollAdjustment> bonuses;
  final List<PayrollAdjustment> penalties;

  /// (السلفة، القسطُ المستحقّ هذا الشهر).
  final List<(EmployeeAdvance, double)> advances;

  /// تسوياتٌ يدويّةٌ محفوظةٌ تُعاد كما هي.
  final List<PayrollItem> manual;
}

/// ناتجُ المحرّك: البنودُ وأيّامُ النسبيّة.
class PayResult {
  const PayResult({
    required this.items,
    required this.paidDays,
    required this.periodDays,
    required this.dailyRate,
    required this.hourlyRate,
  });
  final List<PayrollItem> items;
  final double paidDays;
  final double periodDays;
  final double dailyRate;
  final double hourlyRate;

  PayTotals get totals => PayTotals.of(items);
}

/// مجاميعُ قسيمة.
class PayTotals {
  const PayTotals(
      {required this.gross,
      required this.deductions,
      required this.employerCost});
  final double gross;
  final double deductions;
  final double employerCost;

  double get net => FinancialUtils.round(gross - deductions);

  static PayTotals of(Iterable<PayrollItem> items) {
    double sum(String kind) => FinancialUtils.round(items
        .where((i) => i.kind == kind)
        .fold<double>(0, (a, i) => a + i.amount));
    return PayTotals(
      gross: sum(PayItemKind.earning),
      deductions: sum(PayItemKind.deduction),
      employerCost: sum(PayItemKind.employer),
    );
  }
}

int _days(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays +
    1;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// أيّامُ خدمة الموظف داخل [from]..[to] (صفرٌ إن لم يكن موظفاً فيها).
int employedDaysIn(DateTime from, DateTime to,
    {DateTime? hireDate, DateTime? terminationDate}) {
  var start = _day(from);
  var end = _day(to);
  if (hireDate != null && _day(hireDate).isAfter(start)) start = _day(hireDate);
  if (terminationDate != null && _day(terminationDate).isBefore(end)) {
    end = _day(terminationDate);
  }
  if (end.isBefore(start)) return 0;
  return _days(start, end);
}

/// الضريبةُ التصاعديّةُ على [taxable] بالشرائح الشهريّة.
double progressiveTax(double taxable, List<TaxBracket> brackets) {
  if (taxable <= 0 || brackets.isEmpty) return 0;
  final sorted = [...brackets]..sort((a, b) =>
      (a.upTo ?? double.infinity).compareTo(b.upTo ?? double.infinity));
  var tax = 0.0;
  var lower = 0.0;
  for (final b in sorted) {
    final upper = b.upTo ?? double.infinity;
    if (taxable <= lower) break;
    final slice = math.min(taxable, upper) - lower;
    if (slice > 0) tax += slice * b.ratePct / 100;
    lower = upper;
  }
  return tax;
}

/// محرّكُ القسيمة.
PayResult computePay(PayInput input) {
  final r = input.rules;
  const round = FinancialUtils.round;
  final items = <PayrollItem>[];
  void add(String kind, String code, String label, double amount, String acc,
      {double? qty, double? rate, String? refType, int? refId}) {
    final v = round(amount);
    if (v.abs() < 0.0001) return;
    items.add(PayrollItem(
      kind: kind,
      code: code,
      label: label,
      amount: v,
      accountKey: acc,
      quantity: qty,
      rate: rate,
      refType: refType,
      refId: refId,
    ));
  }

  final periodDays = _days(input.from, input.to);
  final employed = employedDaysIn(input.from, input.to,
      hireDate: input.hireDate, terminationDate: input.terminationDate);
  final proRata = periodDays <= 0 ? 0.0 : employed / periodDays;
  final s = input.summary;
  final hours = (input.hoursPerDay != null && input.hoursPerDay! > 0)
      ? input.hoursPerDay!
      : (r.defaultHoursPerDay > 0 ? r.defaultHoursPerDay : 8);

  // أيّامُ العمل المجدولة في نافذة الخدمة.
  final scheduled = s == null
      ? 0
      : s.workedDays +
          s.absentDays +
          s.paidLeaveDays +
          s.unpaidLeaveDays +
          s.pendingDays;
  final basic = input.basicSalary;
  double divisor;
  switch (r.dayBasis) {
    case DayBasis.calendar:
      divisor = periodDays.toDouble();
    case DayBasis.working:
      divisor = (scheduled > 0 && proRata > 0)
          ? scheduled / proRata
          : periodDays.toDouble();
    default:
      divisor = 30;
  }
  final daily = divisor <= 0 ? 0.0 : basic / divisor;
  final hourly = daily / hours;

  // ── الأساسيّ ───────────────────────────────────────────────────────────
  final monthly = input.salaryType != 'hourly' && input.salaryType != 'daily';
  double basicEarned;
  double paidDays;
  if (input.salaryType == 'daily') {
    paidDays = ((s?.workedDays ?? 0) + (s?.paidLeaveDays ?? 0)).toDouble();
    basicEarned = daily * paidDays;
  } else if (input.salaryType == 'hourly') {
    final h = (s?.workedMinutes ?? 0) / 60 + (s?.paidLeaveDays ?? 0) * hours;
    paidDays = ((s?.workedDays ?? 0) + (s?.paidLeaveDays ?? 0)).toDouble();
    basicEarned = hourly * h;
  } else {
    paidDays = employed.toDouble();
    basicEarned = basic * proRata;
  }
  add(PayItemKind.earning, PayItemCode.basic, 'الراتب الأساسي', basicEarned,
      PayAccountKey.salariesExpense,
      qty: paidDays, rate: monthly ? null : daily);

  // ── البدلاتُ والبنود ────────────────────────────────────────────────────
  var insurableExtra = 0.0;
  var nonTaxableEarnings = 0.0;
  for (final (name, value) in input.allowances) {
    add(PayItemKind.earning, PayItemCode.allowance, name, value * proRata,
        PayAccountKey.allowancesExpense);
  }
  final workedHours = (s?.workedMinutes ?? 0) / 60;
  final vars = <String, double>{
    'basic': basic,
    'days': periodDays.toDouble(),
    'paid_days': paidDays,
    'worked_days': (s?.workedDays ?? 0).toDouble(),
    'absent_days': (s?.absentDays ?? 0).toDouble(),
    'worked_hours': workedHours,
    'overtime_hours': (s?.overtimeMinutes ?? 0) / 60,
    'late_minutes': (s?.lateMinutes ?? 0).toDouble(),
    'daily_rate': daily,
    'hourly_rate': hourly,
  };
  final componentDeductions = <double>[];
  for (final c in input.components) {
    if (!c.isActive) continue;
    final v = switch (c.calc) {
      ComponentCalc.percentBasic => basic * c.amount / 100 * proRata,
      ComponentCalc.perDay => c.amount * (s?.workedDays ?? 0),
      ComponentCalc.perHour => c.amount * workedHours,
      ComponentCalc.formula => evalPayFormula(c.formula ?? '0', vars),
      _ => c.amount * proRata,
    };
    if (c.kind == PayItemKind.deduction) {
      add(PayItemKind.deduction, PayItemCode.component, c.name, v,
          PayAccountKey.salariesExpense,
          refType: 'component', refId: c.id);
      componentDeductions.add(round(v));
    } else {
      add(PayItemKind.earning, PayItemCode.component, c.name, v,
          PayAccountKey.allowancesExpense,
          refType: 'component', refId: c.id);
      if (c.insurable) insurableExtra += round(v);
      if (!c.taxable) nonTaxableEarnings += round(v);
    }
  }

  // ── الإضافيُّ والعمولةُ والمكافآت ───────────────────────────────────────
  final otHours = (s?.overtimeMinutes ?? 0) / 60;
  if (r.overtimeEnabled && otHours > 0) {
    add(PayItemKind.earning, PayItemCode.overtime, 'العمل الإضافي',
        otHours * hourly * r.overtimeRate, PayAccountKey.overtimeExpense,
        qty: otHours, rate: hourly * r.overtimeRate);
  }
  add(PayItemKind.earning, PayItemCode.commission, 'عمولة المبيعات',
      input.commission, PayAccountKey.commissionsExpense);
  for (final b in input.bonuses) {
    add(PayItemKind.earning, PayItemCode.bonus, b.reason, b.amount,
        PayAccountKey.allowancesExpense,
        refType: 'adjustment', refId: b.id);
  }

  // ── استقطاعاتُ الحضور (للشهريّ وحده) ───────────────────────────────────
  var attendanceDeductions = 0.0;
  if (monthly && s != null) {
    final absent = r.deductUnrecordedAbsence
        ? s.absentDays
        : s.days
            .where((d) =>
                d.status == AttendanceStatus.absent &&
                d.record?.mark == AttendanceMark.absent)
            .length;
    if (absent > 0) {
      final v = round(absent * daily * r.absenceDayFactor);
      add(PayItemKind.deduction, PayItemCode.absence, 'خصم الغياب', v,
          PayAccountKey.salariesExpense,
          qty: absent.toDouble(), rate: daily * r.absenceDayFactor);
      attendanceDeductions += v;
    }
    if (r.deductUnpaidLeave && s.unpaidLeaveDays > 0) {
      final v = round(s.unpaidLeaveDays * daily);
      add(PayItemKind.deduction, PayItemCode.unpaidLeave,
          'إجازة بدون أجر', v, PayAccountKey.salariesExpense,
          qty: s.unpaidLeaveDays.toDouble(), rate: daily);
      attendanceDeductions += v;
    }
    var late = 0.0;
    double? lateQty;
    if (r.latenessMode == LatenessMode.perMinute) {
      final minutes = s.lateMinutes +
          (r.includeEarlyLeave ? s.earlyLeaveMinutes : 0) -
          r.latenessGraceMinutes;
      if (minutes > 0) {
        late = minutes * hourly / 60 * r.latenessFactor;
        lateQty = minutes.toDouble();
      }
    } else if (r.latenessMode == LatenessMode.tiers &&
        r.latenessTiers.isNotEmpty) {
      final tiers = [...r.latenessTiers]
        ..sort((a, b) => a.fromMinutes.compareTo(b.fromMinutes));
      var fraction = 0.0;
      for (final d in s.days) {
        final m = d.lateMinutes + (r.includeEarlyLeave ? d.earlyLeaveMinutes : 0);
        if (m <= 0) continue;
        double f = 0;
        for (final t in tiers) {
          if (m >= t.fromMinutes) f = t.dayFraction;
        }
        fraction += f;
      }
      late = fraction * daily;
      lateQty = fraction;
    }
    if (late > 0) {
      final v = round(late);
      add(PayItemKind.deduction, PayItemCode.lateness, 'خصم التأخير', v,
          PayAccountKey.salariesExpense,
          qty: lateQty);
      attendanceDeductions += v;
    }
  }
  var penalties = 0.0;
  for (final p in input.penalties) {
    add(PayItemKind.deduction, PayItemCode.penalty, p.reason, p.amount,
        PayAccountKey.salariesExpense,
        refType: 'adjustment', refId: p.id);
    penalties += round(p.amount);
  }

  // التسوياتُ اليدويّةُ تدخل قبل التأمينات والضريبة (تمسّ الإجمالي).
  for (final m in input.manual) {
    items.add(m);
  }
  final manualDed = input.manual
      .where((m) => m.kind == PayItemKind.deduction)
      .fold<double>(0, (a, m) => a + m.amount);

  // ── التأميناتُ والضريبة ─────────────────────────────────────────────────
  final grossSoFar = PayTotals.of(items).gross;
  var empInsurance = 0.0;
  if (r.insuranceEnabled) {
    var base = r.insuranceBase == InsuranceBase.gross
        ? grossSoFar - attendanceDeductions
        : round(basicEarned) - attendanceDeductions + insurableExtra;
    if (r.insuranceCeiling > 0 && base > r.insuranceCeiling) {
      base = r.insuranceCeiling;
    }
    if (base > 0) {
      empInsurance = round(base * r.insuranceEmployeePct / 100);
      add(PayItemKind.deduction, PayItemCode.insuranceEmployee,
          'التأمينات - حصة الموظف', empInsurance,
          PayAccountKey.insurancePayable,
          qty: base, rate: r.insuranceEmployeePct);
      add(PayItemKind.employer, PayItemCode.insuranceEmployer,
          'التأمينات - حصة المنشأة', base * r.insuranceEmployerPct / 100,
          PayAccountKey.employerInsuranceExpense,
          qty: base, rate: r.insuranceEmployerPct);
    }
  }
  if (r.taxEnabled && r.taxBrackets.isNotEmpty) {
    final taxable = grossSoFar -
        nonTaxableEarnings -
        attendanceDeductions -
        penalties -
        componentDeductions.fold<double>(0, (a, v) => a + v) -
        manualDed -
        empInsurance -
        r.taxExemptionMonthly;
    if (taxable > 0) {
      add(PayItemKind.deduction, PayItemCode.tax, 'ضريبة الدخل',
          progressiveTax(taxable, r.taxBrackets), PayAccountKey.taxPayable,
          qty: taxable);
    }
  }
  // ── أقساطُ السلف: لا تُنزل الصافيَ تحت الصفر ────────────────────────────
  var room = PayTotals.of(items).net;
  for (final (adv, due) in input.advances) {
    final v = round(math.min(due, math.max(0, room)));
    if (v <= 0) continue;
    add(PayItemKind.deduction, PayItemCode.advance,
        adv.kind == AdvanceKind.loan ? 'قسط قرض' : 'قسط سلفة', v,
        PayAccountKey.advancesReceivable,
        refType: 'advance', refId: adv.id);
    room -= v;
  }

  return PayResult(
    items: items,
    paidDays: paidDays,
    periodDays: periodDays.toDouble(),
    dailyRate: daily,
    hourlyRate: hourly,
  );
}

/// صيغةٌ مبسّطة: أرقامٌ ومتغيّراتٌ و`+ - * /` وأقواسٌ و`min(a,b)` و`max(a,b)`.
/// متغيّرٌ مجهولٌ أو صيغةٌ معطوبةٌ ⇒ [FormatException].
double evalPayFormula(String source, Map<String, double> vars) {
  final p = _FormulaParser(source, vars);
  final v = p.expr();
  p.skip();
  if (p.pos != source.length) {
    throw FormatException('unexpected input', source, p.pos);
  }
  return v.isFinite ? v : 0;
}

/// هل الصيغةُ صالحة (للتحقّق في الحوار)؟
bool isValidPayFormula(String source) {
  try {
    evalPayFormula(source, {for (final v in kPayFormulaVariables) v: 1});
    return true;
  } on FormatException {
    return false;
  }
}

const kPayFormulaVariables = [
  'basic',
  'days',
  'paid_days',
  'worked_days',
  'absent_days',
  'worked_hours',
  'overtime_hours',
  'late_minutes',
  'daily_rate',
  'hourly_rate',
];

class _FormulaParser {
  _FormulaParser(this.src, this.vars);
  final String src;
  final Map<String, double> vars;
  int pos = 0;

  void skip() {
    while (pos < src.length && src[pos].trim().isEmpty) {
      pos++;
    }
  }

  bool eat(String c) {
    skip();
    if (pos < src.length && src[pos] == c) {
      pos++;
      return true;
    }
    return false;
  }

  double expr() {
    var v = term();
    while (true) {
      if (eat('+')) {
        v += term();
      } else if (eat('-')) {
        v -= term();
      } else {
        return v;
      }
    }
  }

  double term() {
    var v = factor();
    while (true) {
      if (eat('*')) {
        v *= factor();
      } else if (eat('/')) {
        final d = factor();
        v = d == 0 ? 0 : v / d;
      } else {
        return v;
      }
    }
  }

  double factor() {
    skip();
    if (eat('-')) return -factor();
    if (eat('+')) return factor();
    if (eat('(')) {
      final v = expr();
      if (!eat(')')) throw FormatException('missing )', src, pos);
      return v;
    }
    final start = pos;
    if (pos < src.length && RegExp(r'[0-9.]').hasMatch(src[pos])) {
      while (pos < src.length && RegExp(r'[0-9.]').hasMatch(src[pos])) {
        pos++;
      }
      final v = double.tryParse(src.substring(start, pos));
      if (v == null) throw FormatException('bad number', src, start);
      return v;
    }
    while (pos < src.length && RegExp(r'[A-Za-z_]').hasMatch(src[pos])) {
      pos++;
    }
    final name = src.substring(start, pos);
    if (name.isEmpty) throw FormatException('expected value', src, pos);
    if (name == 'min' || name == 'max') {
      if (!eat('(')) throw FormatException('missing (', src, pos);
      final a = expr();
      if (!eat(',')) throw FormatException('missing ,', src, pos);
      final b = expr();
      if (!eat(')')) throw FormatException('missing )', src, pos);
      return name == 'min' ? math.min(a, b) : math.max(a, b);
    }
    final v = vars[name];
    if (v == null) throw FormatException('unknown variable $name', src, start);
    return v;
  }
}
