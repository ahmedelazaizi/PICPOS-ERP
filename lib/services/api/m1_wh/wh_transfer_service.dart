// W3 (plan 2026-10-23 §B.2-4): staged transfer = dispatch -> goods in transit
// -> receive. Behind setting `wh_staged_transfers_enabled` (OFF until the
// accountant signs off the goods_in_transit accounting; the handlers answer
// `409 staged_transfers_disabled` honestly while it is off).
//
// Why a new service and not `POST /api/inventory/transfer` (plan E-9a): that
// LAN route calls adjustStock twice with no negative-stock block, no lot
// carry-over and no goods_in_transit entries. Warehouse documents never use
// it. `AppDatabase.transferStock` stays untouched for the desktop.
//
//   dispatch  source stock out (never below zero), lots consumed, unit cost
//             FROZEN on the line, Dr goods_in_transit / Cr inventory
//   receive   destination stock in at the frozen cost, lots restored,
//             Dr inventory / Cr goods_in_transit; damaged -> pending damage
//             voucher; short stays in transit; excess is refused
//   resolve   short quantity returns to source (reverse entry) or is written
//             off (Dr shrinkage / Cr goods_in_transit); nothing stays in GIT
import 'package:drift/drift.dart';

import '../../../core/utils/uuid_v7.dart';
import '../../../data/database/database.dart';
import '../../../domain/entities/accounting_entities.dart';
import 'wh_constants.dart';
import 'wh_doc_store.dart';
import 'wh_http.dart';
import 'wh_stock_guard.dart';

const String kStagedTransfersSetting = 'wh_staged_transfers_enabled';

class WhTransferService {
  WhTransferService(this.db, this.store);
  final AppDatabase db;
  final WhDocStore store;

  Future<void> requireEnabled() async {
    if (await db.getSettingValue(kStagedTransfersSetting) != 'true') {
      throw WhError('staged_transfers_disabled', 409);
    }
  }

  // ───────────────────────────── ledger helpers ─────────────────────────────

  Future<void> _post({
    required String description,
    required int warehouseId,
    required double amount,
    required String refType,
    required int docId,
    required String debit, // account purpose
    required String credit,
  }) async {
    if (amount <= 0) return;
    final d = await db.getAccountByPurpose(debit);
    final c = await db.getAccountByPurpose(credit);
    if (d == null || c == null) {
      throw WhError('accounts_not_mapped', 409);
    }
    await db.createJournalEntry(
      description: description,
      date: DateTime.now(),
      lines: [
        JournalLine(accountId: d.id, debit: amount, description: description),
        JournalLine(accountId: c.id, credit: amount, description: description),
      ],
      referenceType: refType,
      referenceId: docId,
      isAutoPosted: true,
      branchId: (await db.getWarehouseById(warehouseId))?.branchId,
    );
  }

  Future<void> _restoreLot(int productId, int warehouseId, Map<String, Object?> lot, double qty) async {
    final number = lot['batchNumber']! as String;
    final expiry = DateTime.fromMillisecondsSinceEpoch((lot['expiry']! as num).toInt());
    final existing = await (db.select(db.productBatches)
          ..where((b) =>
              b.productId.equals(productId) &
              b.warehouseId.equals(warehouseId) &
              b.batchNumber.equals(number) &
              b.expiryDate.equals(expiry))
          ..limit(1))
        .getSingleOrNull();
    if (existing == null) {
      await db.insertBatch(ProductBatchesCompanion.insert(
        productId: productId,
        warehouseId: warehouseId,
        batchNumber: number,
        expiryDate: expiry,
        quantity: Value(qty),
        initialQuantity: Value(qty),
        unitCost: Value((lot['unitCost']! as num).toDouble()),
      ));
    } else {
      await (db.update(db.productBatches)..where((b) => b.id.equals(existing.id))).write(ProductBatchesCompanion(
        quantity: Value(existing.quantity + qty),
        initialQuantity: Value(existing.initialQuantity + qty),
        status: const Value('active'),
      ));
    }
  }

  /// Takes [qty] from the front of [lots]; returns (taken, left) lot lists.
  (List<Map<String, Object?>>, List<Map<String, Object?>>) _split(List<Map<String, Object?>> lots, double qty) {
    final taken = <Map<String, Object?>>[], left = <Map<String, Object?>>[];
    var need = qty;
    for (final l in lots) {
      final q = (l['qty']! as num).toDouble();
      final t = need <= 0 ? 0.0 : (q < need ? q : need);
      if (t > 0) taken.add({...l, 'qty': t});
      if (q - t > 1e-9) left.add({...l, 'qty': q - t});
      need -= t;
    }
    return (taken, left);
  }

  List<Map<String, Object?>> _lotsOf(WhLine l, String key) =>
      [for (final x in (l.extra[key] as List? ?? const [])) (x as Map).cast<String, Object?>()];

  // ────────────────────────────── commands ──────────────────────────────────

  Future<WhDoc> request(WhCtx ctx, Map<String, Object?> body) async {
    final gid = '${body['globalId'] ?? ''}'.trim();
    final from = (body['fromWarehouseId'] as num?)?.toInt();
    final to = (body['toWarehouseId'] as num?)?.toInt();
    final lines = body['lines'];
    if (gid.length < 8 || from == null || to == null || lines is! List || lines.isEmpty) {
      throw WhError('bad_request', 400);
    }
    if (from == to) throw WhError('same_warehouse', 422);
    if (!ctx.scope.allows(from)) throw WhError('warehouse_forbidden', 403);
    final dest = await db.getWarehouseById(to);
    if (dest == null || !dest.isActive) throw WhError('warehouse_not_found', 404);
    final doc = await store.create(
      gid: gid, kind: 'transfer', state: 'requested', warehouseId: from, toWarehouseId: to,
      createdBy: ctx.userId, deviceId: ctx.deviceId, reason: body['note'] as String?,
    );
    final seen = <int>{};
    for (final raw in lines) {
      final l = (raw as Map).cast<String, Object?>();
      final pid = (l['productId'] as num?)?.toInt();
      final lineGid = '${l['lineGlobalId'] ?? ''}'.trim();
      if (pid == null || lineGid.length < 8 || !seen.add(pid)) throw WhError('bad_request', 400);
      if (await db.getProductById(pid) == null) throw WhError('product_not_found', 422);
      await store.addLine(doc, lineGid: lineGid, productId: pid, qty: parseQty(l['quantity']), counterUserId: ctx.userId);
    }
    return doc;
  }

  Future<WhDoc> approve(WhDoc doc, int approver, {int? expectedVersion}) async {
    requireDistinct(approver, [doc.createdBy]);
    return store.transition(doc, 'approve', expectedVersion: expectedVersion, approvedBy: approver);
  }

  Future<WhDoc> reject(WhDoc doc, int approver, {int? expectedVersion}) async {
    requireDistinct(approver, [doc.createdBy]);
    return store.transition(doc, 'reject', expectedVersion: expectedVersion, approvedBy: approver);
  }

  Future<WhDoc> dispatch(WhDoc doc, WhCtx ctx, {int? expectedVersion}) async {
    if (!ctx.scope.allows(doc.warehouseId)) throw WhError('warehouse_forbidden', 403);
    if (doc.state != 'approved') throw WhError('invalid_transition', 409, {'state': doc.state, 'action': 'dispatch'});
    final bins = await db.getSettingValue('warehouse_bins_enabled') == 'true';
    var value = 0.0;
    for (final l in await store.lines(doc.id)) {
      final product = (await db.getProductById(l.productId))!;
      if (bins) await db.syncDefaultBinStock(l.productId, doc.warehouseId);
      final bal = await (db.select(db.inventoryBalances)
            ..where((b) => b.productId.equals(l.productId) & b.warehouseId.equals(doc.warehouseId)))
          .getSingleOrNull();
      await requireCoveredStock(db,
          productId: l.productId, warehouseId: doc.warehouseId, qty: l.qty, viewerId: ctx.userId);
      await requireValidBatchCoverage(db, productId: l.productId, warehouseId: doc.warehouseId, qty: l.qty);
      final cost = (bal != null && bal.averageCost > 0) ? bal.averageCost : product.costPrice;
      final List<Map<String, dynamic>> deductions;
      try {
        deductions = await db.consumeBatchesForIssue(
            productId: l.productId, warehouseId: doc.warehouseId, quantity: l.qty);
      } on Object {
        throw WhError('batch_expired', 409, {'productId': l.productId});
      }
      await db.adjustStock(
        productId: l.productId, warehouseId: doc.warehouseId, quantity: -l.qty, type: 'transfer_out',
        referenceType: 'wh_transfer', referenceId: doc.id, userId: ctx.userId, unitCost: cost,
        notes: WhConstants.transferOutNote(doc.toWarehouseId, doc.gid),
      );
      if (bins) await db.syncDefaultBinStock(l.productId, doc.warehouseId);
      await db.customStatement('UPDATE wh_mobile_doc_lines SET unit_cost = ? WHERE id = ?', [cost, l.id]);
      await store.setLineExtra(l.id, {
        'lots': [
          for (final d in deductions)
            {
              'batchNumber': d['batchNumber'],
              'expiry': (d['expiryDate'] as DateTime).millisecondsSinceEpoch,
              'qty': (d['quantity'] as num).toDouble(),
              'unitCost': (d['unitCost'] as num).toDouble(),
            },
        ],
      });
      value += l.qty * cost;
    }
    await _post(
      description: WhConstants.transferOutJournal(doc.gid), warehouseId: doc.warehouseId, amount: value,
      refType: 'wh_transfer_out', docId: doc.id, debit: 'goods_in_transit', credit: 'inventory',
    );
    return store.transition(doc, 'dispatch', expectedVersion: expectedVersion, data: {...doc.data, 'dispatchedBy': ctx.userId});
  }

  /// [received] maps line id -> (ok, damaged). Lines left out count as 0.
  Future<WhDoc> receive(
    WhDoc doc,
    WhCtx ctx,
    Map<String, ({double ok, double damaged})> received, {
    int? expectedVersion,
  }) async {
    if (doc.toWarehouseId == null || !ctx.scope.allows(doc.toWarehouseId!)) throw WhError('warehouse_forbidden', 403);
    if (doc.state != 'in_transit') throw WhError('invalid_transition', 409, {'state': doc.state, 'action': 'receive'});
    final to = doc.toWarehouseId!;
    final bins = await db.getSettingValue('warehouse_bins_enabled') == 'true';
    final lines = await store.lines(doc.id);
    final byGid = {for (final l in lines) l.gid: l};
    for (final g in received.keys) {
      if (!byGid.containsKey(g)) throw WhError('bad_request', 400);
    }
    var value = 0.0, anyShort = false;
    final damagedLines = <(WhLine, double)>[];
    for (final l in lines) {
      final r = received[l.gid] ?? (ok: 0.0, damaged: 0.0);
      final total = r.ok + r.damaged;
      if (total > l.qty + 1e-9) {
        throw WhError('over_receipt', 409, {'productId': l.productId, 'dispatched': fmtQty(l.qty)});
      }
      final cost = l.unitCost ?? 0;
      final (taken, left) = _split(_lotsOf(l, 'lots'), total);
      if (total > 0) {
        await db.adjustStock(
          productId: l.productId, warehouseId: to, quantity: total, type: 'transfer_in',
          referenceType: 'wh_transfer', referenceId: doc.id, userId: ctx.userId, unitCost: cost,
          notes: WhConstants.transferInNote(doc.warehouseId, doc.gid),
        );
        for (final lot in taken) {
          await _restoreLot(l.productId, to, lot, (lot['qty']! as num).toDouble());
        }
        if (bins) await db.syncDefaultBinStock(l.productId, to);
      }
      if (r.damaged > 0) damagedLines.add((l, r.damaged));
      final short = l.qty - total;
      if (short > 1e-9) anyShort = true;
      await store.setLineExtra(l.id, {
        ...l.extra,
        'received': r.ok,
        'damaged': r.damaged,
        'short': short < 1e-9 ? 0.0 : short,
        'shortLots': left,
      });
      value += total * cost;
    }
    await _post(
      description: WhConstants.transferInJournal(doc.gid), warehouseId: to, amount: value,
      refType: 'wh_transfer_in', docId: doc.id, debit: 'inventory', credit: 'goods_in_transit',
    );
    if (damagedLines.isNotEmpty) {
      final v = await store.create(
        kind: 'voucher', state: 'pending', warehouseId: to, createdBy: ctx.userId, deviceId: ctx.deviceId,
        refType: 'wh_transfer', refId: doc.gid, reason: WhConstants.transferDamageReason(doc.gid),
        data: {'type': 'damage'},
      );
      for (final (l, q) in damagedLines) {
        await store.addLine(v, lineGid: UuidV7.generate(), productId: l.productId, qty: q,
            unitCost: l.unitCost, counterUserId: ctx.userId);
      }
    }
    return store.transition(
      doc, anyShort ? 'receive_short' : 'receive',
      expectedVersion: expectedVersion, data: {...doc.data, 'receivedBy': ctx.userId},
    );
  }

  /// [resolution] is `return_to_source` or `write_off_loss` for the whole shortage.
  Future<WhDoc> resolve(WhDoc doc, int approver, String resolution, {int? expectedVersion}) async {
    final d = doc.data;
    requireDistinct(approver, [doc.createdBy, d['dispatchedBy'] as int?, d['receivedBy'] as int?]);
    if (resolution != 'return_to_source' && resolution != 'write_off_loss') throw WhError('bad_request', 400);
    if (doc.state != 'received_short') throw WhError('invalid_transition', 409, {'state': doc.state, 'action': 'resolve'});
    final bins = await db.getSettingValue('warehouse_bins_enabled') == 'true';
    var value = 0.0;
    for (final l in await store.lines(doc.id)) {
      final short = (l.extra['short'] as num?)?.toDouble() ?? 0;
      if (short <= 1e-9) continue;
      final cost = l.unitCost ?? 0;
      value += short * cost;
      if (resolution == 'return_to_source') {
        await db.adjustStock(
          productId: l.productId, warehouseId: doc.warehouseId, quantity: short, type: 'transfer_in',
          referenceType: 'wh_transfer', referenceId: doc.id, userId: approver, unitCost: cost,
          notes: WhConstants.transferReturnNote(doc.gid),
        );
        for (final lot in _lotsOf(l, 'shortLots')) {
          await _restoreLot(l.productId, doc.warehouseId, lot, (lot['qty']! as num).toDouble());
        }
        if (bins) await db.syncDefaultBinStock(l.productId, doc.warehouseId);
      }
      await store.setLineExtra(l.id, {...l.extra, 'short': 0.0, 'shortLots': <Object>[], 'resolution': resolution});
    }
    final back = resolution == 'return_to_source';
    await _post(
      description: back ? WhConstants.transferReturnJournal(doc.gid) : WhConstants.transferLossJournal(doc.gid),
      warehouseId: doc.warehouseId, amount: value, refType: 'wh_transfer_resolve', docId: doc.id,
      debit: back ? 'inventory' : 'inventory_shrinkage', credit: 'goods_in_transit',
    );
    return store.transition(doc, 'resolve', expectedVersion: expectedVersion, approvedBy: approver,
        data: {...doc.data, 'resolution': resolution});
  }
}
