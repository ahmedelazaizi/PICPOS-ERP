// Document operations of [WarehouseLanClient] (W2-W5). Every write carries
// `x-idempotency-key` = the caller's command id (the outbox entry's globalId),
// so a retry after a lost answer is answered from the server's command log.
part of 'wh_client.dart';

extension WarehouseDocOps on WarehouseLanClient {
  Future<Map<String, Object?>> _get(String path, [Map<String, String>? query]) async =>
      _object(await transport.send(ApiRequest('GET', path, query: query ?? const {}, headers: headers.build(credentials))));

  /// POST with the idempotency key; [approvalProof] = P5 proof of a manager.
  Future<WhCommandResult> command(
    String path,
    Map<String, Object?> body, {
    required String commandId,
    String? approvalProof,
  }) async {
    final h = {...headers.build(credentials, idempotencyKey: commandId), if (approvalProof != null) 'x-approval-proof': approvalProof};
    return WhCommandResult(_object(await transport.send(ApiRequest('POST', path, headers: h, body: body))));
  }

  // ── W2 receive ──
  Future<List<WhPurchaseOrder>> purchaseOrders({int? warehouseId}) async {
    final m = await _get(WhDocPaths.po, {'status': 'open', if (warehouseId != null) 'warehouse': '$warehouseId'});
    return [for (final o in (m['orders'] as List? ?? const [])) WhPurchaseOrder.fromJson((o as Map).cast<String, Object?>())];
  }

  Future<WhPurchaseOrder> purchaseOrder(String ref) async =>
      WhPurchaseOrder.fromJson(await _get('${WhDocPaths.po}/${Uri.encodeComponent(ref)}'));

  Future<WhCommandResult> saveReceiptLines({
    required String poRef,
    required String receiptGlobalId,
    required List<WhReceiptLineInput> lines,
    required String commandId,
    String? note,
  }) =>
      command('${WhDocPaths.po}/${Uri.encodeComponent(poRef)}/receipts',
          {'globalId': receiptGlobalId, 'lines': [for (final l in lines) l.toJson()], if (note != null) 'note': note},
          commandId: commandId);

  Future<WhCommandResult> submitReceipt(String receiptGlobalId, {required String commandId}) =>
      command('${WhDocPaths.receipts}/$receiptGlobalId/submit', const {}, commandId: commandId);

  Future<List<WhDoc>> receipts({String? state}) async {
    final m = await _get(WhDocPaths.receipts, {if (state != null) 'state': state});
    return [for (final d in (m['receipts'] as List? ?? const [])) WhDoc.fromJson((d as Map).cast<String, Object?>())];
  }

  Future<WhBin> binByBarcode(String barcode) async =>
      WhBin.fromJson(await _get('${WhDocPaths.locationByBarcode}/${Uri.encodeComponent(barcode)}'));

  // ── W3 transfers + vouchers ──
  Future<WhCommandResult> requestTransfer(Map<String, Object?> body, {required String commandId}) =>
      command(WhDocPaths.transfers, body, commandId: commandId);

  Future<List<WhDoc>> transfers({String? state}) => _docs(WhDocPaths.transfers, state);

  /// action: approve | reject | dispatch | receive | resolve
  Future<WhCommandResult> transferAction(String gid, String action,
          {Map<String, Object?> body = const {}, required String commandId, String? approvalProof}) =>
      command('${WhDocPaths.transfers}/$gid/$action', body, commandId: commandId, approvalProof: approvalProof);

  Future<WhCommandResult> createVoucher(Map<String, Object?> body, {required String commandId}) =>
      command(WhDocPaths.vouchers, body, commandId: commandId);

  Future<List<WhDoc>> vouchers({String? state}) => _docs(WhDocPaths.vouchers, state);

  /// action: approve | reject
  Future<WhCommandResult> voucherAction(String gid, String action, {required String commandId, String? approvalProof}) =>
      command('${WhDocPaths.vouchers}/$gid/$action', const {}, commandId: commandId, approvalProof: approvalProof);

  Future<List<WhDoc>> _docs(String path, String? state) async {
    final m = await _get(path, {if (state != null) 'state': state});
    return [for (final d in (m['docs'] as List? ?? const [])) WhDoc.fromJson((d as Map).cast<String, Object?>())];
  }

  // ── W4 blind counts ──
  Future<List<WhCountTask>> countTasks() async {
    final m = await _get('${WhDocPaths.counts}/tasks');
    return [for (final t in (m['tasks'] as List? ?? const [])) WhCountTask.fromJson((t as Map).cast<String, Object?>())];
  }

  Future<WhCommandResult> countEntries(String ref, String docGlobalId, List<Map<String, Object?>> entries,
          {required String commandId}) =>
      command('${WhDocPaths.counts}/${Uri.encodeComponent(ref)}/entries', {'globalId': docGlobalId, 'entries': entries},
          commandId: commandId);

  Future<WhCommandResult> countSubmit(String ref, String docGlobalId, {required String commandId}) =>
      command('${WhDocPaths.counts}/${Uri.encodeComponent(ref)}/submit', {'globalId': docGlobalId}, commandId: commandId);

  Future<WhCountReview> countReview(String ref) async =>
      WhCountReview.fromJson(await _get('${WhDocPaths.counts}/${Uri.encodeComponent(ref)}/review'));

  Future<WhCommandResult> countApprove(String ref, {required String commandId, String? approvalProof}) =>
      command('${WhDocPaths.counts}/${Uri.encodeComponent(ref)}/approve', const {},
          commandId: commandId, approvalProof: approvalProof);

  // ── W5 approvals + labels ──
  Future<List<WhApprovalItem>> approvals() async {
    final m = await _get(WhDocPaths.approvals);
    return [for (final a in (m['approvals'] as List? ?? const [])) WhApprovalItem.fromJson((a as Map).cast<String, Object?>())];
  }

  /// WH-010: the supervisor next to the phone proves HIS credential; the host signs a proof
  /// for this document + [action] + version. [kind]: transfer | voucher | count.
  Future<WhApprovalProof> approvalProof({
    required String kind,
    required String ref,
    required String action,
    String? username,
    String? password,
    String? cardCode,
  }) async =>
      WhApprovalProof.fromJson(_object(await transport.send(ApiRequest('POST', WhDocPaths.approvalProof,
          headers: headers.build(credentials),
          body: {'kind': kind, 'ref': ref, 'action': action, 'username': ?username, 'password': ?password, 'cardCode': ?cardCode}))));

  Future<WhLabelData> label(String kind, String ref) async =>
      WhLabelData.fromJson(await _get(WhDocPaths.labels, {'kind': kind, 'ref': ref}));
}
