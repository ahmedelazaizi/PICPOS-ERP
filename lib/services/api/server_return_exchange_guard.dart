// S-03 (part 2) — server-side guard for POST /api/sales/return and
// POST /api/sales/exchange.
//
// The UI return flow (`processSalesReturn`) always refunds at the ORIGINAL line's
// `unitPrice` (the invoice-level discount and tax are carried as the line's
// frozen `discount` / `taxAmount`, never as a different price) and refuses more
// than "sold − already returned" per product. The API trusted the body for both.
//
//  * Return against an original invoice → per product: price must not exceed the
//    price it was sold at (needs `pos_return_price_edit` otherwise), the product
//    must be on that invoice, and the quantity must fit the remaining one
//    (never overridable). Everything is compared in BASE units so a carton
//    return against a piece sale is judged fairly.
//  * Return without an invoice → the existing no-invoice rule of
//    [evaluateSalePriceDiscount] (`pos_return_price_edit`).
//  * Return that names an invoice the server does not hold (sync lag) → not
//    refused for being unknown; its price is only capped by the highest catalog
//    price, so a fake invoice id cannot be used to dodge the no-invoice rule.
//  * Exchange → return legs as above (all legs together, so a sound/damaged
//    split cannot double the quantity) + the new-sale lines go through
//    [enforceSalePriceDiscountPolicy] exactly as in POST /api/sales.
//
// Concurrency: the remaining-quantity read and the insert are not one atomic
// step, so the handlers hold [ReturnInvoiceLock] for the original invoice from
// the check to the end of the insert. The API server is a single isolate over
// one SQLite connection, so an in-process per-invoice FIFO lock is enough; the
// loser re-reads the remaining quantity after the winner committed and gets the
// normal 403 `returnQtyOverRemaining`.
import 'dart:async';

import 'package:drift/drift.dart';

import 'package:shelf/shelf.dart';

import '../../core/permissions/permission_codes.dart';
import '../../data/database/database.dart';
import '../../domain/models/return_original_link.dart';
import 'api_user_context.dart';
import 'server_price_discount_guard.dart';

const double _qtyTolerance = 0.001;

/// FIFO async lock keyed by original invoice id. [acquire] returns the release
/// callback (idempotent); a null key (no original held) takes no lock.
class ReturnInvoiceLock {
  ReturnInvoiceLock._();
  static final Map<int, Future<void>> _tails = {};

  static Future<void Function()> acquire(int? invoiceId) async {
    if (invoiceId == null) return () {};
    final previous = _tails[invoiceId] ?? Future<void>.value();
    final gate = Completer<void>();
    final tail = previous.then((_) => gate.future);
    _tails[invoiceId] = tail;
    await previous;
    var released = false;
    return () {
      if (released) return;
      released = true;
      gate.complete();
      if (identical(_tails[invoiceId], tail)) _tails.remove(invoiceId);
    };
  }
}

double _factor(double qib) => qib > 0 ? qib : 1.0;

bool _claimsInvoice(Map<String, dynamic> data) =>
    [data['originalInvoiceId'], data['originalInvoiceGlobalId']]
        .any((v) => v != null && '$v'.isNotEmpty && '$v' != '0');

/// Base-unit quantity already returned against [original], per product.
/// Both persisted shapes are read (they are mutually exclusive per return):
/// `sale_type='return'` rows linked through `notes`, and the standalone
/// `sales_return` stock movements keyed on the original id.
Future<Map<int, double>> returnedBaseQtyByProduct(
    AppDatabase db, SalesInvoiceData original) async {
  final out = <int, double>{};
  final gid = original.globalId;
  final rows = await (db.select(db.salesInvoices)
        ..where((s) =>
            s.saleType.equals('return') &
            s.isDeleted.equals(false) &
            s.notes.like('Return for invoice #%') &
            (s.notes.like('%#${original.id}%') |
                (gid == null || gid.isEmpty
                    ? const Constant(false)
                    : s.notes.like('%|gid:$gid%')))))
      .get();
  for (final r in rows) {
    final noteGid = returnOriginalGidFromNote(r.notes);
    final byGid = noteGid != null && gid != null && gid.isNotEmpty;
    if (byGid
        ? noteGid != gid
        : returnOriginalIdFromNote(r.notes) != original.id) {
      continue;
    }
    final items = await (db.select(db.salesInvoiceItems)
          ..where((i) => i.invoiceId.equals(r.id) & i.deletedAt.isNull()))
        .get();
    for (final i in items) {
      out[i.productId] =
          (out[i.productId] ?? 0) + i.quantity * _factor(i.quantityInBase);
    }
  }
  final moves = await (db.select(db.stockMovements)
        ..where((m) =>
            m.movementType.equals('return') &
            m.referenceType.equals('sales_return') &
            m.referenceId.equals(original.id)))
      .get();
  for (final m in moves) {
    out[m.productId] = (out[m.productId] ?? 0) + m.quantity.abs();
  }
  return out;
}

/// Violations of return [items] against [original] (pure given the DB facts).
Future<List<GuardViolation>> evaluateReturnAgainstOriginal(
  AppDatabase db,
  SalesInvoiceData original,
  List<SalesInvoiceItemsCompanion> items, {
  required bool canEditReturnPrice,
}) async {
  final sold = await (db.select(db.salesInvoiceItems)
        ..where((i) => i.invoiceId.equals(original.id) & i.deletedAt.isNull()))
      .get();
  final soldBase = <int, double>{};
  final maxBasePrice = <int, double>{};
  for (final s in sold) {
    final f = _factor(s.quantityInBase);
    soldBase[s.productId] = (soldBase[s.productId] ?? 0) + s.quantity * f;
    final p = s.unitPrice / f;
    if (p > (maxBasePrice[s.productId] ?? -1)) maxBasePrice[s.productId] = p;
  }
  final returned = await returnedBaseQtyByProduct(db, original);

  final out = <GuardViolation>[];
  final requested = <int, double>{};
  for (final i in items) {
    final pid = i.productId.value;
    final f = _factor(i.quantityInBase.present ? i.quantityInBase.value : 1.0);
    if (!soldBase.containsKey(pid)) {
      out.add(GuardViolation(
        GuardViolationKind.returnProductNotOnInvoice,
        'الصنف رقم $pid غير موجود في الفاتورة الأصلية ${original.invoiceNumber}',
        productId: pid,
        requiredPermission: PermissionCodes.salesReturnCreate,
        overridable: false,
      ));
      continue;
    }
    requested[pid] = (requested[pid] ?? 0) + i.quantity.value * f;
    final allowed = maxBasePrice[pid]! * f;
    if (!canEditReturnPrice && i.unitPrice.value > allowed + kPriceTolerance) {
      out.add(GuardViolation(
        GuardViolationKind.returnPriceOverOriginal,
        'سعر المرتجع ${i.unitPrice.value.toStringAsFixed(2)} أعلى من سعر البيع '
        'الأصلي ${allowed.toStringAsFixed(2)} ويحتاج صلاحية '
        '${PermissionCodes.posReturnPriceEdit}',
        productId: pid,
        requiredPermission: PermissionCodes.posReturnPriceEdit,
      ));
    }
  }
  for (final e in requested.entries) {
    final remaining = soldBase[e.key]! - (returned[e.key] ?? 0);
    if (e.value > remaining + _qtyTolerance) {
      out.add(GuardViolation(
        GuardViolationKind.returnQtyOverRemaining,
        'الكمية المطلوب إرجاعها ${e.value.toStringAsFixed(2)} أكبر من المتبقي '
        '${(remaining < 0 ? 0 : remaining).toStringAsFixed(2)} للصنف رقم '
        '${e.key} في الفاتورة ${original.invoiceNumber}',
        productId: e.key,
        requiredPermission: PermissionCodes.salesReturnCreate,
        overridable: false,
      ));
    }
  }
  return out;
}

/// Orphan return (names an invoice this server does not hold): cap each price
/// at the product's highest catalog price.
Future<List<GuardViolation>> _orphanCeilingViolations(
  AppDatabase db,
  List<SalesInvoiceItemsCompanion> items,
) async {
  final out = <GuardViolation>[];
  for (final i in items) {
    final pid = i.productId.value;
    final p = await (db.select(db.products)..where((t) => t.id.equals(pid)))
        .getSingleOrNull();
    if (p == null) continue;
    final units = await (db.select(db.productUnits)
          ..where((u) => u.productId.equals(pid) & u.deletedAt.isNull()))
        .get();
    final f = _factor(i.quantityInBase.present ? i.quantityInBase.value : 1.0);
    final ceiling = [
      for (final b in [
        p.salePrice,
        p.wholesalePrice,
        p.priceTalabat,
        p.priceCareem,
        p.priceAshyae,
      ])
        b * f,
      for (final u in units) u.salePrice,
    ].fold<double>(0, (a, b) => b > a ? b : a);
    if (ceiling > 0 && i.unitPrice.value > ceiling + kPriceTolerance) {
      out.add(GuardViolation(
        GuardViolationKind.returnPriceOverOriginal,
        'سعر المرتجع ${i.unitPrice.value.toStringAsFixed(2)} أعلى من أعلى سعر '
        'للصنف ${ceiling.toStringAsFixed(2)} ويحتاج صلاحية '
        '${PermissionCodes.posReturnPriceEdit}',
        productId: pid,
        requiredPermission: PermissionCodes.posReturnPriceEdit,
      ));
    }
  }
  return out;
}

/// 403 [Response] when the return breaks the policy; `null` to proceed.
/// [original] is the invoice the server resolved (null = none / not held).
Future<Response?> enforceReturnPolicy(
  Request request,
  AppDatabase db,
  Map<String, dynamic> data,
  List<SalesInvoiceItemsCompanion> items, {
  required SalesInvoiceData? original,
  String context = 'return',
}) async {
  final userId = ApiUserCtx.userIdOf(request);
  if (userId == null) return null;
  final asReturn = {...data, 'saleType': 'return'};

  if (original == null) {
    // No invoice named → the no-invoice return rule; named but unknown → cap.
    if (!_claimsInvoice(data)) {
      return enforceSalePriceDiscountPolicy(request, db, asReturn, items);
    }
    final canEdit =
        await db.userHasPermission(userId, PermissionCodes.posReturnPriceEdit);
    final v = canEdit ? <GuardViolation>[] : await _orphanCeilingViolations(db, items);
    return denyUnlessApproved(request, db, userId, data, v, context: context);
  }

  final canEdit =
      await db.userHasPermission(userId, PermissionCodes.posReturnPriceEdit);
  final violations = await evaluateReturnAgainstOriginal(db, original, items,
      canEditReturnPrice: canEdit);
  return denyUnlessApproved(request, db, userId, data, violations,
      context: context);
}

/// Exchange guard: every return leg (merged) against the original, then the new
/// sale lines exactly like POST /api/sales. [parseItems] is the handler's own
/// payload→items parser so product resolution cannot drift.
Future<Response?> enforceExchangePolicy(
  Request request,
  AppDatabase db,
  Map<String, dynamic> data, {
  required List<dynamic> legs,
  required Map<String, dynamic> sale,
  required SalesInvoiceData? original,
  required Future<List<SalesInvoiceItemsCompanion>> Function(
          List<dynamic> rawItems, String label)
      parseItems,
}) async {
  final returnItems = <SalesInvoiceItemsCompanion>[];
  for (final leg in legs) {
    final raw = ((leg as Map)['items'] as List?) ?? const <dynamic>[];
    returnItems.addAll(await parseItems(raw, 'exchange return'));
  }
  final deniedReturn = await enforceReturnPolicy(
      request, db, {...data, 'discount': 0}, returnItems,
      original: original, context: 'exchange');
  if (deniedReturn != null) return deniedReturn;

  final saleItems = await parseItems(
      (sale['items'] as List?) ?? const <dynamic>[], 'exchange sale');
  return enforceSalePriceDiscountPolicy(
      request, db, {...sale, 'saleType': 'default'}, saleItems);
}
