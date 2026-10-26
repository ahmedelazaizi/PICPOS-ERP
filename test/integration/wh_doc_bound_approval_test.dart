// WH-010 (owner decision 2026-10-26): the four-eyes approval proof of a warehouse
// action is bound to ONE document + operation + version, and a phone can obtain
// one: the supervisor proves his credential on the keeper's phone, the HOST signs.
// Real middleware + router (wh_api_harness); amounts are asserted on stock.
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/core/permissions/role_grant_matrix.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/approval_proof.dart';

import '../helpers/wh_api_harness.dart';

void main() {
  late WhHarness h;
  late int rice, sup;
  const supPw = 'Sup#Pass12345';

  setUp(() async {
    h = await WhHarness.create();
    rice = await h.product('RICE');
    await h.db.adjustStock(productId: rice, warehouseId: h.a1, quantity: 20, type: 'purchase', unitCost: 10);
    // a supervisor who really knows a password (the harness users have none)
    final role = await (h.db.select(h.db.roles)..where((r) => r.name.equals(kWarehouseSupervisorRole))).getSingle();
    sup = await h.db.createUser(username: 'sup-pw', password: supPw, displayName: 'Sup', roleId: role.id);
    await h.db.into(h.db.userBranchAccess).insert(UserBranchAccessCompanion.insert(userId: sup, branchId: h.branchA));
    for (final w in [h.a1, h.a2]) {
      await h.db.into(h.db.userWarehouseAccess).insert(UserWarehouseAccessCompanion.insert(userId: sup, warehouseId: w));
    }
  });
  tearDown(() => h.dispose());

  Future<WhReply> voucher(int user, String gid, String qty) => h.call('POST', '/api/m1/wh/vouchers', user: user, body: {
        'globalId': gid,
        'type': 'out',
        'warehouseId': h.a1,
        'reason': 'damaged in aisle',
        'lines': [
          {'lineGlobalId': 'vline-$gid', 'productId': rice, 'quantity': qty},
        ],
      });

  Future<WhReply> issue(int requester, String ref, {String action = 'approve', String kind = 'voucher', Map<String, Object?>? creds}) =>
      h.call('POST', '/api/m1/wh/approvals/proof',
          user: requester, body: {'kind': kind, 'ref': ref, 'action': action, ...(creds ?? {'username': 'sup-pw', 'password': supPw})});

  Future<WhReply> approve(int user, String gid, String? proof, {String? key, String action = 'approve'}) => h.call(
        'POST', '/api/m1/wh/vouchers/$gid/$action',
        user: user, key: key, headers: {'x-approval-proof': ?proof});

  Future<double> rices() => h.stock(rice, h.a1);

  test('the phone obtains a proof bound to the voucher; the approval posts once under the APPROVER; a retry replays', () async {
    await voucher(h.keeper, 'voucher-0001', '3');
    final p = await issue(h.keeper, 'voucher-0001');
    expect(p.status, 200, reason: p.text);
    expect(p.json['op'], 'voucher:approve');
    expect(p.json['approverId'], sup);
    final claims = ApprovalProof.parse(p.json['proof'] as String)!;
    expect([claims.docId, claims.docOp, claims.requesterId, claims.approverId], ['voucher-0001', 'voucher:approve', h.keeper, sup]);
    expect(claims.docVersion, isNotNull);

    expect(await rices(), 20, reason: 'issuing a proof moves nothing');
    final ok = await approve(h.keeper, 'voucher-0001', p.json['proof'] as String, key: 'approve-key-0001');
    expect(ok.status, 200, reason: ok.text);
    expect(await rices(), 17);
    final row = await h.db.customSelect("SELECT approved_by FROM wh_mobile_docs WHERE global_id = 'voucher-0001'").getSingle();
    expect(row.read<int>('approved_by'), sup, reason: 'the supervisor who proved his credential approves, not the keeper');

    final again = await approve(h.keeper, 'voucher-0001', p.json['proof'] as String, key: 'approve-key-0001');
    expect(again.status, 200);
    expect(again.json['replayed'], isTrue);
    expect(await rices(), 17, reason: 'a retry never posts twice');
  });

  test('FORGED: a tampered proof is refused approval_invalid and nothing posts', () async {
    await voucher(h.keeper, 'voucher-0001', '3');
    final proof = (await issue(h.keeper, 'voucher-0001')).json['proof'] as String;
    final forged = '${proof.substring(0, proof.length - 2)}${proof.endsWith('AA') ? 'BB' : 'AA'}';
    final r = await approve(h.keeper, 'voucher-0001', forged);
    expect(r.status, 403);
    expect(r.json['code'], 'approval_invalid');
    // a hand-made claims set (even with a doc claim) is not signed by the host
    final handmade = ApprovalProof.mint(permission: 'stock_adjust_approve', requesterId: h.keeper, approverId: sup, deviceId: 'wh-A',
        docId: 'voucher-0001', docOp: 'voucher:approve', docVersion: 1)!;
    final swapped = '${handmade.split('.').first}.${proof.split('.').last}';
    expect((await approve(h.keeper, 'voucher-0001', swapped)).json['code'], 'approval_invalid');
    expect(await rices(), 20);
  });

  test('EXPIRED: a proof older than its ttl is refused approval_expired', () async {
    await voucher(h.keeper, 'voucher-0001', '3');
    final old = ApprovalProof.mint(
        permission: 'stock_adjust_approve', requesterId: h.keeper, approverId: sup, deviceId: 'wh-A',
        docId: 'voucher-0001', docOp: 'voucher:approve', docVersion: 1,
        nowMs: DateTime.now().subtract(const Duration(minutes: 30)).millisecondsSinceEpoch)!;
    final r = await approve(h.keeper, 'voucher-0001', old);
    expect(r.status, 403);
    expect(r.json['code'], 'approval_expired');
    expect(await rices(), 20);
  });

  test('WRONG DOCUMENT: the proof of voucher A cannot approve voucher B', () async {
    await voucher(h.keeper, 'voucher-000A', '3');
    await voucher(h.keeper, 'voucher-000B', '4');
    final proofA = (await issue(h.keeper, 'voucher-000A')).json['proof'] as String;
    final r = await approve(h.keeper, 'voucher-000B', proofA);
    expect(r.status, 403);
    expect(r.error, 'approval_mismatch');
    expect(await rices(), 20);
    expect((await approve(h.keeper, 'voucher-000A', proofA, key: 'other-key-00001')).json['code'], 'approval_already_used',
        reason: 'the proof is spent by the refused B call: single use');
  });

  test('WRONG OPERATION: a proof to REJECT cannot approve (and the other way round)', () async {
    await voucher(h.keeper, 'voucher-0001', '3');
    final rejectProof = (await issue(h.keeper, 'voucher-0001', action: 'reject')).json['proof'] as String;
    final r = await approve(h.keeper, 'voucher-0001', rejectProof);
    expect(r.status, 403);
    expect(r.error, 'approval_mismatch');
    expect(await rices(), 20);

    final approveProof = (await issue(h.keeper, 'voucher-0001')).json['proof'] as String;
    final rj = await approve(h.keeper, 'voucher-0001', approveProof, action: 'reject');
    expect(rj.error, 'approval_mismatch');
    final state = await h.db.customSelect("SELECT state FROM wh_mobile_docs WHERE global_id = 'voucher-0001'").getSingle();
    expect(state.read<String>('state'), 'pending');
  });

  test('STALE VERSION: the document changed after the proof was issued -> 409 approval_stale, nothing posts', () async {
    await voucher(h.keeper, 'voucher-0001', '3');
    final proof = (await issue(h.keeper, 'voucher-0001')).json['proof'] as String;
    await h.db.customStatement("UPDATE wh_mobile_docs SET row_version = row_version + 1 WHERE global_id = 'voucher-0001'");
    final r = await approve(h.keeper, 'voucher-0001', proof);
    expect(r.status, 409);
    expect(r.error, 'approval_stale');
    expect(await rices(), 20);
    // a fresh proof for the new version works
    final fresh = (await issue(h.keeper, 'voucher-0001')).json['proof'] as String;
    expect((await approve(h.keeper, 'voucher-0001', fresh)).status, 200);
    expect(await rices(), 17);
  });

  test('REPLAY: a proof already spent on one operation cannot authorise another call (approval_already_used)', () async {
    await voucher(h.keeper, 'voucher-0001', '3');
    final proof = (await issue(h.keeper, 'voucher-0001')).json['proof'] as String;
    expect((await approve(h.keeper, 'voucher-0001', proof, key: 'approve-key-0001')).status, 200);
    final r = await approve(h.keeper, 'voucher-0001', proof, key: 'approve-key-0002');
    expect(r.status, 403);
    expect(r.json['code'], 'approval_already_used');
    expect(await rices(), 17);
  });

  test('another device cannot carry the proof (approval_mismatch)', () async {
    await voucher(h.keeper, 'voucher-0001', '3');
    final proof = (await issue(h.keeper, 'voucher-0001')).json['proof'] as String;
    final r = await h.call('POST', '/api/m1/wh/vouchers/voucher-0001/approve',
        user: h.keeper, device: 'wh-B', headers: {'x-approval-proof': proof});
    expect(r.status, isNot(200));
    expect(await rices(), 20);
  });

  test('a plain (unbound) P5 proof is no longer accepted for a warehouse document', () async {
    await voucher(h.keeper, 'voucher-0001', '3');
    final plain = ApprovalProof.mint(permission: 'stock_adjust_approve', requesterId: h.keeper, approverId: sup, deviceId: 'wh-A')!;
    final r = await approve(h.keeper, 'voucher-0001', plain);
    expect(r.status, 403);
    expect(r.error, 'approval_not_document_bound');
    expect(await rices(), 20);
  });

  test('CREATOR == APPROVER is refused at issue time and at use time; so is requester == approver', () async {
    await voucher(sup, 'voucher-0001', '3'); // the supervisor authored it
    final r = await issue(h.keeper, 'voucher-0001');
    expect(r.status, 403);
    expect(r.error, 'self_approval');
    // a proof minted outside the route naming the author is still refused when used
    final v = (await h.db.customSelect("SELECT row_version FROM wh_mobile_docs WHERE global_id = 'voucher-0001'").getSingle()).read<int>('row_version');
    final own = ApprovalProof.mint(permission: 'stock_adjust_approve', requesterId: h.keeper, approverId: sup, deviceId: 'wh-A',
        docId: 'voucher-0001', docOp: 'voucher:approve', docVersion: v)!;
    expect((await approve(h.keeper, 'voucher-0001', own)).error, 'self_approval');
    expect(await rices(), 20);

    await voucher(h.keeper, 'voucher-0002', '3');
    final selfReq = await issue(sup, 'voucher-0002', creds: {'username': 'sup-pw', 'password': supPw});
    expect(selfReq.error, 'self_approval', reason: 'the requester cannot vouch for himself');
  });

  test('issuing is guarded: wrong password 403 invalid_credentials, approver without the permission or outside the warehouse is refused, unknown document 404', () async {
    await voucher(h.keeper, 'voucher-0001', '3');
    expect((await issue(h.keeper, 'voucher-0001', creds: {'username': 'sup-pw', 'password': 'nope'})).error, 'invalid_credentials');
    final noPerm = await h.db.createUser(username: 'clerk-pw', password: 'Clerk#Pass9876', displayName: 'C', roleId: (await (h.db.select(h.db.roles)..where((r) => r.name.equals(kWarehouseClerkRole))).getSingle()).id);
    expect((await issue(h.keeper, 'voucher-0001', creds: {'username': 'clerk-pw', 'password': 'Clerk#Pass9876'})).error, 'approver_not_authorised');
    expect(noPerm, isNonZero);
    await h.db.customStatement('DELETE FROM user_warehouse_access WHERE user_id = ? AND warehouse_id = ?', [sup, h.a1]);
    expect((await issue(h.keeper, 'voucher-0001')).error, 'warehouse_forbidden', reason: 'the approver must cover the document\'s warehouse');
    expect((await issue(h.keeper, 'missing-doc-0001')).status, 404);
    expect((await issue(h.keeper, 'voucher-0001', action: 'explode')).status, 400);
    expect(await rices(), 20);
  });

  test('a document that is no longer pending cannot get a proof (invalid_transition)', () async {
    await voucher(h.keeper, 'voucher-0001', '3');
    expect((await h.call('POST', '/api/m1/wh/vouchers/voucher-0001/approve', user: h.supervisor)).status, 200);
    final r = await issue(h.keeper, 'voucher-0001');
    expect(r.status, 409);
    expect(r.error, 'invalid_transition');
  });

  test('a supervisor holding the permission needs no proof; the generic grant route stays closed to a phone', () async {
    await voucher(h.keeper, 'voucher-0001', '3');
    expect((await approve(h.supervisor, 'voucher-0001', null)).status, 200);
    final grant = await h.call('POST', '/api/approvals/grant', user: h.keeper, body: {'permission': 'stock_adjust_approve'});
    expect(grant.status, 403);
  });
}
