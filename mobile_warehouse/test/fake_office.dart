import 'dart:convert';

import 'package:picpos_api_client/picpos_api_client.dart';

import 'fakes.dart';

/// A scripted office for the document routes. It keeps a command log keyed by
/// `x-idempotency-key` like the real one: the same key is answered from the
/// log (`replayed: true`) and applied once. Two phones can share one office.
class FakeOffice extends FakeDesktop {
  final posts = <({String path, String key, Map<String, Object?> body, String? user})>[];

  /// The next N new commands fail with a bare `500 internal` (an unclassified
  /// exception at the office).
  int serverErrors = 0;
  int busyReplies = 0;

  /// The accounting period is closed: stock-posting commands answer 409
  /// `period_closed`, as the real host does.
  bool periodClosed = false;

  // Rules the real host applies (WH-011 / over-receipt), kept in step with it.
  final _lineOwner = <String, String>{}; // lineGlobalId -> receipt gid
  final _receiptLines = <String, List<({int productId, double qty})>>{}; // receipt gid -> lines
  final _log = <String, Map<String, Object?>>{};
  final transfers = <String, Map<String, Object?>>{};

  /// How many commands were actually applied (not replayed).
  int applied = 0;

  /// When set, every NEW command is refused with `409 <code>`.
  String? rejectWith;

  /// The accountant's switch: transfers answer `staged_transfers_disabled`.
  bool transfersDisabled = false;

  /// A count is open: the office answers item lookups without quantities.
  bool blindLookup = false;

  List<Map<String, Object?>> orders = [
    {
      'ref': 'PO1', 'id': 1, 'orderNumber': 'PO-0042', 'status': 'sent', 'warehouseId': 1,
      'items': [
        {'itemId': 9, 'productId': 5, 'name': 'Milk 1L', 'barcode': '6221234567890', 'trackExpiry': false, 'ordered': '12', 'received': '4'},
        {'itemId': 10, 'productId': 6, 'name': 'Yogurt', 'barcode': '6229999999999', 'trackExpiry': true, 'ordered': '20', 'received': '0'},
      ],
    },
  ];
  List<Map<String, Object?>> countTasks = [
    {
      'ref': 'T1', 'warehouseId': 1, 'warehouse': 'Main store',
      'items': [
        {'productId': 5, 'code': 'P-1', 'name': 'Milk 1L', 'barcode': '6221234567890'},
        {'productId': 6, 'code': 'P-2', 'name': 'Yogurt', 'barcode': '6229999999999'},
      ],
    },
  ];
  List<Map<String, Object?>> approvals = [
    {'type': 'voucher', 'ref': 'voucher-0001', 'warehouseId': 1, 'ageMinutes': 12, 'reason': 'damaged in aisle 3'},
    {'type': 'transfer_request', 'ref': 'transfer-0001', 'warehouseId': 1, 'ageMinutes': 3},
    {'type': 'count', 'ref': 'T1', 'warehouseId': 1, 'ageMinutes': 0},
  ];
  Map<String, Object?> review = {
    'ref': 'T1', 'warehouseId': 1, 'status': 'in_progress', 'passes': 1, 'recountNeeded': false, 'readyForApproval': true,
    'items': [
      {'productId': 5, 'name': 'Milk 1L', 'expected': '137', 'counted': '130', 'variance': '-7', 'movementsSinceCount': 0},
    ],
  };
  Map<String, Object?>? label = {'kind': 'item', 'productId': 5, 'code': 'P-1', 'name': 'Milk 1L', 'barcode': '6221234567890'};

  ApiResponse _json(Object body, [int status = 200]) => ApiResponse(status, jsonEncode(body));

  Map<String, Object?> _transferDoc(String gid) {
    final t = transfers[gid]!;
    return {
      'globalId': gid, 'kind': 'transfer', 'state': t['state'], 'version': 1, 'warehouseId': 1, 'toWarehouseId': 2,
      'lines': t['lines'],
    };
  }

  static const _next = {
    'approve': 'approved', 'reject': 'rejected', 'dispatch': 'in_transit', 'receive': 'received', 'resolve': 'closed',
  };

  @override
  ApiResponse handle(ApiRequest r) {
    final p = r.path;
    if (blindLookup && p == '/api/m1/wh/items') {
      return _json({
        'items': [
          {
            'id': 5, 'code': 'P-1', 'barcode': '6221234567890', 'name': 'Milk 1L',
            'stock': [
              {'warehouseId': 1, 'warehouse': 'Main store', 'blind': true},
            ],
          },
        ],
      });
    }
    final isDoc = p.startsWith('/api/m1/wh/') && p != '/api/m1/wh/session' && p != '/api/m1/wh/items';
    if (!isDoc) return super.handle(r);
    if (revoked) return const ApiResponse(401, '{"error":"device_revoked"}');

    if (r.method == 'GET') {
      if (p == '/api/m1/wh/po') return _json({'orders': orders});
      if (p == '/api/m1/wh/counts/tasks') return _json({'tasks': countTasks});
      if (p == '/api/m1/wh/approvals') return _json({'approvals': approvals, 'count': approvals.length});
      if (p == '/api/m1/wh/labels') {
        return label == null ? _json({'error': 'item_not_found'}, 404) : _json(label!);
      }
      if (p.endsWith('/review')) return _json(review);
      if (p == '/api/m1/wh/transfers') {
        if (transfersDisabled) return _json({'error': 'staged_transfers_disabled'}, 409);
        return _json({'docs': [for (final g in transfers.keys) _transferDoc(g)]});
      }
      return _json({'error': 'nf'}, 404);
    }

    final key = r.headers['x-idempotency-key'] ?? '';
    if (key.length < 8) return _json({'error': 'idempotency_key_required'}, 400);
    final seen = _log[key];
    if (seen != null) return _json({...seen, 'replayed': true});
    if (rejectWith != null) return _json({'error': rejectWith!}, 409);
    if (busyReplies > 0) {
      busyReplies--;
      return _json({'error': 'busy'}, 503);
    }
    if (serverErrors > 0) {
      serverErrors--;
      return _json({'error': 'internal'}, 500);
    }
    final postsStock = p.endsWith('/approve') || p.endsWith('/dispatch') || p.endsWith('/receive') || p == '/api/m1/wh/vouchers';
    if (periodClosed && postsStock) return _json({'error': 'period_closed'}, 409);

    final body = (r.body as Map?)?.cast<String, Object?>() ?? {};
    // PO receipts: a line id belongs to ONE receipt; submit refuses an excess.
    if (p.startsWith('/api/m1/wh/po/') && p.endsWith('/receipts')) {
      final gid = body['globalId']! as String;
      for (final l in (body['lines']! as List).cast<Map>()) {
        final owner = _lineOwner[l['lineGlobalId']];
        if (owner != null && owner != gid) return _json({'error': 'doc_mismatch'}, 409);
      }
      for (final l in (body['lines']! as List).cast<Map>()) {
        _lineOwner[l['lineGlobalId']! as String] = gid;
        (_receiptLines[gid] ??= []).add((productId: (l['productId']! as num).toInt(), qty: double.parse('${l['quantity']}')));
      }
    } else if (p.startsWith('/api/m1/wh/receipts/') && p.endsWith('/submit')) {
      final gid = p.split('/')[p.split('/').length - 2];
      final lines = _receiptLines[gid];
      if (lines == null || lines.isEmpty) return _json({'error': 'doc_not_found'}, 404);
      for (final item in (orders.first['items']! as List).cast<Map<String, Object?>>()) {
        final incoming = lines.where((l) => l.productId == item['productId']).fold<double>(0, (s, l) => s + l.qty);
        if (double.parse('${item['received']}') + incoming > double.parse('${item['ordered']}') + 1e-9) {
          return _json({'error': 'over_receipt'}, 409);
        }
      }
    }
    final token = r.headers['x-session-token'] ?? '';
    posts.add((path: p, key: key, body: body, user: token.startsWith('SESS-') ? token.substring(5) : null));
    applied++;
    Map<String, Object?> out = {'ok': true};
    if (p == '/api/m1/wh/transfers') {
      final gid = body['globalId']! as String;
      transfers[gid] = {'state': 'requested', 'lines': [for (final l in (body['lines'] as List)) {'lineGlobalId': (l as Map)['lineGlobalId'], 'productId': l['productId'], 'quantity': l['quantity'], 'condition': 'ok'}]};
      out = {'doc': _transferDoc(gid)};
    } else if (p.startsWith('/api/m1/wh/transfers/')) {
      final parts = p.split('/');
      final gid = parts[parts.length - 2], action = parts.last;
      final t = transfers[gid];
      if (t == null) return _json({'error': 'doc_not_found'}, 404);
      t['state'] = _next[action] ?? t['state'];
      out = {'doc': _transferDoc(gid)};
    }
    _log[key] = out;
    return _json(out);
  }
}
