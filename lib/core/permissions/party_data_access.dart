import '../navigation/screen_id.dart';
import 'financial_figures_access.dart';
import 'permission_codes.dart';

/// AUTHZ-003 (audit 2026-10-23): من يحقّ له كشفُ حساب الطرف، وتصدير الأطراف
/// (بأرصدتها)، واستيرادهم.
///
/// الأصلُ أنّ هذه المداخل سبقت F.2 (الذي صار يفتح الشاشةَ بأكواد الإجراء
/// وحدها) فكانت محميّةً ضمناً بـ`*_view`؛ فتُحرَس صراحةً الآن:
///  * **الكشف**: كود عرض الشاشة (قاعدة الأرقام نفسها — [canSeeScreenFigures]).
///  * **التصدير**: كود العرض **و** `reports_export` (يخرج كلُّ الأطراف بأرصدتهم).
///  * **الاستيراد**: كودا الإضافة والتعديل معاً للنوع (ينشئ ويحدّث).
///
/// ولا كودَ مخصّصاً `customers_export/import` بعد — يحتاج تسجيلاً في بذور
/// الصلاحيات وقوالب الأدوار؛ مؤجّل (انظر تقرير التدقيق).
class PartyDataAccess {
  PartyDataAccess._();

  static ScreenId _screen(bool supplier) =>
      supplier ? ScreenId.suppliers : ScreenId.customers;

  static bool _isAdmin(Iterable<String> perms) =>
      perms.contains('system_admin') || perms.contains('*');

  static bool canViewStatement(
    Iterable<String> perms, {
    required bool supplier,
    bool bypass = false,
  }) =>
      canSeeScreenFigures(perms, _screen(supplier), bypass: bypass);

  static bool canExport(
    Iterable<String> perms, {
    required bool supplier,
    bool bypass = false,
  }) =>
      bypass ||
      (canSeeScreenFigures(perms, _screen(supplier)) &&
          perms.contains(PermissionCodes.reportsExport)) ||
      _isAdmin(perms);

  static bool canImport(
    Iterable<String> perms, {
    required bool supplier,
    bool bypass = false,
  }) {
    if (bypass || _isAdmin(perms)) return true;
    return supplier
        ? perms.contains(PermissionCodes.suppliersAdd) &&
            perms.contains(PermissionCodes.suppliersEdit)
        : perms.contains(PermissionCodes.customersAdd) &&
            perms.contains(PermissionCodes.customersEdit);
  }
}
