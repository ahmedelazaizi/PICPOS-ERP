// أدواتٌ مشتركةٌ لدورة مسوّدة المرتجع وسجلّيه — J2 (قرارُ المالك).
//
// المبيعاتُ والمشترياتُ توأمان في الشكل؛ نسخُ هذه الأسطر بينهما هو «مصيدةُ
// النسخ §٥.٥»، فتعيش هنا مرّةً واحدة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/tr.dart';
import '../../core/permissions/permission_codes.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart' show currentUserPermissionsProvider;
import '../../domain/models/return_draft.dart';

/// ما تعيده صفحةُ الاستمارة إلى السجلّ حين تُغلَق بعد حفظٍ أو اعتماد —
/// ليُختار الصفُّ الجديد.
class ReturnFormResult {
  const ReturnFormResult({
    required this.originalInvoiceId,
    required this.posted,
    this.draftId,
  });

  final int originalInvoiceId;
  final bool posted;
  final int? draftId;
}

/// هل يملك المستخدمُ [code]؟ — نفسُ قاعدة `PermissionGuard`: مديرُ النظام
/// (`system_admin` أو `*`) يملك ما ليس عمليّةً ماليّةً حرجة. وقائمةٌ لم
/// تُقرأ بعد (`null`) تُغلِق لا تفتح.
bool returnPermissionGranted(List<String>? perms, String code) {
  if (perms == null) return false;
  final admin = perms.contains('system_admin') || perms.contains('*');
  if (admin && !PermissionCodes.criticalFinancialOps.contains(code)) {
    return true;
  }
  return perms.contains(code);
}

/// يقرأ صلاحياتِ المستخدم الحاليّ (مراقبةً داخلَ `build`).
bool watchReturnPermission(WidgetRef ref, String code) =>
    returnPermissionGranted(
        ref.watch(currentUserPermissionsProvider).value, code);

/// يقرأ صلاحياتِ المستخدم الحاليّ (قراءةً في معالج فعل).
bool readReturnPermission(WidgetRef ref, String code) =>
    returnPermissionGranted(
        ref.read(currentUserPermissionsProvider).value, code);

/// اسمُ التسوية المعروض — `cash` · `bank` · `balance` · `credit` · `mixed`.
String returnSettlementLabel(String? code) => switch (code) {
      'cash' => tr('نقدي'),
      'bank' => tr('بنكي'),
      'balance' || 'credit' => tr('على الحساب'),
      'mixed' => tr('نقدي + رصيد'),
      _ => '—',
    };

/// لونُ التسوية.
Color returnSettlementTint(String? code) => switch (code) {
      'balance' || 'credit' => AppColors.info,
      'mixed' => AppColors.warning,
      _ => AppColors.success,
    };

/// اسمُ الحالة — «مسودة» · «معتمد» · «ملغى».
String returnStatusLabel(ReturnRecordStatus s) => switch (s) {
      ReturnRecordStatus.draft => tr('مسودة'),
      ReturnRecordStatus.posted => tr('معتمد'),
      ReturnRecordStatus.cancelled => tr('ملغى'),
    };

Color returnStatusTint(ReturnRecordStatus s) => switch (s) {
      ReturnRecordStatus.draft => AppColors.warning,
      ReturnRecordStatus.posted => AppColors.success,
      ReturnRecordStatus.cancelled => AppColors.error,
    };

/// التسويةُ من أجزائها: ذمّةٌ و/أو نقدٌ و/أو بنك.
String settlementFromParts({
  double balance = 0,
  double cash = 0,
  double bank = 0,
}) {
  final parts = [
    if (balance > 0) 'balance',
    if (cash > 0) 'cash',
    if (bank > 0) 'bank',
  ];
  if (parts.isEmpty) return 'cash';
  return parts.length == 1 ? parts.single : 'mixed';
}
