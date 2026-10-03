// J4 (الجزء ٣) — تسمياتُ قيم الرواتب المخزَّنة (حالةُ المسيّر، رمزُ البند،
// مفتاحُ الحساب، القواعد) بالعربيّة وعبر `tr` للإنجليزيّة، وتنسيقُ المبالغ.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/i18n/tr.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/models/hr_payroll.dart';
import '../picpos_shell/picpos_surface.dart';

final _money = NumberFormat(
    '#,##0${AppConstants.decimalPlaces > 0 ? '.${'0' * AppConstants.decimalPlaces}' : ''}',
    'en_US');

/// مبلغٌ بمنازل العملة وفواصل الآلاف (أرقامٌ لاتينيّة في الاتّجاهين).
String hrMoney(double v) => _money.format(v);

String hrPeriod(int year, int month) =>
    '$year-${month.toString().padLeft(2, '0')}';

String payrollStatusLabel(String s) => switch (s) {
      PayrollRunStatus.draft => tr('مسودة'),
      PayrollRunStatus.reviewed => tr('مراجَع'),
      PayrollRunStatus.approved => tr('معتمد'),
      PayrollRunStatus.posted => tr('مرحّل'),
      PayrollRunStatus.paid => tr('مدفوع'),
      PayrollRunStatus.reversed => tr('معكوس'),
      _ => s,
    };

Color payrollStatusColor(BuildContext context, String s) => switch (s) {
      PayrollRunStatus.draft => context.picposMuted,
      PayrollRunStatus.reviewed => AppColors.statusWarning(context),
      PayrollRunStatus.approved => Theme.of(context).colorScheme.primary,
      PayrollRunStatus.posted => AppColors.statusSuccess(context),
      PayrollRunStatus.paid => AppColors.statusSuccess(context),
      _ => AppColors.statusError(context),
    };

/// تسميةُ بندٍ: الرموزُ الثابتةُ عبر `tr`، والأسماءُ المخزَّنة (بدلٌ، بندٌ،
/// سببُ مكافأة) عبر `trData`.
String payItemLabel(PayrollItem i) => switch (i.code) {
      PayItemCode.basic => tr('الراتب الأساسي'),
      PayItemCode.overtime => tr('العمل الإضافي'),
      PayItemCode.commission => tr('عمولة المبيعات'),
      PayItemCode.absence => tr('خصم الغياب'),
      PayItemCode.lateness => tr('خصم التأخير'),
      PayItemCode.unpaidLeave => tr('إجازة بدون أجر'),
      PayItemCode.advance =>
        i.label == 'قسط قرض' ? tr('قسط قرض') : tr('قسط سلفة'),
      PayItemCode.insuranceEmployee => tr('التأمينات - حصة الموظف'),
      PayItemCode.insuranceEmployer => tr('التأمينات - حصة المنشأة'),
      PayItemCode.tax => tr('ضريبة الدخل'),
      PayItemCode.legacy => tr('راتب مصروف'),
      _ => trData(i.label),
    };

String payItemKindLabel(String k) => switch (k) {
      PayItemKind.earning => tr('استحقاق'),
      PayItemKind.deduction => tr('استقطاع'),
      _ => tr('على المنشأة'),
    };

String payAccountKeyLabel(String k) => switch (k) {
      PayAccountKey.salariesExpense => tr('مصروف الرواتب'),
      PayAccountKey.allowancesExpense => tr('مصروف البدلات والمكافآت'),
      PayAccountKey.overtimeExpense => tr('مصروف العمل الإضافي'),
      PayAccountKey.commissionsExpense => tr('مصروف العمولات'),
      PayAccountKey.employerInsuranceExpense =>
        tr('مصروف حصة المنشأة في التأمينات'),
      PayAccountKey.salariesPayable => tr('رواتب مستحقة الدفع'),
      PayAccountKey.insurancePayable => tr('تأمينات مستحقة'),
      PayAccountKey.taxPayable => tr('ضريبة رواتب مستحقة'),
      PayAccountKey.advancesReceivable => tr('سلف الموظفين'),
      _ => k,
    };

String dayBasisLabel(String b) => switch (b) {
      DayBasis.fixed30 => tr('الأساسي ÷ 30'),
      DayBasis.calendar => tr('الأساسي ÷ أيام الشهر'),
      DayBasis.working => tr('الأساسي ÷ أيام العمل'),
      _ => b,
    };

String latenessModeLabel(String m) => switch (m) {
      LatenessMode.none => tr('بلا خصم'),
      LatenessMode.perMinute => tr('بالدقيقة من أجر الساعة'),
      LatenessMode.tiers => tr('بالشرائح اليومية'),
      _ => m,
    };

String insuranceBaseLabel(String b) => switch (b) {
      InsuranceBase.gross => tr('إجمالي الراتب'),
      _ => tr('الراتب الأساسي'),
    };

String componentCalcLabel(String c) => switch (c) {
      ComponentCalc.fixed => tr('مبلغ ثابت'),
      ComponentCalc.percentBasic => tr('نسبة من الأساسي'),
      ComponentCalc.perDay => tr('لكل يوم عمل'),
      ComponentCalc.perHour => tr('لكل ساعة عمل'),
      ComponentCalc.formula => tr('صيغة'),
      _ => c,
    };

String advanceKindLabel(String k) =>
    k == AdvanceKind.loan ? tr('قرض') : tr('سلفة');

String advanceStatusLabel(String s) => switch (s) {
      AdvanceStatus.active => tr('مفتوحة'),
      AdvanceStatus.settled => tr('مسددة'),
      _ => tr('ملغاة'),
    };

String adjustmentKindLabel(String k) =>
    k == AdjustmentKind.bonus ? tr('مكافأة') : tr('جزاء');

String adjustmentStatusLabel(String s) => switch (s) {
      AdjustmentStatus.approved => tr('معتمدة'),
      AdjustmentStatus.rejected => tr('مرفوضة'),
      _ => tr('بانتظار الاعتماد'),
    };

Color adjustmentStatusColor(BuildContext context, String s) => switch (s) {
      AdjustmentStatus.approved => AppColors.statusSuccess(context),
      AdjustmentStatus.rejected => AppColors.statusError(context),
      _ => AppColors.statusWarning(context),
    };

String commissionDocKindLabel(String k) => switch (k) {
      'invoice' => tr('فاتورة'),
      'return' => tr('مرتجع'),
      'receipt' => tr('سند قبض'),
      'collection' => tr('تحصيل ميداني'),
      _ => k,
    };
