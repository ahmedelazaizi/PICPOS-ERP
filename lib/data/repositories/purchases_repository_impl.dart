import '../../core/constants/payment_methods.dart';
import '../../core/errors/app_exceptions.dart';
import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/repositories/purchases_repository.dart';
import '../../domain/models/purchase_return_settlement.dart';
import '../database/database.dart';
import '../../domain/entities/invoice_entity.dart';
import '../../services/accounting_service.dart';
import '../../services/client_write_interceptor.dart';
import '../../core/utils/uuid_v7.dart';
import '../../core/utils/journal_entry_gid.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../database/sync_interceptor.dart';
import '../../domain/entities/accounting_entities.dart' show JournalLine;

class PurchasesRepositoryImpl implements PurchasesRepository {
  final AppDatabase _db;
  final AccountingService _accountingService;

  PurchasesRepositoryImpl(this._db, this._accountingService);

  @override
  Future<int> createInvoice(CreatePurchaseInvoiceParams params) async {
    // Spec 007 / FR-002, FR-005: gate on the broadened predicate so mirror
    // admins' purchase invoices reach HQ. The legacy `NetworkService.isClient`
    // returned false in mirror mode, silently dropping the entire submitPurchase
    // branch and leaving HQ without the invoice.
    final isClientMode = SyncInterceptor.isClientMode;

    // ── Client Mode: Route to server (server handles stock/accounting/treasury) ──
    if (isClientMode) {
      // P5 (Issue #2): Mint a stable globalId so the local cache row and
      // the server-side row share identity. Without this, when the user
      // later submits a return for THIS purchase, the server can't find
      // the original invoice (lookup-by-globalId returns null because the
      // server minted its own UUID). Result: every purchase return
      // dead-letters with "Purchase invoice not found" — exactly what the
      // user reported on the outbox even after 10 retries.
      final purchaseGlobalId = UuidV7.generate();

      // Feature 043 / Route B.1 — per-item globalId threading (R9).
      //
      // Pre-mint ONE UUIDv7 per line BEFORE building either of the two
      // representations (the JSON map sent to the server, and the
      // Companion inserted into the local cache). Both sides then store
      // the line under the SAME global identity, so:
      //
      //   1. `PurchaseSyncStrategy._syncSinglePurchase` Tier-1 dedup
      //      (by globalId) matches on DeltaPull — the strategy UPDATEs
      //      the existing row instead of inserting a fresh duplicate.
      //   2. A purchase with two cartons of the same SKU (same productId
      //      appearing twice) no longer collapses under the legacy
      //      Tier-2 `(invoiceId, productId)` fallback.
      //
      // Pre-Feature-043 the client minted item gids only inside
      // insertPurchaseInvoiceWithoutStock, and the server minted its own
      // gids inside createPurchaseInvoice — two different UUIDs for the
      // same logical line. DeltaPull's Tier-1 missed, and the Tier-2
      // fallback raced on multi-line-same-SKU invoices → user-visible
      // duplicate item rows after the next pull.
      final itemGlobalIds = List<String>.generate(
        params.items.length,
        (_) => UuidV7.generate(),
      );

      final itemMaps = <Map<String, dynamic>>[];
      for (var i = 0; i < params.items.length; i++) {
        final it = params.items[i];
        itemMaps.add({
          'productId': it.productId,
          'quantity': it.stockQuantity,
          'unitCost': it.quantityInBase > 1 ? it.unitCost / it.quantityInBase : it.unitCost,
          'taxRate': it.taxRate,
          'taxAmount': it.taxAmount,
          'total': it.total,
          'batchNumber': it.batchNumber,
          'expiryDate': it.expiryDate?.toIso8601String(),
          'unitName': it.unitName,
          'quantityInBase': it.quantityInBase,
          // 🔴 **والخصمُ يسافر مع السطر.** الخادمُ هو من يوزّعه على التكلفة
          // (`createPurchaseInvoice` عنده)، فإسقاطُه هنا كان يُنتج تكلفةً
          // على الخادم أعلى من تكلفة نسخة العميل لنفس الفاتورة — ومتوسّطَ
          // تكلفةٍ مختلفاً على الجهازَين.
          'discount': it.appliedDiscount,
          // Feature 043 — line-level identity, shared with the local insert below.
          'globalId': itemGlobalIds[i],
        });
      }

      // Client: fire-and-forget (the outbox catches a failed submit).
      // Mirror: awaited — a MirrorOfflineException propagates from here and
      // the local cache insert below never runs. Mirror has no outbox, so a
      // cached row for a purchase HQ never received would show the operator a
      // saved invoice that does not exist anywhere else.
      await ClientWriteInterceptor.dispatchWrite(
        () => ClientWriteInterceptor.submitPurchase(
          supplierId: params.supplierId,
          warehouseId: params.warehouseId,
          items: itemMaps,
          paid: params.paid,
          paymentMethod: params.paymentMethod,
          supplierInvoiceNumber: params.supplierInvoiceNumber,
          notes: params.notes,
          globalId: purchaseGlobalId,
          userId: params.userId,
          createdByUsername: params.createdByUsername,
          discount: params.discount,
          // المرحلة ٨ — العملةُ ووسمُ الاستيراد يسافران مع **نفس** المستند.
          //
          // 🔴 ولا نقطةَ ثانية: لا دفعَ دلتا عامّاً من العميل إلى الخادم في
          //    هذا المستودع (الكتابةُ تُرسَل مستنداً صريحاً)، فوسمٌ يُكتَب
          //    محلّيّاً وحدَه لا يصل الخادمَ أبداً — وتُقرأ الفاتورةُ هناك
          //    محلّيّةً، وتغيب عن شاشة الاستيراد على كلّ جهازٍ آخر.
          currencyId: params.currencyId,
          exchangeRate: params.exchangeRate,
          importDetails: params.importDetails,
          // J1b: the server posts the authoritative JE — same debit account.
          purchaseAccountId: params.purchaseAccountId,
        ),
        tag: 'PURCHASE-SYNC',
      );

      // Local cache only: insert invoice + items without stock/accounting/treasury
      final localItems = <PurchaseInvoiceItemsCompanion>[];
      for (var i = 0; i < params.items.length; i++) {
        final it = params.items[i];
        final baseQty = it.stockQuantity;
        final baseCost = it.quantityInBase > 1 ? it.unitCost / it.quantityInBase : it.unitCost;
        localItems.add(PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: it.productId,
          quantity: baseQty,
          unitCost: baseCost,
          taxRate: Value(it.taxRate),
          taxAmount: Value(it.taxAmount),
          total: it.total,
          batchNumber: Value(it.batchNumber),
          expiryDate: Value(it.expiryDate),
          unitName: Value(it.unitName),
          quantityInBase: Value(it.quantityInBase),
          discount: Value(it.appliedDiscount),
          // Feature 043 — same identity as the JSON map sent to the server.
          globalId: Value(itemGlobalIds[i]),
        ));
      }

      return _db.insertPurchaseInvoiceWithoutStock(
        supplierId: params.supplierId,
        warehouseId: params.warehouseId,
        items: localItems,
        paid: params.paid,
        paymentMethod: params.paymentMethod,
        notes: params.notes,
        supplierInvoiceNumber: params.supplierInvoiceNumber,
        invoiceDate: params.date,
        costCenterId: params.costCenterId,
        globalId: purchaseGlobalId,
        discount: params.discount,
        currencyId: params.currencyId,
        exchangeRate: params.exchangeRate,
        importDetails: params.importDetails,
        purchaseAccountId: params.purchaseAccountId,
      );
    }

    // ── Standalone/Server: Full local processing ──
    return _db.transaction(() async {
      return _db.createPurchaseInvoice(
        supplierId: params.supplierId,
        warehouseId: params.warehouseId,
        items: params.items
            .map(
              (i) {
                // UOM: Convert to base-unit quantities for stock accuracy
                final baseQty = i.stockQuantity;
                final baseCost = i.quantityInBase > 1
                    ? i.unitCost / i.quantityInBase
                    : i.unitCost;
                return PurchaseInvoiceItemsCompanion.insert(
                  invoiceId: 0,
                  productId: i.productId,
                  quantity: baseQty,
                  unitCost: baseCost,
                  taxRate: Value(i.taxRate),
                  taxAmount: Value(i.taxAmount),
                  total: i.total,
                  batchNumber: Value(i.batchNumber),
                  expiryDate: Value(i.expiryDate),
                  unitName: Value(i.unitName), // NEW: Capture unit name
                  quantityInBase: Value(i.quantityInBase), // NEW: Capture conversion factor
                  discount: Value(i.appliedDiscount),
                );
              },
            )
            .toList(),
        paid: params.paid,
        paymentMethod: params.paymentMethod,
        notes: params.notes,
        supplierInvoiceNumber: params.supplierInvoiceNumber,
        invoiceDate: params.date,
        costCenterId: params.costCenterId,
        safeId: params.safeId,
        discount: params.discount,
        sourceOrderId: params.sourceOrderId,
        currencyId: params.currencyId,
        exchangeRate: params.exchangeRate,
        importDetails: params.importDetails,
        purchaseAccountId: params.purchaseAccountId,
      );
    });
  }

  @override
  Future<void> updateInvoice(UpdatePurchaseInvoiceParams params) async {
    // ح-6 — REVERTED 2026-07-25 after the sync review.
    //
    // A client gate was added here (routing the edit to the server like
    // createInvoice does) because editing on a mirror posts a local JE for an
    // event the server also owns. That gate was WRONG and has been removed:
    // `ClientWriteInterceptor.updatePurchase` sends the invoice's LOCAL id and
    // the server's `putPurchase` does `int.parse(id)` with no globalId
    // resolution. Client and server ids diverge by design (DeltaPull keeps the
    // local id and records an FK mapping), so the edit could rebuild a
    // DIFFERENT invoice on the server — reversing another device's stock/WAC
    // and re-posting its journal entry.
    //
    // Restoring the previous behaviour re-exposes the known mirror-divergence
    // issue, which is far less damaging than corrupting an unrelated invoice.
    // Doing this correctly requires threading `globalId` through
    // `_CwiCatalog.updatePurchase` AND resolving globalId → id server-side in
    // `putPurchase` before any mutation; that is separate work, not a gate.
    await _db.transaction(() async {
      await _db.updatePurchaseInvoice(
        invoiceId: params.invoiceId,
        supplierId:
            params.supplierId ?? 0,
        warehouseId: params.warehouseId ?? 1,
        items:
            params.items
                ?.map(
                  (i) {
                    // UOM: Convert to base-unit quantities
                    final baseQty = i.stockQuantity;
                    final baseCost = i.quantityInBase > 1
                        ? i.unitCost / i.quantityInBase
                        : i.unitCost;
                    return PurchaseInvoiceItemsCompanion.insert(
                      invoiceId: params.invoiceId,
                      productId: i.productId,
                      quantity: baseQty,
                      unitCost: baseCost,
                      taxRate: Value(i.taxRate),
                      taxAmount: Value(i.taxAmount),
                      total: i.total,
                      batchNumber: Value(i.batchNumber),
                      expiryDate: Value(i.expiryDate),
                      unitName: Value(i.unitName),
                      quantityInBase: Value(i.quantityInBase),
                      // بلا هذا يفقد التحريرُ خصومَ الأصناف كلَّها: الشاشةُ
                      // تعرضها والمحفوظُ بلا شيء.
                      discount: Value(i.appliedDiscount),
                    );
                  },
                )
                .toList() ??
            [],
         paid: params.paid ?? 0,
        paymentMethod: params.paymentMethod ?? 'cash',
        notes: params.notes,
        supplierInvoiceNumber: params.supplierInvoiceNumber,
        costCenterId: params.costCenterId,
        // Purchase-edit policy — thread the caller's identity so the
        // `purchases_edit` gate in the DAO can actually evaluate it. Before
        // this the parameter was omitted, so the gate saw userId == null and
        // denied EVERY posted invoice regardless of permissions.
        userId: params.userId,
        // ح-1: without this the edit rewrote the total GROSS and re-created
        // the phantom payable the create path was fixed to avoid.
        discount: params.discount,
        changePurchaseAccount: params.changePurchaseAccount,
        purchaseAccountId: params.purchaseAccountId,
      );
    });
  }

  @override
  Future<InvoiceEntity?> getInvoiceById(int id) async {
    final data = await _db.getPurchaseInvoiceById(id);
    if (data == null) return null;
    return InvoiceEntity.fromPurchaseInvoice(data);
  }

  @override
  Stream<List<InvoiceEntity>> watchInvoices() {
    if (SyncInterceptor.isClientMode) {
      // Branch-level data isolation: resolve warehouse IDs then switch to filtered stream
      return Stream.fromFuture(_getClientWarehouseIds()).asyncExpand((whIds) {
        return _db.watchPurchaseInvoices(warehouseIds: whIds.isNotEmpty ? whIds : null).map(
          (list) => list.map((d) => InvoiceEntity.fromPurchaseInvoice(d)).toList(),
        );
      });
    }
    return _db.watchPurchaseInvoices().map(
      (list) => list.map((d) => InvoiceEntity.fromPurchaseInvoice(d)).toList(),
    );
  }

  @override
  Stream<List<InvoiceEntity>> watchInvoicesByDateRange(
    DateTime start,
    DateTime end,
  ) {
    return _db.watchPurchaseInvoicesByDateRange(start, end).map(
      (list) => list.map((d) => InvoiceEntity.fromPurchaseInvoice(d)).toList(),
    );
  }

  @override
  Future<void> recordPayment(int invoiceId, double amount, {int? userId}) async {
    // Spec 151 C-03 (R4/R8/R9) — gate exactly like _voidOrDeleteInvoice.
    // Pre-fix this called addPurchasePayment UNCONDITIONALLY, so in
    // client/mirror mode it wrote invoice.paid + safe_transaction + the Dr AP /
    // Cr cash JE LOCALLY, never told the server, and the payment carried no
    // globalId → the next DeltaPull re-asserted HQ's still-unpaid invoice,
    // leaving the local money/GL orphaned (permanent divergence).
    final isClientMode = SyncInterceptor.isClientMode;
    final invoice = await _db.getPurchaseInvoiceById(invoiceId);
    if (invoice == null) throw Exception('Invoice not found');

    // R9 — a payment is ADDITIVE (unlike a void's idempotent terminal state),
    // so mint a FRESH per-event globalId (NOT derived from the invoice, which
    // would collapse multiple legitimate payments into one). The server and the
    // local DAO both dedup on it, so a retry/replay applies the payment once.
    final paymentGlobalId = UuidV7.generate();

    if (isClientMode) {
      // Server is SSoT for money + GL + treasury. Fire-and-queue the payment;
      // keep only a light local paid marker (no cash/JE side-effects). The
      // authoritative paid/JE/safe move come back on the next DeltaPull
      // (purchase_sync_strategy propagates `paid` on existing rows).
      // Mirror: awaited — the local paid marker below must not claim a payment
      // HQ rejected. Client: unchanged fire-and-queue.
      await ClientWriteInterceptor.dispatchWrite(
        () => ClientWriteInterceptor.submitPurchasePayment(
          purchaseId: invoice.id,
          purchaseGlobalId: invoice.globalId,
          invoiceNumber: invoice.invoiceNumber,
          amount: amount,
          globalId: paymentGlobalId,
          userId: userId,
        ).then((accepted) {
          debugPrint('[PURCHASE-PAYMENT-SYNC] accepted=$accepted '
              'invoice=${invoice.invoiceNumber}');
          return accepted;
        }),
        tag: 'PURCHASE-PAYMENT-SYNC',
      );
      await _db.updatePurchaseInvoicePayment(invoiceId, invoice.paid + amount);
    } else {
      // Standalone / server: this machine IS the source of truth — full apply
      // (paid + safe move + balanced JE), idempotent on paymentGlobalId.
      await _db.addPurchasePayment(
        invoiceId: invoiceId,
        amount: amount,
        userId: userId,
        globalId: paymentGlobalId,
      );
    }
  }

  @override
  Future<void> deleteInvoice(int invoiceId) async {
    // Redirect to atomic voiding in DAO
    await _voidOrDeleteInvoice(invoiceId, reason: 'Delete (Legacy Redirect)');
  }

  @override
  Future<void> voidInvoice(int invoiceId, {String? reason}) async {
    await _voidOrDeleteInvoice(invoiceId, reason: reason);
  }

  /// PR-2 (pre-deploy batch B6) / R4, R8, R9 — gate the void on
  /// `SyncInterceptor.isClientMode` exactly like [createInvoice] and
  /// [processPurchaseReturn] above.
  ///
  /// Root cause fixed here: the pre-fix code called `_db.voidPurchaseInvoice`
  /// UNCONDITIONALLY, so in client/mirror mode it wrote the full
  /// stock/AP/treasury/GL reversal LOCALLY, never told the server, and the
  /// reversal JE carried no globalId. The next DeltaPull then re-asserted
  /// the still-active invoice from HQ, leaving the local reversal orphaned
  /// — permanent divergence between mirror and server.
  Future<void> _voidOrDeleteInvoice(int invoiceId, {String? reason}) async {
    final isClientMode = SyncInterceptor.isClientMode;

    // Need the invoice row to thread its globalId/invoiceNumber to the
    // server and to derive the reversal JE's deterministic globalId (R9).
    // Both modes need it, so load it once up front.
    final invoice = await _db.getPurchaseInvoiceById(invoiceId);
    if (invoice == null) {
      // Preserve legacy behaviour: voidPurchaseInvoice itself silently
      // no-ops on a missing invoice — only the standalone/server path needs
      // to call it (client mode has nothing to identify to the server).
      if (!isClientMode) {
        await _db.voidPurchaseInvoice(invoiceId, reason: reason);
      }
      return;
    }

    // Mirrors voidPurchaseInvoice's own "already voided" guard — avoids a
    // redundant server round-trip (or a wasted local write) for a double-tap
    // on an invoice that's already voided.
    if (invoice.status == 'voided') {
      throw Exception('الفاتورة ملغية بالفعل');
    }

    // R9 — mint ONE deterministic globalId for this void's reversal JE, and
    // thread the SAME value into the server submit (client/mirror) or the
    // local DAO call (standalone/server). Deriving it from the invoice's own
    // globalId means a retried void (outbox replay) always reproduces the
    // same JE identity, converging under journal_entries.globalId's UNIQUE
    // index instead of duplicating — same pattern the landed-cost reversal
    // uses inside voidPurchaseInvoice itself.
    final voidGlobalId =
        (invoice.globalId != null && invoice.globalId!.isNotEmpty)
            ? JournalEntryGid.compute(
                sourceType: JournalEntryGid.sourcePurchase,
                sourceGid: invoice.globalId!,
                verb: 'void',
              )
            : UuidV7.generate();

    // ── Client/Mirror Mode: submit to server, server is SSoT (R4/R8) ──
    if (isClientMode) {
      unawaited(DiagnosticLogger.log('PURCHASE-VOID',
          'enter client-mode path invoiceId=${invoice.id} '
          'invoiceNumber=${invoice.invoiceNumber} '
          'globalId=${invoice.globalId} voidGlobalId=$voidGlobalId'));

      // 1) Submit to server (server performs the authoritative
      // stock/AP/treasury/JE reversal).
      //   • Client — fire-and-forget; the outbox retries and the local status
      //     marker below still flips so the invoice leaves the active list.
      //   • Mirror — awaited; a failure propagates and the status marker never
      //     runs. Marking an invoice "voided" locally when HQ still has it live
      //     is worse than not voiding at all: the operator stops chasing it.
      await ClientWriteInterceptor.dispatchWrite(
        () => ClientWriteInterceptor.submitVoidPurchase(
          purchaseId: invoice.id,
          purchaseGlobalId: invoice.globalId,
          invoiceNumber: invoice.invoiceNumber,
          reason: reason,
          globalId: voidGlobalId,
        ).then((accepted) {
          debugPrint('[PURCHASE-VOID-SYNC] Server response: accepted=$accepted');
          unawaited(DiagnosticLogger.log('PURCHASE-VOID',
              accepted
                  ? '✓ accepted invoice=${invoice.invoiceNumber}'
                  : '⏳ queued offline invoice=${invoice.invoiceNumber} '
                      '(server unreachable, will retry from sync_outbox)'));
          return accepted;
        }),
        tag: 'PURCHASE-VOID-SYNC',
      );

      // 2) Local marker only — MUST NOT run the full stock/AP/treasury/GL
      // reversal (that is now the server's job). The authoritative row
      // (isLocked/isDeleted/notes/deletedAt/deletedBy) arrives on the next
      // DeltaPull; this just flips the user-visible status immediately so
      // the invoice drops out of the active list without waiting for the
      // round-trip. Server's own row overwrites this on the next pull.
      try {
        await _db.updatePurchaseInvoiceStatus(invoice.id, 'voided');
        unawaited(DiagnosticLogger.log('PURCHASE-VOID',
            '✓ local status marker set invoice=${invoice.invoiceNumber}'));
      } catch (e) {
        debugPrint('[PURCHASE-VOID] local status marker failed: $e');
        unawaited(DiagnosticLogger.log('PURCHASE-VOID',
            '⚠ local status marker failed invoice=${invoice.invoiceNumber}: $e'));
      }
      return;
    }

    // ── Standalone/Server: full local processing ──
    await _db.voidPurchaseInvoice(
      invoiceId,
      reason: reason,
      globalId: voidGlobalId,
    );
  }

  @override
  Future<List<InvoiceEntity>> getPurchasesReport(
    DateTime start,
    DateTime end,
  ) async {
    final list = await _db.getPurchasesReport(start, end);
    return list.map((d) => InvoiceEntity.fromPurchaseInvoice(d)).toList();
  }

  @override
  Future<List<InvoiceEntity>> getPurchasesBySupplier(int supplierId) async {
    final list = await _db.getPurchasesBySupplierId(supplierId);
    return list.map((d) => InvoiceEntity.fromPurchaseInvoice(d)).toList();
  }

  @override
  Future<List<PurchaseInvoiceItemWithProduct>> getInvoiceItemsWithProduct(
    int invoiceId,
  ) {
    return _db.getPurchaseInvoiceItemsWithProduct(invoiceId);
  }

  @override
  Future<PurchaseInvoiceData?> getRawInvoiceById(int id) {
    return _db.getPurchaseInvoiceById(id);
  }

  @override
  Future<double> processPurchaseReturn({
    required PurchaseInvoiceData invoice,
    required List<PurchaseReturnItem> returnItems,
    /// سببُ المردود — قائمةٌ ثابتةٌ إلزاميّةٌ في الواجهة (قرارُ المالك
    /// 2026-09-18)، واختيارٌ هنا لأنّ مساراتٍ أخرى قديمةً تناديها.
    String? reason,
  }) async {
    double totalReturnAmount = 0;
    for (final item in returnItems) {
      if (item.returnQuantity <= 0) continue;
      totalReturnAmount += item.returnQuantity * item.unitCost;
    }

    // Feature 014 / Issue 1 — refuse to post a purchase return when the
    // invoice's date falls inside a CLOSED fiscal year or monthly
    // accounting period. Once the operator presses "إقفال" any later
    // mutation against that period would silently rewrite locked
    // numbers (income statement, AP balance, stock movements). The
    // check runs locally; the server's own period-close enforcement
    // catches the same case for the standalone path so the two layers
    // stay consistent.
    final closed = await _db.isDateInClosedPeriod(invoice.invoiceDate);
    if (closed) {
      throw Exception(
        'لا يمكن تنفيذ مرتجع المشتريات — الفترة المحاسبية '
        '(${invoice.invoiceDate.toIso8601String().substring(0, 10)}) '
        'مقفلة. يرجى فتح الفترة من شاشة السنوات المالية إذا كان التعديل ضرورياً.',
      );
    }

    // Spec 007 / FR-004, FR-005: broadened predicate so mirror admins'
    // purchase returns reach HQ.
    final isClientMode = SyncInterceptor.isClientMode;

    // ── Client Mode: lightweight local cache + server handles heavy operations ──
    if (isClientMode) {
      // Spec 136 ISS-7 — mint a per-return-event globalId (R9). The same value
      // is threaded into the server submit AND the local memo placeholder, so
      // multiple partial returns on one invoice each get a DISTINCT, mirror↔
      // server-consistent memo globalId (was constant per invoice → 2067/23505
      // collision on the 2nd return).
      final returnGlobalId = UuidV7.generate();
      unawaited(DiagnosticLogger.log('PURCHASE-RETURN',
          'enter client-mode path invoiceId=${invoice.id} '
          'invoiceNumber=${invoice.invoiceNumber} '
          'globalId=${invoice.globalId} returnGlobalId=$returnGlobalId '
          'warehouseId=${invoice.warehouseId} '
          'items=${returnItems.length} total=$totalReturnAmount'));

      // 1) Submit to server (server handles stock reversal, WAC adjustment,
      // supplier balance, safe transactions, accounting JE).
      //   • Client — fire-and-forget; the outbox retries.
      //   • Mirror — awaited; on failure the local 'partial_return' badge and
      //     the cache rows below never land, so the invoice keeps showing its
      //     true (un-returned) state instead of a return HQ never recorded.
      await ClientWriteInterceptor.dispatchWrite(
        () => ClientWriteInterceptor.submitPurchaseReturn({
          'purchaseId': invoice.id,
          if (invoice.globalId != null && invoice.globalId!.isNotEmpty)
            'purchaseGlobalId': invoice.globalId,
          // Spec 136 ISS-7 — per-return-event id for a unique, consistent
          // memo globalId across mirror + server.
          'returnGlobalId': returnGlobalId,
          // والسببُ يسافر معها: الخادمُ هو من يكتب صفَّ المستند في
          // وضع العميل، فإسقاطُه من الحمولة يجعل الحقلَ ميّتاً على كلّ
          // جهازٍ عميلٍ — وهي أكثرُ التنصيبات.
          if (reason != null && reason.isNotEmpty) 'reason': reason,          'invoiceNumber': invoice.invoiceNumber,
          // Spec 002 Round 7 (FINAL FIX): explicitly type the inner map as
          // <String, dynamic>. Without this annotation, Dart infers the
          // literal as Map<String, num> because all three values are numeric
          // (productId int, returnQuantity/unitCost double). When
          // _enrichItemsWithProductGlobalId later tries to assign a String
          // value (`item['productGlobalId'] = uuid`), the runtime rejects it
          // with: type 'String' is not a subtype of type 'num' of 'value'.
          //
          // Sales returns dodge this because returnItemsList is declared as
          // <Map<String, dynamic>>[] which propagates the element type into
          // the literal via context inference. Purchase returns build the
          // list inline via .map().toList() with no target type, so the
          // numeric LUB wins. Annotating the literal here matches sales-side
          // behavior — symmetric, simple, no schema change.
          'items': returnItems.map((item) => <String, dynamic>{
            'productId': item.productId,
            'returnQuantity': item.returnQuantity,
            'unitCost': item.unitCost,
          }).toList(),
          'totalReturn': totalReturnAmount,
          'costCenterId': invoice.costCenterId,
        }).then((accepted) {
          debugPrint('[PURCHASE-RETURN-SYNC] Server response: accepted=$accepted');
          unawaited(DiagnosticLogger.log('PURCHASE-RETURN',
              accepted
                  ? '✓ accepted invoice=${invoice.invoiceNumber}'
                  : '⏳ queued offline invoice=${invoice.invoiceNumber} '
                      '(server unreachable, will retry from sync_outbox)'));
          return accepted;
        }),
        tag: 'PURCHASE-RETURN-SYNC',
      );

      // 2) Local status update — MUST succeed regardless of optional cache
      // population below. Done OUTSIDE any transaction so the user-visible
      // 'partial_return' badge always lands even if stock_movements seed
      // fails (FK divergence, race, etc.).
      bool isFullReturn = true;
      for (final item in returnItems) {
        if (item.returnQuantity < item.originalQuantity) {
          isFullReturn = false;
          break;
        }
      }
      final newStatus = isFullReturn ? 'returned' : 'partial_return';
      try {
        await _db.updatePurchaseInvoiceStatus(invoice.id, newStatus);
        unawaited(DiagnosticLogger.log('PURCHASE-RETURN',
            '✓ status updated invoice=${invoice.invoiceNumber} → $newStatus'));
      } catch (e) {
        debugPrint('[PURCHASE-RETURN] status update failed: $e');
        unawaited(DiagnosticLogger.log('PURCHASE-RETURN',
            '❌ status update failed invoice=${invoice.invoiceNumber}: $e'));
        rethrow; // Status update failure is fatal — caller needs to know.
      }

      // 3) Optional cache population: insert stock_movements rows so the
      // returns-history detail view (getPurchaseReturnItemDetails) shows
      // the actual returned subset right away. Server's authoritative rows
      // overwrite ours on the next DeltaPull.
      //
      // Each insert is guarded individually — an FK violation on one
      // line (e.g. a product that hasn't synced yet) must not abort the
      // others. If the cache is incomplete, the UI falls back to "details
      // not available locally — sync pending" which is honest, not wrong.
      int seeded = 0;
      int failed = 0;
      for (final item in returnItems) {
        if (item.returnQuantity <= 0) continue;
        try {
          await _db.into(_db.stockMovements).insert(
                StockMovementsCompanion.insert(
                  productId: item.productId,
  // ignore: dead_code
                  warehouseId: invoice.warehouseId ?? 1,
                  movementType: 'purchase_return',
                  quantity: -item.returnQuantity,
                  balanceAfter: 0,
                  unitCost: Value(item.unitCost),
                  referenceType: const Value('purchase_return'),
                  referenceId: Value(invoice.id),
                  notes: const Value(
                    'Local cache for purchase return — '
                    'authoritative row arrives via sync.',
                  ),
                  globalId: Value(UuidV7.generate()),
                ),
              );
          seeded++;
        } catch (e) {
          failed++;
          debugPrint('[PURCHASE-RETURN] stock_movement seed failed for '
              'productId=${item.productId}: $e');
          unawaited(DiagnosticLogger.log('PURCHASE-RETURN',
              '⚠ stock_movement seed failed productId=${item.productId} '
              'qty=${item.returnQuantity}: $e'));
        }
      }
      unawaited(DiagnosticLogger.log('PURCHASE-RETURN',
          'cache seed done invoice=${invoice.invoiceNumber} '
          'seeded=$seeded failed=$failed'));

      // 4) Feature 010 / Cluster D — supplier-statement memo cache.
      // Mirror the standalone path's safe_transactions memo write (lines
      // 484-498 below, and api_purchase_handler.postPurchaseReturn:384-397
      // server-side) so كشف حساب المورد shows the AP balance adjustment
      // immediately on the mirror, instead of staying blank until the
      // server's DeltaPull arrives.
      //
      // Why this is safe under R4 (server = SSoT): the row is a pure
      // display cache — no cash moves and the supplier balance itself
      // is not adjusted here (server still owns that authoritative
      // write). When the server's DeltaPull echoes back its own memo
      // row, SafeTransactionSyncStrategy._syncSingleTransaction dedups
      // by (referenceType='purchase_return', referenceId=invoice.id,
      // safeId) at safe_transaction_sync_strategy.dart:103-121, so we
      // do NOT double-count.
      //
      // Best-effort: a missing default safe (rare on a properly set-up
      // mirror) leaves the statement blank for this return, but never
      // aborts the user-visible status update above.
      double totalVatReturn = 0;
      for (final item in returnItems) {
        if (item.taxAmount > 0 && item.originalQuantity > 0) {
          totalVatReturn +=
              item.taxAmount * (item.returnQuantity / item.originalQuantity);
        }
      }
      // القسمةُ من الصيغة الواحدة — والواجهةُ تقرأ عينَها، فالمرآةُ
      // تعرض ما سيفعله المحرّكُ لا ما تحسبه بنفسها.
      final settlement = resolvePurchaseReturnSettlement(
        returnNet: totalReturnAmount,
        returnVat: totalVatReturn,
        invoiceTotal: invoice.total,
        invoicePaid: invoice.paid,
      );
  // ignore: unused_local_variable
      final grossReturnAmount = settlement.gross;
      final balanceCorrection = settlement.apPortion;
      if (balanceCorrection > 0) {
        try {
          final isBank =
              isBankPaymentMethod(invoice.paymentMethod);
          final balanceSafe = isBank
              ? await _db.getDefaultSafeByType('bank')
              : await _db.getDefaultSafeByType('cash');
          if (balanceSafe != null) {
            // Cluster 028 / Bug 1: derive a DETERMINISTIC globalId from the
            // purchase invoice's globalId so the server's authoritative memo
            // (which derives the same value) deduplicates via Tier 1
            // (globalId match) when the DeltaPull arrives. Without this both
            // rows survive — mirror's `referenceId` is the local invoice id,
            // server's is the server's invoice id (almost always different),
            // so the Tier 2 (`refType+refId+partyId`) fallback misses.
            final memoGlobalId =
                (invoice.globalId != null && invoice.globalId!.isNotEmpty)
                    ? UuidV7.deriveReturnMemoGlobalId(
                        invoiceGlobalId: invoice.globalId!,
                        returnType: 'purchase_return',
                        partyId: invoice.supplierId,
                        // Spec 136 ISS-7 — unique per return event.
                        returnEventId: returnGlobalId,
                      )
                    : UuidV7.generate();
            await _db.into(_db.safeTransactions).insert(
                  SafeTransactionsCompanion.insert(
                    voucherNumber: 'PRET-LOC-${invoice.id}',
                    safeId: balanceSafe.id,
                    transactionType: 'memo',
                    category: 'purchase_return_balance',
                    amount: balanceCorrection,
                    balanceAfter: balanceSafe.balance,
                    referenceType: const Value('purchase_return'),
                    referenceId: Value(invoice.id),
                    partyId: Value(invoice.supplierId),
                    description: Value(
                      'تسوية رصيد مرتجع مشتريات فاتورة '
                      '${invoice.invoiceNumber} (محلي - يحدّث بعد المزامنة)',
                    ),
                    globalId: Value(memoGlobalId),
                  ),
                );
            unawaited(DiagnosticLogger.log('PURCHASE-RETURN',
                '✓ memo seeded invoice=${invoice.invoiceNumber} '
                'amount=$balanceCorrection safeId=${balanceSafe.id}'));
          } else {
            unawaited(DiagnosticLogger.log('PURCHASE-RETURN',
                '⚠ memo skipped — no default '
                '${isBank ? 'bank' : 'cash'} safe '
                'invoice=${invoice.invoiceNumber}'));
          }
        } catch (e) {
          debugPrint('[PURCHASE-RETURN] memo seed failed: $e');
          unawaited(DiagnosticLogger.log('PURCHASE-RETURN',
              '⚠ memo seed failed invoice=${invoice.invoiceNumber}: $e'));
        }
      }

      return totalReturnAmount;
    }

    // ── Standalone/Server: Full local processing ──

    // Validate return quantities before processing
    for (final item in returnItems) {
      if (item.returnQuantity > item.originalQuantity + 0.001) {
        throw Exception(
          'كمية الإرجاع (${item.returnQuantity}) تتجاوز الكمية الأصلية (${item.originalQuantity}) للصنف رقم ${item.productId}',
        );
      }
    }

    await _db.transaction(() async {
      await _processPurchaseReturnBody(
        invoice: invoice,
        returnItems: returnItems,
        totalReturnAmount: totalReturnAmount,
        reason: reason,
      );
    });

    return totalReturnAmount;
  }

  /// Standalone purchase-return body — extracted (Feature 015) so
  /// [editPurchaseReturn] can run reverse + recreate inside a single
  /// transaction. MUST be called from inside an open `_db.transaction(...)`
  /// — this helper does NOT open one itself.
  Future<void> _processPurchaseReturnBody({
    required PurchaseInvoiceData invoice,
    required List<PurchaseReturnItem> returnItems,
    required double totalReturnAmount,
    String? reason,
  }) async {
      // B3: Generate sequential return invoice number
      // allow-bare-generateInvoiceNumber: _processPurchaseReturnBody requires caller to open the transaction (see method docstring above).
      final returnVoucherNumber = await _db.generateInvoiceNumber('PRET-');
      double totalVatReturn = 0;

      for (final item in returnItems) {
        if (item.returnQuantity <= 0) continue;

        // C-05 FIX: Calculate proportional VAT for returned quantity
        if (item.taxAmount > 0 && item.originalQuantity > 0) {
          totalVatReturn += item.taxAmount * (item.returnQuantity / item.originalQuantity);
        }

        // FIX 2026-04-28: returnQuantity is ALREADY in base units (it comes from
        // purchase_invoice_items.quantity which is stored as base units after the
        // unit-conversion at createPurchaseInvoice). Multiplying by quantityInBase
        // here was double-converting → 10x quantity bug. Same applies to unitCost
        // which is stored per-base-unit (cost / quantityInBase) at insertion time.
        final stockReturnQty = item.returnQuantity;

        // P0 FIX: Reverse the WAC impact of the returned purchase line before adjusting stock
        await _db.reverseProductWAC(
          productId: item.productId,
          reversedQuantity: stockReturnQty,
          reversedUnitCost: item.unitCost, // already per base unit
        );

        // Reverse stock: remove from warehouse (in base units)
        await _db.adjustStock(
          productId: item.productId,
          warehouseId: invoice.warehouseId,
          quantity: -stockReturnQty,
          type: 'purchase_return',
          referenceType: 'purchase_return',
          referenceId: invoice.id,
           unitCost: item.unitCost,
        );
      }

      // ── Supplier balance & cash refund ──────────────────────────────────
      // Supplier balance is stored as GROSS (net + VAT) — match that convention.
      // Case A: Invoice partially/fully unpaid → reduce what we still owe.
      // Case B: Invoice already paid → record cash received back from supplier.
      // القسمةُ من الصيغة الواحدة — والواجهةُ تقرأ عينَها، فالمرآةُ
      // تعرض ما سيفعله المحرّكُ لا ما تحسبه بنفسها.
      final settlement = resolvePurchaseReturnSettlement(
        returnNet: totalReturnAmount,
        returnVat: totalVatReturn,
        invoiceTotal: invoice.total,
        invoicePaid: invoice.paid,
      );
  // ignore: unused_local_variable
      final grossReturnAmount = settlement.gross;
      final balanceCorrection = settlement.apPortion;
      if (balanceCorrection > 0) {
        await _db.adjustPartyBalance(invoice.supplierId, -balanceCorrection);

        // Record a balance-adjustment entry for the supplier statement.
        // No cash moves so we look up the default safe but don't change its balance.
        final balanceSafe = isBankPaymentMethod(invoice.paymentMethod)
            ? await _db.getDefaultSafeByType('bank')
            : await _db.getDefaultSafeByType('cash');
        if (balanceSafe != null) {
          // IMPORTANT: use a direct INSERT (NOT createSafeTransaction), and
          // use transactionType='memo'. Reason: createSafeTransaction with
          // type='receipt' would (a) INCREASE the safe balance via SQL
          // arithmetic — wrong, no cash moved — and (b) re-adjust the
          // supplier's party balance a second time, double-counting the
          // refund. Memo rows fall into the 'else' branch of the balance
          // router and are skipped by downstream aggregation queries.
          await _db.into(_db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: returnVoucherNumber,
              safeId: balanceSafe.id,
              transactionType: 'memo',
              category: 'purchase_return_balance',
              amount: balanceCorrection,
              balanceAfter: balanceSafe.balance, // balance unchanged — memo entry only
              referenceType: const Value('purchase_return'),
              referenceId: Value(invoice.id),
              partyId: Value(invoice.supplierId),
              description: Value('تسوية رصيد مرتجع مشتريات فاتورة ${invoice.invoiceNumber}'),
            ),
          );
        }
      }

      // Cash actually received back (paid portion of the gross return)
      //
      // Same freeze/double-count bug pattern as the sales-return cash
      // refund branch: `createSafeTransaction` opens a nested transaction
      // inside the outer `_db.transaction(...)` AND performs its own safe-
      // balance + party-balance mutations on top of the explicit ones we
      // already ran above. Plain insert avoids the nested transaction
      // (root cause of the full-return freeze) and keeps the balances
      // consistent.
      final cashReturnAmount = settlement.cashPortion;
      if (cashReturnAmount > 0) {
        // Record in safe: supplier gives back money → receipt into our safe
        final isBank = isBankPaymentMethod(invoice.paymentMethod);
        // مواصفة 2026-08-18 (ح‑٢/ح‑٣): خزنةُ فرعِ المخزن لا الافتراضيّةُ
        // العامّة، ورميٌ لا تخطٍّ صامت. كان `getDefaultSafeByType` ثمّ
        // `if (safe != null)` بلا `else`: فرعٌ بلا خزنةٍ افتراضيّةٍ عامّة كان
        // يمضي مرتجعُه كامل الأثر — مخزونٌ يخرج وقيدٌ مدينُه النقديّة —
        // ودرجٌ لم يتحرّك.
        final safe = await _db.resolveSafeForOperation(
          safeType: isBank ? 'bank' : 'cash',
          warehouseId: invoice.warehouseId,
          operationLabel: 'purchase-return #${invoice.invoiceNumber}',
          noSafeMessage:
              'لا توجد خزنة ${isBank ? 'بنكية' : 'نقدية'} صالحة لاستلام '
              'مرتجع المشتريات. اضبط الخزائن من الإعدادات ← الخزينة '
              '(المرتجع لم يُحفَظ).',
        );
        // ح‑١: نقدٌ **يدخل** الدرجَ هنا (المورّدُ يردّ المال)، فبلا نافذةٍ
        // تحويه يعدّه الكاشيرُ التالي فائضاً ويُقيَّد «فائض نقدية».
        //
        // والسؤالُ عن فرعِ الخزنة لا عن المستخدم: توقيعُ
        // `processPurchaseReturn` لا يحمل `userId` أصلاً.
        if (!await _db.drawerMovementAllowed(safe.id)) {
          throw ShiftRequiredException(cashAmount: cashReturnAmount);
        }
        {
          // 069 (D5-003): atomic delta update.
          final newBalance = safe.balance + cashReturnAmount;
          await _db.adjustSafeBalance(safe.id, cashReturnAmount);
          await _db.into(_db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: returnVoucherNumber,
              safeId: safe.id,
              transactionType: 'receipt',
              category: 'purchase_return',
              amount: cashReturnAmount,
              balanceAfter: newBalance,
              referenceType: const Value('purchase_return'),
              referenceId: Value(invoice.id),
              partyId: Value(invoice.supplierId),
              description: Value('استرداد نقدي مرتجع مشتريات فاتورة ${invoice.invoiceNumber}'),
            ),
          );
        }
      }

      // Auto-post accounting entry with VAT
      // B8 (PRET-1): thread the return's own voucher number as the dedup
      // discriminator so two distinct partial returns of the same amount on
      // this invoice don't collide (see autoPostPurchaseReturn docstring).
      // B9 (PRET-2): thread the AP/cash split already computed above
      // (balanceCorrection = unpaid portion → Dr Payables; cashReturnAmount
      // = paid portion → Dr Cash) so the GL mirrors exactly what happened
      // to the supplier's balance and the safe, instead of lumping the
      // whole refund onto a single leg keyed only on paymentMethod.
      await _db.autoPostPurchaseReturn(
        originalPurchase: invoice,
        reason: reason,
        // نفس سبب مرتجع المبيعات: المرتجع حدث لاحق له فترته الخاصة.
        returnDate: DateTime.now(),
        returnAmount: totalReturnAmount,
        vatAmount: totalVatReturn,
        costCenterId: invoice.costCenterId, // FIX: Pass original cost center
        returnEventId: returnVoucherNumber,
        apPortion: balanceCorrection,
        cashPortion: cashReturnAmount,
      );

      // FIX: Mark the invoice as returned so it appears in history
      bool isFullReturn = true;
      for (final item in returnItems) {
        if (item.returnQuantity < item.originalQuantity) {
          isFullReturn = false;
          break;
        }
      }
      await _db.updatePurchaseInvoiceStatus(
        invoice.id,
        isFullReturn ? 'returned' : 'partial_return',
      );
  }

  // ════════════════════════════════════════════════════════════════════════
  // Feature 015 — editPurchaseReturn
  // ════════════════════════════════════════════════════════════════════════

  @override
  Future<double> editPurchaseReturn({
    required PurchaseInvoiceData invoice,
    required List<PurchaseReturnItem> newReturnItems,
  }) async {
    // Period gate (Feature 014) — same Arabic message as processPurchaseReturn.
    final closed = await _db.isDateInClosedPeriod(invoice.invoiceDate);
    if (closed) {
      throw Exception(
        'لا يمكن تنفيذ مرتجع المشتريات — الفترة المحاسبية '
        '(${invoice.invoiceDate.toIso8601String().substring(0, 10)}) '
        'مقفلة. يرجى فتح الفترة من شاشة السنوات المالية إذا كان التعديل ضرورياً.',
      );
    }

    // Validate new return quantities against the original invoice qty.
    for (final item in newReturnItems) {
      if (item.returnQuantity > item.originalQuantity + 0.001) {
        throw Exception(
          'كمية الإرجاع (${item.returnQuantity}) تتجاوز الكمية الأصلية '
          '(${item.originalQuantity}) للصنف رقم ${item.productId}',
        );
      }
    }

    // Compute the CURRENT-NET old return state from stock_movements
    // (purchase_return + purchase_return_reverse). This is what we need to
    // reverse before re-posting the new values.
    final oldReturnItems = await _computeCurrentReturnedItems(invoice);
    final oldTotalReturnAmount = oldReturnItems.fold<double>(
      0.0,
      (sum, item) => sum + item.returnQuantity * item.unitCost,
    );

    // No-op detection: identical (productId, qty, cost) tuples.
    if (_returnItemsEqual(oldReturnItems, newReturnItems)) {
      unawaited(DiagnosticLogger.log(
        'PURCHASE-RETURN-EDIT',
        'no-op invoice=${invoice.invoiceNumber} (items unchanged)',
      ));
      return oldTotalReturnAmount;
    }

    final newTotalReturnAmount = newReturnItems.fold<double>(
      0.0,
      (sum, item) =>
          sum + (item.returnQuantity > 0 ? item.returnQuantity * item.unitCost : 0.0),
    );

    // ── Mirror/Client mode (Spec 015 FR-007 + R4 SSoT) ──
    // Route the edit through ClientWriteInterceptor.submitPurchaseReturnEdit.
    // The server's /api/purchases/return/edit handler runs the authoritative
    // reverse + recreate; the next DeltaPull reconciles our local cache.
    // Local writes are intentionally skipped here — even the cache. The
    // existing UI's status badge updates from the next sync; doing partial
    // local writes for an EDIT (where the prior return state may itself be
    // stale on the mirror) risks double-counting once the server's rows
    // arrive. Rule R8 / SYNC_ARCHITECTURE §7.
    final isClientMode = SyncInterceptor.isClientMode;
    if (isClientMode) {
      unawaited(DiagnosticLogger.log('PURCHASE-RETURN-EDIT',
          'enter client-mode path invoiceId=${invoice.id} '
          'invoiceNumber=${invoice.invoiceNumber} '
          'globalId=${invoice.globalId} '
          'oldTotal=$oldTotalReturnAmount newTotal=$newTotalReturnAmount '
          'items=${newReturnItems.length}'));
      // Mirror: awaited — this path writes NOTHING locally and returns the new
      // total as if it were applied, so a swallowed failure is a pure silent
      // loss. The caller now gets the exception instead.
      await ClientWriteInterceptor.dispatchWrite(
        () => ClientWriteInterceptor.submitPurchaseReturnEdit({
          'purchaseId': invoice.id,
          if (invoice.globalId != null && invoice.globalId!.isNotEmpty)
            'purchaseGlobalId': invoice.globalId,
          'invoiceNumber': invoice.invoiceNumber,
          // Same Map<String, dynamic> annotation as submitPurchaseReturn —
          // without it Dart infers Map<String, num> and the interceptor's
          // _enrichItemsWithProductGlobalId fails to add String fields.
          'items': newReturnItems.map((item) => <String, dynamic>{
                'productId': item.productId,
                'returnQuantity': item.returnQuantity,
                'unitCost': item.unitCost,
              }).toList(),
          'totalReturn': newTotalReturnAmount,
          'costCenterId': invoice.costCenterId,
        }).then((accepted) {
          unawaited(DiagnosticLogger.log('PURCHASE-RETURN-EDIT',
              accepted
                  ? '✓ accepted invoice=${invoice.invoiceNumber}'
                  : '⏳ queued offline invoice=${invoice.invoiceNumber} '
                      '(server unreachable, will retry from sync_outbox)'));
          return accepted;
        }),
        tag: 'PURCHASE-RETURN-EDIT-SYNC',
      );
      return newTotalReturnAmount;
    }

    // ── Standalone/Server: atomic reverse + recreate ──
    await _db.transaction(() async {
      await _reversePurchaseReturn(
        invoice: invoice,
        oldReturnItems: oldReturnItems,
        oldTotalReturnAmount: oldTotalReturnAmount,
      );
      await _processPurchaseReturnBody(
        invoice: invoice,
        returnItems: newReturnItems,
        totalReturnAmount: newTotalReturnAmount,
      );
    });

    unawaited(DiagnosticLogger.log(
      'PURCHASE-RETURN-EDIT',
      'edit complete invoice=${invoice.invoiceNumber} '
      'old=$oldTotalReturnAmount new=$newTotalReturnAmount',
    ));

    return newTotalReturnAmount;
  }

  /// Append-only reverse of a previously-posted purchase return so
  /// [editPurchaseReturn] can re-post fresh values atomically.
  ///
  /// Inserts compensating rows (positive stock_movements, restore-balance
  /// memo, un-refund cash transaction, flipped JE) and flips every
  /// matching original JE's `isAutoPosted=false` so the recreate step's
  /// `hasAutoPostEntry` guard doesn't dedup-skip if the new total
  /// hashes to the same `returnKey` as the old one.
  ///
  /// Cash refund is reversed only if the safe still has enough balance —
  /// otherwise we fail closed rather than going negative.
  ///
  /// MUST be called from inside an open `_db.transaction(...)`.
  Future<void> _reversePurchaseReturn({
    required PurchaseInvoiceData invoice,
    required List<PurchaseReturnItem> oldReturnItems,
    required double oldTotalReturnAmount,
  }) async {
    // 1) Stock + WAC: append compensating positive movements and reset
    //    WAC defensively (full recalc avoids drift over multi-edit cycles).
    for (final item in oldReturnItems) {
      if (item.returnQuantity <= 0) continue;
      await _db.adjustStock(
        productId: item.productId,
        warehouseId: invoice.warehouseId,
        quantity: item.returnQuantity, // POSITIVE — restore stock
        type: 'purchase_return_reverse',
        referenceType: 'purchase_return_reverse',
        referenceId: invoice.id,
      );
      await _db.recalculateProductWAC(item.productId);
    }

    // 2) Recompute the original gross / balance / cash split exactly the
    //    way _processPurchaseReturnBody computed it for the original post.
    double oldVatReturn = 0;
    for (final item in oldReturnItems) {
      if (item.returnQuantity <= 0) continue;
      if (item.taxAmount > 0 && item.originalQuantity > 0) {
        oldVatReturn +=
            item.taxAmount * (item.returnQuantity / item.originalQuantity);
      }
    }
    // ونفسُ الصيغة في العكس — وإلّا عاد ما لم يُخصَم.
    final oldSettlement = resolvePurchaseReturnSettlement(
      returnNet: oldTotalReturnAmount,
      returnVat: oldVatReturn,
      invoiceTotal: invoice.total,
      invoicePaid: invoice.paid,
    );
  // ignore: unused_local_variable
    final oldGrossReturn = oldSettlement.gross;
    final oldBalanceCorrection = oldSettlement.apPortion;
    final oldCashReturn = oldSettlement.cashPortion;

    final reverseVoucher =
        'PRET-REV-${invoice.id}-${DateTime.now().millisecondsSinceEpoch}';

    // 3) Restore supplier balance + compensating memo for the statement.
    if (oldBalanceCorrection > 0) {
      await _db.adjustPartyBalance(invoice.supplierId, oldBalanceCorrection);
      final balanceSafe =
          isBankPaymentMethod(invoice.paymentMethod)
              ? await _db.getDefaultSafeByType('bank')
              : await _db.getDefaultSafeByType('cash');
      if (balanceSafe != null) {
        await _db.into(_db.safeTransactions).insert(
              SafeTransactionsCompanion.insert(
                voucherNumber: reverseVoucher,
                safeId: balanceSafe.id,
                transactionType: 'memo',
                category: 'purchase_return_balance_reverse',
                amount: oldBalanceCorrection,
                balanceAfter: balanceSafe.balance, // memo only, no cash moved
                referenceType: const Value('purchase_return_reverse'),
                referenceId: Value(invoice.id),
                partyId: Value(invoice.supplierId),
                description: Value(
                  'إلغاء تسوية رصيد مرتجع مشتريات فاتورة '
                  '${invoice.invoiceNumber}',
                ),
              ),
            );
      }
    }

    // 4) Reverse the cash refund (if any). Fail closed if the safe is
    //    below the un-refund amount — we never want to go negative.
    if (oldCashReturn > 0) {
      final isBank =
          isBankPaymentMethod(invoice.paymentMethod);
      final safe = isBank
          ? await _db.getDefaultSafeByType('bank')
          : await _db.getDefaultSafeByType('cash');
      if (safe != null) {
        if (safe.balance + 0.001 < oldCashReturn) {
          throw Exception(
            'لا يمكن تعديل المرتجع — رصيد الخزنة (${safe.balance}) '
            'لا يكفي لاستعادة الاسترداد النقدي ($oldCashReturn). '
            'يرجى تعويض الخزنة قبل التعديل.',
          );
        }
        // 069 (D5-003): atomic delta update.
        final newBalance = safe.balance - oldCashReturn;
        await _db.adjustSafeBalance(safe.id, -oldCashReturn);
        await _db.into(_db.safeTransactions).insert(
              SafeTransactionsCompanion.insert(
                voucherNumber: reverseVoucher,
                safeId: safe.id,
                transactionType: 'payment',
                category: 'purchase_return_reverse',
                amount: oldCashReturn,
                balanceAfter: newBalance,
                referenceType: const Value('purchase_return_reverse'),
                referenceId: Value(invoice.id),
                partyId: Value(invoice.supplierId),
                description: Value(
                  'إلغاء استرداد نقدي مرتجع مشتريات فاتورة '
                  '${invoice.invoiceNumber}',
                ),
              ),
            );
      }
    }

    // 5) Reverse the journal trail. Spec 151 (F-04): autoPostPurchaseReturn now
    //    keys referenceId on the ORIGINATING invoice id, so match by that id.
    //    The previous `description LIKE '%فاتورة {number}%'` scan cross-matched
    //    substring-colliding invoices — editing invoice "12" also reversed
    //    invoice "120"'s return JE and flipped its isAutoPosted=false, killing
    //    its future dedup and leaving its GL half-reversed.
    //
    //    For each match: post a flipped (debit↔credit) compensating JE
    //    with isAutoPosted=false, description prefixed with "إلغاء".
    //    Then flip the original's isAutoPosted=false so the recreate step's
    //    guard doesn't re-match it and a subsequent edit only touches the new
    //    canonical JE.
    //
    // §٦‑٢ — ويُبطَل مستندُ المرتجع مع قيده. بلا هذا تقرأ تسويةُ ض.ق.م ضريبةَ
    // مرتجعٍ أُلغي، فينقلب الفرقُ الزائفُ إلى الاتّجاه الآخر.
    await _db.voidPurchaseReturnDocs(invoice.id);

    final originalEntries = await (_db.select(_db.journalEntries)
          ..where((e) =>
              e.referenceType.equals('purchase_return') &
              e.isAutoPosted.equals(true) &
              e.referenceId.equalsNullable(invoice.id)))
        .get();
    for (final entry in originalEntries) {
      final lines = await (_db.select(_db.journalEntryLines)
            ..where((l) => l.entryId.equals(entry.id)))
          .get();
      final reverseLines = <JournalLine>[];
      for (final line in lines) {
        reverseLines.add(JournalLine(
          accountId: line.accountId,
          debit: line.credit,
          credit: line.debit,
          description: 'إلغاء — ${line.description ?? ''}',
        ));
      }
      if (reverseLines.isNotEmpty) {
        await _db.createJournalEntry(
          description:
              'إلغاء قيد مرتجع مشتريات فاتورة ${invoice.invoiceNumber}',
          date: DateTime.now(),
          lines: reverseLines,
          referenceType: 'purchase_return',
          referenceId: invoice.id,
          isAutoPosted: false,
          costCenterId: entry.costCenterId,
        );
      }
      await (_db.update(_db.journalEntries)
            ..where((e) => e.id.equals(entry.id)))
          .write(const JournalEntriesCompanion(
        isAutoPosted: Value(false),
      ));
    }

    // 6) Reset invoice status — recreate step recomputes the right value
    //    from the new items (returned / partial_return / none).
    await _db.updatePurchaseInvoiceStatus(invoice.id, 'none');
  }

  /// Build the current-net returned items per product on [invoice] from
  /// the stock_movements ledger (purchase_return − purchase_return_reverse
  /// for this invoiceId). Returned with positive `returnQuantity` values
  /// so they're directly comparable to the user's requested edit.
  Future<List<PurchaseReturnItem>> _computeCurrentReturnedItems(
    PurchaseInvoiceData invoice,
  ) async {
    final invoiceItems = await _db.getPurchaseInvoiceItemsWithProduct(invoice.id);
    final result = <PurchaseReturnItem>[];
    for (final pi in invoiceItems) {
      final movements = await (_db.select(_db.stockMovements)
            ..where((m) =>
                m.productId.equals(pi.item.productId) &
                m.referenceId.equalsNullable(invoice.id) &
                (m.referenceType.equals('purchase_return') |
                    m.referenceType.equals('purchase_return_reverse'))))
          .get();
      double net = 0;
      for (final mv in movements) {
        net += mv.quantity;
      }
      // Returns deduct stock (negative qty) — flip to "currently returned".
      final currentReturnedQty = -net;
      if (currentReturnedQty <= 0.001) continue;
      result.add(PurchaseReturnItem(
        itemId: pi.item.id,
        productId: pi.item.productId,
        returnQuantity: currentReturnedQty,
        unitCost: pi.item.unitCost,
        taxAmount: pi.item.taxAmount,
        originalQuantity: pi.item.quantity,
        quantityInBase: 1.0,
      ));
    }
    return result;
  }

  /// True iff [a] and [b] describe the same set of (productId, qty, cost)
  /// tuples — used to short-circuit no-op edits.
  bool _returnItemsEqual(
    List<PurchaseReturnItem> a,
    List<PurchaseReturnItem> b,
  ) {
    final aActive = a.where((i) => i.returnQuantity > 0).toList();
    final bActive = b.where((i) => i.returnQuantity > 0).toList();
    if (aActive.length != bActive.length) return false;
    final am = <int, PurchaseReturnItem>{
      for (final i in aActive) i.productId: i,
    };
    for (final y in bActive) {
      final x = am[y.productId];
      if (x == null) return false;
      if ((x.returnQuantity - y.returnQuantity).abs() > 0.001) return false;
      if ((x.unitCost - y.unitCost).abs() > 0.001) return false;
    }
    return true;
  }

  /// Resolve the warehouse IDs for the current client's branch.
  /// Branch 1 (الإدارة) = full access (mirror of server) → returns empty = no filter.
  Future<List<int>> _getClientWarehouseIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final branchId = prefs.getInt('client_branch_id');
      if (branchId == null || branchId <= 1) return []; // Admin = see all
      final warehouses = await (_db.select(_db.warehouses)
        ..where((w) => w.branchId.equals(branchId))).get();
      return warehouses.map((w) => w.id).toList();
    } catch (e) {
      debugPrint('[PurchasesRepo] Error resolving client warehouse IDs: $e');
      return [];
    }
  }
}
