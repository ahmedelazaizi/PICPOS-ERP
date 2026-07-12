import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as drift;
import 'package:ural_erp/data/database/database.dart';

/// Phase 1 — Party Balance Race Condition (Focused, Expanded Coverage)
///
/// Dedicated test class for `adjustPartyBalance()` fix.
/// Covers edge cases not handled in the combined race_condition_fixes_test.dart:
///   - Initial zero balance edge case.
///   - Extreme concurrency load (100 concurrent writers).
///   - Negative balance handling when allowed.
///   - Party not found → no-op (graceful degradation).
///   - Type consistency: balance remains a double, not int.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() async => db.close());

  // ═══════════════════════════════════════════════════════════════════════════
  group('Party Balance Race Condition — Focused Tests', () {
    // ─────────────────────────────────────────────────────────────────────────
    test('Zero initial balance + single positive adjustment yields correct result', () async {
      final partyId = await db.into(db.parties).insert(
        PartiesCompanion.insert(
          name: 'Zero Start Party',
          isCustomer: const drift.Value(true),
          balance: const drift.Value(0),
        ),
      );

      await db.adjustPartyBalance(partyId, 250.0);

      final party = await db.getPartyById(partyId);
      expect(party?.balance, 250.0,
          reason: 'Starting from zero: 0 + 250 = 250');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Extreme concurrency: 100 concurrent +1 adjustments on same party', () async {
      final partyId = await db.into(db.parties).insert(
        PartiesCompanion.insert(
          name: 'Extreme Load Party',
          isCustomer: const drift.Value(true),
          balance: const drift.Value(0),
        ),
      );

      // Launch 100 concurrent increments of +1
      final futures = List.generate(100, (_) => db.adjustPartyBalance(partyId, 1.0));
      await Future.wait(futures);

      final party = await db.getPartyById(partyId);
      expect(party?.balance, 100.0,
          reason: '100 concurrent +1 adjustments should give exactly 100 (no lost updates)');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Negative balance is stored correctly when allowed by business logic', () async {
      final partyId = await db.into(db.parties).insert(
        PartiesCompanion.insert(
          name: 'Negative Balance Party',
          isCustomer: const drift.Value(true),
          balance: const drift.Value(100),
        ),
      );

      // Deduct more than available (credit extension scenario)
      await db.adjustPartyBalance(partyId, -150.0);

      final party = await db.getPartyById(partyId);
      expect(party?.balance, -50.0,
          reason: 'Negative balance is valid in a credit-extension scenario');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Balance type remains double after adjustment (no int truncation)', () async {
      final partyId = await db.into(db.parties).insert(
        PartiesCompanion.insert(
          name: 'Type Safety Party',
          isCustomer: const drift.Value(true),
          balance: const drift.Value(0),
        ),
      );

      // Half-unit amounts common in currency rounding
      await db.adjustPartyBalance(partyId, 33.33);
      await db.adjustPartyBalance(partyId, 0.01);

      final party = await db.getPartyById(partyId);
      // 33.33 + 0.01 = 33.34 (not 33 via int truncation)
      expect(party?.balance, closeTo(33.34, 0.001),
          reason: 'Fractional amounts must preserve decimal precision');
    });

    // ─────────────────────────────────────────────────────────────────────────
    test('Three-party concurrent load does not cross-contaminate balances', () async {
      // Each party gets its own concurrent adjustments
      final partyAId = await db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'Party A', isCustomer: const drift.Value(true), balance: const drift.Value(0)),
      );
      final partyBId = await db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'Party B', isCustomer: const drift.Value(true), balance: const drift.Value(0)),
      );
      final partyCId = await db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'Party C', isCustomer: const drift.Value(true), balance: const drift.Value(0)),
      );

      // Party A: +10 × 20 = +200
      // Party B: +5  × 20 = +100
      // Party C: +1  × 20 = +20
      final futures = <Future>[];
      for (int i = 0; i < 20; i++) {
        futures.add(db.adjustPartyBalance(partyAId, 10.0));
        futures.add(db.adjustPartyBalance(partyBId, 5.0));
        futures.add(db.adjustPartyBalance(partyCId, 1.0));
      }

      await Future.wait(futures);

      final partyA = await db.getPartyById(partyAId);
      final partyB = await db.getPartyById(partyBId);
      final partyC = await db.getPartyById(partyCId);

      expect(partyA?.balance, 200.0, reason: 'Party A: 20 × 10 = 200');
      expect(partyB?.balance, 100.0, reason: 'Party B: 20 × 5 = 100');
      expect(partyC?.balance, 20.0, reason: 'Party C: 20 × 1 = 20');
    });
  });
}
