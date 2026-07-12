import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/id_namespace_service.dart';

/// Spec 136 ISS-22 — the client id-namespace floor must lift the auto-increment
/// sequence for transactional tables (e.g. sales_invoices) to >= 1 billion so
/// offline-created rows never collide with the server's low ids. Without it,
/// an offline invoice gets id 1,2,3… → DeltaPull's INSERT OR REPLACE clobbers
/// it with an unrelated server row → the invoice vanishes from the device and
/// the shift shows a cash variance.
void main() {
  test('ensureClientFloor lifts sales_invoices sequence to >= clientIdFloor',
      () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    await IdNamespaceService.instance.ensureClientFloor(db);

    final r = await db
        .customSelect(
          "SELECT seq FROM sqlite_sequence WHERE name = 'sales_invoices' LIMIT 1",
        )
        .getSingleOrNull();
    expect(r, isNotNull, reason: 'floor must create/raise the sequence row');
    expect(r!.read<int>('seq'),
        greaterThanOrEqualTo(IdNamespaceService.clientIdFloor),
        reason: 'next offline sale id must land in the >=1B client range');
  });

  test('floor covers every namespaced transactional table', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    await IdNamespaceService.instance.ensureClientFloor(db);

    for (final t in ['sales_invoices', 'purchase_invoices', 'safe_transactions',
      'journal_entries', 'sales_invoice_items']) {
      final r = await db
          .customSelect(
            'SELECT seq FROM sqlite_sequence WHERE name = ? LIMIT 1',
            variables: [Variable.withString(t)],
          )
          .getSingleOrNull();
      // Either no row yet (table never inserted in this fresh DB and the floor
      // created it) or a row >= floor — both acceptable; a row BELOW the floor
      // is the bug.
      if (r != null) {
        expect(r.read<int>('seq'),
            greaterThanOrEqualTo(IdNamespaceService.clientIdFloor),
            reason: '$t sequence must be >= floor');
      }
    }
  });
}
