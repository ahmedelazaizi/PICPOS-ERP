import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/fiscal_permission_codes.dart';
import '../scenarios/scenario_world.dart';

void main() {
  late ScenarioWorld w;
  setUp(() async => w = await ScenarioWorld.create());
  tearDown(() => w.dispose());

  test('period close and reopen create distinct audit events for acting user', () async {
    await w.grant(FiscalPermissionCodes.fiscalPeriodClose);
    final yearId = await w.db.createFiscalYear(
      name: 'Audit FY', startDate: DateTime(2028), endDate: DateTime(2028, 12, 31));
    await w.db.generatePeriodsForYear(yearId, DateTime(2028), DateTime(2028, 12, 31));
    final period = await (w.db.select(w.db.accountingPeriods)
      ..where((p) => p.fiscalYearId.equals(yearId) & p.month.equals(1))).getSingle();
    await w.db.closeAccountingPeriod(period.id, w.userId);
    await w.db.reopenAccountingPeriod(period.id, w.userId);

    final logs = await (w.db.select(w.db.activityLogs)
      ..where((a) => a.entityType.equals('accounting_period') &
          a.entityId.equals(period.id) & a.userId.equals(w.userId))
      ..orderBy([(a) => OrderingTerm.asc(a.id)])).get();
    expect(logs.map((log) => log.action), ['close', 'reopen']);
    expect(logs.map((log) => log.description), [
      'إقفال الفترة المحاسبية ${period.name}',
      'إعادة فتح الفترة المحاسبية ${period.name}',
    ]);
  });
}
