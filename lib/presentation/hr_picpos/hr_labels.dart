// J4 — تسمياتُ قيم الموارد البشريّة المخزَّنة (حالةٌ ونوعُ توظيفٍ وحدثٌ
// ووسمُ دور) بالعربيّة وعبر `tr` للإنجليزيّة.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/i18n/tr.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/models/hr_employee_file.dart';

String hrStatusLabel(String status) => switch (status) {
      EmployeeStatus.active => tr('نشط'),
      EmployeeStatus.suspended => tr('موقوف'),
      EmployeeStatus.terminated => tr('منتهي الخدمة'),
      _ => status,
    };

Color hrStatusColor(BuildContext context, String status) => switch (status) {
      EmployeeStatus.active => AppColors.statusSuccess(context),
      EmployeeStatus.suspended => AppColors.statusWarning(context),
      _ => AppColors.statusError(context),
    };

String hrEmploymentTypeLabel(String type) => switch (type) {
      EmploymentType.fullTime => tr('دوام كامل'),
      EmploymentType.partTime => tr('دوام جزئي'),
      EmploymentType.contract => tr('عقد مؤقت'),
      _ => type,
    };

String hrRoleTagLabel(String tag) => switch (tag) {
      HrRoleTag.rep => tr('مندوب مبيعات'),
      HrRoleTag.cashier => tr('كاشير'),
      HrRoleTag.accountant => tr('محاسب'),
      HrRoleTag.warehouseKeeper => tr('أمين مخزن'),
      _ => tag,
    };

IconData hrRoleTagIcon(String tag) => switch (tag) {
      HrRoleTag.rep => PhosphorIconsBold.truck,
      HrRoleTag.cashier => PhosphorIconsBold.cashRegister,
      HrRoleTag.accountant => PhosphorIconsBold.calculator,
      HrRoleTag.warehouseKeeper => PhosphorIconsBold.warehouse,
      _ => PhosphorIconsBold.tag,
    };

String hrEventLabel(String type) => switch (type) {
      HrEventType.appointment => tr('تعيين'),
      HrEventType.transfer => tr('نقل'),
      HrEventType.promotion => tr('ترقية / تغيير المسمى'),
      HrEventType.salaryChange => tr('تعديل الراتب'),
      HrEventType.statusChange => tr('تغيير الحالة'),
      HrEventType.termination => tr('إنهاء الخدمة'),
      HrEventType.userLink => tr('ربط مستخدم النظام'),
      HrEventType.roleChange => tr('تغيير الأدوار'),
      _ => type,
    };

IconData hrEventIcon(String type) => switch (type) {
      HrEventType.appointment => PhosphorIconsBold.userPlus,
      HrEventType.transfer => PhosphorIconsBold.arrowsLeftRight,
      HrEventType.promotion => PhosphorIconsBold.trendUp,
      HrEventType.salaryChange => PhosphorIconsBold.money,
      HrEventType.termination => PhosphorIconsBold.userMinus,
      HrEventType.userLink => PhosphorIconsBold.key,
      HrEventType.roleChange => PhosphorIconsBold.tag,
      _ => PhosphorIconsBold.clockCounterClockwise,
    };

/// قيمةُ حدثٍ مخزَّنةٌ بمفتاحٍ (حالةٌ أو وسومُ أدوار) تُعرض بتسميتها.
String hrEventValue(String type, String? value) {
  if (value == null) return '—';
  if (type == HrEventType.statusChange || type == HrEventType.termination) {
    return hrStatusLabel(value);
  }
  if (type == HrEventType.roleChange) {
    return HrRoleTag.decode(value).map(hrRoleTagLabel).join('، ');
  }
  return value;
}

String hrDate(DateTime? d) => d == null
    ? '—'
    : '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
