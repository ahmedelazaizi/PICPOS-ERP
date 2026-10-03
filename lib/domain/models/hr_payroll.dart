// J4 (الجزء ٣) — الرواتبُ والسلفُ والجزاءاتُ وعمولاتُ المندوبين (PicPos).
//
// نماذجُ خالصةٌ بلا Flutter ولا قاعدة، تُبنى من جداول v193 الخامّة:
// `hr_payroll_settings` · `hr_salary_components` · `hr_employee_advances` ·
// `hr_advance_repayments` · `hr_payroll_adjustments` · `hr_commission_plans` ·
// `hr_payroll_runs` · `hr_payroll_lines` · `hr_payroll_items`.
//
// ⚠️ النسبُ والقواعدُ الافتراضيّةُ هنا **قيمٌ قابلةٌ للتعديل لا نصيحةٌ
// قانونيّة**: التأميناتُ والضريبةُ معطّلتان افتراضيّاً، ونسبُهما صفرٌ حتى
// يضبطها المستخدم.
import 'dart:convert';

/// حالةُ مسيّر الرواتب: مسودة → مراجَع → معتمد → مرحَّل → مدفوع، أو معكوس.
abstract final class PayrollRunStatus {
  static const draft = 'draft';
  static const reviewed = 'reviewed';
  static const approved = 'approved';
  static const posted = 'posted';
  static const paid = 'paid';
  static const reversed = 'reversed';
  static const values = [draft, reviewed, approved, posted, paid, reversed];

  /// مسيّرٌ ما زال يحجز موظفيه عن مسيّرٍ آخر للشهر نفسه.
  static bool isActive(String s) => s != reversed;

  /// تُعدَّل بنودُه (تسويةٌ يدويّة أو إعادةُ احتساب).
  static bool isEditable(String s) => s == draft || s == reviewed;
}

/// نوعُ بند القسيمة.
abstract final class PayItemKind {
  static const earning = 'earning';
  static const deduction = 'deduction';

  /// كلفةٌ على المنشأة لا تمسّ الصافي (حصّةُ صاحب العمل في التأمينات).
  static const employer = 'employer';
}

/// رموزُ البنود المحسوبة. `label` يُخزَّن عربيّاً ويُترجَم عند العرض.
abstract final class PayItemCode {
  static const basic = 'basic';
  static const allowance = 'allowance';
  static const component = 'component';
  static const overtime = 'overtime';
  static const commission = 'commission';
  static const bonus = 'bonus';
  static const absence = 'absence';
  static const lateness = 'lateness';
  static const unpaidLeave = 'unpaid_leave';
  static const penalty = 'penalty';
  static const advance = 'advance';
  static const insuranceEmployee = 'insurance_employee';
  static const tax = 'tax';
  static const insuranceEmployer = 'insurance_employer';
  static const manual = 'manual';
  static const legacy = 'legacy';
}

/// مفاتيحُ حسابات الرواتب وأكوادُها الافتراضيّة في الدليل القائم.
abstract final class PayAccountKey {
  static const salariesExpense = 'salaries_expense';
  static const allowancesExpense = 'allowances_expense';
  static const overtimeExpense = 'overtime_expense';
  static const commissionsExpense = 'commissions_expense';
  static const employerInsuranceExpense = 'employer_insurance_expense';
  static const salariesPayable = 'salaries_payable';
  static const insurancePayable = 'insurance_payable';
  static const taxPayable = 'tax_payable';
  static const advancesReceivable = 'advances_receivable';

  static const values = [
    salariesExpense,
    allowancesExpense,
    overtimeExpense,
    commissionsExpense,
    employerInsuranceExpense,
    salariesPayable,
    insurancePayable,
    taxPayable,
    advancesReceivable,
  ];

  /// قرارٌ مفترَض: الدليلُ القائم لا يحمل حساباتٍ للبدلات أو الإضافيّ أو
  /// حصّةِ التأمينات، فتؤول إلى «رواتب وأجور» (621) و«مصروفات مستحقة الدفع»
  /// (2132) حتى يغيّرها المستخدم.
  static const defaultCodes = <String, String>{
    salariesExpense: '621',
    allowancesExpense: '621',
    overtimeExpense: '621',
    commissionsExpense: '612',
    employerInsuranceExpense: '621',
    salariesPayable: '2131',
    insurancePayable: '2132',
    taxPayable: '2123',
    advancesReceivable: '1146',
  };

  /// غرضُ ربط الحسابات القديم (‏`account_mappings`) الذي يُقرأ أوّلاً لكلّ
  /// مفتاحٍ له مقابل — فيرث المسيّرُ ما ضبطه المحاسبُ للشاشة القديمة.
  static const legacyPurposes = <String, String>{
    salariesExpense: 'salary_expense',
    salariesPayable: 'accrued_salaries',
    advancesReceivable: 'employee_advances',
  };
}

/// مقامُ الأجر اليوميّ.
abstract final class DayBasis {
  /// الأساسيُّ ÷ ٣٠ (الافتراضيّ).
  static const fixed30 = 'fixed30';

  /// الأساسيُّ ÷ أيّامِ الشهر التقويميّة.
  static const calendar = 'calendar';

  /// الأساسيُّ ÷ أيّامِ العمل المجدولة في الشهر.
  static const working = 'working';
  static const values = [fixed30, calendar, working];
}

abstract final class LatenessMode {
  static const none = 'none';
  static const perMinute = 'per_minute';
  static const tiers = 'tiers';
  static const values = [none, perMinute, tiers];
}

abstract final class InsuranceBase {
  static const basic = 'basic';
  static const gross = 'gross';
  static const values = [basic, gross];
}

/// طريقةُ احتساب بند الراتب.
abstract final class ComponentCalc {
  static const fixed = 'fixed';
  static const percentBasic = 'percent_basic';
  static const perDay = 'per_day';
  static const perHour = 'per_hour';
  static const formula = 'formula';
  static const values = [fixed, percentBasic, perDay, perHour, formula];
}

abstract final class AdvanceKind {
  static const advance = 'advance';
  static const loan = 'loan';
  static const values = [advance, loan];
}

abstract final class AdvanceStatus {
  static const active = 'active';
  static const settled = 'settled';
  static const cancelled = 'cancelled';
}

abstract final class RepaymentSource {
  static const payroll = 'payroll';
  static const earlySettlement = 'early_settlement';
  static const legacy = 'legacy';
}

abstract final class AdjustmentKind {
  static const bonus = 'bonus';
  static const penalty = 'penalty';
  static const values = [bonus, penalty];
}

abstract final class AdjustmentStatus {
  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';
}

abstract final class PayLineStatus {
  static const unpaid = 'unpaid';
  static const paid = 'paid';
}

double _d(Object? v, [double fallback = 0]) =>
    v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? fallback);

/// شريحةُ تأخيرٍ: من [fromMinutes] دقيقةً في اليوم يُخصم [dayFraction] يوم.
class LatenessTier {
  const LatenessTier({required this.fromMinutes, required this.dayFraction});
  final int fromMinutes;
  final double dayFraction;

  Map<String, Object?> toJson() =>
      {'from': fromMinutes, 'fraction': dayFraction};
  static LatenessTier fromJson(Map<String, Object?> j) => LatenessTier(
      fromMinutes: _d(j['from']).round(), dayFraction: _d(j['fraction']));
}

/// شريحةُ ضريبةٍ تصاعديّة شهريّة: حتى [upTo] (‏null ⇒ ما فوقها) بنسبة [ratePct].
class TaxBracket {
  const TaxBracket({this.upTo, required this.ratePct});
  final double? upTo;
  final double ratePct;

  Map<String, Object?> toJson() => {'up_to': upTo, 'rate': ratePct};
  static TaxBracket fromJson(Map<String, Object?> j) => TaxBracket(
      upTo: j['up_to'] == null ? null : _d(j['up_to']), ratePct: _d(j['rate']));
}

/// قواعدُ المسيّر — تُخزَّن JSON في `hr_payroll_settings` (مفتاح `rules`).
class PayrollRules {
  const PayrollRules({
    this.dayBasis = DayBasis.fixed30,
    this.defaultHoursPerDay = 8,
    this.absenceDayFactor = 1,
    this.deductUnrecordedAbsence = false,
    this.deductUnpaidLeave = true,
    this.latenessMode = LatenessMode.perMinute,
    this.latenessGraceMinutes = 0,
    this.latenessFactor = 1,
    this.includeEarlyLeave = true,
    this.latenessTiers = const [],
    this.overtimeEnabled = true,
    this.overtimeRate = 1.25,
    this.insuranceEnabled = false,
    this.insuranceEmployeePct = 0,
    this.insuranceEmployerPct = 0,
    this.insuranceBase = InsuranceBase.basic,
    this.insuranceCeiling = 0,
    this.taxEnabled = false,
    this.taxExemptionMonthly = 0,
    this.taxBrackets = const [],
  });

  final String dayBasis;
  final double defaultHoursPerDay;
  final double absenceDayFactor;

  /// يومُ عملٍ مضى بلا بصمةٍ ولا علامة يُعدّ غياباً يُخصم؟ قرارُ المالك
  /// 2026-08-09 للشاشة القديمة: «غيابٌ لم يُسجَّل = لا خصم» ⇒ معطّلٌ
  /// افتراضيّاً، فلا يُخصم إلّا الغيابُ المعلَّم صراحةً.
  final bool deductUnrecordedAbsence;
  final bool deductUnpaidLeave;
  final String latenessMode;

  /// دقائقُ سماحٍ شهريّة قبل خصم التأخير (فوق سماح الورديّة).
  final int latenessGraceMinutes;
  final double latenessFactor;
  final bool includeEarlyLeave;
  final List<LatenessTier> latenessTiers;
  final bool overtimeEnabled;

  /// مُعامِلُ ساعة الإضافيّ من أجر الساعة (‏1.25 = ١٢٥٪).
  final double overtimeRate;
  final bool insuranceEnabled;
  final double insuranceEmployeePct;
  final double insuranceEmployerPct;
  final String insuranceBase;

  /// سقفُ الأجر الخاضع للتأمينات (‏0 ⇒ بلا سقف).
  final double insuranceCeiling;
  final bool taxEnabled;
  final double taxExemptionMonthly;
  final List<TaxBracket> taxBrackets;

  Map<String, Object?> toJson() => {
        'day_basis': dayBasis,
        'hours_per_day': defaultHoursPerDay,
        'absence_factor': absenceDayFactor,
        'deduct_unrecorded_absence': deductUnrecordedAbsence,
        'deduct_unpaid_leave': deductUnpaidLeave,
        'lateness_mode': latenessMode,
        'lateness_grace': latenessGraceMinutes,
        'lateness_factor': latenessFactor,
        'include_early_leave': includeEarlyLeave,
        'lateness_tiers': [for (final t in latenessTiers) t.toJson()],
        'overtime_enabled': overtimeEnabled,
        'overtime_rate': overtimeRate,
        'insurance_enabled': insuranceEnabled,
        'insurance_employee_pct': insuranceEmployeePct,
        'insurance_employer_pct': insuranceEmployerPct,
        'insurance_base': insuranceBase,
        'insurance_ceiling': insuranceCeiling,
        'tax_enabled': taxEnabled,
        'tax_exemption': taxExemptionMonthly,
        'tax_brackets': [for (final b in taxBrackets) b.toJson()],
      };

  String encode() => jsonEncode(toJson());

  static PayrollRules decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const PayrollRules();
    try {
      return fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } catch (_) {
      return const PayrollRules();
    }
  }

  static PayrollRules fromJson(Map<String, Object?> j) {
    const d = PayrollRules();
    bool b(String k, bool f) => j[k] is bool ? j[k] as bool : f;
    List<Map<String, Object?>> list(String k) => [
          for (final e in (j[k] as List?) ?? const [])
            if (e is Map) e.cast<String, Object?>(),
        ];
    return PayrollRules(
      dayBasis: DayBasis.values.contains(j['day_basis'])
          ? j['day_basis'] as String
          : d.dayBasis,
      defaultHoursPerDay: _d(j['hours_per_day'], d.defaultHoursPerDay),
      absenceDayFactor: _d(j['absence_factor'], d.absenceDayFactor),
      deductUnrecordedAbsence:
          b('deduct_unrecorded_absence', d.deductUnrecordedAbsence),
      deductUnpaidLeave: b('deduct_unpaid_leave', d.deductUnpaidLeave),
      latenessMode: LatenessMode.values.contains(j['lateness_mode'])
          ? j['lateness_mode'] as String
          : d.latenessMode,
      latenessGraceMinutes: _d(j['lateness_grace']).round(),
      latenessFactor: _d(j['lateness_factor'], d.latenessFactor),
      includeEarlyLeave: b('include_early_leave', d.includeEarlyLeave),
      latenessTiers: [for (final t in list('lateness_tiers')) LatenessTier.fromJson(t)],
      overtimeEnabled: b('overtime_enabled', d.overtimeEnabled),
      overtimeRate: _d(j['overtime_rate'], d.overtimeRate),
      insuranceEnabled: b('insurance_enabled', d.insuranceEnabled),
      insuranceEmployeePct: _d(j['insurance_employee_pct']),
      insuranceEmployerPct: _d(j['insurance_employer_pct']),
      insuranceBase: InsuranceBase.values.contains(j['insurance_base'])
          ? j['insurance_base'] as String
          : d.insuranceBase,
      insuranceCeiling: _d(j['insurance_ceiling']),
      taxEnabled: b('tax_enabled', d.taxEnabled),
      taxExemptionMonthly: _d(j['tax_exemption']),
      taxBrackets: [for (final t in list('tax_brackets')) TaxBracket.fromJson(t)],
    );
  }
}

/// ربطُ مفاتيح الرواتب بأكواد الحسابات (حساباتٌ تفصيليّةٌ وحدَها).
class PayrollAccounts {
  const PayrollAccounts([this.codes = const {}]);
  final Map<String, String> codes;

  String codeFor(String key) =>
      codes[key] ?? PayAccountKey.defaultCodes[key] ?? '621';

  String encode() => jsonEncode(codes);

  static PayrollAccounts decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const PayrollAccounts();
    try {
      final m = (jsonDecode(raw) as Map).cast<String, Object?>();
      return PayrollAccounts({
        for (final e in m.entries)
          if (e.value is String) e.key: e.value as String,
      });
    } catch (_) {
      return const PayrollAccounts();
    }
  }
}

/// بندُ راتبٍ عامٌّ (لكلّ الموظفين أو لقسم): استحقاقٌ أو استقطاع.
class SalaryComponent {
  const SalaryComponent({
    this.id,
    required this.name,
    this.nameEn,
    this.kind = PayItemKind.earning,
    this.calc = ComponentCalc.fixed,
    this.amount = 0,
    this.formula,
    this.departmentId,
    this.isActive = true,
    this.taxable = true,
    this.insurable = false,
  });
  final int? id;
  final String name;
  final String? nameEn;
  final String kind;
  final String calc;
  final double amount;
  final String? formula;
  final int? departmentId;
  final bool isActive;
  final bool taxable;
  final bool insurable;
}

/// سلفةٌ أو قرضٌ بأقساطٍ تُستقطع من المسيّر.
class EmployeeAdvance {
  const EmployeeAdvance({
    this.id,
    required this.employeeId,
    this.employeeName,
    this.kind = AdvanceKind.advance,
    required this.amount,
    required this.issueDate,
    this.installments = 1,
    this.installmentAmount = 0,
    required this.startYear,
    required this.startMonth,
    this.status = AdvanceStatus.active,
    this.repaid = 0,
    this.safeTransactionId,
    this.journalEntryId,
    this.voucherNumber,
    this.bookNumber,
    this.notes,
    this.legacy = false,
  });
  final int? id;
  final int employeeId;
  final String? employeeName;
  final String kind;
  final double amount;
  final DateTime issueDate;
  final int installments;
  final double installmentAmount;
  final int startYear;
  final int startMonth;
  final String status;
  final double repaid;
  final int? safeTransactionId;
  final int? journalEntryId;
  final String? voucherNumber;
  final int? bookNumber;
  final String? notes;
  final bool legacy;

  double get balance {
    final b = amount - repaid;
    return b < 0.005 ? 0 : b;
  }

  /// قسطُ الشهر ([year]، [month]) — صفرٌ قبل شهر البدء أو بعد السداد.
  double dueFor(int year, int month) {
    if (status != AdvanceStatus.active || balance <= 0) return 0;
    if (year * 12 + month < startYear * 12 + startMonth) return 0;
    final per = installmentAmount > 0
        ? installmentAmount
        : amount / (installments <= 0 ? 1 : installments);
    return per > balance ? balance : per;
  }
}

class AdvanceRepayment {
  const AdvanceRepayment({
    this.id,
    required this.advanceId,
    required this.amount,
    required this.date,
    required this.source,
    this.payrollRunId,
  });
  final int? id;
  final int advanceId;
  final double amount;
  final DateTime date;
  final String source;
  final int? payrollRunId;
}

/// مكافأةٌ أو جزاءٌ لمرّةٍ واحدة في شهرٍ، بسببٍ واعتماد.
class PayrollAdjustment {
  const PayrollAdjustment({
    this.id,
    required this.employeeId,
    this.employeeName,
    required this.kind,
    required this.amount,
    required this.year,
    required this.month,
    required this.reason,
    this.status = AdjustmentStatus.pending,
    this.payrollRunId,
    this.decidedBy,
  });
  final int? id;
  final int employeeId;
  final String? employeeName;
  final String kind;
  final double amount;
  final int year;
  final int month;
  final String reason;
  final String status;
  final int? payrollRunId;
  final int? decidedBy;
}

/// شريحةُ عمولةٍ: عند تحقيق [minAchievementPct]٪ من الهدف تصير نسبةُ
/// المبيعات [salesRatePct].
class CommissionTier {
  const CommissionTier(
      {required this.minAchievementPct, required this.salesRatePct});
  final double minAchievementPct;
  final double salesRatePct;

  Map<String, Object?> toJson() =>
      {'min': minAchievementPct, 'rate': salesRatePct};
  static CommissionTier fromJson(Map<String, Object?> j) => CommissionTier(
      minAchievementPct: _d(j['min']), salesRatePct: _d(j['rate']));
}

/// خطّةُ عمولة: لمندوبٍ بعينه أو الافتراضيّة (‏[employeeId] null).
class CommissionPlan {
  const CommissionPlan({
    this.id,
    required this.name,
    this.employeeId,
    this.employeeName,
    this.salesRatePct = 0,
    this.collectionsRatePct = 0,
    this.tiers = const [],
    this.categoryRates = const {},
    this.isActive = true,
  });
  final int? id;
  final String name;
  final int? employeeId;
  final String? employeeName;
  final double salesRatePct;
  final double collectionsRatePct;
  final List<CommissionTier> tiers;

  /// نسبةُ مبيعاتٍ خاصّةٌ بفئة منتجات (معرّف الفئة ⇒ ٪).
  final Map<int, double> categoryRates;
  final bool isActive;

  String encodeTiers() => jsonEncode([for (final t in tiers) t.toJson()]);
  String encodeCategoryRates() =>
      jsonEncode({for (final e in categoryRates.entries) '${e.key}': e.value});

  static List<CommissionTier> decodeTiers(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          if (e is Map) CommissionTier.fromJson(e.cast<String, Object?>()),
      ]..sort((a, b) => a.minAchievementPct.compareTo(b.minAchievementPct));
    } catch (_) {
      return const [];
    }
  }

  static Map<int, double> decodeCategoryRates(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final m = (jsonDecode(raw) as Map).cast<String, Object?>();
      return {
        for (final e in m.entries)
          if (int.tryParse(e.key) != null) int.parse(e.key): _d(e.value),
      };
    } catch (_) {
      return const {};
    }
  }

  /// نسبةُ المبيعات المطبَّقة لنسبة تحقيقٍ [achievementPct] (‏null ⇒ بلا هدف).
  double salesRateFor(double? achievementPct) {
    var rate = salesRatePct;
    if (achievementPct == null) return rate;
    for (final t in tiers) {
      if (achievementPct + 1e-9 >= t.minAchievementPct) rate = t.salesRatePct;
    }
    return rate;
  }
}

/// مستندٌ في كشف العمولة.
class CommissionDoc {
  const CommissionDoc({
    required this.date,
    required this.kind,
    required this.number,
    required this.amount,
    required this.commission,
    this.customerName,
  });
  final DateTime date;

  /// `invoice` · `return` · `receipt` · `collection`.
  final String kind;
  final String number;
  final double amount;
  final double commission;
  final String? customerName;
}

class CommissionStatement {
  const CommissionStatement({
    required this.employeeId,
    required this.from,
    required this.to,
    this.plan,
    this.sales = 0,
    this.returns = 0,
    this.collections = 0,
    this.target,
    this.achievementPct,
    this.appliedSalesRatePct = 0,
    this.salesCommission = 0,
    this.collectionsCommission = 0,
    this.docs = const [],
  });
  final int employeeId;
  final DateTime from;
  final DateTime to;
  final CommissionPlan? plan;
  final double sales;
  final double returns;
  final double collections;
  final double? target;
  final double? achievementPct;
  final double appliedSalesRatePct;
  final double salesCommission;
  final double collectionsCommission;
  final List<CommissionDoc> docs;

  double get netSales => sales - returns;
  double get total => salesCommission + collectionsCommission;
}

/// مسيّرُ رواتب شهرٍ (لفرعٍ أو قسمٍ أو للكلّ).
class PayrollRun {
  const PayrollRun({
    required this.id,
    required this.year,
    required this.month,
    required this.from,
    required this.to,
    required this.status,
    this.branchId,
    this.departmentId,
    this.journalEntryId,
    this.reversalJournalEntryId,
    this.gross = 0,
    this.deductions = 0,
    this.net = 0,
    this.employerCost = 0,
    this.paid = 0,
    this.employeeCount = 0,
    this.legacy = false,
    this.notes,
    this.createdBy,
    this.approvedBy,
    this.postedAt,
  });
  final int id;
  final int year;
  final int month;
  final DateTime from;
  final DateTime to;
  final String status;
  final int? branchId;
  final int? departmentId;
  final int? journalEntryId;
  final int? reversalJournalEntryId;
  final double gross;
  final double deductions;
  final double net;
  final double employerCost;
  final double paid;
  final int employeeCount;
  final bool legacy;
  final String? notes;
  final int? createdBy;
  final int? approvedBy;
  final DateTime? postedAt;

  String get period => '$year-${month.toString().padLeft(2, '0')}';
  bool get editable => !legacy && PayrollRunStatus.isEditable(status);
}

/// بندٌ في قسيمة موظف.
class PayrollItem {
  const PayrollItem({
    this.id,
    this.lineId,
    required this.kind,
    required this.code,
    required this.label,
    required this.amount,
    required this.accountKey,
    this.quantity,
    this.rate,
    this.isManual = false,
    this.reason,
    this.refType,
    this.refId,
  });
  final int? id;
  final int? lineId;
  final String kind;
  final String code;
  final String label;
  final double amount;
  final String accountKey;
  final double? quantity;
  final double? rate;
  final bool isManual;
  final String? reason;
  final String? refType;
  final int? refId;
}

/// قسيمةُ موظفٍ في مسيّر.
class PayrollLine {
  const PayrollLine({
    required this.id,
    required this.runId,
    required this.employeeId,
    required this.employeeName,
    this.employeeCode,
    this.departmentId,
    this.departmentName,
    this.branchId,
    this.basicSalary = 0,
    this.paidDays = 0,
    this.periodDays = 0,
    this.gross = 0,
    this.deductions = 0,
    this.net = 0,
    this.employerCost = 0,
    this.paidAmount = 0,
    this.paymentStatus = PayLineStatus.unpaid,
    this.paymentMethod,
    this.safeTransactionId,
    this.items = const [],
  });
  final int id;
  final int runId;
  final int employeeId;
  final String employeeName;
  final String? employeeCode;
  final int? departmentId;
  final String? departmentName;
  final int? branchId;
  final double basicSalary;
  final double paidDays;
  final double periodDays;
  final double gross;
  final double deductions;
  final double net;
  final double employerCost;
  final double paidAmount;
  final String paymentStatus;
  final String? paymentMethod;
  final int? safeTransactionId;
  final List<PayrollItem> items;

  bool get isPaid => paymentStatus == PayLineStatus.paid;
  Iterable<PayrollItem> get earnings =>
      items.where((i) => i.kind == PayItemKind.earning);
  Iterable<PayrollItem> get deductionItems =>
      items.where((i) => i.kind == PayItemKind.deduction);
}

/// قسيمةٌ في سجلّ موظف: السطرُ مع مسيّره.
class PayslipEntry {
  const PayslipEntry({required this.run, required this.line});
  final PayrollRun run;
  final PayrollLine line;
}

/// خزنةٌ أو بنكٌ يُصرف منه (للعرض في الحوارات).
class PayrollSafe {
  const PayrollSafe(
      {required this.id, required this.name, required this.type, this.branchId});
  final int id;
  final String name;
  final String type;
  final int? branchId;
}

/// حسابٌ تفصيليٌّ للاختيار في ربط الحسابات.
class PayrollAccountOption {
  const PayrollAccountOption(
      {required this.id, required this.code, required this.name});
  final int id;
  final String code;
  final String name;
}
