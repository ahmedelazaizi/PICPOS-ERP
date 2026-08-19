import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/domain/models/table_actions.dart';

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
}
