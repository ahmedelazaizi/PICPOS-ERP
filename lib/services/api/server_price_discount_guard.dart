// S-03 — server-side price / discount guard for POST /api/sales.
//
// The UI enforces `pos_price_edit`, `pos_return_price_edit` and the discount
// cap; the API used to trust `unitPrice` / `discount` from the body, so a paired
// cashier device could sell at any price. [evaluateSalePriceDiscount] is pure
// (no DB, no I/O); [enforceSalePriceDiscountPolicy] loads the facts and answers
// 403 + a critical audit event.
//
// ⚠️ Price source: the UI also sells at offer prices and customer price levels
// that the server cannot reproduce with confidence. So the handler runs in the
// relaxed mode (`strictCatalogPrice: false`): a sale line is refused only when it
// is BELOW COST (or a no-invoice return price differs from the catalog) without
// the permission. Strict mode (any price ≠ catalog) is kept for callers that can
// prove no offer applies.
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';

import '../../core/permissions/permission_codes.dart';
import '../../data/database/database.dart';
import '../../domain/models/quick_sale_policy.dart';
import '../audit_log.dart';
import 'approval_proof.dart';
import 'api_user_context.dart';

/// Tolerance for comparing prices (rounding), in currency units.
const double kPriceTolerance = 0.011;

/// Tolerance for comparing discount percentages.
const double kDiscountPercentTolerance = 0.05;

enum GuardViolationKind {
  priceNotCatalog,
  priceBelowCost,
  returnPriceNotCatalog,
  lineDiscountOverCap,
  invoiceDiscountOverCap,
  // Returns against an original invoice (server_return_exchange_guard.dart).
  returnPriceOverOriginal,
  returnQtyOverRemaining,
  returnProductNotOnInvoice,
}

class GuardLine {
  const GuardLine({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.discountPercent,
    this.quantityInBase = 1,
  });

  final int productId;
  final double quantity;

  /// Price per SALE unit as sent by the client.
  final double unitPrice;

  /// Line discount as a percentage (the client's `discount` field).
  final double discountPercent;
  final double quantityInBase;
}

/// What the DB says about a product.
class GuardProduct {
  const GuardProduct({
    required this.costPrice,
    required this.basePrices,
    this.unitPrices = const [],
  });

  /// Cost per BASE unit (0 = unknown).
  final double costPrice;

  /// Every catalog price level per base unit (sale, wholesale, apps...).
  final List<double> basePrices;

  /// Prices of the product's own sale units (carton, box...).
  final List<double> unitPrices;
}

class GuardPolicy {
  const GuardPolicy({
    required this.capPercent,
    this.userMaxDiscount,
    this.userLimitIsPercent = true,
  });

  /// `quickSaleDiscountCap` of the stored policy.
  final double capPercent;

  /// `users.max_discount_percent` (null = no personal limit).
  final double? userMaxDiscount;
  final bool userLimitIsPercent;
}

class GuardViolation {
  const GuardViolation(this.kind, this.message,
      {this.productId,
      required this.requiredPermission,
      this.overridable = true});

  /// `false` = no permission or approval proof clears it (e.g. returning more
  /// units than were sold).
  final bool overridable;

  final GuardViolationKind kind;
  final String message;
  final int? productId;

  /// Permission whose grant (or `X-Approval-Proof`) would clear it.
  final String requiredPermission;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'message': message,
        'productId': ?productId,
        'requiredPermission': requiredPermission,
      };
}

bool _matchesCatalog(GuardLine l, GuardProduct p) {
  final factor = l.quantityInBase > 0 ? l.quantityInBase : 1.0;
  return [...p.unitPrices, for (final b in p.basePrices) b * factor]
      .where((c) => c > 0)
      .any((c) => (c - l.unitPrice).abs() <= kPriceTolerance);
}

/// Violations of [lines] given the DB facts. Empty list = allowed.
///
/// [hasInvoice] is meaningful for returns only. [headerDiscount] is the
/// invoice `discount` field (line discounts + invoice discount, as the client
/// builds it). Discounts are not checked on returns (they repeat the original).
List<GuardViolation> evaluateSalePriceDiscount({
  required List<GuardLine> lines,
  required Map<int, GuardProduct> products,
  required Set<String> permissions,
  required GuardPolicy policy,
  required double headerDiscount,
  bool isReturn = false,
  bool hasInvoice = true,
  bool strictCatalogPrice = false,
}) {
  final out = <GuardViolation>[];
  final canEditPrice = permissions.contains(PermissionCodes.posPriceEdit);
  final canEditReturnPrice =
      permissions.contains(PermissionCodes.posReturnPriceEdit);

  for (final l in lines) {
    final p = products[l.productId];
    if (p == null) continue;
    final onCatalog = _matchesCatalog(l, p);
    if (isReturn) {
      if (!hasInvoice && !canEditReturnPrice && !onCatalog) {
        out.add(GuardViolation(
          GuardViolationKind.returnPriceNotCatalog,
          'سعر سطر مرتجع بلا فاتورة يخالف سعر الصنف ويحتاج صلاحية '
          '${PermissionCodes.posReturnPriceEdit}',
          productId: l.productId,
          requiredPermission: PermissionCodes.posReturnPriceEdit,
        ));
      }
      continue;
    }
    if (canEditPrice || onCatalog) continue;
    final factor = l.quantityInBase > 0 ? l.quantityInBase : 1.0;
    final cost = p.costPrice * factor;
    if (strictCatalogPrice) {
      out.add(GuardViolation(
        GuardViolationKind.priceNotCatalog,
        'سعر السطر يخالف سعر الصنف ويحتاج صلاحية ${PermissionCodes.posPriceEdit}',
        productId: l.productId,
        requiredPermission: PermissionCodes.posPriceEdit,
      ));
    } else if (cost > 0 && l.unitPrice < cost - kPriceTolerance) {
      out.add(GuardViolation(
        GuardViolationKind.priceBelowCost,
        'سعر السطر أقل من التكلفة ويحتاج صلاحية ${PermissionCodes.posPriceEdit}',
        productId: l.productId,
        requiredPermission: PermissionCodes.posPriceEdit,
      ));
    }
  }
  if (isReturn) return out;

  // ── discounts ────────────────────────────────────────────────────────────
  final amountLimit =
      policy.userMaxDiscount != null && !policy.userLimitIsPercent;
  final cap = (policy.userMaxDiscount != null && policy.userLimitIsPercent)
      ? policy.userMaxDiscount!
      : policy.capPercent;
  bool within(double pct) => quickSaleDiscountAllowed(
      percent: pct - kDiscountPercentTolerance, cap: cap);

  var gross = 0.0;
  var lineDiscounts = 0.0;
  for (final l in lines) {
    final lineGross = l.quantity * l.unitPrice;
    gross += lineGross;
    lineDiscounts += lineGross * l.discountPercent / 100;
    if (!within(l.discountPercent)) {
      out.add(GuardViolation(
        GuardViolationKind.lineDiscountOverCap,
        'خصم السطر ${l.discountPercent.toStringAsFixed(1)}% يتجاوز الحد '
        'المسموح ${cap.toStringAsFixed(1)}%',
        productId: l.productId,
        requiredPermission: PermissionCodes.posDiscount,
      ));
    }
  }
  final base = gross - lineDiscounts;
  final invoiceOnly = headerDiscount - lineDiscounts;
  if (base > 0 && invoiceOnly > kPriceTolerance) {
    final pct = invoiceOnly / base * 100;
    if (!within(pct)) {
      out.add(GuardViolation(
        GuardViolationKind.invoiceDiscountOverCap,
        'خصم الفاتورة ${pct.toStringAsFixed(1)}% يتجاوز الحد '
        'المسموح ${cap.toStringAsFixed(1)}%',
        requiredPermission: PermissionCodes.posDiscount,
      ));
    }
  }
  if (amountLimit && headerDiscount > policy.userMaxDiscount! + kPriceTolerance) {
    out.add(GuardViolation(
      GuardViolationKind.invoiceDiscountOverCap,
      'مبلغ الخصم ${headerDiscount.toStringAsFixed(2)} يتجاوز حد المستخدم '
      '${policy.userMaxDiscount!.toStringAsFixed(2)}',
      requiredPermission: PermissionCodes.posDiscount,
    ));
  }
  return out;
}

/// Loads the facts, evaluates, and returns a 403 [Response] (after a critical
/// audit event) when the sale breaks the policy; `null` when it may proceed.
/// A valid `X-Approval-Proof` for the violated permission clears it.
Future<Response?> enforceSalePriceDiscountPolicy(
  Request request,
  AppDatabase db,
  Map<String, dynamic> data,
  List<SalesInvoiceItemsCompanion> items,
) async {
  final userId = ApiUserCtx.userIdOf(request);
  if (userId == null) return null; // requirePermission already refused.

  final productIds = {for (final i in items) i.productId.value};
  final products = <int, GuardProduct>{};
  for (final id in productIds) {
    final p = await (db.select(db.products)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (p == null) continue;
    final units = await (db.select(db.productUnits)
          ..where((u) => u.productId.equals(id) & u.deletedAt.isNull()))
        .get();
    products[id] = GuardProduct(
      costPrice: p.costPrice,
      basePrices: [
        p.salePrice,
        p.wholesalePrice,
        p.priceTalabat,
        p.priceCareem,
        p.priceAshyae,
      ],
      unitPrices: [for (final u in units) u.salePrice],
    );
  }

  final user = await (db.select(db.users)..where((u) => u.id.equals(userId)))
      .getSingleOrNull();
  final capRaw = await db.getSettingValue('pos_manual_discount_cap');
  final policy = GuardPolicy(
    capPercent: quickSaleDiscountCap(QuickSalePolicyValues(
        {'pos_manual_discount_cap': ?capRaw})),
    userMaxDiscount: user?.maxDiscountPercent,
    userLimitIsPercent: user?.discountLimitIsPercent ?? true,
  );

  Future<Set<String>> permissionsOf() async => {
        for (final c in [
          PermissionCodes.posPriceEdit,
          PermissionCodes.posReturnPriceEdit,
        ])
          if (await db.userHasPermission(userId, c)) c,
      };

  num n(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;
  final lines = [
    for (final i in items)
      GuardLine(
        productId: i.productId.value,
        quantity: i.quantity.value,
        unitPrice: i.unitPrice.value,
        discountPercent: i.discount.present ? i.discount.value : 0,
        quantityInBase: i.quantityInBase.present ? i.quantityInBase.value : 1,
      ),
  ];
  final isReturn = data['saleType'] == 'return';
  final hasInvoice = [data['originalInvoiceId'], data['originalInvoiceGlobalId']]
      .any((v) => v != null && '$v'.isNotEmpty && '$v' != '0');
  List<GuardViolation> run(Set<String> perms) => evaluateSalePriceDiscount(
        lines: lines,
        products: products,
        permissions: perms,
        policy: policy,
        headerDiscount: n(data['discount']).toDouble(),
        isReturn: isReturn,
        hasInvoice: hasInvoice,
      );

  return denyUnlessApproved(
      request, db, userId, data, run(await permissionsOf()));
}

/// Turns [violations] into a 403 (+ critical audit) unless a signed four-eyes
/// `X-Approval-Proof` stands in for the single missing permission. Empty list →
/// `null`. A violation with `overridable == false` can never be cleared.
/// [context] names the endpoint in the audit payload (`sale`/`return`/`exchange`).
Future<Response?> denyUnlessApproved(
  Request request,
  AppDatabase db,
  int userId,
  Map<String, dynamic> data,
  List<GuardViolation> violations, {
  String context = 'sale',
}) async {
  if (violations.isEmpty) return null;

  final claims = ApprovalProof.parse(request.headers[ApprovalGate.headerName]);
  if (claims != null &&
      violations.every(
          (v) => v.overridable && v.requiredPermission == claims.permission)) {
    final decision =
        await ApprovalGate.authorise(request, db, userId, claims.permission);
    if (decision != null && decision.isGranted) return null;
  }

  final user = await (db.select(db.users)..where((u) => u.id.equals(userId)))
      .getSingleOrNull();
  final message = violations.map((v) => v.message).join('؛ ');
  try {
    await AuditLog.record(
      'sale_price_discount_rejected',
      level: AuditLevel.critical,
      userId: userId,
      userName: user?.username ?? '#$userId',
      entityType: 'sales_invoice',
      payload: {
        'invoice': data['invoiceNumber'],
        'context': context,
        'violations': [for (final v in violations) v.toJson()],
      },
    );
  } catch (e) {
    debugPrint('[API] sale guard audit failed: $e');
  }
  return Response(
    403,
    body: jsonEncode({
      'error': 'مرفوض: $message',
      'code': 'price_discount_policy_violation',
      'violations': [for (final v in violations) v.toJson()],
    }),
    headers: const {'content-type': 'application/json'},
  );
}
