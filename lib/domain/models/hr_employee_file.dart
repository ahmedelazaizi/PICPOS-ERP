// J4 (الجزء ١) — ملفُّ الموظف في PicPos: البياناتُ الشخصيّة والوظيفيّة
// والعقدُ والأجر والمستنداتُ والسجلُّ، وربطُ الموظف بأدواره في النظام.
//
// نماذجُ خالصةٌ بلا Flutter ولا قاعدة: تُبنى من صفوف `employees` (أعمدةُ
// drift + أعمدةُ v191 الخامّة) وجداول v191 (‏`hr_departments` ·
// `hr_job_titles` · `employee_allowances` · `employee_documents` ·
// `employee_history`).
//
// ⚠️ نقاطُ التوصيل للجزأين ٢ و٣ (الحضور والإجازات / الرواتب والعمولات):
//   • `EmployeeProfile.basicSalary` + `allowances` ⇒ أساسُ مسيّر الرواتب.
//   • `paymentMethod` + `bankName/bankAccount/iban` ⇒ طريقةُ صرف الراتب.
//   • `employmentType` + `hoursPerDay` ⇒ الورديّاتُ وأجرُ الساعة.
//   • `status` / `terminationDate` ⇒ يُستبعَد المنتهي من الحضور والمسيّر.
//   • `HrEventType` ⇒ أحداثٌ جديدة (‏`salary_change` · `leave` …) تُسجَّل
//     بنفس `employee_history`.

import '../../core/i18n/tr.dart';

/// A rejected HR operation. [key] is the Arabic catalog key.
class HrException implements Exception {
  HrException(this.key, [this.params = const {}]);
  final String key;
  final Map<String, Object?> params;

  String get message => tr(key, params);

  @override
  String toString() => message;
}

/// نوعُ التوظيف.
abstract final class EmploymentType {
  static const fullTime = 'full_time';
  static const partTime = 'part_time';
  static const contract = 'contract';
  static const values = [fullTime, partTime, contract];
}

/// حالةُ الموظف. `employees.is_active` (drift) تتبعها: نشِطٌ ⇔ `active`.
abstract final class EmployeeStatus {
  static const active = 'active';
  static const suspended = 'suspended';
  static const terminated = 'terminated';
  static const values = [active, suspended, terminated];
}

/// نوعُ البدل: مبلغٌ ثابتٌ أو نسبةٌ من الأساسيّ.
abstract final class AllowanceType {
  static const fixed = 'fixed';
  static const percent = 'percent';
}

/// طريقةُ صرف الراتب (تُخزَّن للجزء ٣).
abstract final class SalaryPaymentMethod {
  static const cash = 'cash';
  static const bank = 'bank';
}

/// الجنس.
abstract final class EmployeeGender {
  static const male = 'male';
  static const female = 'female';
}

/// أحداثُ سجلّ الموظف — تُسجَّل آليّاً عند الحفظ.
abstract final class HrEventType {
  static const appointment = 'appointment';
  static const transfer = 'transfer';
  static const promotion = 'promotion';
  static const salaryChange = 'salary_change';
  static const statusChange = 'status_change';
  static const termination = 'termination';
  static const userLink = 'user_link';
  static const roleChange = 'role_change';
}

/// وسومُ الأدوار في النظام — تُقترَح بها صلاحيّةُ المستخدم وموارده.
abstract final class HrRoleTag {
  static const rep = 'rep';
  static const cashier = 'cashier';
  static const accountant = 'accountant';
  static const warehouseKeeper = 'warehouse_keeper';
  static const values = [rep, cashier, accountant, warehouseKeeper];

  /// اسمُ الدور المبذور الذي يُقترَح للمستخدم الجديد (‏`roles.name`).
  static const suggestedRoleNames = <String, List<String>>{
    rep: ['مندوب', 'مندوب مبيعات', 'كاشير'],
    cashier: ['كاشير', 'كاشير متقدم'],
    accountant: ['محاسب', 'محاسب متقدم'],
    warehouseKeeper: ['مخزني', 'مدير مخزون'],
  };

  static Set<String> decode(String? csv) => {
        for (final t in (csv ?? '').split(','))
          if (values.contains(t.trim())) t.trim(),
      };

  static String? encode(Set<String> tags) {
    final ordered = [for (final t in values) if (tags.contains(t)) t];
    return ordered.isEmpty ? null : ordered.join(',');
  }
}

class HrDepartment {
  const HrDepartment({
    required this.id,
    required this.name,
    this.nameEn,
    this.code,
    this.parentId,
    this.managerEmployeeId,
    this.isActive = true,
    this.employeeCount = 0,
  });
  final int id;
  final String name;
  final String? nameEn;
  final String? code;
  final int? parentId;
  final int? managerEmployeeId;
  final bool isActive;
  final int employeeCount;
}

class HrJobTitle {
  const HrJobTitle({
    required this.id,
    required this.name,
    this.nameEn,
    this.departmentId,
    this.isActive = true,
    this.employeeCount = 0,
  });
  final int id;
  final String name;
  final String? nameEn;
  final int? departmentId;
  final bool isActive;
  final int employeeCount;
}

class EmployeeAllowance {
  const EmployeeAllowance({
    this.id,
    required this.name,
    required this.amount,
    this.type = AllowanceType.fixed,
  });
  final int? id;
  final String name;
  final double amount;
  final String type;

  /// قيمةُ البدل الشهريّة على [basicSalary].
  double valueFor(double basicSalary) =>
      type == AllowanceType.percent ? basicSalary * amount / 100 : amount;
}

/// حالةُ صلاحيّة المستند.
enum DocumentExpiryState { none, valid, expiringSoon, expired }

class EmployeeDocument {
  const EmployeeDocument({
    this.id,
    required this.docType,
    this.docNumber,
    this.issueDate,
    this.expiryDate,
    this.filePath,
    this.notes,
  });
  final int? id;
  final String docType;
  final String? docNumber;
  final DateTime? issueDate;
  final DateTime? expiryDate;
  final String? filePath;
  final String? notes;

  /// أيّامُ التنبيه قبل انتهاء المستند.
  static const warningDays = 30;

  DocumentExpiryState expiryState(DateTime now) {
    final expiry = expiryDate;
    if (expiry == null) return DocumentExpiryState.none;
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(expiry.year, expiry.month, expiry.day);
    if (end.isBefore(today)) return DocumentExpiryState.expired;
    if (end.difference(today).inDays <= warningDays) {
      return DocumentExpiryState.expiringSoon;
    }
    return DocumentExpiryState.valid;
  }
}

class EmployeeHistoryEvent {
  const EmployeeHistoryEvent({
    required this.id,
    required this.employeeId,
    required this.eventType,
    required this.eventDate,
    this.fromValue,
    this.toValue,
    this.notes,
    this.userId,
  });
  final int id;
  final int employeeId;
  final String eventType;
  final DateTime eventDate;
  final String? fromValue;
  final String? toValue;
  final String? notes;
  final int? userId;
}

/// ملفُّ الموظف كاملاً — ما يُقرأ ويُحفَظ من شاشة «ملف الموظف».
class EmployeeProfile {
  const EmployeeProfile({
    this.id,
    this.globalId,
    this.code,
    required this.name,
    this.nameEn,
    this.nationalId,
    this.birthDate,
    this.gender,
    this.nationality,
    this.phone,
    this.phone2,
    this.email,
    this.address,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.photoPath,
    this.departmentId,
    this.jobTitleId,
    this.branchId,
    this.managerId,
    this.hireDate,
    this.employmentType = EmploymentType.fullTime,
    this.status = EmployeeStatus.active,
    this.terminationDate,
    this.terminationReason,
    this.contractStart,
    this.contractEnd,
    this.probationEnd,
    this.basicSalary = 0,
    this.salaryType = 'monthly',
    this.hoursPerDay,
    this.paymentMethod = SalaryPaymentMethod.cash,
    this.bankName,
    this.bankAccount,
    this.iban,
    this.userId,
    this.roleTags = const {},
    this.legacyRole = 'staff',
    this.departmentName,
    this.jobTitleName,
    this.branchName,
    this.managerName,
    this.username,
  });

  final int? id;
  final String? globalId;
  final String? code;
  final String name;
  final String? nameEn;
  final String? nationalId;
  final DateTime? birthDate;
  final String? gender;
  final String? nationality;
  final String? phone;
  final String? phone2;
  final String? email;
  final String? address;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? photoPath;

  final int? departmentId;
  final int? jobTitleId;
  final int? branchId;
  final int? managerId;
  final DateTime? hireDate;
  final String employmentType;
  final String status;
  final DateTime? terminationDate;
  final String? terminationReason;

  final DateTime? contractStart;
  final DateTime? contractEnd;
  final DateTime? probationEnd;
  final double basicSalary;
  final String salaryType;
  final double? hoursPerDay;
  final String paymentMethod;
  final String? bankName;
  final String? bankAccount;
  final String? iban;

  final int? userId;
  final Set<String> roleTags;

  /// `employees.role` القديم (‏cashier/waiter/…) — يبقى لشاشات UralCash.
  final String legacyRole;

  // للعرض فقط (‏JOIN) — لا تُحفَظ.
  final String? departmentName;
  final String? jobTitleName;
  final String? branchName;
  final String? managerName;
  final String? username;

  bool get isActive => status == EmployeeStatus.active;
  bool get isRep => roleTags.contains(HrRoleTag.rep);
}

/// مرشّحاتُ سجلّ الموظفين.
class EmployeeListFilter {
  const EmployeeListFilter({
    this.query = '',
    this.departmentId,
    this.jobTitleId,
    this.branchId,
    this.status,
    this.roleTag,
  });
  final String query;
  final int? departmentId;
  final int? jobTitleId;
  final int? branchId;
  final String? status;
  final String? roleTag;

  bool get isEmpty =>
      query.trim().isEmpty &&
      departmentId == null &&
      jobTitleId == null &&
      branchId == null &&
      status == null &&
      roleTag == null;

  bool matches(EmployeeProfile p) {
    if (departmentId != null && p.departmentId != departmentId) return false;
    if (jobTitleId != null && p.jobTitleId != jobTitleId) return false;
    if (branchId != null && p.branchId != branchId) return false;
    if (status != null && p.status != status) return false;
    if (roleTag != null && !p.roleTags.contains(roleTag)) return false;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      p.name,
      p.nameEn,
      p.code,
      p.phone,
      p.nationalId,
      p.jobTitleName,
      p.departmentName,
    ].any((v) => v != null && v.toLowerCase().contains(q));
  }

  EmployeeListFilter copyWith({
    String? query,
    int? Function()? departmentId,
    int? Function()? jobTitleId,
    int? Function()? branchId,
    String? Function()? status,
    String? Function()? roleTag,
  }) =>
      EmployeeListFilter(
        query: query ?? this.query,
        departmentId: departmentId == null ? this.departmentId : departmentId(),
        jobTitleId: jobTitleId == null ? this.jobTitleId : jobTitleId(),
        branchId: branchId == null ? this.branchId : branchId(),
        status: status == null ? this.status : status(),
        roleTag: roleTag == null ? this.roleTag : roleTag(),
      );
}

/// عقدةٌ في الهيكل التنظيميّ (‏شجرةٌ بالمدير المباشر).
class OrgChartNode {
  OrgChartNode(this.employee);
  final EmployeeProfile employee;
  final List<OrgChartNode> reports = [];
}

/// يبني شجرةَ المدير المباشر. موظفٌ مديرُه غيرُ موجودٍ (أو حلقةٌ) جذرٌ.
List<OrgChartNode> buildOrgChart(List<EmployeeProfile> employees) {
  final nodes = {
    for (final e in employees)
      if (e.id != null) e.id!: OrgChartNode(e),
  };
  bool createsCycle(int id, int managerId) {
    final seen = <int>{id};
    int? cursor = managerId;
    while (cursor != null) {
      if (!seen.add(cursor)) return true;
      cursor = nodes[cursor]?.employee.managerId;
    }
    return false;
  }

  final roots = <OrgChartNode>[];
  for (final node in nodes.values) {
    final managerId = node.employee.managerId;
    final manager = managerId == null ? null : nodes[managerId];
    if (manager == null || createsCycle(node.employee.id!, managerId!)) {
      roots.add(node);
    } else {
      manager.reports.add(node);
    }
  }
  return roots;
}
