import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/quick_sale_shift_variance.dart';

void main() {
  test('signed governing variance preserves the direction of the largest channel', () {
    final shortfall =
        quickSaleSignedGoverningShiftDiff(cash: -76.89, bank: 0, click: 0);
    final surplus =
        quickSaleSignedGoverningShiftDiff(cash: 0, bank: 76.89, click: 0);
    final bankGoverns =
        quickSaleSignedGoverningShiftDiff(cash: -76.89, bank: 90, click: 0);
    expect(shortfall, -76.89);
    expect(quickSaleShiftDiffTitle(shortfall), 'عجزٌ في الدرج');
    expect(surplus, 76.89);
    expect(quickSaleShiftDiffTitle(surplus), 'فائضٌ في الدرج');
    expect(bankGoverns, 90);
    expect(quickSaleShiftDiffTitle(bankGoverns), 'فائضٌ في الدرج');
  });
}
