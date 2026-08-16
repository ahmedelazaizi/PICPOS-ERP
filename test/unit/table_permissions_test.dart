import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';

void main() {
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
