import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/presentation/screens/tables_screen.dart';

void main() {
  // الأفعالُ الثلاثةُ الموصولةُ حديثاً (الإلغاء، تغييرُ الحالة، طباعةُ
  // الفاتورة) تُنادى من قائمةٍ مبنيّةٍ من دالّةٍ خالصة، فحراستُها تعيش عند
  // التنفيذ لا عند الرسم — نفسُ نمط `canPrintPosWorkOrder` المجاور.
  group('hasTableActionPermission', () {
    test('مرفوض من غير الكود', () {
      expect(
          hasTableActionPermission(const [], PermissionCodes.tablesCancel),
          isFalse);
    });

    test('مسموح مع الكود', () {
      expect(
          hasTableActionPermission(
              [PermissionCodes.tablesCancel], PermissionCodes.tablesCancel),
          isTrue);
    });

    test('كودٌ آخرُ لا يفتح البابَ', () {
      expect(
          hasTableActionPermission(
              [PermissionCodes.tablesView], PermissionCodes.tablesCancel),
          isFalse);
    });

    test('مديرُ النظام يمرّ بلا الكود صراحة', () {
      expect(
          hasTableActionPermission(
              const ['system_admin'], PermissionCodes.tablesPrintBill),
          isTrue);
      expect(
          hasTableActionPermission(
              const ['*'], PermissionCodes.tablesManage),
          isTrue);
    });
  });

  test('صلاحيةُ خصم الطاولة مسجَّلةٌ في تصنيف الطاولات', () {
    final entry = PermissionCodes.masterList
        .firstWhere((p) => p['code'] == PermissionCodes.tablesDiscount);
    expect(entry['category'], 'tables');
    expect(entry['name'], isNotEmpty);
  });

  test('طباعةُ فاتورة الطاولة لم تعد محجوزة', () {
    expect(
        PermissionCodes.nonToggleable
            .containsKey(PermissionCodes.tablesPrintBill),
        isFalse);
  });
}
