// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';
import 'package:flutter/foundation.dart';

class PaymentAllocationSyncStrategy extends SyncStrategy {
  PaymentAllocationSyncStrategy(super.db);

  @override
  String get tableName => 'payment_allocations';

  @override
  String get apiEndpoint => '/api/payment-allocations';

  /// R5 — payment allocations are derived from receipt + invoice pairing
  /// on the server. The server can re-allocate or void allocations
  /// (e.g. after a credit memo), so `serverWins` lets those status
  /// changes overwrite the local cached row.
  @override
  ConflictPolicy get conflictPolicy => ConflictPolicy.serverWins;

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final allocations = json['payment_allocations'] as List? ?? [];
    // Collect invoice IDs that receive new allocations so we can recalculate
    // their `paid` column once — after all rows for this batch are inserted.
    final affectedSalesInvoiceIds = <int>{};

    for (final a in allocations) {
      final map = a as Map<String, dynamic>;
      final invoiceType = map['invoiceType'] as String? ?? 'sales';
      final invoiceId = parseInt(map['invoiceId']);

      await db.into(db.paymentAllocations).insertOnConflictUpdate(
        PaymentAllocationsCompanion(
          id: Value(parseInt(map['id'])),
          paymentId: Value(parseInt(map['paymentId'])),
          invoiceType: Value(invoiceType),
          invoiceId: Value(invoiceId),
          allocatedAmount: Value(parseDouble(map['allocatedAmount'])),
        ),
      );

      if (invoiceType == 'sales' && invoiceId > 0) {
        affectedSalesInvoiceIds.add(invoiceId);
      }
    }

    // Recalculate paid amount for every affected sales invoice so that
    // the "remaining" column (= total - paid) reflects the latest receipts
    // without waiting for a manual refresh.
    //
    // ═══ 🔴 v175: قاعدةٌ زائدَ المجموع — لا المجموعُ وحدَه ═══
    //
    // كان السطرُ: `paid = Σ payment_allocations` — **يستبدل ولا يجمع**.
    // وهو نائمٌ ما دام صفرُ كُتّابٍ للجدول، لكنّ `paid` يُكتَب **وقتَ البيع**
    // من الدفعة الحاضرة: فاتورةٌ دُفع منها ٣٠٠ نقداً وبقي ٧٠٠ آجلاً لا
    // تحمل أيَّ تخصيص. فأوّلُ سندِ قبضٍ يخصّص لها ٧٠٠ كان يجعل `paid = ٧٠٠`
    // بدل ١٠٠٠ — تختفي الثلاثُمئة، ويتضخّم رصيدُ العملاء، وتعود الفاتورةُ
    // «جزئيّةً» وهي مسدَّدة. ولا شيءَ يُبلِّغ.
    //
    // فالقاعدةُ صارت عموداً (`sales_invoices.paid_unallocated`) والحسابُ
    // جمعاً — راجع شرحَ العمود في `sales_purchase_tables.dart`.
    for (final invoiceId in affectedSalesInvoiceIds) {
      try {
        final invoice = await db.getSalesInvoiceById(invoiceId);
        if (invoice == null) continue;
        final totalPaid =
            invoice.paidUnallocated + await db.getPaymentAllocationsTotal(invoiceId);
        await db.updateSalesInvoicePaidAmount(invoiceId, totalPaid);
        debugPrint('[Sync] PaymentAllocations: updated paid=$totalPaid '
            '(base=${invoice.paidUnallocated}) for invoice #$invoiceId');
      } catch (e) {
        debugPrint('[Sync] PaymentAllocations: failed to update invoice #$invoiceId: $e');
      }
    }

    if (allocations.isNotEmpty) {
      db.markTablesUpdated({db.paymentAllocations, db.salesInvoices});
      debugPrint('[Sync] PaymentAllocations: ${allocations.length} synced, '
          '${affectedSalesInvoiceIds.length} invoices updated');
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    if (record is PaymentAllocationsCompanion) {
      await db.into(db.paymentAllocations).insertOnConflictUpdate(record);
    }
  }
}