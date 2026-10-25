// P5 (plan 2026-10-24, B.9): the device-side four-eyes flow.
//  * standalone/main: the second user is verified locally;
//  * branch device / console: the MAIN decides and signs a proof that the device
//    then carries; every refusal of the main maps to its own outcome;
//  * main unreachable: a mirror is refused, a CRITICAL operation is refused,
//    any other operation falls back to the local check and is audited
//    `offline: true`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/services/approval/approval_proof_carrier.dart';
import 'package:picpos_erp/services/approval/manager_approval_flow.dart';

class _Wire implements ApprovalWirePort {
  _Wire(this.reply);
  Object Function(Map<String, dynamic> body) reply; // ApprovalWireResult | throw
  final calls = <Map<String, dynamic>>[];

  @override
  Future<ApprovalWireResult> grant(Map<String, dynamic> body) async {
    calls.add(body);
    final r = reply(body);
    if (r is ApprovalWireResult) return r;
    throw r;
  }
}

class _Local implements LocalApproverPort {
  _Local(this.byInput);
  final Map<String, LocalApprover> byInput;
  int asked = 0;
  @override
  Future<LocalApprover?> authenticate(String input) async {
    asked++;
    return byInput[input];
  }
}

const _noncritical = 'pos_expense';

void main() {
  final critical = PermissionCodes.criticalFinancialOps.first;
  const boss = LocalApprover(
      id: 12, name: 'Boss', permissions: [_noncritical, 'void_paid_invoice']);
  late ApprovalProofCarrier carrier;
  late List<Map<String, Object?>> audits;

  ManagerApprovalFlow flow(
    _Wire wire,
    _Local local, {
    bool client = true,
    bool mirror = false,
    int requester = 10,
  }) =>
      ManagerApprovalFlow(
        wire: wire,
        local: local,
        requesterId: () => requester,
        isClientMode: () => client,
        isMirror: () => mirror,
        carrier: carrier,
        audit: ({
          required String permission,
          required int? approverId,
          required int? requesterId,
          required bool offline,
        }) async =>
            audits.add({
              'permission': permission,
              'approver': approverId,
              'requester': requesterId,
              'offline': offline,
            }),
      );

  setUp(() {
    carrier = ApprovalProofCarrier.instance..debugReset();
    audits = [];
  });
  tearDown(() => carrier.debugReset());

  ApprovalWireResult ok() => const ApprovalWireResult(200, {
        'proof': 'p.sig',
        'approverId': 12,
        'approverName': 'Boss',
      });

  test('standalone (the device is the authority): local check, no network',
      () async {
    final wire = _Wire((_) => throw StateError('must not be called'));
    final local = _Local({'boss': boss});
    final d = await flow(wire, local, client: false)
        .approve(input: 'boss', permission: _noncritical);
    expect(d.approved, isTrue);
    expect(d.offline, isFalse);
    expect(wire.calls, isEmpty);
    expect(audits, isEmpty, reason: 'on the main the approval is its own record');
  });

  test('standalone: the requester cannot approve himself; a holder without the '
      'permission cannot approve', () async {
    final local = _Local({
      'me': const LocalApprover(id: 10, name: 'Me', permissions: [_noncritical]),
      'peer': const LocalApprover(id: 11, name: 'Peer', permissions: ['x']),
    });
    final f = flow(_Wire((_) => ok()), local, client: false);
    expect((await f.approve(input: 'me', permission: _noncritical)).kind,
        ManagerApprovalKind.selfApproval);
    expect((await f.approve(input: 'peer', permission: _noncritical)).kind,
        ManagerApprovalKind.notAuthorised);
    expect((await f.approve(input: 'nobody', permission: _noncritical)).kind,
        ManagerApprovalKind.invalidCredentials);
    expect(audits, isEmpty);
  });

  test('branch device online: the MAIN decides, the proof is held and carried',
      () async {
    final wire = _Wire((_) => ok());
    final local = _Local({'boss': boss});
    final d = await flow(wire, local)
        .approve(input: 'boss', permission: _noncritical, scope: 'invoice:7');
    expect(d.approved, isTrue);
    expect(d.proof, 'p.sig');
    expect(wire.calls.single, {
      'permission': _noncritical,
      'scope': 'invoice:7',
      'password': 'boss',
    });
    expect(local.asked, 0, reason: 'online: the local check is not consulted');
    expect(carrier.proof, 'p.sig');
    expect(carrier.permission, _noncritical);
    final payload = <String, dynamic>{'a': 1};
    carrier.stamp(payload);
    expect(payload['approvalProof'], 'p.sig',
        reason: 'an outbox row keeps the proof');
  });

  test('each refusal of the main maps to its own outcome (and holds no proof)',
      () async {
    ApprovalWireResult r(int s, String c) => ApprovalWireResult(s, {'code': c});
    final cases = <(ApprovalWireResult, ManagerApprovalKind)>[
      (r(403, 'self_approval'), ManagerApprovalKind.selfApproval),
      (r(403, 'approver_not_authorised'), ManagerApprovalKind.notAuthorised),
      (r(403, 'branch_access_denied'), ManagerApprovalKind.branchDenied),
      (r(403, 'password_change_required'),
          ManagerApprovalKind.passwordChangeRequired),
      (r(401, 'invalid_credentials'), ManagerApprovalKind.invalidCredentials),
      (r(401, 'session_required'), ManagerApprovalKind.sessionRequired),
      (r(429, 'locked_out'), ManagerApprovalKind.lockedOut),
      (r(500, 'boom'), ManagerApprovalKind.error),
    ];
    for (final (reply, kind) in cases) {
      final d = await flow(_Wire((_) => reply), _Local({}))
          .approve(input: 'x', permission: _noncritical);
      expect(d.kind, kind, reason: '${reply.status} ${reply.code}');
      expect(carrier.proof, isNull);
    }
  });

  group('main unreachable', () {
    test('a CRITICAL operation is refused offline - even for a valid local '
        'approver', () async {
      final local = _Local({'boss': boss});
      final d = await flow(_Wire((_) => const SocketException('down')), local)
          .approve(input: 'boss', permission: critical);
      expect(d.kind, ManagerApprovalKind.offlineRefusedCritical);
      expect(local.asked, 0, reason: 'not even a local look-up');
      expect(audits, isEmpty);
      expect(carrier.proof, isNull);
    });

    test('the console (mirror) never approves offline', () async {
      final d = await flow(_Wire((_) => const SocketException('down')),
              _Local({'boss': boss}),
              mirror: true)
          .approve(input: 'boss', permission: _noncritical);
      expect(d.kind, ManagerApprovalKind.offlineRefusedMirror);
    });

    test('a non-critical operation falls back to the local check and is '
        'audited offline: true', () async {
      final d = await flow(_Wire((_) => const SocketException('down')),
              _Local({'boss': boss}))
          .approve(input: 'boss', permission: _noncritical);
      expect(d.approved, isTrue);
      expect(d.offline, isTrue);
      expect(audits.single, {
        'permission': _noncritical,
        'approver': 12,
        'requester': 10,
        'offline': true,
      });
    });

    test('the offline fallback still refuses the requester himself', () async {
      final d = await flow(_Wire((_) => const SocketException('down')),
              _Local({'me': const LocalApprover(id: 10, name: 'Me', permissions: [_noncritical])}))
          .approve(input: 'me', permission: _noncritical);
      expect(d.kind, ManagerApprovalKind.selfApproval);
      expect(audits, isEmpty);
    });
  });

  test('isCritical follows PermissionCodes.criticalFinancialOps', () {
    expect(ManagerApprovalFlow.isCritical(critical), isTrue);
    expect(ManagerApprovalFlow.isCritical(_noncritical), isFalse);
  });
}
