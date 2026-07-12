import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';

/// E2E Test: Fiscal Year Close
/// Create Fiscal Year → Close Year → Verify Status
void main() {
  late AppDatabase db;
  late int userId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
      RolesCompanion.insert(name: 'محاسب', isSystemRole: const Value(false)),
    );
    userId = await db.createUser(
      username: 'fiscal_test',
      password: 'test123',
      displayName: 'Fiscal Tester',
      roleId: roleId,
    );
  });

  tearDown(() async => db.close());

  group('Fiscal Year Close E2E', () {
    test('Complete fiscal year lifecycle', () async {
      // 1. Create fiscal year
      final yearId = await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          name: 'السنة المالية 2025',
          startDate: DateTime(2025, 1, 1),
          endDate: DateTime(2025, 12, 31),
        ),
      );

      expect(yearId, isPositive);

      // 2. Verify year was created
      final year = await (db.select(db.fiscalYears)
            ..where((y) => y.id.equals(yearId)))
          .getSingleOrNull();
      expect(year, isNotNull);
      expect(year!.name, 'السنة المالية 2025');

      // 3. Close the fiscal year
      await db.closeFiscalYear(yearId, userId);

      // 4. Verify year was closed
      final closedYear = await (db.select(db.fiscalYears)
            ..where((y) => y.id.equals(yearId)))
          .getSingleOrNull();
      expect(closedYear, isNotNull);
      // closeFiscalYear should mark the year as closed
      expect(closedYear!.isClosed, isTrue);
    });

    test('Multiple fiscal years can coexist', () async {
      // Create two fiscal years
      final year1 = await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          name: 'السنة المالية 2024',
          startDate: DateTime(2024, 1, 1),
          endDate: DateTime(2024, 12, 31),
        ),
      );

      final year2 = await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          name: 'السنة المالية 2025',
          startDate: DateTime(2025, 1, 1),
          endDate: DateTime(2025, 12, 31),
        ),
      );

      expect(year1, isPositive);
      expect(year2, isPositive);
      expect(year1, isNot(year2));

      // Close first year
      await db.closeFiscalYear(year1, userId);

      // Second year should still be open
      final openYear = await (db.select(db.fiscalYears)
            ..where((y) => y.id.equals(year2)))
          .getSingleOrNull();
      expect(openYear!.isClosed, isFalse);
    });
  });
}
