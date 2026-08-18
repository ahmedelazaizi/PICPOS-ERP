import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../../domain/entities/invoice_entity.dart';
import '../../domain/entities/cart_item_entity.dart';
import '../../domain/repositories/sales_repository.dart';
import '../../services/generators/base_generator.dart' show InvoiceItem;
import '../../services/accounting_service.dart';
import '../../services/kitchen_service.dart';
import '../../services/network_service.dart';
import '../database/sync_interceptor.dart';
import '../../services/client_write_interceptor.dart';
import '../../core/utils/uuid_v7.dart';
import '../../core/utils/journal_entry_gid.dart';
import '../../core/logging/diagnostic_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database.dart';
import '../../services/invoice_integrity_service.dart';
import 'sales_transaction_orchestrator.dart';

/// Sales repository implementation
///
/// Implements [SalesRepository] with Drift-based persistence,
/// accounting integration, kitchen service, and client/server sync.
///
/// Complex sale-creation logic lives in [SalesTransactionOrchestrator]
/// (ISS-ARCH-02 extraction).
class SalesRepositoryImpl extends DatabaseAccessor<AppDatabase>
    implements SalesRepository {
  final AccountingService _accountingService;
  late final SalesTransactionOrchestrator _orchestrator;

  SalesRepositoryImpl(
    super.db,
    this._accountingService,
  ) {
    _orchestrator = SalesTransactionOrchestrator(db, _accountingService);
  }

  void _appendDiag(String msg) {
    try {
      final diagFile = File('sync_diagnostic.txt');
      final ts = DateTime.now().toIso8601String();
      diagFile.writeAsStringSync('[$ts] $msg\n', mode: FileMode.append);
    } catch (_) {}
  }

  /// Resolve the warehouse IDs for the current client's branch.
  /// Used for branch-level data isolation: clients only see their own branch data.
  /// Branch 1 (الإدارة) = full access (mirror of server) → returns empty = no filter.
  Future<List<int>> _getClientWarehouseIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final branchId = prefs.getInt('client_branch_id');
      // No branch set OR admin branch (ID 1) = full access (same as server)
      if (branchId == null || branchId <= 1) return [];
      final warehouses = await (db.select(db.warehouses)
        ..where((w) => w.branchId.equals(branchId))).get();
      return warehouses.map((w) => w.id).toList();
    } catch (e) {
      debugPrint('[SalesRepo] Error resolving client warehouse IDs: $e');
      return [];
    }
  }

  @override
  Future<int> createSalesInvoice({
    required int? customerId,
    required int warehouseId,
    required int userId,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,
    required String paymentMethod,
    required List<CartItemEntity> items,
    double? cashAmount,
    double? bankAmount,
    double? clickAmount,
    int? cashSafeId,
    int? bankSafeId,
    int? clickSafeId,
    double deliveryFee = 0,
    int? deliveryCompanyId,
    int? courierId,
    String? deliveryStatus,
    String? notes,
    String? saleType,
    int? costCenterId,
    String? platformOrderNumber,
    String? adhocCustomerName,
    String? adhocCustomerPhone,
    String? adhocCustomerNote,
  }) =>
      _orchestrator.createSalesInvoice(
        customerId: customerId,
        warehouseId: warehouseId,
        userId: userId,
        subtotal: subtotal,
        discount: discount,
        tax: tax,
        total: total,
        paid: paid,
        paymentMethod: paymentMethod,
        items: items,
        cashAmount: cashAmount,
        bankAmount: bankAmount,
        clickAmount: clickAmount,
        cashSafeId: cashSafeId,
        bankSafeId: bankSafeId,
        clickSafeId: clickSafeId,
        deliveryFee: deliveryFee,
        deliveryCompanyId: deliveryCompanyId,
        courierId: courierId,
        deliveryStatus: deliveryStatus,
        notes: notes,
        saleType: saleType,
        costCenterId: costCenterId,
        platformOrderNumber: platformOrderNumber,
        adhocCustomerName: adhocCustomerName,
        adhocCustomerPhone: adhocCustomerPhone,
        adhocCustomerNote: adhocCustomerNote,
      );

  @override
  Future<SaleResult> completeSalesTransaction(SaleRequest request) =>
      _orchestrator.completeSalesTransaction(request);

  @override
  Future<InvoiceEntity?> getInvoiceById(int id) async {
    final data = await db.getSalesInvoiceById(id);
    if (data == null) return null;
    // Map to domain entity - this logic might be in a separate mapper
    return null; // TODO: Implement mapping
  }

  @override
  Future<InvoiceEntity?> getInvoiceByNumber(String invoiceNumber) async {
    final data = await (db.select(db.salesInvoices)..where((s) => s.invoiceNumber.equals(invoiceNumber))).getSingleOrNull();
    if (data == null) return null;
    return null; // TODO: Implement mapping
  }

  @override
  Stream<List<InvoiceEntity>> watchInvoices() {
    if (!SyncInterceptor.isClientMode) {
      // Server/Standalone: show ALL invoices
      return db.watchSalesInvoices().map(
        (list) {
          debugPrint('[SalesRepo] Server: ${list.length} invoices loaded');
          return list.map((d) => InvoiceEntity.fromSalesInvoice(d)).toList();
        },
      );
    }
    // Client: filter by branch warehouse IDs
    return Stream.fromFuture(_getClientWarehouseIds()).asyncExpand((whIds) {
      debugPrint('[SalesRepo] Client scope warehouseIds: $whIds');
      return db.watchSalesInvoices(warehouseIds: whIds.isNotEmpty ? whIds : null).map(
        (list) => list.map((d) => InvoiceEntity.fromSalesInvoice(d)).toList(),
      );
    });
  }

  @override
  Future<List<InvoiceEntity>> getInvoicesPaged({int limit = 500, int offset = 0}) async {
    if (!SyncInterceptor.isClientMode) {
      // Server/Standalone: show ALL invoices
      final list = await db.getSalesInvoicesPaged(limit: limit, offset: offset);
      debugPrint('[SalesRepo] getInvoicesPaged: ${list.length} invoices');
      return list.map((d) => InvoiceEntity.fromSalesInvoice(d)).toList();
    }
    // Client: filter by branch warehouse IDs
    final whIds = await _getClientWarehouseIds();
    final list = await db.getSalesInvoicesPaged(
      warehouseIds: whIds.isNotEmpty ? whIds : null,
      limit: limit,
      offset: offset,
    );
    return list.map((d) => InvoiceEntity.fromSalesInvoice(d)).toList();
  }

  @override
  Future<List<InvoiceEntity>> getRawInvoices({int limit = 500}) async {
    // Day 6B: Raw local-store fallback, no server/client routing.
    // Keeps Drift Companion types out of the presentation layer.
    //
    // Phase 5C.8 (Issue 4) — defence-in-depth. Even though the
    // sales_invoices_controller now drops cross-branch rows after the
    // fetch (5C.1), this raw fallback should also respect the client's
    // paired branch directly so a path that ever reads the result
    // without going through the controller still gets a scoped list.
    // Server / standalone mode is unaffected.
    final query = db.select(db.salesInvoices)
      ..where((i) => i.isDeleted.equals(false))
      ..orderBy([(i) => OrderingTerm.desc(i.createdAt)])
      ..limit(limit);
    if (SyncInterceptor.isClientMode) {
      final whIds = await _getClientWarehouseIds();
      if (whIds.isNotEmpty) {
        query.where((i) => i.warehouseId.isIn(whIds) | i.warehouseId.isNull());
      }
    }
    final raw = await query.get();
    return raw.map((d) => InvoiceEntity.fromSalesInvoice(d)).toList();
  }

  @override
  Future<DiagnosticSample> getDiagnosticSample({int limit = 20}) async {
    final allRows = await (db.select(db.salesInvoices)..limit(limit)).get();
    final undeleted = await (db.select(db.salesInvoices)
          ..where((i) => i.isDeleted.equals(false))
          ..limit(limit))
        .get();
    final sampleText = allRows
        .map((s) =>
            '${s.invoiceNumber}:saleType=${s.saleType},status=${s.status},'
            'deleted=${s.isDeleted},warehouseId=${s.warehouseId}')
        .join(' | ');
    return DiagnosticSample(
      totalCount: allRows.length,
      undeletedSample: undeleted.map((d) => InvoiceEntity.fromSalesInvoice(d)).toList(),
      sampleText: sampleText,
    );
  }

  @override
  Stream<List<SalesInvoiceData>> watchTodaySales() {
    if (SyncInterceptor.isClientMode) {
      return Stream.fromFuture(_getClientWarehouseIds()).asyncExpand((whIds) {
        return db.watchTodaySales(warehouseIds: whIds.isNotEmpty ? whIds : null);
      });
    }
    return db.watchTodaySales();
  }

  @override
  Stream<List<SalesInvoiceData>> watchTodaySalesForUser(int userId) {
    // Branch scoping added for parity with watchTodaySales/watchSalesSince —
    // this stream is the cashier's fallback when no shift is open, and it was
    // the only one of the four that showed rows from every branch.
    if (SyncInterceptor.isClientMode) {
      return Stream.fromFuture(_getClientWarehouseIds()).asyncExpand((whIds) {
        return db.watchTodaySalesForUser(
          userId,
          warehouseIds: whIds.isNotEmpty ? whIds : null,
        );
      });
    }
    return db.watchTodaySalesForUser(userId);
  }

  @override
  Stream<SalesInvoiceData?> watchLastInvoiceForUser(
    int userId, {
    DateTime? since,
  }) {
    if (SyncInterceptor.isClientMode) {
      return Stream.fromFuture(_getClientWarehouseIds()).asyncExpand((whIds) {
        return db.watchLastInvoiceForUser(
          userId,
          since: since,
          warehouseIds: whIds.isNotEmpty ? whIds : null,
        );
      });
    }
    return db.watchLastInvoiceForUser(userId, since: since);
  }

  @override
  Stream<List<SalesInvoiceData>> watchSalesSince(DateTime from, {int? userId}) {
    if (SyncInterceptor.isClientMode) {
      return Stream.fromFuture(_getClientWarehouseIds()).asyncExpand((whIds) {
        return db.watchSalesSince(
          from,
          userId: userId,
          warehouseIds: whIds.isNotEmpty ? whIds : null,
        );
      });
    }
    return db.watchSalesSince(from, userId: userId);
  }

  @override
  Stream<List<InvoiceEntity>> watchPaginatedInvoices({
    int limit = 50,
    int offset = 0,
    DateTime? fromDate,
    DateTime? toDate,
    String? status,
  }) {
    // H-9 FIX: Apply branch scope filter in client mode
    if (SyncInterceptor.isClientMode) {
      return Stream.fromFuture(_getClientWarehouseIds()).asyncExpand((whIds) {
        return _buildPaginatedQuery(limit: limit, offset: offset, fromDate: fromDate, toDate: toDate, warehouseIds: whIds.isNotEmpty ? whIds : null);
      });
    }
    return _buildPaginatedQuery(limit: limit, offset: offset, fromDate: fromDate, toDate: toDate);
  }

  Stream<List<InvoiceEntity>> _buildPaginatedQuery({
    int limit = 50,
    int offset = 0,
    DateTime? fromDate,
    DateTime? toDate,
    List<int>? warehouseIds,
  }) {
    var query = db.select(db.salesInvoices)
      ..orderBy([(s) => OrderingTerm.desc(s.createdAt)])
      ..limit(limit, offset: offset);

    if (fromDate != null) {
      query = query..where((s) => s.invoiceDate.isBiggerOrEqualValue(fromDate));
    }
    if (toDate != null) {
      final endOfDay = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);
      query = query..where((s) => s.invoiceDate.isSmallerOrEqualValue(endOfDay));
    }
    if (warehouseIds != null) {
      query = query..where((s) => s.warehouseId.isIn(warehouseIds));
    }

    return query.watch().map(
      (list) => list.map((d) => InvoiceEntity.fromSalesInvoice(d)).toList(),
    );
  }

  @override
  Stream<List<InvoiceEntity>> watchInvoicesByDateRange(
    DateTime start,
    DateTime end,
  ) {
    // H-9 FIX: Apply branch scope filter in client mode
    if (SyncInterceptor.isClientMode) {
      return Stream.fromFuture(_getClientWarehouseIds()).asyncExpand((whIds) {
        var q = db.select(db.salesInvoices)
          ..where((i) => i.invoiceDate.isBetween(Variable(start), Variable(end)));
        if (whIds.isNotEmpty) {
          q = q..where((i) => i.warehouseId.isIn(whIds));
        }
        return q.watch().map(
          (list) => list.map((d) => InvoiceEntity.fromSalesInvoice(d)).toList(),
        );
      });
    }
    return (db.select(db.salesInvoices)
          ..where(
            (i) => i.invoiceDate.isBetween(Variable(start), Variable(end)),
          ))
        .watch()
        .map(
          (list) => list.map((d) => InvoiceEntity.fromSalesInvoice(d)).toList(),
        );
  }

  /// C-05 (Spec 151) / R4, R9 — customer collection against a sales invoice.
  /// TWIN of PurchasesRepositoryImpl.recordPayment (C-03), gated exactly like
  /// [voidInvoice] below.
  ///
  /// ⚠️ CRUX: sales [amount] is the ABSOLUTE new paid total (NOT a delta, unlike
  /// the purchase side). The money to move THIS event is `delta = amount -
  /// invoice.paid`, so we compute the delta here and feed the DELTA to the
  /// server submit / DAO. A non-positive delta (a correction that lowers paid)
  /// has no money to post — it stays a light paid marker.
  ///
  /// Root cause fixed here: the pre-fix code called
  /// `db.updateSalesInvoicePaidAmount` UNCONDITIONALLY and wrote ONLY
  /// paid+status — no receipt voucher, no treasury move, no GL, no party
  /// balance, and no client gate. A credit-sale collection therefore never hit
  /// the safe/AR/GL, and in client/mirror mode never reached HQ (permanent
  /// divergence on the next DeltaPull).
  @override
  Future<void> recordPayment(int invoiceId, double amount, {int? userId}) async {
    final isClientMode = SyncInterceptor.isClientMode;

    final invoice = await db.getSalesInvoiceById(invoiceId);
    if (invoice == null) throw Exception('Invoice not found');

    // CRUX 1 — recordPayment carries the ABSOLUTE newPaid; the collected amount
    // is the delta over the current paid. Guard non-positive: a correction that
    // lowers paid (or a no-op re-save) has no cash to receive → light marker only.
    final delta = amount - invoice.paid;
    if (delta <= 0) {
      await db.updateSalesInvoicePaidAmount(invoiceId, amount);
      return;
    }

    // R9 — a collection is ADDITIVE (unlike a void's idempotent terminal state),
    // so mint a FRESH per-event globalId (NOT derived from the invoice, which
    // would collapse multiple legitimate collections into one). The server and
    // the local DAO both dedup on it, so a retry/replay applies it once.
    final paymentGlobalId = UuidV7.generate();

    if (isClientMode) {
      // Server is SSoT for money + GL + treasury. Fire-and-queue the collection;
      // keep only a light local paid marker (no cash/JE/AR side-effects). The
      // authoritative paid/JE/safe/AR come back on the next DeltaPull.
      // Mirror: awaited — the local paid marker below must not credit a
      // collection HQ never recorded, or the customer's balance diverges.
      await ClientWriteInterceptor.dispatchWrite(
        () => ClientWriteInterceptor.submitSalesPayment(
          salesId: invoice.id,
          salesGlobalId: invoice.globalId,
          invoiceNumber: invoice.invoiceNumber,
          amount: delta,
          globalId: paymentGlobalId,
          userId: userId,
        ).then((accepted) {
          debugPrint('[SALES-PAYMENT-SYNC] accepted=$accepted '
              'invoice=${invoice.invoiceNumber}');
          return accepted;
        }),
        tag: 'SALES-PAYMENT-SYNC',
      );
      await db.updateSalesInvoicePaidAmount(invoiceId, amount);
    } else {
      // Standalone / server: this machine IS the source of truth — full apply
      // (paid + receipt Dr Safe / Cr Customer + balanced JE), idempotent on
      // paymentGlobalId.
      await db.addSalesPayment(
        invoiceId: invoiceId,
        amount: delta,
        userId: userId,
        globalId: paymentGlobalId,
      );
    }
  }

  @override
  Future<void> cancelInvoice(int invoiceId, {int? userId}) async {
    // Redirect to atomic voiding in DAO. voidInvoice below is client-gated
    // (R4/R9), so cancel is covered by the same gate — no direct DAO reach.
    await voidInvoice(invoiceId,
        reason: 'Cancel (Legacy Redirect)', userId: userId);
  }

  /// C-02 (Spec 151) / R4, R9 — gate the void on `SyncInterceptor.isClientMode`
  /// and thread a caller-minted globalId end-to-end, mirroring
  /// [PurchasesRepositoryImpl] `_voidOrDeleteInvoice` (batch B6) exactly.
  ///
  /// Root cause fixed here: the pre-fix code called `db.voidSalesInvoice`
  /// UNCONDITIONALLY, so in client/mirror mode it ran the FULL local
  /// stock/treasury/GL reversal, never told the server, and left the server's
  /// copy of the invoice live. The next DeltaPull then re-asserted the still-
  /// active invoice from HQ, orphaning the local reversal — permanent
  /// divergence between mirror/client and the server.
  ///
  /// Committee-BLOCKED interim (Option A): routing the client void through
  /// `ClientWriteInterceptor.deleteSalesInvoice(invoiceId)` shipped the LOCAL
  /// autoincrement id, and the server's `DELETE /api/sales/<id>` resolves by raw
  /// `int.parse(id)` with NO globalId. Client-created sales have local id ≠
  /// server id, so a strict client voiding its own sale either no-ops on the
  /// server (void lost) or voids a DIFFERENT innocent invoice at HQ.
  ///
  /// Fix (R9): the CALLER mints ONE deterministic void globalId and threads the
  /// SAME value into (1) the server submit `submitVoidSalesInvoice` — the server
  /// resolves globalId → invoiceNumber → id and performs the authoritative
  /// reversal — and (2) the standalone local reversal `db.voidSalesInvoice`.
  /// Client/mirror writes only a LIGHT status marker; the server's row
  /// overwrites it on the next DeltaPull.
  @override
  Future<void> voidInvoice(int invoiceId, {String? reason, int? userId}) async {
    final isClientMode = SyncInterceptor.isClientMode;

    // Load the invoice once — need its globalId/invoiceNumber to thread to the
    // server and to derive the reversal JE's deterministic globalId (R9).
    final invoice = await db.getSalesInvoiceById(invoiceId);
    if (invoice == null) {
      // voidSalesInvoice itself no-ops (or throws "already voided") on a
      // missing/soft-deleted invoice — only standalone needs to call it
      // (client mode has nothing to identify to the server).
      if (!isClientMode) {
        await db.voidSalesInvoice(invoiceId, reason: reason, deletedBy: userId);
      }
      return;
    }

    // Mirror voidSalesInvoice's own "already voided" guard — avoids a redundant
    // server round-trip (or wasted local write) for a double-tap.
    if (invoice.status == 'voided') {
      throw Exception('الفاتورة ملغية بالفعل');
    }

    // R9 — mint ONE deterministic globalId for this void's reversal JE, and
    // thread the SAME value into the server submit (client/mirror) or the local
    // DAO call (standalone). Deriving it from the invoice's own globalId means a
    // retried void (outbox replay) always reproduces the same JE identity,
    // converging under journal_entries.globalId's UNIQUE index instead of
    // duplicating — same pattern the purchase void uses.
    final voidGlobalId =
        (invoice.globalId != null && invoice.globalId!.isNotEmpty)
            ? JournalEntryGid.compute(
                sourceType: JournalEntryGid.sourceSale,
                sourceGid: invoice.globalId!,
                verb: 'void',
              )
            : UuidV7.generate();

    // ── Client/Mirror Mode: submit to server, server is SSoT (R4/R9) ──
    if (isClientMode) {
      unawaited(DiagnosticLogger.log('SALES-VOID',
          'enter client-mode path invoiceId=${invoice.id} '
          'invoiceNumber=${invoice.invoiceNumber} '
          'globalId=${invoice.globalId} voidGlobalId=$voidGlobalId'));

      // 1) Submit to server (server performs the authoritative
      // stock/treasury/JE reversal).
      //   • Client — fire-and-forget; the outbox retries.
      //   • Mirror — awaited; on failure the status marker below never runs, so
      //     the invoice keeps showing as live rather than "voided" on a device
      //     where HQ still has it outstanding.
      await ClientWriteInterceptor.dispatchWrite(
        () => ClientWriteInterceptor.submitVoidSalesInvoice(
          salesId: invoice.id,
          salesGlobalId: invoice.globalId,
          invoiceNumber: invoice.invoiceNumber,
          reason: reason,
          globalId: voidGlobalId,
          // R9/062: thread the acting user so the server's voidPaidInvoice
          // critical-op gate resolves a real userId (null → PermissionDenied →
          // silent void loss for fully-paid invoices).
          userId: userId,
        ).then((accepted) {
          debugPrint('[SALES-VOID-SYNC] Server response: accepted=$accepted');
          unawaited(DiagnosticLogger.log('SALES-VOID',
              accepted
                  ? '✓ accepted invoice=${invoice.invoiceNumber}'
                  : '⏳ queued offline invoice=${invoice.invoiceNumber} '
                      '(server unreachable, will retry from sync_outbox)'));
          return accepted;
        }),
        tag: 'SALES-VOID-SYNC',
      );

      // 2) LIGHT local marker ONLY — MUST NOT run the full stock/treasury/GL
      // reversal (that is now the server's job). Flips the user-visible status
      // so the invoice drops out of the active list immediately; the server's
      // authoritative row overwrites this on the next DeltaPull.
      try {
        await db.updateSalesInvoiceStatus(invoice.id, 'voided');
        unawaited(DiagnosticLogger.log('SALES-VOID',
            '✓ local status marker set invoice=${invoice.invoiceNumber}'));
      } catch (e) {
        debugPrint('[SALES-VOID] local status marker failed for '
            'invoice=${invoice.id}: $e');
        unawaited(DiagnosticLogger.log('SALES-VOID',
            '⚠ local status marker failed invoice=${invoice.invoiceNumber}: $e'));
      }
      return;
    }

    // ── Standalone/Server: full local processing (correct — no server) ──
    await db.voidSalesInvoice(invoiceId,
        reason: reason, deletedBy: userId, globalId: voidGlobalId);
  }

  @override
  Future<SalesPrintData?> getSalesPrintData(int invoiceId) async {
    final invoice = await (db.select(db.salesInvoices)..where((s) => s.id.equals(invoiceId))).getSingleOrNull();
    if (invoice == null) return null;

    // PIR P0-02: Integrity verification before printing — only on locked invoices
    if (invoice.isLocked && invoice.integrityHash != null) {
      try {
        final isValid = InvoiceIntegrityService.verifySalesInvoiceHash(
          storedHash: invoice.integrityHash!,
          invoiceNumber: invoice.invoiceNumber,
          invoiceDate: invoice.invoiceDate,
          total: invoice.total,
          subtotal: invoice.subtotal,
          discount: invoice.discount,
          tax: invoice.tax,
          paid: invoice.paid,
          customerId: invoice.customerId,
          userId: invoice.userId,
          paymentMethod: invoice.paymentMethod,
        );

        if (!isValid) {
          debugPrint(
            '[INTEGRITY] WARNING: Sales invoice #${invoice.invoiceNumber} '
            '(id=$invoiceId) hash mismatch detected during print — possible tampering!',
          );
          // Log to field_audit_logs for auditor visibility
          await db.logFieldChange(
            entityType: 'sales_invoice',
            entityId: invoiceId,
            fieldName: 'INTEGRITY_VIOLATION',
            fieldKey: 'integrity_hash',
            oldValue: invoice.integrityHash,
            newValue: 'MISMATCH_DETECTED_ON_PRINT',
            changedBy: 0,
            changedByName: 'SYSTEM',
            changeReason: 'Integrity hash mismatch detected during print — possible data tampering',
            transactionId: 'integrity-print-${DateTime.now().millisecondsSinceEpoch}',
          );
        }
      } catch (e) {
        debugPrint('[INTEGRITY] Verification error for invoice $invoiceId during print: $e');
      }
    }

    final items = await db.getSalesInvoiceItems(invoiceId);
    final receiptSettings = await db.getReceiptSettings();
    
    String? customerName;
    String? customerPhone;
    String? customerAddress;
    if (invoice.customerId != null) {
      final customer = await db.getPartyById(invoice.customerId!);
      customerName = customer?.name;
      customerPhone = customer?.phone;
      customerAddress = customer?.address;
    }

    String? courierName;
    if (invoice.courierId != null) {
      final courier = await db.getUserByIdRaw(invoice.courierId!);
      courierName = courier?.displayName;
    }

    final printableItems = <InvoiceItem>[];
    for(final item in items) {
       final product = await db.getProductById(item.productId);
       printableItems.add(InvoiceItem(
         name: product?.name ?? 'منتج #${item.productId}',
         quantity: item.quantity,
         price: item.unitPrice,
         total: item.total,
         note: item.note,
       ));
    }

      // ISS-FIN-05: adhoc customer data now stored in dedicated columns.
      // Fallback: legacy rows may still have data embedded in notes — parse if new columns are empty.
      String? adhocName = invoice.adhocCustomerName;
      String? adhocPhone = invoice.adhocCustomerPhone;
      String? cleanNotes = invoice.notes;
      if ((adhocName == null || adhocName.isEmpty) && invoice.notes != null && invoice.notes!.isNotEmpty) {
        final parts = invoice.notes!.split(' | ');
        final remainingParts = <String>[];
        for (final part in parts) {
          if (part.startsWith('العميل: ') && adhocName == null) {
            adhocName = part.substring(7).trim();
          } else if (part.startsWith('هاتف: ') && adhocPhone == null) {
            adhocPhone = part.substring(5).trim();
          } else if (part.trim().isNotEmpty) {
            remainingParts.add(part.trim());
          }
        }
        cleanNotes = remainingParts.isNotEmpty ? remainingParts.join(' | ') : null;
      }

      return SalesPrintData(
        invoiceNumber: invoice.invoiceNumber,
        date: invoice.invoiceDate,
        customerName: customerName,
        customerPhone: customerPhone,
        customerAddress: customerAddress,
        items: printableItems,
        subtotal: invoice.subtotal,
        discount: invoice.discount,
        tax: invoice.tax,
        deliveryFee: invoice.deliveryFee,
        total: invoice.total,
        paid: invoice.paid,
        paymentMethod: invoice.paymentMethod,
        orderNumber: invoice.orderNumber,
        courierName: courierName,
        isDelivery: invoice.deliveryStatus != null
            || const ['delivery', 'talabat', 'careem', 'ashyae'].contains(invoice.saleType),
        salesTypeText: switch (invoice.saleType) {
              'return' => 'مرتجع',
              'delivery' => 'توصيل',
              'talabat' => 'طلبات',
              'careem' => 'كريم',
              'ashyae' => 'أشيائي',
              'internal' => 'محلي',
              'takeaway' => 'سفري',
              'dine_in' => 'صالة',
              _ => 'مبيعات',
            },
        saleType: invoice.saleType,
        receiptSettings: receiptSettings,
        notes: cleanNotes,
        adhocCustomerName: adhocName,
        adhocCustomerPhone: adhocPhone,
        platformOrderNumber: invoice.platformOrderNumber,
      );
    }

  @override
  Future<List<SalesInvoiceItem>> getSalesInvoiceItems(int invoiceId) {
    return db.getSalesInvoiceItems(invoiceId);
  }

  @override
  Future<SalesInvoiceData?> getRawInvoiceById(int id) {
    return db.getSalesInvoiceById(id);
  }

  @override
  Future<String> generateInvoiceNumber(String prefix) {
    // 066 (D5-001): wrap the delegation in a transaction so callers from
    // the presentation layer (e.g. sales_invoices_notifier.dart:321-322)
    // get rollback-safe counter advancement without violating Constitution
    // §IV (presentation never opens a Drift txn directly). The downstream
    // db.generateInvoiceNumber's inner transaction() becomes a SAVEPOINT.
    return db.transaction(() => db.generateInvoiceNumber(prefix));
  }

  @override
  Future<void> updateInvoiceStatus(int invoiceId, String status) async {
    await db.updateSalesInvoiceStatus(invoiceId, status);
  }

  @override
  Future<void> updateSaleType(int invoiceId, String saleType) async {
    await (db.update(db.salesInvoices)..where((i) => i.id.equals(invoiceId)))
        .write(SalesInvoicesCompanion(saleType: Value(saleType)));
  }

  @override
  Future<List<SalesInvoiceData>> getInvoicesSince(DateTime since) {
    return (db.select(db.salesInvoices)
          ..where((i) => i.invoiceDate.isBiggerOrEqualValue(since)))
        .get();
  }

  /// Get sales summary for date range (Performance Optimized)
  Future<SalesSummaryData> getSummary({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final end = DateTime(
      toDate.year,
      toDate.month,
      toDate.day,
    ).add(const Duration(days: 1));

    final totalSales = await db.getTotalSales(from: start, to: end);
    final invoiceCount = await db.getSalesCount(from: start, to: end);

    final result = await db
        .customSelect(
          'SELECT COALESCE(SUM(paid), 0) as paid FROM sales_invoices WHERE invoice_date BETWEEN ? AND ?',
          variables: [Variable(start), Variable(end)],
          readsFrom: {db.salesInvoices},
        )
        .getSingle();
    final totalPaid = (result.data['paid'] as num?)?.toDouble() ?? 0.0;

    return SalesSummaryData(
      totalSales: totalSales,
      totalPaid: totalPaid,
      totalDue: totalSales - totalPaid,
      invoiceCount: invoiceCount,
    );
  }

  @override
  Future<List<SalesInvoiceData>> searchInvoicesByNumber(String query) {
    return db.searchInvoicesByNumber(query);
  }

  @override
  Future<void> updateSalesInvoicePayment(
    int invoiceId,
    String paymentMethod,
    String? notes, {
    double? newCashAmount,
    double? newBankAmount,
  }) {
    return db.updateSalesInvoicePayment(
      invoiceId,
      paymentMethod,
      notes,
      newCashAmount: newCashAmount,
      newBankAmount: newBankAmount,
    );
  }

  @override
  Future<List<SalesInvoiceItemWithProduct>> getInvoiceItemsWithProduct(int invoiceId) async {
    // leftOuterJoin, NOT innerJoin: a line whose product row was hard-deleted
    // must still be returned. An innerJoin dropped it silently, so the invoice
    // rendered a total its own lines didn't add up to — and re-saving from the
    // edit screen persisted the invoice without that line.
    final query = db.select(db.salesInvoiceItems).join([
      leftOuterJoin(db.products, db.products.id.equalsExp(db.salesInvoiceItems.productId)),
    ])..where(db.salesInvoiceItems.invoiceId.equals(invoiceId));

    final rows = await query.get();
    return rows.map((row) {
      return SalesInvoiceItemWithProduct(
        item: row.readTable(db.salesInvoiceItems),
        product: row.readTableOrNull(db.products),
      );
    }).toList();
  }

  @override
  Future<void> updateFullSalesInvoice({
    required int invoiceId,
    int? customerId,
    int warehouseId = 1,
    required double paid,
    required String paymentMethod,
    String? notes,
    required List<CartItemEntity> items,
    int? costCenterId,
  }) async {
    // 0) Get original invoice to check if it's locked
    final oldInvoice = await db.getSalesInvoiceById(invoiceId);
    if (oldInvoice == null) throw Exception('Invoice not found');
    
    // ISS-04: Prevent editing locked/posted invoices to maintain immutable accounting
    if (oldInvoice.isLocked) {
      throw Exception('لا يمكن تعديل فاتورة مبيعات مُرحّلة محاسبيًا. استخدم الإلغاء بدلاً من التعديل لإنشاء قيد عكسي.');
    }

    await db.transaction(() async {
      // 0.5) Soft/Hard Period Closing Gating
      await db.validateFinancialPeriod(oldInvoice.invoiceDate, operation: 'تعديل فاتورة مبيعات');

      // 1) Reverse old GL entry (only safe because it is not locked)
      // NOTE: referenceType may be 'sales_invoice' (new path), 'sale' (autopost DAO path),
      // or the legacy 'cash_sale'/'credit_sale' — check all variants.
      final oldEntry = await (db.select(db.journalEntries)
            ..where((e) =>
                (e.referenceType.equals('sales_invoice') |
                 e.referenceType.equals('sale') |
                 e.referenceType.equals('cash_sale') |
                 e.referenceType.equals('credit_sale')) &
                e.referenceId.equals(invoiceId)))
          .getSingleOrNull();
      if (oldEntry != null) {
        final affectedAccs = await db.customSelect(
          'SELECT DISTINCT account_id FROM journal_entry_lines WHERE entry_id = ?',
          variables: [Variable(oldEntry.id)],
          readsFrom: {db.journalEntryLines},
        ).get();
        final accIds = affectedAccs.map((r) => r.read<int>('account_id')).toList();
        await (db.delete(db.journalEntryLines)..where((l) => l.entryId.equals(oldEntry.id))).go();
        await (db.delete(db.journalEntries)..where((e) => e.id.equals(oldEntry.id))).go();
        // Recalculate affected account balances inline (private method inaccessible)
        for (final accId in accIds) {
          final result = await db.customSelect(
            'SELECT COALESCE(SUM(debit),0) as total_debit, COALESCE(SUM(credit),0) as total_credit '
            'FROM journal_entry_lines WHERE account_id = ?',
            variables: [Variable(accId)],
            readsFrom: {db.journalEntryLines},
          ).getSingle();
          final totalDebit = (result.data['total_debit'] as num).toDouble();
          final totalCredit = (result.data['total_credit'] as num).toDouble();
          final newBalance = totalDebit - totalCredit;
          await db.customStatement(
            'UPDATE accounts SET balance = ? WHERE id = ?',
            [newBalance, accId],
          );
        }
      }

      // 2) Delete old invoice items
      await (db.delete(db.salesInvoiceItems)..where((i) => i.invoiceId.equals(invoiceId))).go();

      // 3) Insert new items and compute totals
      double subtotal = 0;
      double totalTax = 0;

      for (final item in items) {
        final lineTotal = item.quantity * item.unitPrice;
        subtotal += lineTotal;
        totalTax += item.taxAmount;

        // Build composite note from itemNote + modifiers (same logic as createSalesInvoice)
        final compositeNote = item.note;

        await db.into(db.salesInvoiceItems).insert(SalesInvoiceItemsCompanion.insert(
          invoiceId: invoiceId,
          productId: item.productId,
          quantity: item.quantity,
          unitName: Value(item.selectedUnitName),
          quantityInBase: Value(item.quantityInBase),
          unitPrice: item.unitPrice,
          total: lineTotal + item.taxAmount,
          taxRate: Value(item.taxRate),
          taxAmount: Value(item.taxAmount),
          note: Value(compositeNote),
        ));
      }

      final total = subtotal + totalTax;
      final status = paid >= total ? 'paid' : (paid > 0 ? 'partial' : 'credit');

      // 4) Update invoice record
      await (db.update(db.salesInvoices)..where((i) => i.id.equals(invoiceId))).write(
        SalesInvoicesCompanion(
          customerId: Value(customerId),
          warehouseId: Value(warehouseId),
          subtotal: Value(subtotal),
          tax: Value(totalTax),
          total: Value(total),
          paid: Value(paid),
          paymentMethod: Value(paymentMethod),
          status: Value(status),
          notes: Value(notes),
          costCenterId: Value(costCenterId),
        ),
      );

      // 5) Re-post accounting — fetch updated invoice data for auto-post
      final updatedInvoice = await (db.select(db.salesInvoices)
            ..where((i) => i.id.equals(invoiceId)))
          .getSingle();

      final isCash = paymentMethod == 'cash';
      if (isCash) {
        await db.autoPostCashSale(updatedInvoice, costCenterId: costCenterId);
      } else {
        await db.autoPostCreditSale(updatedInvoice, costCenterId: costCenterId);
      }
    });

    // === Client Mode Sync ===
    await ClientWriteInterceptor.updateSalesInvoice(invoiceId, {
      'customerId': customerId,
      'warehouseId': warehouseId,
      'paid': paid,
      'paymentMethod': paymentMethod,
      'notes': notes,
      'costCenterId': costCenterId,
      // Spec 002 Round 7: explicitly type as <String, dynamic> so that
      // ClientWriteInterceptor._enrichItemsWithProductGlobalId can later
      // assign a String productGlobalId. Without the annotation Dart infers
      // Map<String, num> from the all-numeric values and the assignment
      // throws 'String is not a subtype of num of value' (same bug class
      // as the partial purchase return path).
      'items': items.map((i) => <String, dynamic>{
        'productId': i.productId,
        'quantity': i.quantity,
        'unitPrice': i.unitPrice,
        'taxAmount': i.taxAmount,
      }).toList(),
    });
  }

  @override
  Stream<List<SalesInvoiceData>> watchAllRawInvoices() {
    if (SyncInterceptor.isClientMode) {
      return Stream.fromFuture(_getClientWarehouseIds()).asyncExpand((whIds) {
        return db.watchSalesInvoices(warehouseIds: whIds.isNotEmpty ? whIds : null);
      });
    }
    return db.watchSalesInvoices();
  }

}

/// Sales summary data class (Data layer version)
class SalesSummaryData {
  final double totalSales;
  final double totalPaid;
  final double totalDue;
  final int invoiceCount;

  SalesSummaryData({
    required this.totalSales,
    required this.totalPaid,
    required this.totalDue,
    required this.invoiceCount,
  });
}
