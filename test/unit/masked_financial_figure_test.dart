import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/financial_figures_access.dart';
import 'package:ural_erp/presentation/widgets/masked_financial_figure.dart';

void main() {
  test('financial figure stays visible with the required permission', () {
    expect(maskFinancialFigure(true, '12,000'), '12,000');
  });

  test('financial figure export value is masked without permission', () {
    expect(maskFinancialFigure(false, '12,000'), maskedFinancialFigure);
  });
}
