import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/domain/models/table_actions.dart';
import 'package:picpos_erp/presentation/screens/role_management/data/permission_categories.dart';

void main() {
  test('كلُّ فعلٍ يحرّك مالاً أو حالةً له كودُ صلاحيّة', () {
    const moneyOrState = [
      TableAction.open,
      TableAction.addItems,
      TableAction.transfer,
      TableAction.merge,
      TableAction.splitBill,
      TableAction.printBill,
      TableAction.reserve,
      TableAction.pay,
      TableAction.changeStatus,
      TableAction.cancelOrder,
      TableAction.closeTable,
    ];
    for (final a in moneyOrState) {
      expect(permissionForAction(a), isNotNull,
          reason: 'الفعلُ $a بلا صلاحيّةٍ تحرسه');
    }
  });

  test('سجلُّ الطاولة قراءةٌ محضة — لا صلاحيّةَ خاصّةً له', () {
    expect(permissionForAction(TableAction.log), isNull);
  });

  test('الأكوادُ الثلاثةُ الجديدة مسجَّلةٌ في masterList', () {
    final codes = PermissionCodes.masterList
        .map((e) => e['code'] as String)
        .toSet();
    expect(codes, contains(PermissionCodes.tablesMerge));
    expect(codes, contains(PermissionCodes.tablesSplitBill));
    expect(codes, contains(PermissionCodes.tablesReserve));
  });

  test('كلُّ كودٍ ترجعه الخريطةُ موجودٌ في masterList', () {
    final codes = PermissionCodes.masterList
        .map((e) => e['code'] as String)
        .toSet();
    for (final a in TableAction.values) {
      final p = permissionForAction(a);
      if (p != null) {
        expect(codes, contains(p), reason: 'الكودُ $p للفعل $a غيرُ مسجَّل');
      }
    }
  });

  // التسجيلُ في `masterList` يهيّئ الصفَّ في القاعدة فحسب؛ أمّا **المنحُ** فيمرّ
  // من شاشة «الأدوار والصلاحيّات»، وهي تُبنى من `permissionCategories` وحدَها
  // لا من القاعدة. فكودٌ غائبٌ عن هذه الخريطة لا مربّعَ له ⇒ لا يُمنح لأيِّ
  // دورٍ أبداً، ويبقى حكراً على `system_admin`. هذا التوكيدُ يقيس القابليّةَ
  // للمنح لا مجرّدَ الوجود.
  test('كلُّ كودٍ ترجعه الخريطةُ قابلٌ للمنح من شاشة الأدوار', () {
    final grantable = <String>{
      for (final c in permissionCategories.values) ...c.permissions.keys,
    };
    for (final a in TableAction.values) {
      final p = permissionForAction(a);
      if (p != null) {
        expect(grantable, contains(p),
            reason: 'الكودُ $p للفعل $a لا مربّعَ له في شاشة الأدوار');
      }
    }
  });
}
