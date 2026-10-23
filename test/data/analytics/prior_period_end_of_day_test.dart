// priorPeriod with the screen's real inputs: `from` = start of day and
// `to` = END of day (DateRangeFilter.normalizeStart/End). Date-only `to`
// values hid a bug where the prior period ended at 00:00 of its last day.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/providers/financial_analytics_provider.dart';

import 'analytics_harness.dart';

void main() {
  group('priorPeriod', () {
    test('ends at the END of the day before from; same calendar-day count',
        () {
      final p = priorPeriod(
          DateTime(2026, 2, 1), DateTime(2026, 2, 28, 23, 59, 59, 999));
      expect(p.from, DateTime(2026, 1, 4));
      expect(p.to, DateTime(2026, 1, 31, 23, 59, 59, 999));
    });

    test('single day and month/year boundaries use calendar dates', () {
      final one = priorPeriod(
          DateTime(2026, 1, 1), DateTime(2026, 1, 1, 23, 59, 59, 999));
      expect(one.from, DateTime(2025, 12, 31));
      expect(one.to, DateTime(2025, 12, 31, 23, 59, 59, 999));
      // Spans the spring DST switch in many zones: still whole calendar days.
      final dst = priorPeriod(
          DateTime(2026, 3, 30), DateTime(2026, 3, 31, 23, 59, 59, 999));
      expect(dst.from, DateTime(2026, 3, 28));
      expect(dst.to, DateTime(2026, 3, 29, 23, 59, 59, 999));
    });
  });

  group('computeFinancialAnalytics with an end-of-day to', () {
    late AppDatabase db;
    late Ledger gl;
    setUp(() {
      db = AppDatabase.forTesting();
      gl = Ledger(db);
    });
    tearDown(() => db.close());

    test('last prior day revenue is in; prior budget and actuals agree',
        () async {
      final fy = await gl.addFiscalYear(
          'FY2026', DateTime(2026, 1, 1), DateTime(2026, 12, 31));
      await gl.addBudget(fy, '4121', {1: 3100});
      // Prior period of 1..28 Feb is 4..31 Jan.
      await gl.post(DateTime(2026, 1, 3, 12), [('1111', 50, 0), ('4121', 0, 50)]); // before
      await gl.post(DateTime(2026, 1, 4, 0, 0, 0), [('1111', 100, 0), ('4121', 0, 100)]); // first day
      await gl.post(DateTime(2026, 1, 31, 15), [('1111', 400, 0), ('4121', 0, 400)]); // last day

      final r = await computeFinancialAnalytics(
        db,
        (from: DateTime(2026, 2, 1), to: DateTime(2026, 2, 28, 23, 59, 59, 999)),
      );
      expect(r.prior.revenue, closeTo(500, 1e-6));
      // 28 of January's 31 days, last day counted fully like the actuals.
      expect(r.priorBudget.revenue, closeTo(3100 * 28 / 31, 1e-6));
    });
  });
}
