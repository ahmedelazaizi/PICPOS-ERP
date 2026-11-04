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

  test('depreciation posted to 6213 appears separately without changing profit',
      () async {
    final income = await cycle.income();
    expect((income['totalDepreciation'] as num).toDouble(), closeTo(100, 0.005));
    expect((income['netProfit'] as num).toDouble(), closeTo(-1008.333, 0.02));
  });
}
