import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/offline_sync_worker.dart';

void main() {
  test('stock and zero-cost business rejections are terminal, not duplicates', () {
    expect(isPermanentSalesRejection(
      'Server error (422): {"code":"INSUFFICIENT_STOCK","error":"الكمية المتوفرة حالياً غير كافية"}',
    ), isTrue);
    expect(isPermanentSalesRejection(
      'Server error (422): {"code":"ZERO_COST_BLOCKED","error":"تكلفة صفرية محجوبة"}',
    ), isTrue);
    expect(isPermanentSalesRejection(
      'Server error (422): {"code":"PAYMENT_EXCEEDS_REMAINING","error":"مبلغ التحصيل يتجاوز المتبقي"}',
    ), isTrue);
    expect(isPermanentSalesRejection(
      'Server error (422): {"code":"PAYMENT_NOT_POSITIVE","error":"يجب أن يكون مبلغ التحصيل أكبر من صفر"}',
    ), isTrue);
    expect(isTerminalBusinessConflict(
      'Server error (422): {"code":"INSUFFICIENT_STOCK"}',
    ), isFalse);
    expect(isTerminalBusinessConflict(
      'Server error (422): {"code":"ZERO_COST_BLOCKED"}',
    ), isFalse);
    expect(isPermanentSalesRejection('500 Internal Server Error'), isFalse);
  });

  test('rejected sale is persisted in dead-letter and not retryable', () async {
    final db = AppDatabase.forTesting();
    try {
      const rejection =
          'Server error (422): {"code":"INSUFFICIENT_STOCK",'
          '"error":"الكمية المتوفرة حالياً غير كافية"}';
      final id = await db.into(db.syncOutbox).insert(SyncOutboxCompanion.insert(
        targetTable: 'sales_invoices',
        recordId: 'sale-1',
        operation: 'insert',
        payload: jsonEncode({'invoiceNumber': 'sale-1'}),
        status: const drift.Value('pending'),
      ));

      expect(isPermanentSalesRejection(rejection), isTrue);
      expect(isTerminalBusinessConflict(rejection), isFalse);
      await db.markAsSyncDeadLetter(id, rejection);

      final stored = await (db.select(db.syncOutbox)
            ..where((row) => row.id.equals(id)))
          .getSingle();
      expect(stored.status, 'dead_letter');
      expect(stored.lastError, contains('INSUFFICIENT_STOCK'));
      expect(await db.getPendingSyncItems(limit: 10), isEmpty);
    } finally {
      await db.close();
    }
  });
}
