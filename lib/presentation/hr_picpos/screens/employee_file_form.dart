// J4 — حالةُ نموذج ملفّ الموظف: متحكّماتُ النصوص وقيمُ الاختيار لكلّ
// التبويبات، تُبنى من [EmployeeProfile] وتُعيده عند الحفظ. التبويباتُ تقرأ
// منها وتكتب فيها فلا يضيع إدخالٌ عند التنقّل بينها.
import 'package:flutter/widgets.dart';

import '../../../domain/models/hr_employee_file.dart';

class EmployeeFileForm extends ChangeNotifier {
  EmployeeFileForm(EmployeeProfile? p, {List<EmployeeAllowance>? allowances})
      : source = p,
        code = TextEditingController(text: p?.code ?? ''),
        name = TextEditingController(text: p?.name ?? ''),
        nameEn = TextEditingController(text: p?.nameEn ?? ''),
        nationalId = TextEditingController(text: p?.nationalId ?? ''),
        nationality = TextEditingController(text: p?.nationality ?? ''),
        phone = TextEditingController(text: p?.phone ?? ''),
        phone2 = TextEditingController(text: p?.phone2 ?? ''),
        email = TextEditingController(text: p?.email ?? ''),
        address = TextEditingController(text: p?.address ?? ''),
        emergencyName =
            TextEditingController(text: p?.emergencyContactName ?? ''),
        emergencyPhone =
            TextEditingController(text: p?.emergencyContactPhone ?? ''),
        photoPath = TextEditingController(text: p?.photoPath ?? ''),
        terminationReason =
            TextEditingController(text: p?.terminationReason ?? ''),
        basicSalary = TextEditingController(
            text: p == null ? '' : _num(p.basicSalary)),
        hoursPerDay = TextEditingController(
            text: p?.hoursPerDay == null ? '' : _num(p!.hoursPerDay!)),
        bankName = TextEditingController(text: p?.bankName ?? ''),
        bankAccount = TextEditingController(text: p?.bankAccount ?? ''),
        iban = TextEditingController(text: p?.iban ?? ''),
        birthDate = p?.birthDate,
        gender = p?.gender,
        departmentId = p?.departmentId,
        jobTitleId = p?.jobTitleId,
        branchId = p?.branchId,
        managerId = p?.managerId,
        hireDate = p?.hireDate ?? DateTime.now(),
        employmentType = p?.employmentType ?? EmploymentType.fullTime,
        status = p?.status ?? EmployeeStatus.active,
        terminationDate = p?.terminationDate,
        contractStart = p?.contractStart,
        contractEnd = p?.contractEnd,
        probationEnd = p?.probationEnd,
        salaryType = p?.salaryType ?? 'monthly',
        paymentMethod = p?.paymentMethod ?? SalaryPaymentMethod.cash,
        allowances = [
          for (final a in allowances ?? const <EmployeeAllowance>[])
            AllowanceRow.of(a),
        ];

  final EmployeeProfile? source;
  final TextEditingController code, name, nameEn, nationalId, nationality;
  final TextEditingController phone, phone2, email, address;
  final TextEditingController emergencyName, emergencyPhone, photoPath;
  final TextEditingController terminationReason, basicSalary, hoursPerDay;
  final TextEditingController bankName, bankAccount, iban;

  DateTime? birthDate;
  String? gender;
  int? departmentId;
  int? jobTitleId;
  int? branchId;
  int? managerId;
  DateTime? hireDate;
  String employmentType;
  String status;
  DateTime? terminationDate;
  DateTime? contractStart;
  DateTime? contractEnd;
  DateTime? probationEnd;
  String salaryType;
  String paymentMethod;
  final List<AllowanceRow> allowances;

  bool get isNew => source?.id == null;

  /// يُعلِم التبويباتِ بتغيّر قيمةٍ اختياريّة.
  void set(VoidCallback change) {
    change();
    notifyListeners();
  }

  void addAllowance() => set(() => allowances.add(AllowanceRow.blank()));

  void removeAllowance(AllowanceRow row) => set(() {
        allowances.remove(row);
        row.dispose();
      });

  double get basic => double.tryParse(basicSalary.text.trim()) ?? 0;

  /// إجماليُّ البدلات الشهريّ على الأساسيّ الحاليّ.
  double get allowancesTotal =>
      allowances.fold(0, (s, a) => s + a.toAllowance().valueFor(basic));

  EmployeeProfile toProfile() {
    String? t(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final s = source;
    return EmployeeProfile(
      id: s?.id,
      globalId: s?.globalId,
      code: t(code),
      name: name.text.trim(),
      nameEn: t(nameEn),
      nationalId: t(nationalId),
      birthDate: birthDate,
      gender: gender,
      nationality: t(nationality),
      phone: t(phone),
      phone2: t(phone2),
      email: t(email),
      address: t(address),
      emergencyContactName: t(emergencyName),
      emergencyContactPhone: t(emergencyPhone),
      photoPath: t(photoPath),
      departmentId: departmentId,
      jobTitleId: jobTitleId,
      branchId: branchId,
      managerId: managerId,
      hireDate: hireDate,
      employmentType: employmentType,
      status: status,
      terminationDate: terminationDate,
      terminationReason: t(terminationReason),
      contractStart: contractStart,
      contractEnd: contractEnd,
      probationEnd: probationEnd,
      basicSalary: basic,
      salaryType: salaryType,
      hoursPerDay: double.tryParse(hoursPerDay.text.trim()),
      paymentMethod: paymentMethod,
      bankName: t(bankName),
      bankAccount: t(bankAccount),
      iban: t(iban),
      userId: s?.userId,
      roleTags: s?.roleTags ?? const {},
      legacyRole: s?.legacyRole ?? 'staff',
    );
  }

  List<EmployeeAllowance> toAllowances() => [
        for (final a in allowances)
          if (a.name.text.trim().isNotEmpty) a.toAllowance(),
      ];

  @override
  void dispose() {
    for (final c in [
      code, name, nameEn, nationalId, nationality, phone, phone2, email,
      address, emergencyName, emergencyPhone, photoPath, terminationReason,
      basicSalary, hoursPerDay, bankName, bankAccount, iban,
    ]) {
      c.dispose();
    }
    for (final a in allowances) {
      a.dispose();
    }
    super.dispose();
  }
}

/// صفُّ بدلٍ في النموذج.
class AllowanceRow {
  AllowanceRow._(this.id, String name, String amount, this.type)
      : name = TextEditingController(text: name),
        amount = TextEditingController(text: amount);

  factory AllowanceRow.of(EmployeeAllowance a) =>
      AllowanceRow._(a.id, a.name, _num(a.amount), a.type);

  factory AllowanceRow.blank() =>
      AllowanceRow._(null, '', '', AllowanceType.fixed);

  final int? id;
  final TextEditingController name;
  final TextEditingController amount;
  String type;

  EmployeeAllowance toAllowance() => EmployeeAllowance(
        id: id,
        name: name.text.trim(),
        amount: double.tryParse(amount.text.trim()) ?? 0,
        type: type,
      );

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

String _num(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
