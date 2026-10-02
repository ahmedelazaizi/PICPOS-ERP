// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';
import 'package:flutter/foundation.dart';

class SalesSyncStrategy extends SyncStrategy {
  SalesSyncStrategy(super.db);

  @override
  String get tableName => 'sales';

  @override
  String get apiEndpoint => '/api/sales';

  /// R5 — sales invoice headers are append-only on issuance but their
  /// status (pending/partial/paid/void) is mutated server-side as
  /// receipts land. `serverWins` lets those status transitions overwrite
  /// the local cached row authoritatively. (Items themselves are append-
  /// only via the line-level identity of `invoiceId + productId`.)
  @override
  ConflictPolicy get conflictPolicy => ConflictPolicy.serverWins;

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final salesList = json['sales'] as List? ?? [];
    int inserted = 0;
    int updated = 0;
    for (final sale in salesList) {
      final result = await _syncSingleSale(sale as Map<String, dynamic>);
      if (result == _SyncResult.inserted) inserted++;
      if (result == _SyncResult.updated) updated++;
    }
    // Force UI refresh if any invoices were synced or updated
    if (inserted > 0 || updated > 0) {
      db.markTablesUpdated({db.salesInvoices, db.salesInvoiceItems});
      debugPrint('[Sync] Sales: $inserted new, $updated updated → UI notified');
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async {
    return 0; // To be implemented with server-side support
  }

  /// Returns the sync result: inserted, updated, or skipped.
  Future<_SyncResult> _syncSingleSale(Map<String, dynamic> saleMap) async {
    final serverId = parseInt(saleMap['id']);
    final invoiceNumber = saleMap['invoiceNumber'] as String? ?? '';
    final saleTotal = parseDouble(saleMap['total']);
    final saleDate = DateTime.tryParse(saleMap['invoiceDate']?.toString() ?? '') ?? DateTime.now();
    final saleCustomerId = parseIntNullable(saleMap['customerId']);

    // Resolve server party ID → local party ID via FK mappings.
    // PartySyncStrategy preserves the local auto-increment id on parties created
    // by this client (using globalId match), so the local party may exist under
    // a different id than what the server stored. Storing the server id in the
    // invoice FK breaks the customerNames lookup in the invoice list screen.
    final resolvedCustomerId =
        await resolveLocalPartyId(saleCustomerId, label: 'customerId');

    final saleWarehouseId = parseInt(saleMap['warehouseId'], 1);

    // Parse the missing fields that were previously not synced
    final serverIsDeleted = parseBool(saleMap['isDeleted']);
    final serverDeletedAt = DateTime.tryParse(saleMap['deletedAt']?.toString() ?? '');
    final serverDeletedBy = parseIntNullable(saleMap['deletedBy']);
    final serverClickPaid = parseDouble(saleMap['clickPaid']);
    // Spec 151 C-05 — pull `paid` on existing rows too. Option S advances
    // sales_invoices.paid server-side; without healing it here the client's
    // light local paid marker could never be corrected (a dead-lettered
    // collection submit, a mirror-offline collection, or a delta<=0 correction
    // would leave paid permanently divergent), mirroring purchase_sync_strategy.
    final serverPaid = parseDouble(saleMap['paid']);

    /// قاعدةُ حساب [serverPaid] — v175.
    ///
    /// 🔴 **وخادمٌ لا يرسل المفتاح يسقط على `paid` ناقصَ التخصيصات
    /// المحلّيّة، لا على صفر.** صفرٌ يقول «كلُّ ما دُفع كان تخصيصاً»، فأوّلُ
    /// إعادةِ حسابٍ تُصفّر مسدَّدَ كلِّ فاتورةٍ وصلت بالمزامنة — وهو عينُ
    /// العطب الذي بُني العمودُ لأجله، من بابٍ آخر.
    ///
    /// ⚠️ **والطرحُ يُقرأ من القاعدة لا يُفترَض صفراً**: ترتيبُ الدفعات في
    /// السحب غيرُ مضمون، فقد تصل تخصيصاتُ الفاتورة قبل صفِّها.
    Future<double> serverPaidUnallocated() async {
      final sent = saleMap['paidUnallocated'] ?? saleMap['paid_unallocated'];
      if (sent != null) return parseDouble(sent);
      final allocated = await db.getPaymentAllocationsTotal(serverId);
      final base = serverPaid - allocated;
      return base < 0 ? 0 : base;
    }
    // خادمٌ أقدمُ لا يرسل المفتاح ⇒ صفرٌ، وهو الحقُّ لفاتورةٍ لم تُقرَّب.
    final serverRoundingAdjustment =
        parseDouble(saleMap['roundingAdjustment']);
    final serverIsLocked = parseBool(saleMap['isLocked']);
    final serverUpdatedAt = DateTime.tryParse(saleMap['updatedAt']?.toString() ?? '');
    final serverStatus = saleMap['status'] as String? ?? 'completed';

    try {
      var result = _SyncResult.skipped;
      // CRITICAL FIX: Wrap entire check-and-insert in atomic transaction
      // to prevent TOCTOU (Time-Of-Check-Time-Of-Use) race condition
      await db.transaction(() async {
        // Check if already exists by server ID — use raw select to include
        // soft-deleted records (getSalesInvoiceById filters isDeleted=false)
        final existing = await (db.select(db.salesInvoices)
          ..where((s) => s.id.equals(serverId))
          ..limit(1)
        ).getSingleOrNull();

        if (existing != null) {
          // Record exists locally — update critical mutable fields from server
          // so that voids, locks, and status changes propagate to clients
          final needsUpdate =
              existing.isDeleted != serverIsDeleted ||
              existing.isLocked != serverIsLocked ||
              existing.status != serverStatus ||
              existing.clickPaid != serverClickPaid ||
              existing.paid != serverPaid ||
              // فرقُ التقريب يُشفى كما يُشفى `paid` تماماً: بدونه لا سبيلَ
              // لتصحيح صفٍّ موجودٍ محلّيّاً عبر هذا المسار أبداً — والمرآةُ
              // تُشغِّل هذه الاستراتيجيّةَ فعلاً (‏`isClient` تُكذَب للمرآة).
              existing.roundingAdjustment != serverRoundingAdjustment ||
              existing.currencyId != parseIntNullable(saleMap['currencyId'] ?? saleMap['currency_id']) ||
              existing.exchangeRate != parseDoubleNullable(saleMap['exchangeRate'] ?? saleMap['exchange_rate']) ||
              existing.deletedAt != serverDeletedAt;

          if (needsUpdate) {
            await (db.update(db.salesInvoices)
              ..where((s) => s.id.equals(serverId))
            ).write(SalesInvoicesCompanion(
              isDeleted: Value(serverIsDeleted),
              deletedAt: Value(serverDeletedAt),
              deletedBy: Value(serverDeletedBy),
              isLocked: Value(serverIsLocked),
              status: Value(serverStatus),
              clickPaid: Value(serverClickPaid),
              paid: Value(serverPaid),
              paidUnallocated: Value(await serverPaidUnallocated()),
              roundingAdjustment: Value(serverRoundingAdjustment),
              updatedAt: Value(serverUpdatedAt ?? DateTime.now()),
              customerId: Value(resolvedCustomerId),
               currencyId: Value(parseIntNullable(saleMap['currencyId'] ?? saleMap['currency_id'])),
               exchangeRate: Value(parseDoubleNullable(saleMap['exchangeRate'] ?? saleMap['exchange_rate'])),
            ));
            await db.resignSalesInvoice(serverId);
            result = _SyncResult.updated;
            debugPrint('[Sync] Updated existing invoice $invoiceNumber '
                '(isDeleted=$serverIsDeleted, isLocked=$serverIsLocked, '
                'status=$serverStatus)');
          }
          // C2 (v183) — raw column outside the companion; an older server
          // that omits the key leaves the local value untouched.
          if (saleMap.containsKey('revenueAccountId')) {
            await db.setSalesInvoiceRevenueAccountId(
                serverId, parseIntNullable(saleMap['revenueAccountId']));
          }
          // v185 — the rep/route stamp (never overwrites a local stamp).
          await db.applyRepStampJson('sales_invoices', serverId, saleMap);
          return;
        }

        // Dedup 2: Skip if invoiceNumber already exists locally
        if (invoiceNumber.isNotEmpty) {
          final byNumber = await (db.select(db.salesInvoices)
            ..where((s) => s.invoiceNumber.equals(invoiceNumber))
            ..limit(1)
          ).getSingleOrNull();
          if (byNumber != null) return;
        }

        // PHASE-7 FIX: Enhanced Dedup 3 — Universal duplicate detection
        // Matches by total + date + warehouseId regardless of invoice number prefix
        // This catches ALL duplicates: CLTclient_, server-created for branch, etc.
        final startOfDay = DateTime(saleDate.year, saleDate.month, saleDate.day);
        final endOfDay = startOfDay.add(const Duration(days: 1));

        // Build match query: same total + same date + same warehouse
        final localMatches = await (db.select(db.salesInvoices)
          ..where((s) =>
            s.total.equals(saleTotal) &
            s.warehouseId.equals(saleWarehouseId) &
            s.invoiceDate.isBiggerOrEqualValue(startOfDay) &
            s.invoiceDate.isSmallerThanValue(endOfDay)
          )
          ..limit(5)
        ).get();

        // Check for a match with same customer (or both null)
        for (final localInvoice in localMatches) {
          final customerMatch = (resolvedCustomerId == null && localInvoice.customerId == null) ||
              (resolvedCustomerId != null && localInvoice.customerId == resolvedCustomerId);
          if (customerMatch) {
            debugPrint('[Sync] Skipping duplicate sale $invoiceNumber '
                '(matches local ${localInvoice.invoiceNumber}, '
                'total=$saleTotal, warehouse=$saleWarehouseId)');
            return;
          }
        }

        // NOW insert — still within transaction, no TOCTOU window
        result = _SyncResult.inserted;
        await db.into(db.salesInvoices).insertOnConflictUpdate(
          SalesInvoicesCompanion(
            id: Value(serverId),
            invoiceNumber: Value(invoiceNumber),
            customerId: Value(resolvedCustomerId),
               currencyId: Value(parseIntNullable(saleMap['currencyId'] ?? saleMap['currency_id'])),
               exchangeRate: Value(parseDoubleNullable(saleMap['exchangeRate'] ?? saleMap['exchange_rate'])),
            warehouseId: Value(saleWarehouseId),
            branchId: Value(parseIntNullable(saleMap['branchId'])),
            userId: Value(parseInt(saleMap['userId'], 1)),
            invoiceDate: Value(saleDate),
            subtotal: Value(parseDouble(saleMap['subtotal'])),
            discount: Value(parseDouble(saleMap['discount'])),
            tax: Value(parseDouble(saleMap['tax'])),
            total: Value(saleTotal),
            paid: Value(parseDouble(saleMap['paid'])),
            paidUnallocated: Value(await serverPaidUnallocated()),
            // خادمٌ أقدمُ لا يرسل المفتاح ⇒ `parseDouble` تعطي صفراً، وهو
            // الحقُّ حرفيّاً لفاتورةٍ لم تُقرَّب. فلا انكسارَ في الاتجاهين.
            roundingAdjustment:
                Value(parseDouble(saleMap['roundingAdjustment'])),
            cashPaid: Value(parseDouble(saleMap['cashPaid'])),
            bankPaid: Value(parseDouble(saleMap['bankPaid'])),
            clickPaid: Value(serverClickPaid),
            paymentMethod: Value(saleMap['paymentMethod'] as String? ?? 'cash'),
            status: Value(serverStatus),
            orderNumber: Value(parseInt(saleMap['orderNumber'])),
            deliveryFee: Value(parseDouble(saleMap['deliveryFee'])),
            notes: Value(saleMap['notes'] as String?),
            saleType: Value(saleMap['saleType'] as String? ?? 'default'),
            costCenterId: Value(parseIntNullable(saleMap['costCenterId'])),
            isDeleted: Value(serverIsDeleted),
            deletedAt: Value(serverDeletedAt),
            deletedBy: Value(serverDeletedBy),
            isLocked: Value(serverIsLocked),
            updatedAt: Value(serverUpdatedAt ?? DateTime.now()),
          ),
        );
        // C2 (v183) — raw column outside the companion.
        final revenueAccountId =
            parseIntNullable(saleMap['revenueAccountId']);
        if (revenueAccountId != null) {
          await db.setSalesInvoiceRevenueAccountId(serverId, revenueAccountId);
        }
        // v185 — the rep/route stamp rides the sale payload.
        await db.applyRepStampJson('sales_invoices', serverId, saleMap);

        final items = saleMap['items'] as List? ?? [];
        for (final item in items) {
          final itemMap = item as Map<String, dynamic>;
          // Issue 11 (Feature 018): remap server productId → local id when the
          // client originally minted the product offline and the server
          // reassigned the id. Falls through to the raw value when mappings
          // line up (the common case).
          final remoteProductId = parseInt(itemMap['productId']);
          final localProductId = await db.resolveItemFk(
            'products',
            remoteProductId,
            context: 'sales_invoice_items invoice=$serverId',
          );

          // Issue 3 (Feature 022): dedup by globalId then by
          // (invoiceId, productId) so a synced item never doubles up
          // alongside an already-present local copy. Mirrors the
          // purchase-side fix.
          final remoteGlobalId = itemMap['globalId'] as String?;
          SalesInvoiceItem? existingItem;
          if (remoteGlobalId != null && remoteGlobalId.isNotEmpty) {
            existingItem = await (db.select(db.salesInvoiceItems)
                  ..where((i) => i.globalId.equals(remoteGlobalId))
                  ..limit(1))
                .getSingleOrNull();
          }
          existingItem ??= await (db.select(db.salesInvoiceItems)
                ..where((i) =>
                    i.invoiceId.equals(serverId) &
                    i.productId.equals(localProductId))
                ..limit(1))
              .getSingleOrNull();

          if (existingItem != null) {
            await (db.update(db.salesInvoiceItems)
                  ..where((i) => i.id.equals(existingItem!.id)))
                .write(SalesInvoiceItemsCompanion(
              invoiceId: Value(serverId),
              productId: Value(localProductId),
              quantity: Value(parseDouble(itemMap['quantity'])),
              unitPrice: Value(parseDouble(itemMap['unitPrice'])),
              discount: Value(parseDouble(itemMap['discount'])),
              total: Value(parseDouble(itemMap['total'])),
              costPrice: Value(parseDouble(itemMap['costPrice'])),
              // SAL-2 (pull): default 1.0 keeps legacy payloads (no field) at
              // base-unit; carton sales now replicate the real UOM factor so
              // local COGS reports match the authoritative GL.
              quantityInBase: Value(parseDouble(itemMap['quantityInBase'], 1.0)),
              taxRate: Value(parseDouble(itemMap['taxRate'])),
              taxAmount: Value(parseDouble(itemMap['taxAmount'])),
            ));
          } else {
            await db.into(db.salesInvoiceItems).insert(
              SalesInvoiceItemsCompanion(
                id: Value(parseInt(itemMap['id'])),
                invoiceId: Value(serverId),
                productId: Value(localProductId),
                quantity: Value(parseDouble(itemMap['quantity'])),
                unitPrice: Value(parseDouble(itemMap['unitPrice'])),
                discount: Value(parseDouble(itemMap['discount'])),
                total: Value(parseDouble(itemMap['total'])),
                costPrice: Value(parseDouble(itemMap['costPrice'])),
                // SAL-2 (pull): default 1.0 keeps legacy payloads (no field) at
                // base-unit; carton sales now replicate the real UOM factor so
                // local COGS reports match the authoritative GL.
                quantityInBase: Value(parseDouble(itemMap['quantityInBase'], 1.0)),
                taxRate: Value(parseDouble(itemMap['taxRate'])),
                taxAmount: Value(parseDouble(itemMap['taxAmount'])),
                globalId: remoteGlobalId != null && remoteGlobalId.isNotEmpty
                    ? Value(remoteGlobalId)
                    : const Value.absent(),
              ),
              // Bare `ON CONFLICT DO NOTHING`. These strategies pull onto a
              // SQLite mirror today, where `insertOrIgnore` behaves — but the
              // mode is silently dropped on postgres, so the moment a mirror
              // runs on PG this would raise 23505 on `global_id` instead of
              // skipping an already-pulled row. Converted rather than reasoned
              // about: the form below is correct on both dialects and with or
              // without the constraint.
              onConflict: DoNothing(target: []),
            );
          }
        }
      });
      await db.resignSalesInvoice(serverId);
      return result;
    } on Exception catch (e) {
      if (e.toString().contains('UNIQUE constraint failed') ||
          e.toString().contains('duplicate key')) {
        debugPrint('[Sync] Invoice already synced (duplicate detected): $invoiceNumber');
        return _SyncResult.skipped;
      }
      debugPrint('[Sync] Error in SalesSyncStrategy: $e');
      rethrow;
    }
  }

  @override
  Future<void> upsert(Insertable record) async {
    if (record is SalesInvoicesCompanion) {
      await db.into(db.salesInvoices).insertOnConflictUpdate(record);
    }
  }
}

/// Internal result type for _syncSingleSale.
enum _SyncResult { inserted, updated, skipped }