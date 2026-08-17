import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/table_actions.dart';
import 'package:ural_erp/domain/models/table_status.dart';

void main() {
  test('المتاحةُ لا تُظهر دفعاً ولا نقلاً', () {
    final a = actionsForStatus(TableStatus.available);
    expect(a, contains(TableAction.open));
    expect(a, contains(TableAction.reserve));
    expect(a, isNot(contains(TableAction.pay)));
    expect(a, isNot(contains(TableAction.transfer)));
    expect(a, isNot(contains(TableAction.closeTable)));
  });

  test('المشغولةُ تُظهر الإلغاء لا الإغلاق', () {
    final a = actionsForStatus(TableStatus.occupied);
    expect(a, contains(TableAction.cancelOrder));
    expect(a, isNot(contains(TableAction.closeTable)));
    expect(a, containsAll([
      TableAction.addItems,
      TableAction.transfer,
      TableAction.merge,
      TableAction.splitBill,
      TableAction.printBill,
      TableAction.pay,
    ]));
  });

  test('المدفوعةُ تُظهر الإغلاق لا الإلغاء ولا الدفع', () {
    final a = actionsForStatus(TableStatus.paid);
    expect(a, contains(TableAction.closeTable));
    expect(a, isNot(contains(TableAction.cancelOrder)));
    expect(a, isNot(contains(TableAction.pay)));
    expect(a, contains(TableAction.addItems),
        reason: 'الإضافةُ بعد الدفع تفتح طلباً جديداً');
    expect(a, contains(TableAction.printBill));
  });

  test('غيرُ المتاحة لا تقبل إلا تغييرَ الحالة والسجل', () {
    final a = actionsForStatus(TableStatus.outOfService);
    expect(a, containsAll([TableAction.changeStatus, TableAction.log]));
    expect(a, hasLength(2));
  });

  test('السجلُّ يظهر في كلّ الحالات', () {
    for (final s in TableStatus.all) {
      expect(actionsForStatus(s), contains(TableAction.log), reason: s);
    }
  });
}
