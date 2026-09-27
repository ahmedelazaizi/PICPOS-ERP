import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import '../core/utils/uuid_v7.dart';
import '../core/logging/diagnostic_logger.dart';
import '../data/database/database.dart';
import '../domain/entities/accounting_entities.dart';
import '../domain/repositories/settings_repository.dart';
import 'costing_method_service.dart';
import 'client_write_interceptor.dart';

/// الحساب المقابل لقيد السند المخزني، حسب **نوع السند** مش إشارة القيمة وحدها.
///
/// ── ليه دالة منفصلة ─────────────────────────────────────────────────────────
/// القرار ده كان سطر واحد جوه `createAddingBond` بيقرا `bond.type`، بينما
/// نفس الدالة بتثبّت `type: 'in'` على كل سند — فشرط `'opening'` كان **مستحيل
/// يتحقق** وفرع `capital` كود ميت من يوم ما اتكتب.
///
/// والنتيجة إن رصيد أول المدة كان بيتقيّد على `4317 فائض مخزون` **ونوعه
/// revenue**: عميل بيدخل ٢٥٠ ألف بضاعة افتتاحية بيلاقي ٢٥٠ ألف ربح وهمي في
/// قائمة الدخل من أول يوم، وحقوق ملكية ناقصة بنفس المبلغ، وضريبة دخل محسوبة
/// على ربح مش موجود.
///
/// الرصيد الافتتاحي حركة **حقوق ملكية** بطبيعتها — مش فايض تشغيلي — فنوع
/// السند بيغلب على إشارة القيمة.
@visibleForTesting
String inventoryBondAccountPurpose({
  required String? bondType,
  required double totalValue,
}) {
  if (bondType == 'opening') return 'capital';
  return totalValue >= 0 ? 'inventory_surplus' : 'inventory_shrinkage';
}

class InventoryService {
  final AppDatabase db;
  final ISettingsRepository settingsRepo;

  InventoryService(this.db, this.settingsRepo);

  /// Create a new inventory bond (Adding stock)
  ///
  /// [bondType] بيتكتب على الهيدر ويحدد الحساب المقابل في القيد — كان مثبّت
  /// `'in'` دايماً فسندات الرصيد الافتتاحي كانت بتضيع هويتها قبل ما توصل
  /// للقرار المحاسبي. الافتراضي `'in'` = سلوك النهاردة لكل المستدعيين.
  Future<int> createAddingBond({
    required List<InventoryBondItemsCompanion> items,
    required int warehouseId,
    String bondType = 'in',
    String? notes,
    int? userId,
    DateTime? date,
  }) async {
    // Spec 129 F4 — mint a UUIDv7 ONCE per call and thread it into both the
    // local DAO insert and the server-submit payload. Mirror's local bond and
    // server's bond now share identity, so the server's globalId dedup (and
    // any future DeltaPull strategy) catches the pair as one logical row.
    final bondGid = UuidV7.generate();
    final bondId = await db.transaction(() async {
      // 1. Create Bond Header
      final bondId = await db.createInventoryBond(
        InventoryBondsCompanion.insert(
          bondNumber: await db.generateInvoiceNumber('BND'),
          type: Value(bondType),
          warehouseId: warehouseId,
          notes: Value(notes),
          createdBy: Value(userId),
          bondDate: Value(date ?? DateTime.now()),
          globalId: Value(bondGid),
        ),
      );

      double totalValue = 0;
      final warehouse = await db.getWarehouseById(warehouseId);
      final branchId = warehouse?.branchId;

      // 2. Process Items
      for (var item in items) {
        // Link to bond
        final bondIdResolved = bondId;
        final bondItem = item.copyWith(bondId: Value(bondIdResolved));
        await db.into(db.inventoryBondItems).insert(bondItem);

        // 3. Update Product Stock & Cost
        final productId = item.productId.value;
        final qty = item.quantity.value;
        final cost = item.unitCost.value;
        totalValue += qty * cost;

        // Update Stock
        //
        // `unitCost` لازم يتمرّر: بدونه `adjustStock` يرجع إلى
        // `product.costPrice`، فيقول السندُ قيمةً وتقول حركةُ المخزون ورصيدُ
        // المخزن قيمةً أخرى. مقيس: صنفٌ تكلفتُه صفرٌ يدخل بسندٍ ١٠×١٠ = ١٠٠
        // ⇒ `stock_movements.unit_cost` و`inventory_balances.average_cost`
        // صفرٌ ⇒ تقييمُ المخزون في التقارير يخالف قيدَ السند بـ١٠٠.
        await db.adjustStock(
          productId: productId,
          warehouseId: warehouseId,
          quantity: qty,
          type: 'bond_in',
          unitCost: cost,
          notes: 'Bond #$bondIdResolved',
          branchId: branchId,
        );

        // [ISS-V01] Accurate Cost Valuation: Resolve costing method from settings
        final product = await db.getProductById(productId);
        if (product != null) {
          final method = await CostingMethodService.load(settingsRepo);
          final newCost = CostingMethodService.calculateCost(
            method: method,
            currentStock: product.currentStock - qty, 
            currentCost: product.costPrice,
            purchaseQty: qty,
            purchaseUnitCost: cost,
          );

          await db.updateProduct(
            product.copyWith(
              costPrice: newCost > 0 ? newCost : product.costPrice,
            ),
          );
        }
      }

      // 4. GENERATE ACCOUNTING ENTRY (Standardized Hardening)
      if (totalValue != 0) {
        try {
          final bond = await (db.select(db.inventoryBonds)..where((b) => b.id.equals(bondId))).getSingle();
          final String purpose = inventoryBondAccountPurpose(
            bondType: bond.type,
            totalValue: totalValue,
          );
          
          final invAccount = await db.getAccountByPurpose('inventory');
          final targetAccount = await db.getAccountByPurpose(purpose);

          if (invAccount == null || targetAccount == null) {
             throw StateError('لا يمكن حفظ سند المخزون: حساب المخزون أو الحساب المقابل غير مربوط.');
           }
           {
            final isAddition = totalValue > 0;
            await db.createJournalEntry(
              description: 'إثبات قيد سند مخزني #$bondId (${bond.notes ?? ''})',
              date: date ?? DateTime.now(),
              branchId: branchId,
              isAutoPosted: true,
              referenceType: 'inventory_bond',
              referenceId: bondId,
              lines: [
                JournalLine(
                  accountId: invAccount.id,
                  debit: isAddition ? totalValue.abs() : 0,
                  credit: isAddition ? 0 : totalValue.abs(),
                  description: 'تعديل قيمة المخزون',
                ),
                JournalLine(
                  accountId: targetAccount.id,
                  debit: isAddition ? 0 : totalValue.abs(),
                  credit: isAddition ? totalValue.abs() : 0,
                  description: bond.type == 'opening' ? 'رصيد أول المدة' : 'تسوية فروقات مخزنية',
                ),
              ],
            );
          }
        } catch (e) {
          debugPrint('[FINANCIAL_WARNING] Inventory bond accounting failed: $e');
          unawaited(DiagnosticLogger.log(
            'FINANCIAL_WARNING',
            'Inventory bond accounting failed: $e',
           ));
           rethrow;
        }
      }

      return bondId;
    });

    // === Client Mode Sync ===
    // Spec 117 (Bug J) — تغليف submit بـ try/catch.
    // قبلاً: لو submitInventoryBond يفشل (server 500، mirror offline,
    // أو أي exception)، الـ exception يصعد لـ caller → controller.saveBond
    // catch → state.error → toast "فشل حفظ السند" — رغم أن الـ local
    // transaction (bond + stock_movement + JE) قد اكتملت بنجاح.
    //
    // الـ Mirror خصوصاً يُولِّد MirrorOfflineException على عدم اتصال،
    // فالـ flow ينهار رغم اكتمال الحفظ المحلي.
    //
    // الإصلاح: نُعتبر الـ local save authoritative، الـ server sync
    // fire-and-forget مع logging. الـ next sync pull سيُعيد تأكيد البيانات.
    try {
      await ClientWriteInterceptor.submitInventoryBond({
        'type': bondType == 'opening' || bondType == 'in' ? 'in' : 'out',
        'warehouseId': warehouseId,
        'notes': notes,
        'userId': userId,
        'date': (date ?? DateTime.now()).toIso8601String(),
        'globalId': bondGid,
        'items': items.map((i) => {
          'productId': i.productId.value,
          'quantity': i.quantity.value,
          'unitCost': i.unitCost.value,
        }).toList(),
      });
    } catch (e) {
      // local data محفوظ، الـ sync سيُعاد لاحقاً
      // ignore: avoid_print
      print('[INVENTORY-BOND-SYNC] submit failed (local data saved, will retry sync): $e');
    }

    return bondId;
  }

  /// Create Inventory Bond for "Opening Balance" specifically
  /// This might have slightly different logic (e.g. setting initial stock)
  Future<int> createOpeningBalanceBond({
    required List<InventoryBondItemsCompanion> items,
    required int warehouseId,
    String? notes,
    int? userId,
  }) async {
    return createAddingBond(
      items: items,
      warehouseId: warehouseId,
      // من غير ده الهيدر بيتكتب `'in'` فالقرار المحاسبي تحت بيقرا نوع غلط
      // ويدائن «فائض مخزون» (إيراد) بدل رأس المال.
      bondType: 'opening',
      notes: notes ?? 'رصيد افتتاحي',
      userId: userId,
    );
  }

  /// Perform a stock transfer between warehouses.
  ///
  /// Returns the created transfer bond id (Spec 148 — the requisition-approval
  /// flow links the fulfilled requisition to it).
  Future<int> transferStock({
    required int fromWarehouseId,
    required int toWarehouseId,
    required List<Map<String, dynamic>> items,
    String? notes,
    int? userId,
  }) async {
    // Spec 129 F4 — mint a UUIDv7 ONCE so the local bond row and the server
    // payload agree on identity. Mirror local + server can later dedup
    // against the same globalId without a fragile (refType, refId) fallback.
    final transferGid = UuidV7.generate();
    final bondId = await db.transferStock(
      fromWarehouseId: fromWarehouseId,
      toWarehouseId: toWarehouseId,
      items: items,
      notes: notes,
      userId: userId,
      globalId: transferGid,
    );

    // ── Client → Server sync (fire-and-forget) ──
    try {
      await ClientWriteInterceptor.submitStockTransfer(
        fromWarehouseId: fromWarehouseId,
        toWarehouseId: toWarehouseId,
        items: items,
        userId: userId,
        notes: notes,
        globalId: transferGid,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[INVENTORY-SYNC] Stock transfer sync failed: $e');
    }

    return bondId;
  }

  /// Spec 148 (S-ISSUE) — approve a `pending` stock requisition by issuing its
  /// items as a warehouse transfer (supplier → requester), then mark it
  /// `fulfilled` and link it to the produced transfer bond.
  ///
  /// Throws (Arabic) and changes nothing if the requisition is not found /
  /// not pending, if either branch has no default warehouse, or if the
  /// transfer itself fails (insufficient stock, unmapped accounts, …) — the
  /// requisition then stays `pending` for a later retry.
  ///
  /// Returns the created transfer bond id.
  Future<int> approveRequisition({
    required int requisitionId,
    int? userId,
  }) async {
    final req = await db.getStockRequisitionById(requisitionId);
    if (req == null) {
      throw Exception('طلب الصرف غير موجود.');
    }
    if (req.status != 'pending') {
      throw Exception('لا يمكن اعتماد الطلب لأن حالته ليست "معلق".');
    }

    // Resolve default warehouses. Direction is intentionally crossed: the
    // create screen names fromBranchId = requester ("الفرع الطالب لي") and
    // toBranchId = supplier ("الفرع المورد منه"); goods flow supplier →
    // requester.
    final supplierWarehouse = await _defaultWarehouseForBranch(req.toBranchId);
    if (supplierWarehouse == null) {
      throw Exception(
          'الفرع المورد لا يملك مستودعاً افتراضياً — لا يمكن تنفيذ الصرف.');
    }
    final requesterWarehouse =
        await _defaultWarehouseForBranch(req.fromBranchId);
    if (requesterWarehouse == null) {
      throw Exception(
          'الفرع الطالب لا يملك مستودعاً افتراضياً — لا يمكن تنفيذ الصرف.');
    }

    final items = await db.getStockRequisitionItems(requisitionId);
    if (items.isEmpty) {
      throw Exception('طلب الصرف لا يحتوي على أصناف.');
    }
    final transferItems = items
        .map((i) => {'productId': i.productId, 'quantity': i.quantity})
        .toList();

    // Spec 129 F4 — mint the transfer gid once so the local bond and the server
    // submit agree on identity.
    final transferGid = UuidV7.generate();

    // FR-012 atomicity: the transfer (bond + stock movements + the two balanced
    // goods-in-transit JEs) AND the requisition fulfilled/link write commit
    // TOGETHER. Without this, a crash between the transfer commit and the status
    // write would leave a committed transfer with the requisition still
    // `pending` → a re-approve would issue a SECOND transfer (fresh gid ⇒ the
    // server can't dedup it) → goods double-issued. `db.transferStock` opens a
    // nested savepoint inside this transaction, so if the status write throws
    // the whole thing rolls back. If the transfer itself throws (insufficient
    // stock, unmapped accounts) nothing moves and the requisition stays pending.
    final bondId = await db.transaction(() async {
      final id = await db.transferStock(
        fromWarehouseId: supplierWarehouse,
        toWarehouseId: requesterWarehouse,
        items: transferItems,
        notes: 'صرف طلب ${req.requisitionNumber}',
        userId: userId,
        globalId: transferGid,
      );
      await (db.update(db.stockRequisitions)
            ..where((r) => r.id.equals(requisitionId)))
          .write(StockRequisitionsCompanion(
        status: const Value('fulfilled'),
        fulfilledByTransferId: Value(id),
      ));
      return id;
    });

    // Client → server sync (fire-and-forget), AFTER the local commit so no DB
    // transaction is held open during network I/O. Mirrors
    // InventoryService.transferStock's submit; the next pull re-confirms.
    try {
      await ClientWriteInterceptor.submitStockTransfer(
        fromWarehouseId: supplierWarehouse,
        toWarehouseId: requesterWarehouse,
        items: transferItems,
        userId: userId,
        notes: 'صرف طلب ${req.requisitionNumber}',
        globalId: transferGid,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[REQUISITION-SYNC] approve transfer submit failed (local saved): $e');
    }

    return bondId;
  }

  /// Spec 148 — reject a `pending` requisition. Terminal, no inventory/GL
  /// effect. Throws (Arabic) if the requisition is not found / not pending.
  Future<void> rejectRequisition({required int requisitionId}) async {
    final req = await db.getStockRequisitionById(requisitionId);
    if (req == null) {
      throw Exception('طلب الصرف غير موجود.');
    }
    if (req.status != 'pending') {
      throw Exception('لا يمكن رفض الطلب لأن حالته ليست "معلق".');
    }
    await (db.update(db.stockRequisitions)
          ..where((r) => r.id.equals(requisitionId)))
        .write(const StockRequisitionsCompanion(status: Value('rejected')));
  }

  /// Default (active) warehouse id for a branch, or null if the branch has
  /// none. Mirrors the resolution used in `branches_dao`.
  Future<int?> _defaultWarehouseForBranch(int branchId) async {
    final w = await (db.select(db.warehouses)
          ..where((w) => w.branchId.equals(branchId))
          ..where((w) => w.isDefault.equals(true))
          ..where((w) => w.isActive.equals(true)))
        .getSingleOrNull();
    return w?.id;
  }
}
