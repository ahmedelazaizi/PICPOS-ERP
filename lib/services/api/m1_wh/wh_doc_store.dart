// Document store + explicit state machines of the warehouse phone
// (plan 2026-10-23 ADR-W5, §B.2-7). Everything goes through [WhDocStore.command]
// so that a write is (a) idempotent by the client's command id, (b) refused
// with `409 idempotency_conflict` when the same id arrives with another body,
// and (c) logged with the acting user and device INSIDE the transaction of its
// effect (unlike the post-commit `processed_messages` of the generic API).
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/utils/uuid_v7.dart';
import '../../../data/database/database.dart';
import '../../../data/database/wh_mobile_docs_schema.dart';
import 'wh_http.dart';

/// kind -> state -> action -> next state. Anything else is `invalid_transition`.
const Map<String, Map<String, Map<String, String>>> kWhTransitions = {
  'po_receipt': {
    'draft': {'submit': 'submitted', 'cancel': 'cancelled'},
    'submitted': {'convert': 'posted'},
  },
  'transfer': {
    'requested': {'approve': 'approved', 'reject': 'rejected'},
    'approved': {'dispatch': 'in_transit'},
    'in_transit': {'receive': 'received', 'receive_short': 'received_short'},
    'received_short': {'resolve': 'closed'},
  },
  'voucher': {
    'pending': {'approve': 'posted', 'reject': 'rejected'},
  },
  'count_submission': {
    'draft': {'submit': 'submitted'},
    'submitted': {'post': 'posted'},
  },
};

String? nextWhState(String kind, String state, String action) => kWhTransitions[kind]?[state]?[action];

DateTime? _ms(Object? v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());

class WhDoc {
  WhDoc(this.row);
  final Map<String, Object?> row;
  int get id => (row['id'] as num).toInt();
  String get gid => row['global_id']! as String;
  String get kind => row['kind']! as String;
  String get state => row['state']! as String;
  int get warehouseId => (row['warehouse_id'] as num).toInt();
  int? get toWarehouseId => (row['to_warehouse_id'] as num?)?.toInt();
  String? get refType => row['ref_type'] as String?;
  String? get refId => row['ref_id'] as String?;
  String? get reason => row['reason'] as String?;
  int get createdBy => (row['created_by'] as num).toInt();
  int get rowVersion => (row['row_version'] as num).toInt();
  int? get approvedBy => (row['approved_by'] as num?)?.toInt();
  String? get postedRefId => row['posted_ref_id'] as String?;
  DateTime? get createdAt => _ms(row['created_at']);
  Map<String, Object?> get data {
    final t = row['data_json'] as String?;
    return t == null || t.isEmpty ? {} : (jsonDecode(t) as Map).cast<String, Object?>();
  }
}

class WhLine {
  WhLine(this.row);
  final Map<String, Object?> row;
  int get id => (row['id'] as num).toInt();
  String get gid => row['line_global_id']! as String;
  int get productId => (row['product_id'] as num).toInt();
  double get qty => (row['qty_base'] as num).toDouble();
  int? get locationId => (row['location_id'] as num?)?.toInt();
  String? get batchNumber => row['batch_number'] as String?;
  DateTime? get expiry => _ms(row['expiry_date']);
  String get condition => row['condition']! as String;
  int? get poItemId => (row['po_item_id'] as num?)?.toInt();
  int get pass => (row['pass'] as num).toInt();
  int? get counterUserId => (row['counter_user_id'] as num?)?.toInt();
  double? get unitCost => (row['unit_cost'] as num?)?.toDouble();
  Map<String, Object?> get extra {
    final t = row['extra_json'] as String?;
    return t == null || t.isEmpty ? {} : (jsonDecode(t) as Map).cast<String, Object?>();
  }
}

Variable<Object> _v(Object? x) => switch (x) {
      null => const Variable<String>(null),
      int i => Variable<int>(i),
      double d => Variable<double>(d),
      bool b => Variable<bool>(b),
      _ => Variable<String>(x.toString()),
    };

class WhDocStore {
  WhDocStore(this.db);
  final AppDatabase db;

  Future<List<Map<String, Object?>>> _rows(String sql, [List<Object?> args = const []]) async {
    final r = await db.customSelect(sql, variables: [for (final a in args) _v(a)]).get();
    return [for (final x in r) x.data.cast<String, Object?>()];
  }

  Future<WhDoc?> byGid(String gid) async {
    await db.ensureWhMobileDocsSchema();
    final r = await _rows('SELECT * FROM wh_mobile_docs WHERE global_id = ?', [gid]);
    return r.isEmpty ? null : WhDoc(r.first);
  }

  Future<WhDoc> mustGet(String gid) async => await byGid(gid) ?? (throw WhError('doc_not_found', 404));

  Future<WhDoc> create({
    required String kind,
    required String state,
    required int warehouseId,
    required int createdBy,
    required String deviceId,
    String? gid,
    int? toWarehouseId,
    String? refType,
    String? refId,
    String? reason,
    Map<String, Object?> data = const {},
  }) async {
    await db.ensureWhMobileDocsSchema();
    final now = DateTime.now().millisecondsSinceEpoch;
    final g = gid ?? UuidV7.generate();
    await db.customStatement(
      'INSERT INTO wh_mobile_docs (global_id, kind, state, warehouse_id, to_warehouse_id, '
      'ref_type, ref_id, reason, created_by, device_id, created_at, updated_at, data_json) '
      'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [g, kind, state, warehouseId, toWarehouseId, refType, refId, reason, createdBy, deviceId, now, now, jsonEncode(data)],
    );
    return mustGet(g);
  }

  /// Returns false when a line with this id already exists (idempotent replay).
  Future<bool> addLine(
    WhDoc doc, {
    required String lineGid,
    required int productId,
    required double qty,
    int? locationId,
    String? batchNumber,
    DateTime? expiry,
    String condition = 'ok',
    int? poItemId,
    int pass = 1,
    int? counterUserId,
    double? unitCost,
    Map<String, Object?> extra = const {},
  }) async {
    final exists = await _rows('SELECT id FROM wh_mobile_doc_lines WHERE line_global_id = ?', [lineGid]);
    if (exists.isNotEmpty) return false;
    await db.customStatement(
      'INSERT INTO wh_mobile_doc_lines (doc_id, line_global_id, product_id, qty_base, location_id, '
      'batch_number, expiry_date, condition, po_item_id, pass, observed_at, counter_user_id, unit_cost, extra_json) '
      'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        doc.id, lineGid, productId, qty, locationId, batchNumber, expiry?.millisecondsSinceEpoch, condition,
        poItemId, pass, DateTime.now().millisecondsSinceEpoch, counterUserId, unitCost, jsonEncode(extra),
      ],
    );
    return true;
  }

  Future<List<WhLine>> lines(int docId) async => [
        for (final r in await _rows('SELECT * FROM wh_mobile_doc_lines WHERE doc_id = ? ORDER BY id', [docId]))
          WhLine(r),
      ];

  Future<void> setLineExtra(int lineId, Map<String, Object?> extra) =>
      db.customStatement('UPDATE wh_mobile_doc_lines SET extra_json = ? WHERE id = ?', [jsonEncode(extra), lineId]);

  Future<List<WhDoc>> list({
    String? kind,
    List<String>? states,
    Iterable<int>? warehouseIds,
    String? refType,
    String? refId,
    int? createdBy,
    int limit = 200,
  }) async {
    await db.ensureWhMobileDocsSchema();
    final where = <String>[];
    final args = <Object?>[];
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind);
    }
    if (states != null && states.isNotEmpty) {
      where.add('state IN (${List.filled(states.length, '?').join(',')})');
      args.addAll(states);
    }
    if (warehouseIds != null) {
      final ids = warehouseIds.toList();
      if (ids.isEmpty) return const [];
      where.add('(warehouse_id IN (${ids.join(',')}) OR to_warehouse_id IN (${ids.join(',')}))');
    }
    if (refType != null) {
      where.add('ref_type = ?');
      args.add(refType);
    }
    if (refId != null) {
      where.add('ref_id = ?');
      args.add(refId);
    }
    if (createdBy != null) {
      where.add('created_by = ?');
      args.add(createdBy);
    }
    final rows = await _rows(
      'SELECT * FROM wh_mobile_docs ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} ORDER BY id DESC LIMIT $limit',
      args,
    );
    return [for (final r in rows) WhDoc(r)];
  }

  /// Applies [action] to [doc] under the state machine. `stale` when
  /// [expectedVersion] no longer matches; the UPDATE itself is guarded by the
  /// row version so two racing commands cannot both win.
  Future<WhDoc> transition(
    WhDoc doc,
    String action, {
    int? expectedVersion,
    int? approvedBy,
    String? postedRefType,
    String? postedRefId,
    Map<String, Object?>? data,
  }) async {
    if (expectedVersion != null && expectedVersion != doc.rowVersion) {
      throw WhError('stale', 409, {'currentVersion': doc.rowVersion});
    }
    final next = nextWhState(doc.kind, doc.state, action);
    if (next == null) throw WhError('invalid_transition', 409, {'state': doc.state, 'action': action});
    final now = DateTime.now().millisecondsSinceEpoch;
    // Only the columns that change are written (no NULL-typed parameters).
    final sets = <String>['state = ?', 'row_version = row_version + 1', 'updated_at = ?'];
    final args = <Object?>[next, now];
    void set(String col, Object? v) {
      if (v == null) return;
      sets.add('$col = ?');
      args.add(v);
    }

    set('approved_by', approvedBy);
    if (approvedBy != null) set('approved_at', now);
    set('posted_ref_type', postedRefType);
    set('posted_ref_id', postedRefId);
    set('data_json', data == null ? null : jsonEncode(data));
    final n = await db.customUpdate(
      'UPDATE wh_mobile_docs SET ${sets.join(', ')} WHERE id = ? AND row_version = ?',
      variables: [for (final a in [...args, doc.id, doc.rowVersion]) _v(a)],
    );
    if (n != 1) throw WhError('stale', 409);
    return mustGet(doc.gid);
  }

  Future<void> patchData(WhDoc doc, Map<String, Object?> data) =>
      db.customStatement('UPDATE wh_mobile_docs SET data_json = ?, updated_at = ? WHERE id = ?',
          [jsonEncode(data), DateTime.now().millisecondsSinceEpoch, doc.id]);

  Future<Map<String, Object?>?> _event(String commandId) async {
    final r = await _rows('SELECT * FROM wh_mobile_doc_events WHERE command_id = ?', [commandId]);
    return r.isEmpty ? null : r.first;
  }

  /// Runs [effect] exactly once per [ctx] command id. A replay returns the
  /// stored result (plus `replayed: true`); the same id with a different body
  /// is `409 idempotency_conflict`. The event row commits with the effect.
  Future<Map<String, Object?>> command(
    WhCtx ctx, {
    required String action,
    required Object? body,
    required Future<({int? docId, Map<String, Object?> result})> Function() effect,
  }) async {
    await db.ensureWhMobileDocsSchema();
    final id = ctx.commandId;
    final hash = payloadHash({'action': action, 'body': body});
    return db.transaction(() async {
      final seen = await _event(id);
      if (seen != null) {
        if (seen['payload_hash'] != hash) throw WhError('idempotency_conflict', 409);
        final stored = jsonDecode((seen['result_json'] as String?) ?? '{}') as Map;
        return {...stored.cast<String, Object?>(), 'replayed': true};
      }
      final out = await effect();
      await db.customStatement(
        'INSERT INTO wh_mobile_doc_events (command_id, doc_id, action, actor_user_id, device_id, '
        'payload_hash, result_json, at) VALUES (?,?,?,?,?,?,?,?)',
        [id, out.docId, action, ctx.userId, ctx.deviceId, hash, jsonEncode(out.result),
         DateTime.now().millisecondsSinceEpoch],
      );
      return out.result;
    });
  }

  Future<List<Map<String, Object?>>> events(int docId) =>
      _rows('SELECT action, actor_user_id, device_id, at FROM wh_mobile_doc_events WHERE doc_id = ? ORDER BY id', [docId]);

  /// Document JSON for the phone. Lines optional. Never carries cost.
  Future<Map<String, Object?>> toJson(WhDoc d, {bool withLines = true}) async => {
        'globalId': d.gid,
        'kind': d.kind,
        'state': d.state,
        'version': d.rowVersion,
        'warehouseId': d.warehouseId,
        if (d.toWarehouseId != null) 'toWarehouseId': d.toWarehouseId,
        if (d.refType != null) 'refType': d.refType,
        if (d.refId != null) 'refId': d.refId,
        if (d.reason != null) 'reason': d.reason,
        'createdBy': d.createdBy,
        if (d.approvedBy != null) 'approvedBy': d.approvedBy,
        if (d.postedRefId != null) 'postedRefId': d.postedRefId,
        'createdAt': d.row['created_at'],
        if (withLines)
          'lines': [
            for (final l in await lines(d.id))
              {
                'lineGlobalId': l.gid,
                'productId': l.productId,
                'quantity': fmtQty(l.qty),
                'condition': l.condition,
                if (l.batchNumber != null) 'batchNumber': l.batchNumber,
                if (l.expiry != null) 'expiryDate': l.expiry!.toIso8601String().substring(0, 10),
                if (l.locationId != null) 'locationId': l.locationId,
                if (l.poItemId != null) 'poItemId': l.poItemId,
              },
          ],
      };
}
