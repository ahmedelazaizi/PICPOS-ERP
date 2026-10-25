/// Contract of the warehouse documents (W2-W5): purchase-order receipts,
/// staged transfers, vouchers, blind counts, approvals inbox, labels.
/// Mirrors `lib/services/api/m1_wh/*` on the desktop. Decimals are strings.
/// A counter-facing DTO (`WhCountTask`) deliberately has NO quantity field.
library;

abstract final class WhDocPaths {
  static const po = '/api/m1/wh/po';
  static const receipts = '/api/m1/wh/receipts';
  static const transfers = '/api/m1/wh/transfers';
  static const vouchers = '/api/m1/wh/vouchers';
  static const counts = '/api/m1/wh/counts';
  static const approvals = '/api/m1/wh/approvals';
  static const labels = '/api/m1/wh/labels';
  static const locationByBarcode = '/api/m1/wh/locations/by-barcode';
}

Map<String, Object?> _m(Object? o) => (o as Map).cast<String, Object?>();
List<Map<String, Object?>> _list(Object? o) => [for (final e in (o as List? ?? const [])) _m(e)];

class WhPoItem {
  const WhPoItem({
    required this.itemId,
    required this.productId,
    required this.name,
    required this.barcode,
    required this.trackExpiry,
    required this.ordered,
    required this.received,
  });
  final int itemId;
  final int productId;
  final String? name;
  final String? barcode;
  final bool trackExpiry;
  final String ordered;
  final String received;

  /// Still to receive (never negative), for the progress line «6/12».
  double get remaining {
    final r = (double.tryParse(ordered) ?? 0) - (double.tryParse(received) ?? 0);
    return r < 0 ? 0 : r;
  }

  factory WhPoItem.fromJson(Map<String, Object?> m) => WhPoItem(
        itemId: (m['itemId'] as num).toInt(),
        productId: (m['productId'] as num).toInt(),
        name: m['name'] as String?,
        barcode: m['barcode'] as String?,
        trackExpiry: m['trackExpiry'] == true,
        ordered: '${m['ordered'] ?? '0'}',
        received: '${m['received'] ?? '0'}',
      );
}

class WhPurchaseOrder {
  const WhPurchaseOrder({
    required this.ref,
    required this.orderNumber,
    required this.status,
    required this.warehouseId,
    required this.items,
  });
  final String ref;
  final String orderNumber;
  final String status;
  final int warehouseId;
  final List<WhPoItem> items;

  factory WhPurchaseOrder.fromJson(Map<String, Object?> m) => WhPurchaseOrder(
        ref: '${m['ref']}',
        orderNumber: '${m['orderNumber'] ?? ''}',
        status: '${m['status'] ?? ''}',
        warehouseId: (m['warehouseId'] as num).toInt(),
        items: [for (final i in _list(m['items'])) WhPoItem.fromJson(i)],
      );
}

/// One received line the phone sends. `lineGlobalId` is client-generated.
class WhReceiptLineInput {
  const WhReceiptLineInput({
    required this.lineGlobalId,
    required this.productId,
    required this.quantity,
    this.condition = 'ok',
    this.batchNumber,
    this.expiryDate,
    this.locationBarcode,
  });
  final String lineGlobalId;
  final int productId;
  final String quantity;
  final String condition; // ok | damaged
  final String? batchNumber;
  final String? expiryDate; // yyyy-mm-dd
  final String? locationBarcode;

  Map<String, Object?> toJson() => {
        'lineGlobalId': lineGlobalId,
        'productId': productId,
        'quantity': quantity,
        'condition': condition,
        if (batchNumber != null) 'batchNumber': batchNumber,
        if (expiryDate != null) 'expiryDate': expiryDate,
        if (locationBarcode != null) 'locationBarcode': locationBarcode,
      };
}

class WhDocLine {
  const WhDocLine({required this.lineGlobalId, required this.productId, required this.quantity, required this.condition});
  final String lineGlobalId;
  final int productId;
  final String quantity;
  final String condition;
  factory WhDocLine.fromJson(Map<String, Object?> m) => WhDocLine(
        lineGlobalId: '${m['lineGlobalId']}',
        productId: (m['productId'] as num).toInt(),
        quantity: '${m['quantity']}',
        condition: '${m['condition'] ?? 'ok'}',
      );
}

/// A receipt / transfer / voucher as the server sees it.
class WhDoc {
  const WhDoc({
    required this.globalId,
    required this.kind,
    required this.state,
    required this.version,
    required this.warehouseId,
    required this.toWarehouseId,
    required this.reason,
    required this.lines,
  });
  final String globalId;
  final String kind;
  final String state;
  final int version;
  final int warehouseId;
  final int? toWarehouseId;
  final String? reason;
  final List<WhDocLine> lines;

  factory WhDoc.fromJson(Map<String, Object?> m) => WhDoc(
        globalId: '${m['globalId']}',
        kind: '${m['kind']}',
        state: '${m['state']}',
        version: (m['version'] as num?)?.toInt() ?? 0,
        warehouseId: (m['warehouseId'] as num).toInt(),
        toWarehouseId: (m['toWarehouseId'] as num?)?.toInt(),
        reason: m['reason'] as String?,
        lines: [for (final l in _list(m['lines'])) WhDocLine.fromJson(l)],
      );
}

class WhCountItem {
  const WhCountItem({required this.productId, required this.code, required this.name, required this.barcode});
  final int productId;
  final String? code;
  final String? name;
  final String? barcode;
  factory WhCountItem.fromJson(Map<String, Object?> m) => WhCountItem(
        productId: (m['productId'] as num).toInt(),
        code: m['code'] as String?,
        name: m['name'] as String?,
        barcode: m['barcode'] as String?,
      );
}

/// What a COUNTER gets for a count task: the list of goods to count and
/// nothing else - no expected quantity, variance or value (ADR-MC3).
class WhCountTask {
  const WhCountTask({
    required this.ref,
    required this.warehouseId,
    required this.warehouse,
    required this.items,
    required this.draftGlobalId,
  });
  final String ref;
  final int warehouseId;
  final String? warehouse;
  final List<WhCountItem> items;
  final String? draftGlobalId;
  factory WhCountTask.fromJson(Map<String, Object?> m) => WhCountTask(
        ref: '${m['ref']}',
        warehouseId: (m['warehouseId'] as num).toInt(),
        warehouse: m['warehouse'] as String?,
        items: [for (final i in _list(m['items'])) WhCountItem.fromJson(i)],
        draftGlobalId: m['draftGlobalId'] as String?,
      );
}

/// Manager view of one counted item (only returned to `stock_adjust_approve`).
class WhCountReviewRow {
  const WhCountReviewRow({
    required this.productId,
    required this.name,
    required this.expected,
    required this.counted,
    required this.variance,
    required this.movementsSinceCount,
  });
  final int productId;
  final String? name;
  final String expected;
  final String? counted;
  final String? variance;
  final int movementsSinceCount;
  factory WhCountReviewRow.fromJson(Map<String, Object?> m) => WhCountReviewRow(
        productId: (m['productId'] as num).toInt(),
        name: m['name'] as String?,
        expected: '${m['expected']}',
        counted: m['counted'] as String?,
        variance: m['variance'] as String?,
        movementsSinceCount: (m['movementsSinceCount'] as num?)?.toInt() ?? 0,
      );
}

class WhCountReview {
  const WhCountReview({required this.ref, required this.recountNeeded, required this.readyForApproval, required this.rows});
  final String ref;
  final bool recountNeeded;
  final bool readyForApproval;
  final List<WhCountReviewRow> rows;
  factory WhCountReview.fromJson(Map<String, Object?> m) => WhCountReview(
        ref: '${m['ref']}',
        recountNeeded: m['recountNeeded'] == true,
        readyForApproval: m['readyForApproval'] == true,
        rows: [for (final r in _list(m['items'])) WhCountReviewRow.fromJson(r)],
      );
}

/// One thing waiting for the caller's approval. `type`: transfer_request |
/// transfer_shortage | voucher | count.
class WhApprovalItem {
  const WhApprovalItem({required this.type, required this.ref, required this.warehouseId, required this.ageMinutes, required this.reason});
  final String type;
  final String ref;
  final int warehouseId;
  final int ageMinutes;
  final String? reason;
  factory WhApprovalItem.fromJson(Map<String, Object?> m) => WhApprovalItem(
        type: '${m['type']}',
        ref: '${m['ref']}',
        warehouseId: (m['warehouseId'] as num).toInt(),
        ageMinutes: (m['ageMinutes'] as num?)?.toInt() ?? 0,
        reason: m['reason'] as String?,
      );
}

/// Data for one printed label. `kind`: item | location.
class WhLabelData {
  const WhLabelData({required this.kind, required this.barcode, required this.title, required this.subtitle});
  final String kind;
  final String barcode;
  final String title;
  final String subtitle;
  factory WhLabelData.fromJson(Map<String, Object?> m) => WhLabelData(
        kind: '${m['kind']}',
        barcode: '${m['barcode']}',
        title: '${m['name'] ?? m['binCode'] ?? ''}',
        subtitle: '${m['code'] ?? ''}',
      );
}

class WhBin {
  const WhBin({required this.id, required this.warehouseId, required this.binCode, required this.barcode});
  final int id;
  final int warehouseId;
  final String binCode;
  final String barcode;
  factory WhBin.fromJson(Map<String, Object?> m) => WhBin(
        id: (m['id'] as num).toInt(),
        warehouseId: (m['warehouseId'] as num).toInt(),
        binCode: '${m['binCode']}',
        barcode: '${m['barcode']}',
      );
}

/// A write answer: the body plus whether the server replayed a stored result.
class WhCommandResult {
  const WhCommandResult(this.body);
  final Map<String, Object?> body;
  bool get replayed => body['replayed'] == true;
  WhDoc? get doc {
    final d = body['doc'] ?? body['receipt'];
    return d is Map ? WhDoc.fromJson(_m(d)) : null;
  }
}
