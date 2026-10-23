import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/websocket_sync_client.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';

/// Spec 136 — a coarse server broadcast alias (e.g. `sales`, `accounting`) must
/// expand to concrete delta-pull table names, otherwise the mirror's
/// `_triggerSync` matched neither `DeltaPullService.pullTables` nor a
/// `syncTable` strategy and the new invoice only appeared at the next 300s poll.
void main() {
  test('sales alias expands to the concrete sales tables (in pullTables)', () {
    final targets = WebSocketSyncClient.pullTargetsFor('sales');
    expect(targets, contains('sales_invoices'));
    expect(targets, contains('sales_invoice_items'));
    // Every expanded target must be a real delta-pull table, else the pull
    // silently no-ops again.
    for (final t in targets) {
      expect(DeltaPullService.pullTables, contains(t),
          reason: '$t must be a concrete pullTables entry');
    }
  });

  test('accounting alias expands to journal_entries', () {
    final targets = WebSocketSyncClient.pullTargetsFor('accounting');
    expect(targets, ['journal_entries']);
    expect(DeltaPullService.pullTables, contains('journal_entries'));
  });

  test('every alias expansion resolves to valid pullTables entries', () {
    for (final alias in ['sales', 'purchases', 'accounting', 'journals',
      'treasury', 'inventory']) {
      for (final t in WebSocketSyncClient.pullTargetsFor(alias)) {
        expect(DeltaPullService.pullTables, contains(t),
            reason: 'alias "$alias" → "$t" must be in pullTables');
      }
    }
  });

  test('a concrete table name passes through unchanged', () {
    expect(WebSocketSyncClient.pullTargetsFor('parties'), ['parties']);
    expect(WebSocketSyncClient.pullTargetsFor('sales_invoices'),
        ['sales_invoices']);
  });
}
