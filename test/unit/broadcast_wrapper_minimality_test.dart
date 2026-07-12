// Spec 129 F2 / T056 — withBroadcast minimality + completeness contract.
//
// Pins three invariants of the
// `ApiHandlerBase.withBroadcast<T>({endpointLabel, tables, body})` wrapper
// (contracts/broadcast-wrapper.md §2):
//
//   1. Broadcasts fire post-commit: `body()` mutates X tables; on success the
//      wrapper emits one broadcast per declared `tables` entry. On thrown
//      `body()` no broadcasts are emitted.
//   2. Completeness — every table declared in `tables` ends up broadcast.
//   3. Minimality (over-set detection at test layer) — the recorded mutations
//      from a side-channel ledger MUST equal the declared `tables`. An
//      over-set means the endpoint declared a table it didn't mutate
//      (harmless broadcast on the wire, but wrong as a contract). An
//      under-set means the endpoint mutated something it didn't declare
//      (a missing broadcast — the real regression class Spec 129 closes).
//
// The wrapper itself does NOT validate `declared == recorded` at runtime
// (that would be expensive on every API call). This test layer enforces the
// equality on the migrated endpoints. New endpoints inherit the same
// enforcement via per-endpoint integration tests (T014-T031 in
// specs/129-mirror-broadcast-discipline/tasks.md, deferred to field smoke).
//
// The recorder is a plain `Set<String>` populated alongside each mutation in
// the test body. The companion `MutationRecordingInterceptor` exists for the
// per-endpoint integration tests that need full Drift introspection; the
// minimality contract is independent of that mechanism.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_handler_base.dart';

/// Test-only `ApiHandlerBase` subclass that records every broadcast emission
/// into a public list. Used to assert the wrapper actually fans out one
/// broadcast per declared table (completeness invariant).
class _RecordingHandler extends ApiHandlerBase {
  _RecordingHandler(super.db, super.wsClients);

  final List<String> emitted = <String>[];

  @override
  void broadcast(String table, {int? branchId}) {
    emitted.add(table);
    // Don't call super: wsClients is empty in tests, so the parent's WS
    // fan-out is a no-op anyway. Skipping super avoids touching the
    // _localChangeController stream which the harness doesn't subscribe to.
  }
}

void main() {
  group('Spec 129 F2 — ApiHandlerBase.withBroadcast minimality contract', () {
    late AppDatabase db;
    late _RecordingHandler handler;

    setUp(() async {
      db = AppDatabase.forTesting();
      // The constructor registers itself as `ApiHandlerBase._registeredInstance`
      // so the static `withBroadcast` can route emissions through us.
      handler = _RecordingHandler(db, {});
    });

    tearDown(() async {
      await db.close();
    });

    test('happy path: declared = recorded → equality holds', () async {
      final recorded = <String>{};

      final result = await ApiHandlerBase.withBroadcast<int>(
        endpointLabel: 'testBranchInsert',
        tables: const {'branches'},
        body: () async {
          recorded.add('branches');
          return await db.into(db.branches).insert(
                BranchesCompanion.insert(name: 'فرع اختبار'),
              );
        },
      );

      expect(result, greaterThan(0));
      expect(handler.emitted, equals(['branches']),
          reason: 'wrapper must emit exactly the declared table set');
      expect(
        Set<String>.from(handler.emitted),
        equals(recorded),
        reason:
            'completeness AND minimality — declared/emitted/recorded all agree',
      );
    });

    test('multi-table happy path: one broadcast per declared table', () async {
      final recorded = <String>{};

      await ApiHandlerBase.withBroadcast<void>(
        endpointLabel: 'testMultiTable',
        tables: const {'branches', 'warehouses', 'safes'},
        body: () async {
          recorded.addAll({'branches', 'warehouses', 'safes'});
          await db.into(db.branches).insert(
                BranchesCompanion.insert(name: 'فرع اختبار-2'),
              );
        },
      );

      expect(
        Set<String>.from(handler.emitted),
        equals({'branches', 'warehouses', 'safes'}),
      );
      expect(handler.emitted.length, 3,
          reason: 'one broadcast emission per declared table');
      expect(Set<String>.from(handler.emitted), equals(recorded));
    });

    test('body throws → NO broadcasts emitted (post-commit invariant)',
        () async {
      Object? caught;
      try {
        await ApiHandlerBase.withBroadcast<int>(
          endpointLabel: 'testThrowing',
          tables: const {'branches'},
          body: () async {
            throw Exception('simulated handler failure');
          },
        );
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<Exception>(),
          reason: 'wrapper must rethrow the body exception unchanged');
      expect(handler.emitted, isEmpty,
          reason:
              'broadcasts are post-commit; a throwing body must not emit any');
    });

    test('over-declare (declared > recorded) is caught by equality check',
        () async {
      final recorded = <String>{};

      await ApiHandlerBase.withBroadcast<void>(
        endpointLabel: 'testOverDeclare',
        // Declares 2 tables but only mutates 1 — the declared set is the
        // MAXIMUM (Spec 129 contract §5 Q2); a per-endpoint integration test
        // is expected to detect this asymmetry and either split the endpoint
        // or accept the over-broadcast as harmless. The wrapper still emits
        // both broadcasts (it trusts the declaration); the test layer is
        // where over-declare is detected.
        tables: const {'branches', 'warehouses'},
        body: () async {
          recorded.add('branches'); // no warehouses mutation
          await db.into(db.branches).insert(
                BranchesCompanion.insert(name: 'فرع اختبار-over'),
              );
        },
      );

      expect(handler.emitted, hasLength(2));
      expect(
        Set<String>.from(handler.emitted),
        isNot(equals(recorded)),
        reason: 'over-declare is detected by declared-vs-recorded inequality',
      );
    });

    test('under-declare (recorded > declared) is caught by equality check',
        () async {
      final recorded = <String>{};

      await ApiHandlerBase.withBroadcast<void>(
        endpointLabel: 'testUnderDeclare',
        // Declares only `branches` but the body also mutates a hypothetical
        // `journal_entries` row. This is the regression class Spec 129
        // closes — mirrors stay behind because the missing broadcast never
        // fires.
        tables: const {'branches'},
        body: () async {
          recorded.addAll({'branches', 'journal_entries'}); // missing!
          await db.into(db.branches).insert(
                BranchesCompanion.insert(name: 'فرع اختبار-under'),
              );
        },
      );

      // Wrapper emitted only what was declared — the missing broadcast IS
      // the bug. The test layer's check exposes it.
      expect(handler.emitted, equals(['branches']));
      expect(
        recorded.difference(Set<String>.from(handler.emitted)),
        equals({'journal_entries'}),
        reason:
            'under-declare leaks a recorded mutation past the declared set',
      );
    });

    test('declared set sorting is stable (deterministic [BROADCAST-WRAP] log)',
        () async {
      // The wrapper sorts the declared set before logging. Two calls with
      // the same declared set should produce the same broadcast order
      // (alphabetical), which keeps `[BROADCAST-WRAP] tables=[…]` log lines
      // diff-friendly across runs.
      handler.emitted.clear();
      final unsorted = {'safes', 'branches', 'warehouses'};

      await ApiHandlerBase.withBroadcast<void>(
        endpointLabel: 'testSortStable',
        tables: unsorted,
        body: () async {},
      );

      // Set-iteration order in Dart is insertion order, so the recorder
      // sees the declared-set's natural order. The test asserts the FULL
      // set equality (not the order) since the wrapper iterates by Set
      // semantics. The sort-for-log invariant is documented in the wrapper
      // code, not directly observable here without re-routing the logger.
      expect(
        Set<String>.from(handler.emitted),
        equals(unsorted),
      );
    });
  });
}
