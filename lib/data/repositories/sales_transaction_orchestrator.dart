import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../../core/errors/app_exceptions.dart';
import '../../domain/entities/cart_item_entity.dart';
import '../../domain/entities/sync_dtos.dart';
import '../../domain/models/sales_return_refund_split.dart';
import '../../domain/repositories/sales_repository.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../core/utils/financial_utils.dart';
import '../../services/accounting_service.dart';
import '../../services/kitchen_service.dart';
import '../../services/network_service.dart';
import '../../services/client_write_interceptor.dart';
import '../../services/pos_terminal_registration_service.dart';
import '../../services/stock_shortage_policy_service.dart';
import '../../services/sync/mirror_cache_divergence_exception.dart';
import '../../services/sync/mirror_divergence_handler.dart';
import '../../core/utils/uuid_v7.dart';
import '../../core/permissions/permission_codes.dart';
import '../database/sync_interceptor.dart';
import '../database/database.dart';

/// Orchestrator responsible for creating and completing sales transactions.
///
/// Extracted from [SalesRepositoryImpl] to reduce file size and isolate
/// the complex sale-creation logic (ISS-ARCH-02).
///
/// Handles:
///  - Totals calculation
///  - Credit-limit enforcement
///  - UUID-first idempotency
///  - Client/server mode routing (fire-and-forget sync vs. local persistence)
///  - Accounting and kitchen-service integration
class SalesTransactionOrchestrator {
  final AppDatabase _db;
  final AccountingService _accountingService;
  final KitchenService _kitchenService;

  SalesTransactionOrchestrator(
    this._db,
    this._accountingService,
    this._kitchenService,
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Shared line-construction (Spec 151 · E-01)
  // ──────────────────────────────────────────────────────────────────────────

  /// Build a persisted `sales_invoice_items` companion from the **net-base**
  /// per-line VAT that [completeSalesTransaction]'s two-pass already computed —
  /// net of the line AND invoice discount, gated by `request.taxEnabled`.
  ///
  /// Spec 151 (E-01): BOTH the client/mirror cache path AND the standalone path
  /// build their lines through here so the stored line reconciles with the
  /// invoice header (`SUM(line.taxAmount) == header.tax`; `SUM(line.total) ==
  /// header.total` when there is no invoice-level discount) and, crucially,
  /// `taxEnabled == false ⇒ line.taxAmount == 0`. A later sales RETURN reads the
  /// saved line tax to reverse output-VAT; the old standalone path stored the
  /// raw, pre-discount, ungated, merge-stale `CartItemEntity.taxAmount`, so every
  /// return reversed phantom output-VAT the sale never posted.
  ///
  /// [costPrice] is stamped only on the client/mirror path (which writes via
  /// `insertSalesInvoiceWithoutStock`, bypassing the DAO's WAC auto-stamp). On
  /// the standalone path it is left absent so `SalesMutationsDao.createSalesInvoice`
  /// fills it from the product's current WAC — behaviour unchanged.
  @visibleForTesting
  static SalesInvoiceItemsCompanion buildSalesLineCompanion({
    required CartItemEntity item,
    required double netBeforeTax,
    required double netTax,
    required double netRate,
    double? costPrice,
  }) {
    return SalesInvoiceItemsCompanion.insert(
      invoiceId: 0, // set by the DAO / caller
      productId: item.productId,
      quantity: item.quantity,
      unitName: Value(item.selectedUnitName),
      quantityInBase: Value(item.quantityInBase),
      unitPrice: item.customPrice ?? item.unitPrice,
      total: FinancialUtils.round(netBeforeTax + netTax),
      costPrice: costPrice == null ? const Value.absent() : Value(costPrice),
      taxRate: Value(netRate),
      taxAmount: Value(netTax),
      note: Value(item.note),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────────────

  /// Create a new sales invoice with full orchestration (stock, accounting,
  /// kitchen service). Runs inside a Drift transaction so any accounting
  /// failure rolls back the invoice insert.
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
    // Spec 151 (E-01): net-base per-line VAT (before-tax net, tax, rate),
    // index-aligned with [items], as computed by [completeSalesTransaction]'s
    // two-pass. When supplied, each persisted line uses these net values so it
    // reconciles with the header and a return reverses only real output-VAT.
    // When null — the currently-unwired CreateSalesInvoiceUseCase path (E-05) —
    // the raw gross `CartItemEntity.taxAmount` is used verbatim, preserving that
    // path's existing behaviour.
    List<({double beforeTax, double tax, double rate})>? netLines,
  }) async {
    // Spec 002 (B1): mint the globalId here so the local insert and the
    // post-commit fire-and-forget push share the same identity. Without
    // this, non-POS invoices created on a cashier-mode client never reach
    // the server until an admin manually triggers pushLocalSalesToServer.
    final saleGlobalId = UuidV7.generate();
    // Spec 007 / FR-005: gate the server push on the broadened
    // `SyncInterceptor.isClientMode` (true for client OR mirror) so mirror
    // admins' invoices reach HQ. The legacy `NetworkService.isClient` was
    // false in mirror mode, silently dropping the entire push branch.
    final isClientMode = SyncInterceptor.isClientMode;

    // ── ح‑١ للمسار «ب»: المرتجعُ السريع في نقطة البيع ──
    //
    // مواصفة 2026-08-18. المرتجعُ عبر شاشة المرتجعات يمرّ بحارسِ
    // `processSalesReturn`، أمّا «المرتجع السريع» فيسلك هذا المسار (فاتورةٌ
    // سالبة) ولم يكن يمرّ بحارسٍ إطلاقاً. يحرسه عمليّاً `_ensureShiftOpen`
    // من شاشة نقطة البيع — **لكنّه يُتخطّى لمدير النظام عمداً** (Spec 135
    // NOTE 2)، فمديرٌ يُجري مرتجعاً سريعاً بلا ورديّة كان نقدُه يخرج بلا
    // نافذةٍ تحويه ⇒ عجزٌ وهميٌّ في ذمّة الكاشير التالي.
    //
    // وموضعُه هنا لا في `sales_mutations_dao.createSalesInvoice` **عن قصد**:
    // الخادمُ ينادي الـDAO مباشرةً (`api_sales_handler`)، ولا ورديّةَ للخادم،
    // فحارسٌ هناك كان سيرفض كلَّ مرتجعِ عميل. الأوركستريتر مسارُ الأجهزة
    // التي أمامها درجٌ — standalone والعميل — وهو تماماً من يجب أن يُحرَس.
    if (saleType == 'return') {
      final cashOut = SalesReturnRefundSplit.cashOutForNegativeInvoice(
        paid: paid,
        paymentMethod: paymentMethod,
        cashAmount: cashAmount,
        bankAmount: bankAmount,
      );
      if (cashOut > 0 &&
          await _db.resolveOpenShiftForDrawer(userId) == null) {
        throw ShiftRequiredException(cashAmount: cashOut);
      }
    }

    final invoiceId = await _db.transaction(() async {
      // 1. Generate invoice number — Cluster 027 / Issue 5 (counter mix):
      // returns share canonical SRET counter, regular sales use SINV. Without
      // this branch every quick-return ate a number from the SINV sequence
      // (gaps in the displayed sales numbering and zero return numbering).
      final isReturn = saleType == 'return';
      final invoiceNumber = await _db.generateInvoiceNumber(
        isReturn ? 'RET-' : 'INV',
      );

      // 2. Create item companions
      //
      // Spec 151 (E-01): when the POS/standalone caller supplies [netLines]
      // (via completeSalesTransaction), build each line from the net-base
      // per-line VAT so SUM(line.tax)==header.tax, SUM(line.total)==header.total
      // (no invoice discount), and taxEnabled=false ⇒ line tax 0. When null
      // (the unwired CreateSalesInvoiceUseCase path, E-05) fall back to the raw
      // gross CartItemEntity.taxAmount — behaviour unchanged for that dead path.
      final itemCompanions = <SalesInvoiceItemsCompanion>[];
      final useNetLines = netLines != null && netLines.length == items.length;
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        if (useNetLines) {
          final net = netLines[i];
          itemCompanions.add(buildSalesLineCompanion(
            item: item,
            netBeforeTax: net.beforeTax,
            netTax: net.tax,
            netRate: net.rate,
          ));
        } else {
          itemCompanions.add(SalesInvoiceItemsCompanion.insert(
            invoiceId: 0, // Will be set by DAO
            productId: item.productId,
            quantity: item.quantity,
            unitName: Value(item.selectedUnitName),
            quantityInBase: Value(item.quantityInBase),
            unitPrice: item.customPrice ?? item.unitPrice,
            total: (item.customPrice ?? item.unitPrice) * item.quantity +
                item.taxAmount,
            taxRate: Value(item.taxRate),
            taxAmount: Value(item.taxAmount),
            note: Value(item.note),
          ));
        }
      }

      // 3. Persist invoice via DAO
      final invoiceId = await _db.createSalesInvoice(
        globalId: saleGlobalId,
        invoiceNumber: invoiceNumber,
        customerId: customerId,
        warehouseId: warehouseId,
        userId: userId,
        subtotal: subtotal,
        discount: discount,
        tax: tax,
        total: total,
        paid: paid,
        paymentMethod: paymentMethod,
        items: itemCompanions,
        saleType: saleType ?? 'default',
        costCenterId: costCenterId,
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
        platformOrderNumber: platformOrderNumber,
        adhocCustomerName: adhocCustomerName,
        adhocCustomerPhone: adhocCustomerPhone,
        adhocCustomerNote: adhocCustomerNote,
        // نفسُ شرطِ القيد في آخر هذه الدالة بالضبط: حين نصدره بأنفسنا — ومعنا
        // `cogsBreakdown` من الخصم التلقائيّ في الخطوة ٤٫٥ — لا يصدره الـDAO
        // قبلنا بلا تكلفة. اقرا `SalesMutationsDao.createSalesInvoice →
        // deferAutoPost`.
        deferAutoPost: (saleType ?? 'default') != 'return' && !isClientMode,
      );

      // Fetch the generated invoice record
      final invoice = await (_db.select(_db.salesInvoices)
            ..where((s) => s.id.equals(invoiceId)))
          .getSingleOrNull();
      if (invoice == null) return invoiceId; // U-04: Safety guard

      // 4. Kitchen Service (non-fatal)
      try {
        await _kitchenService.generateKitchenWorkOrder(
          invoiceId: invoiceId,
          tableName: adhocCustomerName ?? platformOrderNumber,
          items: itemCompanions,
          notes: notes,
        );
      } catch (e) {
        debugPrint('[KitchenService] فشل إنشاء أمر المطبخ للفاتورة $invoiceId: $e');
      }

      // 5. Accounting — ATOMIC with invoice (P0-01 fix)
      // No try/catch: an accounting failure MUST propagate to rollback the
      // enclosing transaction so the invoice is never committed without a GL
      // entry.
      final savedItems = await (_db.select(_db.salesInvoiceItems)
            ..where((i) => i.invoiceId.equals(invoiceId)))
          .get();

      final warehouse = await _db.getWarehouseById(warehouseId);
      final branchId = warehouse?.branchId;

      String? branchName;
      String? regionName;
      if (branchId != null) {
        final branchRow = await (_db.select(_db.branches)
              ..where((b) => b.id.equals(branchId))
              ..limit(1))
            .getSingleOrNull();
        branchName = branchRow?.name;
        if (branchRow?.regionId != null) {
          final regionRow = await (_db.select(_db.regions)
                ..where((r) => r.id.equals(branchRow!.regionId!))
                ..limit(1))
            .getSingleOrNull();
          regionName = regionRow?.name;
        }
      }

      // 4.5 [Feature 009 / T018] Auto-deplete raw materials for any line
      // whose product has an active auto-deplete BOM. Gated on
      // `!isClientMode` per R4 / Constitution III: in client/mirror mode
      // the SERVER runs the auto-deplete (T020) so we don't double-deduct.
      // The shortage-policy string is currently hard-coded to
      // 'allow_negative' (the schema default); T025 (US2) will resolve it
      // from StockShortagePolicyService.
      List<CogsLine>? cogsBreakdown;
      // Invoice lines whose cost the breakdown already covers — see
      // SaleAutoDepleteResult.coveredSaleItemIds.
      Set<int>? autoDepletedItemIds;
      // `saleType != 'return'` mirrors the guard on the JE at the bottom of
      // this method. A return runs through this same DAO with the quantities
      // POSITIVE, so auto-deplete would consume the raw materials A SECOND
      // TIME instead of giving them back: the finished item is restored to
      // stock and its inputs are deducted again. Returning a BOM meal ate
      // another meal's worth of ingredients.
      //
      // Reversal is a different operation with its own implementation —
      // `reverseSaleConsumption` (manufacturing_dao), which the returns
      // dialog already calls via returns_repository_impl. Auto-deplete simply
      // has no role on a return.
      final isReturnSale = saleType == 'return';
      if (!isClientMode && !isReturnSale) {
        final saleLineRefs = savedItems
            .map((item) => SaleLineRef(
                  saleItemId: item.id,
                  productId: item.productId,
                  qty: item.quantity,
                  warehouseId: warehouseId,
                ))
            .toList();
        // Feature 009 / T025: resolve the active shortage policy via the
        // three-tier service (per-terminal → per-branch → global default).
        // The legacy `enable_negative_sales` toggle is now a *fallback*
        // only — if the admin hasn't picked an explicit per-install policy
        // yet, we honour the old toggle so existing installs keep their
        // current behaviour (Constitution I). New deployments rely on the
        // settings-screen entry from T027.
        final terminalId =
            PosTerminalRegistrationService.instance.getCurrentTerminalId();
        final resolvedPolicy =
            await StockShortagePolicyService.resolveWith(
          get: _db.getSettingValue,
          terminalId: terminalId,
          branchId: branchId,
        );
        // If the admin hasn't configured ANY policy yet (resolver returned
        // the hard-coded default), keep honouring the legacy toggle so
        // existing installs see no behaviour change at upgrade time.
        var policyWire = resolvedPolicy.wireName;
        if (resolvedPolicy == StockShortagePolicyService.defaultPolicy) {
          final globalRaw =
              await _db.getSettingValue('stock_shortage_policy');
          if (globalRaw == null || globalRaw.isEmpty) {
            final negativeSalesRaw =
                await _db.getSettingValue('enable_negative_sales');
            policyWire =
                (negativeSalesRaw == 'true') ? 'allow_negative' : 'block';
          }
        }
        try {
          final result = await _db.applyAutoDepleteForSale(
            saleInvoiceId: invoiceId,
            items: saleLineRefs,
            branchId: branchId,
            shortagePolicy: policyWire,
            saleGlobalId: saleGlobalId,
            posTerminalId: terminalId,
          );
          cogsBreakdown = result.cogsBreakdown;
          autoDepletedItemIds = result.coveredSaleItemIds;
        } on InsufficientStockException catch (e) {
          // Feature 009 / T026 (FR-016): rewrap into a plain Exception
          // carrying a clean Arabic message so the POS / sales-invoice
          // screen's generic catch shows a user-friendly toast instead
          // of leaking the type name. The transaction rolls back via
          // the rethrow.
          final shortages = e.shortages;
          final lines = (shortages == null || shortages.isEmpty)
              ? e.message
              : shortages.entries
                  .map((s) =>
                      '• ${s.value.name}: متوفر ${s.value.available}، مطلوب ${s.value.required.toStringAsFixed(2)}')
                  .join('\n');
          throw Exception(
            'تعذّر إتمام الفاتورة بسبب نقص الخامات:\n$lines',
          );
        } on BomCycleException catch (e) {
          throw Exception(
            'دورة فى تعريف قائمة الخامات (BOM) — راجع الإعدادات. '
            'المسار: ${e.path.join(' → ')}',
          );
        } on InvalidPolicyException catch (e) {
          throw Exception(e.message);
        }
      }

      // Cluster 023 / Issue 1 — for saleType='return' the DAO already
      // posted the JE via autoPostSalesReturn (correct contra-revenue
      // direction). Calling generateSalesAccountingEntry here would post
      // a second, wrong-direction JE (Dr Cash / Cr Sales) that the dedup
      // guard might keep instead. So skip the regular sales JE for returns.
      //
      // ALSO skip in client/mirror mode — the mirror of the `!isClientMode`
      // auto-deplete gate above (R4 / Constitution III): "the SERVER runs it
      // so we don't double-post". In client mode the server autoposts the
      // sale's revenue JE when it receives the submitSale POST below
      // (api_sales_handler → autoPostCashSale, keyed on referenceType='sale'
      // + a DETERMINISTIC globalId). This local factory JE instead used
      // referenceType='sales_invoice' + a RANDOM globalId + the client-local
      // invoiceId, so it never deduped against the server's JE and BOTH
      // revenue entries survived in the server GL — the GL-sourced dashboard
      // "revenue" card then read ~2× the invoice-based sales screen. The
      // authoritative JE comes back via DeltaPull, exactly like the POS path
      // (insertSalesInvoiceWithoutStock, which never posts locally).
      if (saleType != 'return' && !isClientMode) {
        await _accountingService.generateSalesAccountingEntry(
          invoiceId: invoiceId,
          invNumber: invoice.invoiceNumber,
          tax: tax,
          paid: paid,
          remaining: total - paid,
          paymentMethod: paymentMethod,
          deliveryFee: deliveryFee,
          items: savedItems,
          customerId: invoice.customerId,
          costCenterId: costCenterId,
          branchId: branchId,
          branchName: branchName,
          regionName: regionName,
          invoiceDate: invoice.invoiceDate,
          cogsBreakdown: cogsBreakdown,
          autoDepletedItemIds: autoDepletedItemIds,
        );
      }

      return invoiceId;
    });

    // Spec 002 (B1): fire-and-forget push to server in client mode so a
    // non-POS sales invoice (e.g. a credit sale created from the regular
    // sales screen) reaches the server immediately, without waiting for
    // an admin to open the invoices screen and trigger pushLocalSalesToServer.
    // Mirrors the POS path's submit (see completeSalesTransaction).
    if (isClientMode) {
      try {
        final invoice = await (_db.select(_db.salesInvoices)
              ..where((s) => s.id.equals(invoiceId)))
            .getSingleOrNull();
        if (invoice != null) {
          final syncItems = <SyncSaleItem>[];
          for (final item in items) {
            final itemSubtotal =
                (item.customPrice ?? item.unitPrice) * item.quantity;
            final itemDiscount = itemSubtotal * (item.discountPercent / 100);
            final product = await _db.getProductById(item.productId);
            syncItems.add(SyncSaleItem(
              productId: item.productId,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              discount: item.discountPercent,
              taxRate: 0,
              taxAmount: item.taxAmount,
              total: itemSubtotal - itemDiscount + item.taxAmount,
              note: item.note,
              costPrice: product?.costPrice ?? 0,
              quantityInBase: item.quantityInBase,
            ));
          }
          // Look up cashier identity for server-side user resolution
          // (same pattern as completeSalesTransaction lines 286-293).
          String? createdByUsername;
          String? userGlobalId;
          try {
            final cashier = await (_db.select(_db.users)
                  ..where((u) => u.id.equals(userId))
                  ..limit(1))
                .getSingleOrNull();
            createdByUsername = cashier?.username;
            userGlobalId = cashier?.globalId;
          } catch (_) {}

          // Spec 117 (Bug G) — resolve branchId من warehouse للـ syncRequest.
          // قبلاً كان مفقوداً من الـ payload فالـ mirror يرسل branchId=null
          // فالـ server يحفظ الفاتورة بدون فرع → غير منسوبة لـ filters الفروع.
          int? resolvedBranchIdForSync;
          try {
            final wh = await _db.getWarehouseById(warehouseId);
            resolvedBranchIdForSync = wh?.branchId;
          } catch (_) {}

          final syncRequest = {
            'globalId': saleGlobalId,
            'invoiceNumber': invoice.invoiceNumber,
            'clientIpSuffix': 'CL',
            'customerId': customerId,
            'warehouseId': warehouseId,
            'branchId': resolvedBranchIdForSync,
            'userId': userId,
            'createdByUsername': ?createdByUsername,
            if (userGlobalId != null && userGlobalId.isNotEmpty)
              'userGlobalId': userGlobalId,
            'costCenterId': costCenterId,
            'subtotal': subtotal,
            'discount': discount,
            'tax': tax,
            'total': total,
            'paid': paid,
            'paymentMethod': paymentMethod,
            'deliveryFee': deliveryFee,
            'notes': notes,
            'cashAmount': cashAmount,
            'bankAmount': bankAmount,
            'saleType': saleType,
            'items': syncItems.map((i) => i.toJson()).toList(),
            'invoiceDate': invoice.invoiceDate.toIso8601String(),
            'adhocCustomerName': adhocCustomerName,
            'adhocCustomerPhone': adhocCustomerPhone,
            'adhocCustomerNote': adhocCustomerNote,
            'cashSafeId': cashSafeId,
            'bankSafeId': bankSafeId,
            'clickSafeId': clickSafeId,
            'clickAmount': clickAmount,
            'deliveryCompanyId': deliveryCompanyId,
            'courierId': courierId,
            'deliveryStatus': deliveryStatus,
          };

          debugPrint(
              '[SALE-SYNC] Submitting non-POS sale to server (fire-and-forget)...');
          unawaited(DiagnosticLogger.log('SALE-SYNC',
              'submit non-POS invoice=${invoice.invoiceNumber} userId=$userId '
              'total=$total globalId=$saleGlobalId'));
          unawaited(ClientWriteInterceptor.submitSale(syncRequest).then((serverId) {
            debugPrint('[SALE-SYNC] Server response: serverId=$serverId');
            unawaited(DiagnosticLogger.log('SALE-SYNC',
                serverId != null
                    ? '✓ accepted non-POS invoice=${invoice.invoiceNumber} → '
                        'serverId=$serverId'
                    : '⏳ queued offline non-POS invoice=${invoice.invoiceNumber} '
                        '(server unreachable, will retry from sync_outbox)'));
          }).catchError((e) {
            debugPrint('[SALE-SYNC] Server sync failed (queued in outbox): $e');
            unawaited(DiagnosticLogger.log('SALE-SYNC',
                '❌ sync error non-POS invoice=${invoice.invoiceNumber}: $e'));
          }));
        }
      } catch (e) {
        debugPrint('[SALE-SYNC] Non-POS sync setup failed: $e');
        unawaited(DiagnosticLogger.log('SALE-SYNC',
            '❌ non-POS setup failed invoiceId=$invoiceId: $e'));
      }
    }

    return invoiceId;
  }

  /// Complete a full sales transaction — validates, calculates totals, enforces
  /// credit limits, then routes to either the client-sync path or the local
  /// standalone path.
  Future<SaleResult> completeSalesTransaction(SaleRequest request) async {
    // Spec 007 / FR-001, FR-005: use the broadened predicate so mirror-mode
    // sales also fire the server push. Diagnostics below still surface the
    // raw NetworkService mode to keep operator-facing logs unambiguous.
    final isClientMode = SyncInterceptor.isClientMode;
    final syncInterceptorActive = SyncInterceptor.isClientMode;
    debugPrint('[SALE] Mode: ${NetworkService.instance.mode}, isClient: $isClientMode, '
        'syncInterceptor: $syncInterceptorActive, '
        'interceptorInstance: ${SyncInterceptor.instance != null}');

    // Spec 131 (FR-005) — sale-time pre-flight check. On mirror/client mode
    // verify that every direct master-data foreign key referenced by the
    // sale exists in the local cache. Any miss throws
    // MirrorCacheDivergenceException, which the catch at the top of this
    // method converts to the Fatal-screen path (Spec 131 FR-006). Server
    // and standalone modes bypass — they're authoritative against their
    // own DB.
    await _preflightSaleParity(request);

    // 1. Calculate Totals (once for both Sync and Local)
    // Cluster 034 follow-up — every monetary value goes through
    // FinancialUtils.round (half-up at AppConstants.decimalPlaces) so
    // accumulated floating-point drift can't leak into the DB or the
    // server submit. Without rounding, totals like `2.1033599999999995`
    // appeared in the field log instead of `2.10`, producing piastre-
    // level mismatches across invoices and POS receipts.
    double subtotal = 0;
    double totalTax = 0;
    double totalDiscountValue = 0;

    final syncItems = <SyncSaleItem>[];

    // Spec 137 (BUG-C02 / BUG-H01): two-pass tax. PASS 1 = line subtotals +
    // line discounts. Tax is deferred to PASS 2 so it can be computed on the
    // net AFTER the invoice-level discount (policy) and gated by
    // request.taxEnabled. item.taxAmount is intentionally NOT a tax source here
    // — it is a gross, merge-stale UI field.
    final lineSubtotals = <double>[];
    final lineDiscounts = <double>[];
    for (final item in request.items) {
      final itemSubtotal = FinancialUtils.round(
          (item.customPrice ?? item.unitPrice) * item.quantity);
      final itemDiscount = FinancialUtils.round(
          itemSubtotal * (item.discountPercent / 100));
      lineSubtotals.add(itemSubtotal);
      lineDiscounts.add(itemDiscount);
      subtotal += itemSubtotal;
      totalDiscountValue += itemDiscount;
    }

    subtotal = FinancialUtils.round(subtotal);
    totalDiscountValue = FinancialUtils.round(totalDiscountValue);

    // Invoice-level discount on the post-line-discount base.
    final afterItemDiscounts = subtotal - totalDiscountValue;
    final invoiceDiscountAmount = FinancialUtils.round(
        afterItemDiscounts * (request.discountPercent / 100));
    final discountRatio = afterItemDiscounts > 0
        ? ((afterItemDiscounts - invoiceDiscountAmount) / afterItemDiscounts)
        : 0.0;

    // PASS 2: per-line VAT on net-after-all-discounts, gated by taxEnabled.
    // The per-line results are retained so the persisted sales_invoice_items
    // rows use the SAME net-base values as the header and the SyncSaleItem
    // payload (Spec 137 P2: SUM(line.tax) == header.tax).
    final perLineTax = <double>[];
    final perLineBeforeTax = <double>[];
    final perLineRate = <double>[];
    for (var i = 0; i < request.items.length; i++) {
      final item = request.items[i];
      final lineBeforeTax = lineSubtotals[i] - lineDiscounts[i];
      final lineNet = lineBeforeTax * discountRatio;
      final lineRate = request.taxEnabled
          ? (item.taxRate > 0 ? item.taxRate : request.taxPercent)
          : 0.0;
      final lineTax = FinancialUtils.round(lineNet * (lineRate / 100));
      totalTax += lineTax;
      perLineTax.add(lineTax);
      perLineBeforeTax.add(FinancialUtils.round(lineBeforeTax));
      perLineRate.add(lineRate);

      // ALWAYS build sync items in client mode (even if SyncService is null)
      if (isClientMode) {
        // M-07 FIX: Look up actual cost price instead of hardcoding 0
        final product = await _db.getProductById(item.productId);
        syncItems.add(SyncSaleItem(
          productId: item.productId,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          discount: item.discountPercent,
          taxRate: lineRate,
          taxAmount: lineTax,
          total: FinancialUtils.round(lineBeforeTax + lineTax),
          note: item.note, // POS-6 FIX: Include item notes
          costPrice: product?.costPrice ?? 0, // M-07 FIX: Use actual WAC cost price
          quantityInBase: item.quantityInBase,
        ));
      }
    }

    totalTax = FinancialUtils.round(totalTax);

    final finalDiscount = FinancialUtils.round(
        totalDiscountValue + invoiceDiscountAmount);
    final finalTotal = FinancialUtils.round(
        subtotal - finalDiscount + totalTax + request.deliveryFee);

    // 2a. Cluster 035 / Issue 3 — business rule: sales to a delivery-company
    // party are ALWAYS credit/آجل, regardless of what the cashier typed in the
    // payment-method dropdown. Without this override, a delivery_company
    // accidentally rung up as "cash" creates a phantom cash receipt in the
    // company's ledger while the real-world balance still owes the merchant
    // the full amount. The rule was confirmed by the user as "متفق عليه من
    // البداية" on 2026-05-12 (memory: delivery_companies_credit_default).
    //
    // Implemented as local `effective*` variables instead of mutating
    // SaleRequest (which is immutable) — every reference below to
    // payment/paid/cash/bank/click now flows through these vars.
    String effectivePaymentMethod = request.paymentMethod;
    double effectivePaid = request.paidAmount;
    double? effectiveCash = request.cashAmount;
    double? effectiveBank = request.bankAmount;
    double? effectiveClick = request.clickAmount;

    // 2b. Credit limit enforcement + delivery-company override.
    // Merged into a single block to avoid double-fetching the party.
    if (!request.isReturn && request.customerId != null) {
      final customer = await _db.getPartyById(request.customerId!);

      if (customer != null && customer.isDeliveryCompany) {
        unawaited(DiagnosticLogger.log(
            'SALE-POLICY',
            'forced credit for delivery_company customerId=${request.customerId} '
                'name=${customer.name} '
                '(original paymentMethod=${request.paymentMethod} '
                'paid=${request.paidAmount})'));
        effectivePaymentMethod = 'credit';
        effectivePaid = 0;
        effectiveCash = 0;
        effectiveBank = 0;
        effectiveClick = 0;
      }

      // Use the effective paid value so the credit-limit check applies
      // after the delivery-company override (otherwise paid==full bypasses
      // the limit entirely).
      final remaining = finalTotal - effectivePaid;
      if (remaining > 0.01) {
        if (customer != null && customer.creditLimit > 0) {
          final projected = customer.balance + remaining;
          if (projected > customer.creditLimit) {
            // 062 (D1-004): allow override for users holding
            // overrideCreditLimit; emit CREDIT-OVERRIDE log.
            final hasOverride = await _db.permissionEnforcer.hasCriticalOp(
              request.userId, PermissionCodes.overrideCreditLimit);
            if (!hasOverride) {
              return SaleResult.failure(
                'تجاوز العميل "${customer.name}" الحد الائتمانى المسموح به '
                '(${customer.creditLimit.toStringAsFixed(2)}). '
                'الرصيد المتوقع بعد الفاتورة: ${projected.toStringAsFixed(2)}',
              );
            }
            unawaited(DiagnosticLogger.log('CREDIT-OVERRIDE',
                'orchestrator user=${request.userId} '
                'customer=${customer.id} projected=$projected '
                'limit=${customer.creditLimit}'));
          }
        }
      }
    }

    // 3. UUID-First — mint one globalId shared between server and local cache
    final saleGlobalId = UuidV7.generate();

    // 4. Client Mode: fire-and-forget sync to server
    if (isClientMode) {
      // Cluster 027 / Issue 5 — same branching as the standalone path above:
      // returns advance the SRET counter, sales advance the POS counter.
      final isReturn = request.isReturn || request.saleType == 'return';
      // 066 (D5-001): generateInvoiceNumber must run inside a transaction so
      // the counter advance is rollback-safe. The number ends up only in the
      // server submit JSON (no local insert here), but the wrap still
      // protects the future case where the JSON build throws and we need to
      // retry without burning a number.
      final localInvoiceNumber = request.invoiceNumber ??
          await _db.transaction(
            () => _db.generateInvoiceNumber(isReturn ? 'RET-' : 'Receipt'),
          );

      // P5 (Issue #6): Look up the cashier's username/globalId so the server
      // can resolve the user even when client/server IDs diverge — typical
      // when a cashier was created on the client (locally minted id=2) and
      // the server hasn't seen them yet. Without this fallback, the server's
      // _resolveUserId returns null and the sale either gets attributed to
      // admin or fails outright. Username is the deterministic key.
      String? createdByUsername;
      String? userGlobalId;
      try {
        final cashier = await (_db.select(_db.users)
              ..where((u) => u.id.equals(request.userId))
              ..limit(1))
            .getSingleOrNull();
        createdByUsername = cashier?.username;
        userGlobalId = cashier?.globalId;
      } catch (_) {}

      final syncRequest = {
        'globalId': saleGlobalId,
        'invoiceNumber': localInvoiceNumber,
        'clientIpSuffix': 'CL',
        'customerId': request.customerId,
        'warehouseId': request.warehouseId,
        'userId': request.userId,
        'createdByUsername': ?createdByUsername,
        if (userGlobalId != null && userGlobalId.isNotEmpty)
          'userGlobalId': userGlobalId,
        'branchId': request.branchId,
        'costCenterId': request.costCenterId,
        'subtotal': subtotal,
        'discount': finalDiscount,
        'tax': totalTax,
        'total': finalTotal,
        'paid': effectivePaid,
        'paymentMethod': effectivePaymentMethod,
        'deliveryFee': request.deliveryFee,
        'notes': request.notes,
        'cashAmount': effectiveCash,
        'bankAmount': effectiveBank,
        'saleType': request.saleType,
        'items': syncItems.map((i) => i.toJson()).toList(),
        'invoiceDate': DateTime.now().toIso8601String(),
        'adhocCustomerName': request.adhocCustomerName,
        'adhocCustomerPhone': request.adhocCustomerPhone,
        'adhocCustomerNote': request.adhocCustomerNote,
        'cashSafeId': request.cashSafeId,
        'bankSafeId': request.bankSafeId,
        'clickSafeId': request.clickSafeId,
        'clickAmount': effectiveClick,
        'deliveryCompanyId': request.deliveryCompanyId,
        'courierId': request.courierId,
        'deliveryStatus': request.deliveryStatus,
      };

      // IMPORTANT: Do NOT await — local save must never block on network latency.
      // But DO log the outcome to DiagnosticLogger so the operator can confirm
      // whether each invoice actually reached the server. The user reported
      // invoices saving locally but never appearing on the server, and the
      // previous debugPrint-only logging was invisible in release builds.
      debugPrint('[SALE-SYNC] Submitting sale to server...');
      unawaited(DiagnosticLogger.log('SALE-SYNC',
          'submit invoice=$localInvoiceNumber userId=${request.userId} '
          'total=$finalTotal globalId=$saleGlobalId'));
      // Local persistence (step 5, below) runs AFTER this point, which is what
      // lets the mirror branch abort cleanly: a rejected sale leaves no local
      // invoice at all. Client mode keeps fire-and-forget — the cashier must
      // be able to sell while the server is down.
      await ClientWriteInterceptor.dispatchWrite(
        () => ClientWriteInterceptor.submitSale(syncRequest).then((serverId) {
          debugPrint('[SALE-SYNC] Server response: serverId=$serverId');
          unawaited(DiagnosticLogger.log('SALE-SYNC',
              serverId != null
                  ? '✓ accepted invoice=$localInvoiceNumber → serverId=$serverId'
                  : '⏳ queued offline invoice=$localInvoiceNumber '
                      '(server unreachable, will retry from sync_outbox)'));
          return serverId;
        }),
        tag: 'SALE-SYNC',
      );
    } else {
      // Not in client mode — make this visible too. If the operator
      // expected client mode but isClientMode came back false, the sale
      // would silently never push (the symptom: "saved locally but didn't
      // reach the server"). With this log, the cause is unambiguous.
      unawaited(DiagnosticLogger.log('SALE-SYNC',
          '⚠ NOT client mode — sale stays local '
          '(networkMode=${NetworkService.instance.mode}, '
          'syncInterceptor=$syncInterceptorActive, '
          'instance=${SyncInterceptor.instance != null})'));
    }

    // 5. Local Persistence
    // Cluster 034 follow-up — every step here is logged to diagnostic.log
    // because the field operator reported "invoice didn't save on client"
    // and the original code only emitted to debugPrint (invisible in
    // release builds). We need to know exactly where the local save fails
    // so cross-branch / FK / id-collision issues can be diagnosed.
    unawaited(DiagnosticLogger.log('SALE-LOCAL',
        'starting local persistence isClient=$isClientMode '
        'warehouseId=${request.warehouseId} requestBranchId=${request.branchId} '
        'globalId=$saleGlobalId'));
    try {
      int invoiceId;
      if (isClientMode) {
        // Build lightweight companions for local cache only
        // Cluster 027 / Issue 5 — same branching as above so the local
        // cache mirrors the prefix the server will assign.
        final isReturn = request.isReturn || request.saleType == 'return';
        // 066 (D5-001): wrap counter advance + downstream local insert in
        // one outer transaction. insertSalesInvoiceWithoutStock has its own
        // inner transaction() — Drift makes that a SAVEPOINT under this
        // outer txn so counter + invoice + items roll back together.
        invoiceId = await _db.transaction(() async {
        final invoiceNumber =
            await _db.generateInvoiceNumber(isReturn ? 'RET-' : 'INV');
        final remaining = finalTotal - effectivePaid;
        final status = remaining <= 0.01 ? 'completed' : 'pending';

        final itemCompanions = <SalesInvoiceItemsCompanion>[];
        for (var i = 0; i < request.items.length; i++) {
          final item = request.items[i];
          // Feature 016 — stamp cost_price from the local product WAC at
          // sale time, exactly like SalesMutationsDao.createSalesInvoice
          // does on the standalone path. Without this, the mirror's
          // sales_invoice_items.cost_price stays at 0, the analytics
          // COGS query (`SUM(quantity * cost_price)`) returns 0, and
          // صافي الربح comes out inflated by the missing COGS.
          //
          // Per-base-unit convention: cost_price is the WAC of ONE base
          // unit (the same units `quantity` is stored in after unit
          // conversion). The standalone DAO copies `product.costPrice`
          // verbatim with no multiplier — match that exactly.
          final product = await _db.getProductById(item.productId);
          final localWac = product?.costPrice ?? 0.0;

          // Spec 137 P2 / Spec 151 E-01: persist the net-base per-line
          // tax/rate/total from the two-pass (matching the header + SyncSaleItem),
          // NOT the stale gross item.taxAmount, so SUM(line.tax) reconciles with
          // the invoice header. Shared with the standalone path via
          // buildSalesLineCompanion; the client cache path additionally stamps
          // the local WAC because it writes through insertSalesInvoiceWithoutStock
          // (no DAO WAC auto-stamp).
          itemCompanions.add(buildSalesLineCompanion(
            item: item,
            netBeforeTax: perLineBeforeTax[i],
            netTax: perLineTax[i],
            netRate: perLineRate[i],
            costPrice: localWac,
          ));
        }

        // L3 (2026-04-28): Resolve branchId for direct stamping on the invoice.
        // Prefer the request's branchId (if explicitly set), otherwise derive
        // from the warehouse — so invoices saved offline still carry the
        // correct branch even when the request didn't specify one.
        //
        // Cluster 034 follow-up — also detect cross-branch mismatch (cashier's
        // branch differs from warehouse's branch). Server rejects this combo
        // with `Cross-branch operation denied`, so log it loudly here. The
        // local save still proceeds with the warehouse's branch (the only
        // one that satisfies local FK + matches what the server expects),
        // preventing data loss when the cashier's user_branch_access points
        // at a different branch than the POS terminal's warehouse.
        int? resolvedBranchId = request.branchId;
        int? warehouseBranchId;
        try {
          final wh = await _db.getWarehouseById(request.warehouseId);
          warehouseBranchId = wh?.branchId;
        } catch (_) {/* non-fatal */}
        if (resolvedBranchId == null) {
          resolvedBranchId = warehouseBranchId;
        } else if (warehouseBranchId != null &&
            warehouseBranchId != resolvedBranchId) {
          // Mismatch — log loudly. Prefer the warehouse's branch for the
          // saved row so it matches the server's authz check on retry.
          unawaited(DiagnosticLogger.log('SALE-LOCAL',
              '⚠ branch mismatch — request says branchId=$resolvedBranchId '
              'but warehouse ${request.warehouseId} belongs to branch '
              '$warehouseBranchId. Using warehouse branch to match server.'));
          resolvedBranchId = warehouseBranchId;
        }

        unawaited(DiagnosticLogger.log('SALE-LOCAL',
            'inserting invoice=$invoiceNumber items=${itemCompanions.length} '
            'resolvedBranchId=$resolvedBranchId total=$finalTotal '
            'status=$status'));

        final localInvoiceId = await _db.insertSalesInvoiceWithoutStock(
          invoice: SalesInvoicesCompanion(
            globalId: Value(saleGlobalId),
            invoiceNumber: Value(invoiceNumber),
            customerId: Value(request.customerId),
            warehouseId: Value(request.warehouseId),
            branchId: Value(resolvedBranchId),
            userId: Value(request.userId),
            subtotal: Value(subtotal),
            discount: Value(finalDiscount),
            tax: Value(totalTax),
            total: Value(finalTotal),
            paid: Value(effectivePaid),
            status: Value(status),
            paymentMethod: Value(effectivePaymentMethod),
            notes: Value(request.notes),
            adhocCustomerName: Value(request.adhocCustomerName),
            adhocCustomerPhone: Value(request.adhocCustomerPhone),
            adhocCustomerNote: Value(request.adhocCustomerNote),
            invoiceDate: Value(DateTime.now()),
            deliveryFee: Value(request.deliveryFee),
            costCenterId: Value(request.costCenterId),
            saleType: Value(request.saleType ?? 'default'),
            originClientId: Value(_deviceName()),
          ),
          items: itemCompanions,
        );
        return localInvoiceId;
        }); // 066: end client-mode atomic txn
      } else {
        // Spec 151 (E-01): thread the net-base per-line VAT (already net of the
        // line + invoice discount and gated by taxEnabled by the two-pass above)
        // into the standalone line build so SUM(line.tax)==header.tax and
        // taxEnabled=false ⇒ line tax 0. Previously this path passed raw
        // request.items, persisting the gross, pre-discount, ungated
        // CartItemEntity.taxAmount — which every sales RETURN then reversed as
        // phantom output-VAT the sale never posted (orphan negative VAT in GL).
        final netLines = [
          for (var i = 0; i < request.items.length; i++)
            (
              beforeTax: perLineBeforeTax[i],
              tax: perLineTax[i],
              rate: perLineRate[i],
            ),
        ];
        invoiceId = await createSalesInvoice(
          customerId: request.customerId,
          warehouseId: request.warehouseId,
          userId: request.userId,
          subtotal: subtotal,
          discount: finalDiscount,
          tax: totalTax,
          total: finalTotal,
          paid: effectivePaid,
          paymentMethod: effectivePaymentMethod,
          items: request.items,
          netLines: netLines,
          cashAmount: effectiveCash,
          bankAmount: effectiveBank,
          clickAmount: effectiveClick,
          cashSafeId: request.cashSafeId,
          bankSafeId: request.bankSafeId,
          clickSafeId: request.clickSafeId,
          deliveryFee: request.deliveryFee,
          deliveryCompanyId: request.deliveryCompanyId,
          courierId: request.courierId,
          deliveryStatus: request.deliveryStatus,
          notes: request.notes,
          saleType: request.saleType,
          costCenterId: request.costCenterId,
          platformOrderNumber: request.platformOrderNumber,
          adhocCustomerName: request.adhocCustomerName,
          adhocCustomerPhone: request.adhocCustomerPhone,
          adhocCustomerNote: request.adhocCustomerNote,
        );
      }

      unawaited(DiagnosticLogger.log('SALE-LOCAL',
          '✓ insert returned invoiceId=$invoiceId — reading back'));
      // Spec 136 ISS-12 — time the readback. A field smoke showed a ~7s gap
      // between "insert returned" and "complete" on standalone with FEW
      // products, which the insert (252ms, single transaction) doesn't
      // explain. This pins whether the readback select itself is slow (DB
      // executor blocked by post-commit stream re-queries) vs. something else.
      final rbSw = Stopwatch()..start();
      final invoice = await (_db.select(_db.salesInvoices)
            ..where((s) => s.id.equals(invoiceId)))
          .getSingleOrNull();
      rbSw.stop();
      if (invoice == null) {
        unawaited(DiagnosticLogger.log('SALE-LOCAL',
            '❌ readback returned null for invoiceId=$invoiceId'));
        return SaleResult.failure('لم يتم العثور على الفاتورة بعد الحفظ');
      }
      unawaited(DiagnosticLogger.log('SALE-LOCAL',
          '✓ local persistence complete invoiceNumber=${invoice.invoiceNumber} '
          'readbackMs=${rbSw.elapsedMilliseconds}'));

      // Fire-and-forget: don't block the sale on activity logging
      _db.logActivity(
        userId: request.userId,
        userName: 'System',
        action: 'create',
        entityType: 'invoice',
        entityId: invoiceId,
        description: 'إنشاء فاتورة مبيعات ${invoice.invoiceNumber}',
        amount: finalTotal,
      );

      return SaleResult.success(
        invoiceId: invoiceId,
        invoiceNumber: invoice.invoiceNumber,
        totals: null,
      );
    } on MirrorCacheDivergenceException catch (e) {
      // Spec 131 (FR-006) — pre-flight raised divergence. Surface the
      // Fatal screen immediately (no 3-retry policy applies on this path)
      // and propagate a friendly error so callers can stop their UI flow.
      unawaited(MirrorDivergenceHandler.surface(
        exception: e,
        origin: 'pre-flight',
      ));
      return SaleResult.failure(
        'تعارض فى بيانات المرآة — تم فتح شاشة استعادة المزامنة. '
        'سيتم إعادة المحاولة بعد إعادة المزامنة مع السيرفر.',
      );
    } catch (e, st) {
      // Spec 131 (FR-006) — server-side "Strict Mapping Violation". The
      // existing 3-retry policy on submitSale fires this catch; we
      // short-circuit it by detecting the marker phrase in the error text
      // and routing through the same Fatal-screen path as the pre-flight.
      // Note: detection by phrase is fragile but the server emits this
      // exact text from ApiSalesHandler._resolveWarehouseId — pinned by
      // the diagnostic-breadcrumb test (US4).
      if (e.toString().contains('Strict Mapping Violation')) {
        final synthetic = MirrorCacheDivergenceException(
          kind: MirrorMasterDataKind.warehouse,
          requestedId: -1, // server didn't echo the id back
          cachedIds: const [],
          serverResponse: e.toString(),
        );
        unawaited(DiagnosticLogger.log(
          'MIRROR-CACHE-DIVERGENCE',
          'kind=warehouse_missing '
              'requested=-1 cached=[] '
              'server_response=${e.toString()} '
              'origin=server-500',
        ));
        unawaited(MirrorDivergenceHandler.surface(
          exception: synthetic,
          origin: 'server-500',
        ));
        return SaleResult.failure(
          'رفض السيرفر البيع بسبب تعارض فى البيانات — '
          'تم فتح شاشة استعادة المزامنة.',
        );
      }
      debugPrint('CRITICAL ERROR in completeSalesTransaction: $e');
      debugPrint('StackTrace: $st');
      // Cluster 034 follow-up — surface the actual error in
      // diagnostic.log too. Without this the operator only sees the
      // toast "فشل في حفظ الفاتورة محلياً" and we have no way to know
      // whether it was a FK constraint, an id-collision, or a DB lock.
      final stStr = st.toString();
      final shortSt = stStr.length > 1200
          ? '${stStr.substring(0, 1200)}…[truncated]'
          : stStr;
      unawaited(DiagnosticLogger.log('SALE-LOCAL',
          '❌ local persistence THREW: $e\nstack=$shortSt'));
      return SaleResult.failure('فشل في حفظ الفاتورة محلياً: $e');
    }
  }

  String _deviceName() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'unknown';
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Spec 131 — Mirror Cache Integrity pre-flight (FR-005)
  // ═════════════════════════════════════════════════════════════════════════

  /// On mirror/client mode, verify every direct sale-header master-data
  /// foreign key exists in the local cache BEFORE any DB write. First-miss
  /// wins — throws [MirrorCacheDivergenceException] identifying which table
  /// the missing id belonged to. The orchestrator's catch wraps the
  /// exception into the Spec 130 Fatal-screen contract
  /// (kind=mirrorCacheDivergence).
  ///
  /// Server and standalone modes bypass: they're authoritative against
  /// their own DB and can't be in cache-divergence by definition.
  ///
  /// Performance: 5 indexed PK lookups against in-process SQLite, ~5 ms
  /// total on a populated install. Negligible compared to the 50–200 ms
  /// sale-write transaction this guards.
  Future<void> _preflightSaleParity(SaleRequest req) async {
    if (!SyncInterceptor.isClientMode) return;

    // Emit one breadcrumb per sale-attempt, regardless of pass/fail, so a
    // field-debug log line for every sale is easy to grep.
    final invoiceTag = req.invoiceNumber ?? 'pending';

    // Build the list of (field, id) checks to run. Skip optional fields
    // when their id is null or when an adhoc customer is in play.
    final checks = <(MirrorMasterDataKind, String, int)>[
      (MirrorMasterDataKind.warehouse, 'warehouses', req.warehouseId),
      if (req.branchId != null)
        (MirrorMasterDataKind.branch, 'branches', req.branchId!),
      if (req.customerId != null &&
          (req.adhocCustomerName == null || req.adhocCustomerName!.isEmpty))
        (MirrorMasterDataKind.customer, 'parties', req.customerId!),
      if (req.costCenterId != null)
        (MirrorMasterDataKind.costCenter, 'cost_centers', req.costCenterId!),
      // Safe checks: per-payment-method ids may each carry a value.
      if (req.cashSafeId != null)
        (MirrorMasterDataKind.safe, 'safes', req.cashSafeId!),
      if (req.bankSafeId != null)
        (MirrorMasterDataKind.safe, 'safes', req.bankSafeId!),
      if (req.clickSafeId != null)
        (MirrorMasterDataKind.safe, 'safes', req.clickSafeId!),
    ];

    for (final check in checks) {
      final (kind, table, id) = check;
      final exists = await _existsInMasterTable(table, id);
      if (!exists) {
        // FR-007 breadcrumbs — one MASTERDATA-CHECK (failed) + one
        // CACHE-DIVERGENCE before throwing.
        unawaited(DiagnosticLogger.log(
          'MIRROR-MASTERDATA-CHECK',
          'sale=$invoiceTag '
              'warehouse=${req.warehouseId} '
              'branch=${req.branchId ?? '-'} '
              'customer=${req.customerId ?? '-'} '
              'cost_center=${req.costCenterId ?? '-'} '
              'cash_safe=${req.cashSafeId ?? '-'} '
              'bank_safe=${req.bankSafeId ?? '-'} '
              'click_safe=${req.clickSafeId ?? '-'} '
              'all_resolved=false',
        ));
        final cached = await _sampleMasterTableIds(table);
        unawaited(DiagnosticLogger.log(
          'MIRROR-CACHE-DIVERGENCE',
          'kind=${kind.breadcrumbName}_missing '
              'requested=$id '
              'cached=$cached '
              'server_response=- '
              'origin=pre-flight',
        ));
        throw MirrorCacheDivergenceException(
          kind: kind,
          requestedId: id,
          cachedIds: cached,
        );
      }
    }

    unawaited(DiagnosticLogger.log(
      'MIRROR-MASTERDATA-CHECK',
      'sale=$invoiceTag '
          'warehouse=${req.warehouseId} '
          'branch=${req.branchId ?? '-'} '
          'customer=${req.customerId ?? '-'} '
          'cost_center=${req.costCenterId ?? '-'} '
          'cash_safe=${req.cashSafeId ?? '-'} '
          'bank_safe=${req.bankSafeId ?? '-'} '
          'click_safe=${req.clickSafeId ?? '-'} '
          'all_resolved=true',
    ));
  }

  Future<bool> _existsInMasterTable(String table, int id) async {
    final row = await _db
        .customSelect(
          'SELECT 1 AS p FROM $table WHERE id = ? LIMIT 1',
          variables: [Variable.withInt(id)],
        )
        .getSingleOrNull();
    return row != null;
  }

  Future<List<int>> _sampleMasterTableIds(String table) async {
    final rows = await _db
        .customSelect('SELECT id FROM $table ORDER BY id LIMIT 20')
        .get();
    return rows.map((r) => r.read<int>('id')).toList();
  }
}
