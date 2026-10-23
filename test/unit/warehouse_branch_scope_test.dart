// ═══════════════════════════════════════════════════════════════════════════
// حصرُ المخازن بفرع الجهاز — القاعدةُ الخالصة (Spec 103)
// ═══════════════════════════════════════════════════════════════════════════
//
// كانت هذه القاعدةُ مكتوبةً سطراً بسطر في نافذتَي فاتورة المبيعات (الكاملة
// وتوأمِ PicPos) وغائبةً تماماً عن نافذة فاتورة المشتريات. جمعُها في دالّةٍ
// خالصةٍ يجعلها تُقاس بلا فتح شاشة — واختباراتُ الودجت هنا تتعلّق عند فتح
// الشاشات.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/warehouse_branch_scope.dart';

class _Wh {
  const _Wh(this.id, this.branchId);
  final int id;
  final int? branchId;
}

List<int> _ids(List<_Wh> list) => list.map((w) => w.id).toList();

List<_Wh> _narrow(List<_Wh> list, int? branchId) =>
    narrowWarehousesToClientBranch<_Wh>(
      warehouses: list,
      clientBranchId: branchId,
      branchIdOf: (w) => w.branchId,
    );

void main() {
  const all = [_Wh(1, 10), _Wh(2, 20), _Wh(3, 10), _Wh(4, null)];

  test('يُبقي مخازنَ الفرع وحدَها', () {
    expect(_ids(_narrow(all, 10)), [1, 3]);
  });

  test('بلا فرعٍ للجهاز ⇒ لا حصر', () {
    expect(_ids(_narrow(all, null)), [1, 2, 3, 4]);
  });

  test('فرعٌ بلا مخزنٍ واحد ⇒ القائمةُ كاملةً لا فارغة', () {
    // الحصرُ الصارم هنا يعني نافذةً لا تُحفَظ منها فاتورةٌ إطلاقاً. والقاعدةُ
    // منقولةٌ بحرفها من مسار المبيعات العامل.
    expect(_ids(_narrow(all, 99)), [1, 2, 3, 4]);
  });

  test('مخزنٌ بلا فرعٍ لا يُطابِق فرعاً', () {
    expect(_ids(_narrow(all, 20)), [2]);
  });

  test('قائمةٌ فارغةٌ تبقى فارغة', () {
    expect(_narrow(const [], 10), isEmpty);
  });
}
