import 'package:flutter_test/flutter_test.dart';

import '../../audit_repro/financial_statements/_fs_world.dart';

void main() {
  late ScenarioWorld world;
  late FsCycle cycle;

  setUpAll(() async {
    world = await ScenarioWorld.create();
    cycle = FsCycle(world);
    await cycle.run();
  });

  tearDownAll(() => world.dispose());

  test('cash flow classifies customer receipts, suppliers, payroll and checks', () async {
    final flow = await world.db.getCashFlowStatement(winFrom, winTo);
    final operating = flow['operating'] as Map;
    final investing = flow['investing'] as Map;
    final financing = flow['financing'] as Map;
    expect((operating['receiptsFromCustomers'] as num).toDouble(), closeTo(140, 0.005));
    expect((operating['paymentsToSuppliers'] as num).toDouble(), closeTo(200, 0.005));
    expect((operating['salaries'] as num).toDouble(), closeTo(1000, 0.005));
    expect((financing['checksCollected'] as num).toDouble(), closeTo(0, 0.005));
    final sectionNet = (operating['net'] as num).toDouble() +
        (investing['net'] as num).toDouble() +
        (financing['net'] as num).toDouble();
    expect(sectionNet, closeTo((flow['netChange'] as num).toDouble(), 0.005));
  });
}
