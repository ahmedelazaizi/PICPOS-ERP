// Spec 066 / SC-001 + SC-005 — Voucher numbering atomicity tests.
//
// QA finding D5-001 (P0): generateInvoiceNumber's counter advance MUST
// roll back atomically with the dependent voucher insert. Egyptian VAT
// regulations require that printed invoice numbers form an unbroken
// sequence per prefix; a gap caused by a rollback that didn't take the
// counter with it triggers a tax-audit finding.
//
// These tests use AppDatabase.forTesting() (in-memory NativeDatabase) and
// exercise:
//  - rollback semantics (counter unchanged when caller throws inside txn)
//  - normal advancement (counter +1 on success)
//  - runtime guard (StateError when called outside any transaction)
//  - concurrent issuance (two parallel txns produce consecutive numbers)
//  - audit query (gap detection without auto-fill)
//
// Companion to test/unit/voucher_numbering_grep_guard_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;

import 'package:picpos_erp/data/database/database.dart';

void main() {
  group('Voucher numbering atomicity (Spec 066 / SC-001)', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting();
    });

    tearDown(() async {
      await db.close();
    });

    test('counter rolls back when caller throws inside outer transaction',
        () async {
      // Prime the counter to a known value by issuing one number.
      final firstNumber = await db.transaction(
        () => db.generateInvoiceNumber('SINV'),
      );
      final counterAfterFirst = await db.peekNumberingCounter('SINV');
      expect(firstNumber, isNotEmpty);
      expect(counterAfterFirst, greaterThan(0));

      // Now issue a second number inside a txn that throws.
      await expectLater(
        () => db.transaction<void>(() async {
          await db.generateInvoiceNumber('SINV');
          throw Exception('simulated insert failure');
        }),
        throwsA(isA<Exception>()),
      );

      // Counter MUST be unchanged from after the first issuance.
      final counterAfterRollback = await db.peekNumberingCounter('SINV');
      expect(
        counterAfterRollback,
        equals(counterAfterFirst),
        reason:
            'D5-001: counter advance must roll back atomically with the '
            'caller\'s transaction. Egyptian VAT prohibits gaps in printed '
            'invoice sequences.',
      );

      // Sanity: a subsequent successful issuance should produce the value
      // the failed attempt would have used.
      final thirdNumber = await db.transaction(
        () => db.generateInvoiceNumber('SINV'),
      );
      final counterAfterThird = await db.peekNumberingCounter('SINV');
      expect(thirdNumber, isNot(equals(firstNumber)));
      expect(counterAfterThird, equals(counterAfterFirst + 1));
    });

    test('counter advances exactly +1 on a successful issuance', () async {
      final before = await db.peekNumberingCounter('PINV');
      await db.transaction(() => db.generateInvoiceNumber('PINV'));
      final after = await db.peekNumberingCounter('PINV');
      // First-time-seed inserts nextValue + 1 (one past the issued number).
      // After at least one issue, advancement is strictly +1.
      expect(after, greaterThan(before));
      // Issue a second one; now advancement is exactly +1.
      await db.transaction(() => db.generateInvoiceNumber('PINV'));
      final afterSecond = await db.peekNumberingCounter('PINV');
      expect(afterSecond, equals(after + 1));
    });

    test('runtime guard throws when called outside any transaction',
        () async {
      expect(
        () => db.generateInvoiceNumber('SINV'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('must be called inside a db.transaction'),
          ),
        ),
        reason:
            'INV-2: generator must refuse to advance the counter when '
            'called from outside a transaction context.',
      );
    });

    test('concurrent successful issuances produce consecutive distinct numbers',
        () async {
      // Prime the counter.
      await db.transaction(() => db.generateInvoiceNumber('POS'));
      final counterBefore = await db.peekNumberingCounter('POS');

      // Kick off two concurrent transactions on the same prefix.
      final futureA = db.transaction(() => db.generateInvoiceNumber('POS'));
      final futureB = db.transaction(() => db.generateInvoiceNumber('POS'));
      final results = await Future.wait([futureA, futureB]);

      expect(results[0], isNot(equals(results[1])),
          reason: 'two concurrent issuances must produce distinct numbers');
      final counterAfter = await db.peekNumberingCounter('POS');
      expect(counterAfter, equals(counterBefore + 2),
          reason: 'counter must advance by exactly 2 after two issuances');
    });
  });

  group('Voucher numbering audit query (Spec 066 / SC-001 / FR-003)', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting();
    });

    tearDown(() async {
      await db.close();
    });

    test('reports synthetic gap without auto-fill', () async {
      // Prime by issuing one SINV number AND inserting an aligned row in
      // sales_invoices so the audit query has a `maxUsedNumber` to compare
      // against. Without an actual row, `maxUsedNumber` would be 0 and the
      // gap-count would conflate "issued but unused" with "skipped".
      final issued = await db.transaction(
        () => db.generateInvoiceNumber('SINV'),
      );
      // Insert a minimal sales_invoices row carrying the issued number.
      await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: issued,
              warehouseId: 1,
              userId: 1,
              invoiceDate: DateTime.now(),
              subtotal: const Value(0.0),
              total: const Value(0.0),
              paid: const Value(0.0),
              status: const Value('completed'),
            ),
          );
      final initialCounter = await db.peekNumberingCounter('SINV');

      // Insert a synthetic gap by directly bumping the counter (this
      // simulates the legacy bug pattern this spec fixes).
      await (db.update(db.documentSequences)
            ..where((s) => s.prefix.equals('SINV')))
          .write(DocumentSequencesCompanion(nextValue: Value(initialCounter + 5)));

      final report = await db.auditNumberingGaps();

      // Find the SINV row.
      final sinvRow = report.firstWhere(
        (r) => r.prefix == 'SINV',
        orElse: () => throw StateError('expected SINV row in audit report'),
      );
      expect(sinvRow.gapCount, equals(5),
          reason: 'audit must report the exact size of the synthetic gap');
      expect(sinvRow.counterNext, equals(initialCounter + 5));
      expect(sinvRow.maxUsedNumber, equals(1),
          reason: 'highest numeric tail in sales_invoices for SINV is 1');
      // No-op verification: query is read-only — call it again, counter
      // must still be unchanged.
      final reportAgain = await db.auditNumberingGaps();
      final counterAfterAudit = await db.peekNumberingCounter('SINV');
      expect(counterAfterAudit, equals(initialCounter + 5));
      expect(reportAgain.length, equals(report.length));
    });

    test('returns empty list when no prefix has gaps', () async {
      // No issuances yet → no documentSequences rows → empty result.
      final report = await db.auditNumberingGaps();
      expect(report, isEmpty);
    });
  });
}
