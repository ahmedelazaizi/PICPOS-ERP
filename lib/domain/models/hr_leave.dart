// J4 (الجزء ٢) — أنواعُ الإجازات وأرصدتُها السنويّة وطلباتُها.
//
// نماذجُ خالصةٌ تُبنى من `hr_leave_types` · `hr_leave_entitlements` ·
// `hr_leave_requests` (‏v192). دورةُ الطلب:
//   مسودة → مقدَّم → معتمد / مرفوض، والإلغاءُ من أيّ حالةٍ مفتوحة.
// الاعتمادُ يعلّم أيّامَ العمل في الفترة «إجازة» ويستهلك الرصيد؛ والإلغاءُ
// بعد الاعتماد يردّهما.

/// رموزُ الأنواع المبذورة (‏`custom` لما يعرّفه المستخدم).
abstract final class LeaveTypeCode {
  static const annual = 'annual';
  static const sick = 'sick';
  static const unpaid = 'unpaid';
  static const emergency = 'emergency';
  static const custom = 'custom';
  static const system = [annual, sick, unpaid, emergency];
}

/// طريقةُ استحقاق الرصيد.
abstract final class LeaveAccrual {
  static const yearly = 'yearly';
  static const monthly = 'monthly';
  static const none = 'none';
  static const values = [yearly, monthly, none];
}

abstract final class LeaveRequestStatus {
  static const draft = 'draft';
  static const submitted = 'submitted';
  static const approved = 'approved';
  static const rejected = 'rejected';
  static const cancelled = 'cancelled';
  static const values = [draft, submitted, approved, rejected, cancelled];

  /// حالاتٌ تحجز أيّامَها: طلبٌ يتداخل معها يُرفَض.
  static const blocking = {draft, submitted, approved};
}

class LeaveType {
  const LeaveType({
    this.id,
    required this.code,
    required this.name,
    this.nameEn,
    this.isPaid = true,
    this.yearlyDays = 0,
    this.carryOverMax = 0,
    this.requiresAttachment = false,
    this.accrual = LeaveAccrual.yearly,
    this.isActive = true,
  });
  final int? id;
  final String code;
  final String name;
  final String? nameEn;
  final bool isPaid;
  final double yearlyDays;
  final double carryOverMax;
  final bool requiresAttachment;
  final String accrual;
  final bool isActive;

  bool get isSystem => LeaveTypeCode.system.contains(code);

  /// هل للنوع رصيدٌ يُحَدّ به الطلب؟
  bool get hasEntitlement =>
      isPaid && yearlyDays > 0 && accrual != LeaveAccrual.none;
}

/// المستحَقُّ من [type] في [year] حتى [asOf] لموظفٍ عُيِّن في [hireDate].
///
/// سنويٌّ ⇒ الرصيدُ كاملاً من أوّل السنة (أو من شهر التعيين).
/// شهريٌّ ⇒ ‏١/١٢ من الرصيد عن كلّ شهرٍ بدأ من السنة حتى [asOf]، بدءاً من
/// شهر التعيين. والنتيجةُ مقرَّبةٌ لخانتين.
double accruedLeaveDays(
    LeaveType type, int year, DateTime asOf, DateTime? hireDate) {
  if (!type.hasEntitlement) return 0;
  if (asOf.year < year) return 0;
  if (hireDate != null && hireDate.year > year) return 0;
  final firstMonth =
      hireDate != null && hireDate.year == year ? hireDate.month : 1;
  if (type.accrual == LeaveAccrual.yearly) return type.yearlyDays;
  final lastMonth = asOf.year > year ? 12 : asOf.month;
  final months = lastMonth - firstMonth + 1;
  if (months <= 0) return 0;
  return (type.yearlyDays * months / 12 * 100).roundToDouble() / 100;
}

/// رصيدُ نوعِ إجازةٍ لموظفٍ في سنة. (‏`LeaveEntitlement` لا `LeaveBalance`:
/// الأخيرُ صنفُ drift لجدول `leave_balances` القديم.)
class LeaveEntitlement {
  const LeaveEntitlement({
    required this.employeeId,
    required this.leaveTypeId,
    required this.year,
    this.id,
    this.openingDays = 0,
    this.accruedDays = 0,
    this.usedDays = 0,
    this.openingLocked = false,
    this.entitlementOverride,
    this.type,
  });
  final int? id;
  final int employeeId;
  final int leaveTypeId;
  final int year;

  /// المرحَّلُ من السنة السابقة (مقيَّدٌ بحدّ الترحيل) أو ما أدخله المستخدم.
  final double openingDays;
  final double accruedDays;
  final double usedDays;

  /// الافتتاحيُّ أدخله المستخدمُ يدويّاً فلا يُعاد حسابُه.
  final bool openingLocked;

  /// استحقاقٌ ثابتٌ بدل الحساب (أرصدةٌ مرحَّلةٌ من النظام القديم).
  final double? entitlementOverride;
  final LeaveType? type;

  double get remaining => openingDays + accruedDays - usedDays;
}

class LeaveRequest {
  const LeaveRequest({
    this.id,
    required this.employeeId,
    required this.leaveTypeId,
    required this.startDate,
    required this.endDate,
    this.days = 0,
    this.status = LeaveRequestStatus.draft,
    this.reason,
    this.attachmentPath,
    this.requestedBy,
    this.decidedBy,
    this.decidedAt,
    this.decisionNote,
    this.employeeName,
    this.type,
  });
  final int? id;
  final int employeeId;
  final int leaveTypeId;
  final DateTime startDate;
  final DateTime endDate;

  /// أيّامُ العمل في الفترة (بلا الراحة الأسبوعيّة والعطلات الرسميّة).
  final double days;
  final String status;
  final String? reason;
  final String? attachmentPath;
  final int? requestedBy;
  final int? decidedBy;
  final DateTime? decidedAt;
  final String? decisionNote;

  // للعرض فقط.
  final String? employeeName;
  final LeaveType? type;

  bool overlaps(DateTime from, DateTime to) =>
      !endDate.isBefore(from) && !startDate.isAfter(to);
}
