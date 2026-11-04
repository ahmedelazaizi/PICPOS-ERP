import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/dashboard_picpos/dashboard_profit_margin.dart';

void main() {
  test('non-positive revenue shows undefined net margin', () {
    final display = dashboardProfitMargin(revenue: -83.333, netProfit: -28.333);
    expect(display.value, 0);
    expect(display.valueLabel, '—');
  });

  test('positive revenue displays net profit margin without changing its basis', () {
    final display = dashboardProfitMargin(revenue: 100, netProfit: 25);
    expect(display.value, 0.25);
    expect(display.valueLabel, '25.0%');
  });
}
