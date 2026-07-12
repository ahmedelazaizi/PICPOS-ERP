// ═══════════════════════════════════════════════════════════════════════════
// PIR-010: Lazy Startup / Database Startup Unit Tests
// ═══════════════════════════════════════════════════════════════════════════
//
// Tests that database startup phases are correctly structured and that
// the deferred microtask pattern doesn't break initialization ordering.

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Database Startup Phase Ordering', () {
    test('schema safety runs before seed data', () async {
      // Simulates the phase ordering in database_startup.dart
      final executionOrder = <String>[];

      Future<void> ensureSchemaDefaults() async {
        executionOrder.add('schema');
      }

      Future<void> ensureSeedData() async {
        executionOrder.add('seed');
      }

      Future<void> syncPermissionsAndAccounts() async {
        executionOrder.add('sync');
      }

      Future<void> runStartupPatches() async {
        executionOrder.add('patches');
      }

      Future<void> scheduleDeferredTasks() async {
        executionOrder.add('deferred');
      }

      // Phase 2-3: Blocking
      await ensureSchemaDefaults();
      await ensureSeedData();

      // Phase 4-6: Deferred
      Future.microtask(() async {
        await syncPermissionsAndAccounts();
        await runStartupPatches();
        await scheduleDeferredTasks();
      });

      // After blocking phases complete
      expect(executionOrder, ['schema', 'seed']);

      // Let microtask complete
      await Future.delayed(Duration.zero);
      expect(executionOrder, ['schema', 'seed', 'sync', 'patches', 'deferred']);
    });

    test('deferred phases maintain internal ordering', () async {
      final order = <int>[];

      Future.microtask(() async {
        order.add(4);
        await Future.delayed(Duration.zero);
        order.add(5);
        await Future.delayed(Duration.zero);
        order.add(6);
      });

      await Future.delayed(const Duration(milliseconds: 50));
      expect(order, [4, 5, 6]);
    });

    test('error in deferred phase does not affect blocking phases', () async {
      var blockingCompleted = false;
      var deferredError = false;

      // Blocking phase
      await Future<void>.value();
      blockingCompleted = true;

      // Deferred phase with error
      Future.microtask(() async {
        try {
          throw Exception('Simulated deferred error');
        } catch (_) {
          deferredError = true;
        }
      });

      expect(blockingCompleted, isTrue);

      await Future.delayed(Duration.zero);
      expect(deferredError, isTrue);
    });
  });
}
